"""Offline persistent list snapshots: protocol, isolation and private storage."""
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
Cache = helper["ListSnapshotCache"]
Key = helper["CacheKey"]


class ListCacheTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / "config.toml"
        self.config.write_text('[accounts.work]\ndefault = true\n[accounts.other]\n')
        self.env = patch.dict(os.environ, {"XDG_CACHE_HOME": str(self.root), "YETIMAIL_CACHE": "1"})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.base = ("--config", str(self.config), "--account", "work")
        self.response = {"envelopes": [{"id": "1", "subject": "Snapshot", "date": "2026-01-01",
                                        "from": [{"email": "offline@example.test"}]}]}
        self.run = patch("subprocess.run", side_effect=self.backend).start()
        self.addCleanup(patch.stopall)

    def backend(self, *args, **kwargs):
        return subprocess.CompletedProcess([], 0, json.dumps(self.response).encode(), b"")

    def invoke(self, command="list", *options):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = helper["main"]([command, *self.base, *options])
        return status, json.loads(out.getvalue())

    def probe(self, *options):
        status, value = self.invoke("list", "--cache-only", *options)
        self.assertEqual(status, 0, value)
        return value

    def test_miss_refresh_restart_hit_and_clear(self):
        self.assertEqual(self.probe(), {"hit": False, "value": None})
        self.run.assert_not_called()
        status, page = self.invoke()
        self.assertEqual(status, 0)
        # A fresh module load (as in each helper invocation) sees the same page.
        fresh = runpy.run_path(str(Path(helper["__file__"])))
        with patch.dict(helper["main"].__globals__, {"ListSnapshotCache": fresh["ListSnapshotCache"]}):
            self.assertEqual(self.probe(), {"hit": True, "value": page})
        self.assertEqual(self.run.call_count, 1)
        self.response = {"envelopes": []}
        self.assertEqual(self.invoke()[1]["messages"], [])
        self.assertEqual(self.probe()["value"]["messages"], [])
        self.assertEqual(self.run.call_count, 2)
        self.assertEqual(self.invoke("cache-clear"), (0, {"cleared": True}))
        self.assertFalse(self.probe()["hit"])

    def test_key_isolation_and_default_account_display(self):
        self.invoke()
        self.assertFalse(self.probe("--page", "2")["hit"])
        self.assertFalse(self.probe("--mailbox", "Other")["hit"])
        self.assertFalse(self.probe("--account", "other")["hit"])
        self.assertEqual(self.probe("--account", "default")["value"]["account"], "default")
        with patch.dict(helper["list_snapshot_key"].__globals__, {"LIST_PARSER_VERSION": "next"}):
            self.assertFalse(self.probe()["hit"])
        self.config.write_text(self.config.read_text() + '# changed\n')
        self.assertFalse(self.probe()["hit"])
        self.assertEqual(self.run.call_count, 1)

    def test_failed_refresh_retains_snapshot_and_disabled_never_fetches(self):
        self.invoke()
        self.run.side_effect = OSError("private error")
        self.assertEqual(self.invoke()[0], 1)
        self.assertTrue(self.probe()["hit"])
        with patch.dict(os.environ, {"YETIMAIL_CACHE": "0"}):
            self.assertFalse(self.probe()["hit"])
        self.assertEqual(self.run.call_count, 2)

    def test_mutations_invalidate_all_pages(self):
        for command, options in (("mark", ("--seen",)), ("move", ("--mailbox", "INBOX", "--destination", "Custom")), ("delete", ())):
            with self.subTest(command=command):
                self.invoke()
                self.invoke("list", "--page", "2")
                self.assertEqual(self.invoke(command, "--id", "1", *options)[0], 0)
                self.assertFalse(self.probe()["hit"])
                self.assertFalse(self.probe("--page", "2")["hit"])

    def test_demo_never_uses_backend_config_or_cache(self):
        self.config.unlink()
        with patch.dict(helper["main"].__globals__, {
                "cache_context": lambda *a: self.fail("demo read config"),
                "ListSnapshotCache": lambda: self.fail("demo opened cache")}):
            self.assertTrue(self.probe("--demo")["hit"])
            self.assertEqual(self.invoke("list", "--demo")[0], 0)
        self.run.assert_not_called()
        self.assertFalse((self.root / "yetimail").exists())

    def test_unavailable_config_cache_only_is_miss_even_with_mailbox(self):
        self.config.unlink()
        self.assertFalse(self.probe("--mailbox", "Archive")["hit"])
        self.run.assert_not_called()

    def test_config_change_during_fetch_does_not_store(self):
        def changed(*args, **kwargs):
            self.config.write_text(self.config.read_text() + '# changed\n')
            return self.backend()
        self.run.side_effect = changed
        self.assertEqual(self.invoke()[0], 0)
        self.assertFalse(self.probe()["hit"])

    def test_clear_during_fetch_rejects_pending_put(self):
        def clearing(*args, **kwargs):
            self.assertTrue(Cache().clear())
            return self.backend()
        self.run.side_effect = clearing
        self.assertEqual(self.invoke()[0], 0)
        self.assertFalse(self.probe()["hit"])

    def test_failed_mutation_keeps_snapshot(self):
        self.invoke()
        self.run.side_effect = OSError("offline failure")
        self.assertEqual(self.invoke("mark", "--id", "1", "--seen")[0], 1)
        self.assertTrue(self.probe()["hit"])

    def test_corrupt_snapshot_is_miss(self):
        self.invoke()
        with contextlib.closing(sqlite3.connect(self.root / "yetimail/lists.sqlite3")) as db:
            db.execute("UPDATE messages SET value='[]'")
            db.commit()
        self.assertFalse(self.probe()["hit"])

    def test_cache_only_rejected_for_unrelated_commands(self):
        self.assertEqual(self.invoke("accounts", "--cache-only")[0], 1)
        self.run.assert_not_called()


class ListStorageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name) / "private"
        self.cache = Cache(self.directory)
        self.key = Key("context", "INBOX", "1", "1", "50")

    def store(self, cache=None, key=None, value=None):
        cache, key = cache or self.cache, key or self.key
        return cache.put(key, value or {"messages": []}, generation=cache.get(key).generation)

    def test_permissions_and_separate_body_storage(self):
        self.assertTrue(self.store())
        self.assertEqual(stat.S_IMODE(self.directory.stat().st_mode), 0o700)
        for file in self.directory.iterdir():
            self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o600)
        self.assertFalse((self.directory / "messages.sqlite3").exists())

    def test_expiry_limits_and_invalidation_epochs(self):
        now = [1000]
        cache = Cache(self.directory, clock=lambda: now[0], ttl_seconds=300, max_bytes=40, max_entry_bytes=30)
        self.assertTrue(self.store(cache))
        pending = cache.get(self.key)
        self.assertTrue(cache.invalidate("context"))
        self.assertFalse(cache.put(self.key, {}, generation=pending.generation))
        self.assertTrue(self.store(cache))
        now[0] += 300
        self.assertFalse(cache.get(self.key).hit)
        self.assertFalse(self.store(cache, value={"large": "x" * 40}))
        for page in ("1", "2", "3"):
            self.assertTrue(self.store(cache, Key("context", "INBOX", page, "1", "50")))
        self.assertFalse(cache.get(self.key).hit)
        self.assertTrue(cache.get(Key("context", "INBOX", "3", "1", "50")).hit)

    def test_unsafe_paths_rejected_without_touching_targets(self):
        victim = Path(self.temp.name) / "victim"
        victim.write_text("untouched")
        victim.chmod(0o644)
        self.directory.mkdir()
        for name in ("lists.sqlite3", "lists.sqlite3-wal", "lists.sqlite3-shm", "lists.sqlite3-journal", "lists-disabled"):
            with self.subTest(name=name):
                path = self.directory / name
                path.unlink(missing_ok=True)
                path.symlink_to(victim)
                self.assertIsNone(self.cache.get(self.key).generation)
                path.unlink()
                self.assertEqual(victim.read_text(), "untouched")
                self.assertEqual(stat.S_IMODE(victim.stat().st_mode), 0o644)
        database = self.directory / "lists.sqlite3"
        database.unlink(missing_ok=True)
        os.link(victim, database)
        self.assertIsNone(self.cache.get(self.key).generation)
        self.assertEqual(victim.read_text(), "untouched")

    def test_symlink_directory_and_corrupt_database_rejected(self):
        target = Path(self.temp.name) / "target"
        target.mkdir()
        self.directory.symlink_to(target, target_is_directory=True)
        self.assertIsNone(self.cache.get(self.key).generation)
        self.assertEqual(list(target.iterdir()), [])
        self.directory.unlink()
        self.directory.mkdir()
        (self.directory / "lists.sqlite3").write_bytes(b"not sqlite")
        self.assertIsNone(self.cache.get(self.key).generation)


if __name__ == "__main__":
    unittest.main()
