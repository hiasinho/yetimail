"""Offline folder snapshot protocol and bounded private persistence."""
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import sqlite3
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch


helper = runpy.run_path(str(Path(__file__).resolve().parents[1] / "bin/yetimail-helper"))
Cache = helper["FolderSnapshotCache"]


class FolderCacheTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.config = self.root / "config.toml"
        self.config.write_text('[accounts.work]\ndefault = true\n[accounts.other]\n')
        env = patch.dict(os.environ, {"XDG_CACHE_HOME": str(self.root), "YETIMAIL_CACHE": "1"})
        env.start()
        self.addCleanup(env.stop)
        self.response = {"mailboxes": [{"id": "INBOX", "name": "Inbox", "role": "inbox", "ignored": True}]}
        backend = patch("subprocess.run", side_effect=lambda *a, **k: subprocess.CompletedProcess(
            [], 0, json.dumps(self.response).encode(), b""))
        self.run = backend.start()
        self.addCleanup(backend.stop)

    def invoke(self, *options, command="folders"):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = helper["main"]([command, "--config", str(self.config), "--account", "work", *options])
        return status, json.loads(out.getvalue())

    def probe(self, *options):
        status, result = self.invoke("--cache-only", *options)
        self.assertEqual(status, 0, result)
        return result

    def test_persistence_authoritative_refresh_and_clear(self):
        self.assertEqual(self.probe(), {"hit": False, "value": None})
        self.run.assert_not_called()
        status, value = self.invoke()
        self.assertEqual(status, 0)
        self.assertEqual(value, {"folders": [{"id": "INBOX", "name": "Inbox", "role": "inbox"}]})
        fresh = runpy.run_path(helper["__file__"])
        with patch.dict(helper["main"].__globals__, {"FolderSnapshotCache": fresh["FolderSnapshotCache"]}):
            self.assertEqual(self.probe(), {"hit": True, "value": value})
        self.assertEqual(self.run.call_count, 1)
        self.response = {"mailboxes": []}
        self.assertEqual(self.invoke(), (0, {"folders": []}))
        self.assertEqual(self.probe()["value"], {"folders": []})
        self.assertEqual(self.invoke(command="cache-clear"), (0, {"cleared": True}))
        self.assertFalse(self.probe()["hit"])

    def test_context_and_parser_isolation(self):
        self.invoke()
        self.assertTrue(self.probe("--account", "default")["hit"])
        self.assertFalse(self.probe("--account", "other")["hit"])
        with patch.dict(helper["main"].__globals__, {"FOLDER_PARSER_VERSION": "next"}):
            self.assertFalse(self.probe()["hit"])
        self.config.write_text(self.config.read_text() + '# changed\n')
        self.assertFalse(self.probe()["hit"])
        self.assertEqual(self.run.call_count, 1)

    def test_failures_preserve_snapshot_and_disabled_probe_never_fetches(self):
        self.invoke()
        self.response = {"mailboxes": [{"id": "bad\n", "name": "Bad"}]}
        self.assertEqual(self.invoke()[0], 1)
        self.assertTrue(self.probe()["hit"])
        self.run.side_effect = OSError("private backend failure")
        self.assertEqual(self.invoke()[0], 1)
        self.assertTrue(self.probe()["hit"])
        with patch.dict(os.environ, {"YETIMAIL_CACHE": "0"}):
            self.assertFalse(self.probe()["hit"])
        self.config.unlink()
        self.assertFalse(self.probe()["hit"])
        self.assertEqual(self.run.call_count, 3)

    def test_config_change_and_clear_reject_pending_write(self):
        for change in (lambda: self.config.write_text(self.config.read_text() + '# changed\n'),
                       lambda: Cache().clear()):
            def backend(*args, **kwargs):
                change()
                return subprocess.CompletedProcess([], 0, json.dumps(self.response).encode(), b"")
            self.run.side_effect = backend
            self.assertEqual(self.invoke()[0], 0)
            self.assertFalse(self.probe()["hit"])

    def test_demo_bypasses_config_cache_and_backend(self):
        self.config.unlink()
        def forbidden(*args, **kwargs):
            self.fail("Demo accessed cache/config")
        with patch.dict(helper["main"].__globals__, {"cache_context": forbidden, "FolderSnapshotCache": forbidden}):
            self.assertEqual(self.invoke("--demo")[0], 0)
            self.assertTrue(self.probe("--demo")["hit"])
        self.run.assert_not_called()
        self.assertFalse((self.root / "yetimail").exists())

    def test_corrupt_snapshot_and_unsafe_storage_are_misses(self):
        self.invoke()
        path = self.root / "yetimail" / "folders.sqlite3"
        with contextlib.closing(sqlite3.connect(path)) as db:
            db.execute("UPDATE messages SET value=?", (json.dumps({"folders": [{"id": "x", "name": "bad\n"}]}),))
            db.commit()
        self.assertFalse(self.probe()["hit"])
        path.unlink()
        path.symlink_to(self.config)
        self.assertFalse(self.probe()["hit"])
        self.assertEqual(self.invoke()[0], 0)
        self.assertTrue(self.config.read_text().startswith('[accounts.work]'))

    def test_parser_rejects_incompatible_options_before_backend(self):
        for options in (("--page", "1"), ("--id", "1"), ("--seen",), ("--force",),
                        ("--destination", "Trash"), ("--attachment", "1"), ("--cache-identity", "a" * 64)):
            self.assertEqual(self.invoke("--cache-only", *options)[0], 1)
        for command in ("read", "mark", "save", "move", "delete", "cache-clear", "accounts"):
            self.assertEqual(self.invoke("--cache-only", command=command)[0], 1)
        self.run.assert_not_called()

    def test_storage_ttl_bounds_permissions_and_list_isolation(self):
        now = [1000]
        directory = self.root / "private"
        cache = Cache(directory, clock=lambda: now[0], max_bytes=30, max_entry_bytes=20)
        key = helper["CacheKey"]("context", "", "folders", "1")
        self.assertTrue(cache.put(key, {"folders": []}, generation=cache.get(key).generation))
        now[0] += 29 * 86400
        # List maintenance must not prune the longer-lived folder snapshot.
        helper["ListSnapshotCache"](directory, clock=lambda: now[0]).get(key)
        self.assertTrue(Cache(directory, clock=lambda: now[0]).get(key).hit)
        self.assertFalse(cache.put(key, "x" * 30, generation=cache.get(key).generation))
        self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        for path in directory.iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        now[0] += 86400
        self.assertFalse(cache.get(key).hit)


if __name__ == "__main__":
    unittest.main()
