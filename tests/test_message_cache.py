"""Standalone cache regressions: synthetic JSON and temporary directories only."""

from dataclasses import replace
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bin"))
from message_cache import (CacheKey, MAX_BYTES, MAX_ENTRY_BYTES, MessageCache,
                           TTL_SECONDS)


class MessageCacheTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.directory = self.home / "cache"
        self.now = 10000000.0
        self.cache = MessageCache(self.directory, clock=lambda: self.now)
        self.key = CacheKey("account/config/backend-identity", "Inbox", "42", "1")

    @property
    def database(self):
        return self.directory / "messages.sqlite3"

    def put(self, key=None, value=None, cache=None):
        key = key or self.key
        cache = cache or self.cache
        generation = cache.get(key).generation
        self.assertIsNotNone(generation)
        self.assertTrue(cache.put(key, value, generation=generation))

    def test_lazy_construction_and_default_limits(self):
        self.assertFalse(self.directory.exists())
        self.assertEqual(self.cache.ttl_seconds, 30 * 86400)
        self.assertEqual(self.cache.max_bytes, 100 * 1024 * 1024)
        self.assertEqual(self.cache.max_entry_bytes, 5 * 1024 * 1024)
        self.assertEqual((TTL_SECONDS, MAX_BYTES, MAX_ENTRY_BYTES),
                         (self.cache.ttl_seconds, self.cache.max_bytes, self.cache.max_entry_bytes))

    def test_json_roundtrip_null_and_persistence(self):
        self.assertFalse(self.cache.get(self.key).hit)
        for value in (None, False, [1, "日本", {"body": "synthetic\nmail"}], {"links": []}):
            with self.subTest(value=value):
                self.put(value=value)
                result = MessageCache(self.directory, clock=lambda: self.now).get(self.key)
                self.assertTrue(result.hit)
                self.assertEqual(result.value, value)

    def test_persistence_in_fresh_python_process(self):
        self.put(value="restart fixture")
        code = ("import sys; from message_cache import CacheKey, MessageCache; "
                "result = MessageCache(sys.argv[1], clock=lambda: 10000000).get("
                "CacheKey('account/config/backend-identity', 'Inbox', '42', '1')); "
                "assert result.hit and result.value == 'restart fixture'")
        result = subprocess.run([sys.executable, "-c", code, str(self.directory)],
                                cwd=Path(__file__).resolve().parents[1] / "bin",
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_key_separates_every_component_and_opaque_strings(self):
        self.put(value="original")
        for field in ("context", "mailbox", "message_id", "parser_version", "fingerprint"):
            key = replace(self.key, **{field: getattr(self.key, field) + "'\x00/日本"})
            self.assertFalse(self.cache.get(key).hit)
            self.put(key, field)
            self.assertEqual(self.cache.get(key).value, field)
        self.assertEqual(self.cache.get(self.key).value, "original")
        self.assertFalse(self.cache.get(replace(self.key, mailbox="inbox")).hit)

    def test_expiry_exact_boundary_and_reads_do_not_extend_it(self):
        self.put(value="old")
        self.now += TTL_SECONDS - 1
        self.assertTrue(self.cache.get(self.key).hit)
        self.now += 1
        self.assertFalse(self.cache.get(self.key).hit)
        with sqlite3.connect(self.database) as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM messages").fetchone()[0], 0)

    def test_replacement_resets_expiry(self):
        self.put(value="old")
        self.now += TTL_SECONDS - 1
        self.put(value="new")
        self.now += 2
        self.assertEqual(self.cache.get(self.key).value, "new")

    def test_lru_reads_and_overwrites_update_recency_even_with_same_clock(self):
        self.cache.max_bytes = 12  # Three JSON strings of four bytes each.
        keys = [replace(self.key, message_id=str(index)) for index in range(4)]
        for key in keys[:3]:
            self.put(key, "aa")
        self.cache.get(keys[0])
        self.put(keys[3], "bb")
        self.assertFalse(self.cache.get(keys[1]).hit)
        self.assertTrue(self.cache.get(keys[0]).hit)
        self.put(keys[2], "cc")
        self.put(keys[1], "dd")
        self.assertFalse(self.cache.get(keys[3]).hit)
        with sqlite3.connect(self.database) as connection:
            self.assertLessEqual(connection.execute("SELECT SUM(size) FROM messages").fetchone()[0], 12)

    def test_size_counts_utf8_json_and_skips_oversize_without_eviction(self):
        self.cache.max_entry_bytes = 6
        self.put(value="éé")  # Two quotes plus four UTF-8 bytes.
        token = self.cache.get(self.key).generation
        self.assertFalse(self.cache.put(self.key, "ééé", generation=token))
        self.assertEqual(self.cache.get(self.key).value, "éé")
        self.cache.max_bytes = 5
        self.assertFalse(self.cache.put(self.key, "éé", generation=token))

    def test_default_five_mib_boundary(self):
        token = self.cache.get(self.key).generation
        self.assertTrue(self.cache.put(self.key, "a" * (MAX_ENTRY_BYTES - 2), generation=token))
        self.assertFalse(self.cache.put(self.key, "a" * (MAX_ENTRY_BYTES - 1), generation=token))

    def test_invalid_json_values_fail_without_harming_entry(self):
        self.put(value="valid")
        token = self.cache.get(self.key).generation
        circular = []
        circular.append(circular)
        for value in (object(), float("nan"), float("inf"), circular, "\ud800"):
            self.assertFalse(self.cache.put(self.key, value, generation=token))
        self.assertEqual(self.cache.get(self.key).value, "valid")

    def test_targeted_invalidation_crosses_parser_versions_not_mailboxes(self):
        other_version = replace(self.key, parser_version="2")
        other_mailbox = replace(self.key, mailbox="Sent")
        other_context = replace(self.key, context="other")
        for key in (self.key, other_version, other_mailbox, other_context):
            self.put(key, "value")
        self.assertTrue(self.cache.invalidate(self.key.context, self.key.mailbox, self.key.message_id))
        self.assertFalse(self.cache.get(self.key).hit)
        self.assertFalse(self.cache.get(other_version).hit)
        self.assertTrue(self.cache.get(other_mailbox).hit)
        self.assertTrue(self.cache.get(other_context).hit)
        self.assertTrue(self.cache.invalidate(self.key.context))
        self.assertFalse(self.cache.get(other_mailbox).hit)
        self.assertTrue(self.cache.get(other_context).hit)

    def test_mailbox_invalidation_and_empty_string_is_not_wildcard(self):
        empty = replace(self.key, mailbox="")
        second = replace(self.key, message_id="43")
        for key in (self.key, empty, second):
            self.put(key)
        self.assertTrue(self.cache.invalidate(self.key.context, ""))
        self.assertFalse(self.cache.get(empty).hit)
        self.assertTrue(self.cache.get(self.key).hit)
        self.assertTrue(self.cache.invalidate(self.key.context, self.key.mailbox))
        self.assertFalse(self.cache.get(self.key).hit)
        self.assertFalse(self.cache.get(second).hit)
        self.assertTrue(self.cache.invalidate(self.key.context, message_id="42"))

    def test_invalidation_rejects_inflight_put_from_other_connection_even_on_miss(self):
        pending = self.cache.get(self.key)
        other = MessageCache(self.directory, clock=lambda: self.now)
        self.assertTrue(other.invalidate(self.key.context, self.key.mailbox, self.key.message_id))
        self.assertFalse(self.cache.put(self.key, "stale", generation=pending.generation))
        self.assertFalse(self.cache.get(self.key).hit)
        self.put(value="fresh")

    def test_scoped_races_preserve_unrelated_puts_and_cross_fingerprints(self):
        variants = [self.key, replace(self.key, fingerprint="changed"),
                    replace(self.key, parser_version="2"), replace(self.key, mailbox="alias")]
        unrelated = [replace(self.key, message_id="B"), replace(self.key, message_id="C"),
                     replace(self.key, context="other")]
        tokens = [(key, self.cache.get(key).generation) for key in variants + unrelated]
        other = MessageCache(self.directory, clock=lambda: self.now)
        self.assertTrue(other.invalidate(self.key.context, message_id=self.key.message_id))
        for key, token in tokens:
            self.assertEqual(self.cache.put(key, "late", generation=token), key in unrelated)
        for key in variants:
            self.put(key, "fresh")
        tokens = [(key, self.cache.get(key).generation) for key in unrelated]
        self.assertTrue(other.invalidate(self.key.context, self.key.mailbox))
        for key, token in tokens:
            self.assertEqual(self.cache.put(key, "late", generation=token), key.context == "other")

    def test_v1_migration_discards_legacy_keys_and_rotates_global_generation(self):
        self.directory.mkdir()
        with sqlite3.connect(self.database) as connection:
            connection.execute("CREATE TABLE state (id INTEGER PRIMARY KEY, generation TEXT)")
            connection.execute("INSERT INTO state VALUES (1, 'old-token')")
            connection.execute("CREATE TABLE messages (message_id TEXT)")
            connection.execute("INSERT INTO messages VALUES ('42' || char(0) || 'nonce')")
            connection.execute("PRAGMA user_version=1")
        result = self.cache.get(self.key)
        self.assertFalse(result.hit)
        self.assertIsNotNone(result.generation)
        self.assertFalse(self.cache.put(self.key, "stale", generation="old-token"))
        self.put(value="new schema")
        with sqlite3.connect(self.database) as connection:
            self.assertEqual(connection.execute("PRAGMA user_version").fetchone()[0], 2)
            self.assertEqual(connection.execute("SELECT message_id, fingerprint FROM messages").fetchall(), [("42", "")])

    def test_failed_invalidation_disables_hits_and_pending_puts_until_clear(self):
        self.put(value="old")
        token = self.cache.get(self.key).generation
        self.cache.timeout = 0.01
        with sqlite3.connect(self.database) as connection:
            connection.execute("BEGIN IMMEDIATE")
            self.assertFalse(self.cache.invalidate(self.key.context, message_id="42"))
        self.assertFalse(self.cache.get(self.key).hit)
        self.assertFalse(self.cache.put(self.key, "late", generation=token))
        self.assertTrue(self.cache.clear())
        self.assertFalse(self.cache.put(self.key, "late", generation=token))
        self.put(value="recovered")

    def test_clear_rejects_inflight_put_and_removes_all_contexts(self):
        self.put(value="first")
        other = replace(self.key, context="other")
        self.put(other, "second")
        token = self.cache.get(self.key).generation
        self.assertTrue(self.cache.clear())
        self.assertFalse(self.cache.get(self.key).hit)
        self.assertFalse(self.cache.get(other).hit)
        self.assertFalse(self.cache.put(self.key, "stale", generation=token))

    def test_disable_fails_closed_until_successful_clear(self):
        self.put(value="secret")
        self.assertTrue(self.cache.disable())
        self.assertIsNone(self.cache.get(self.key).generation)
        self.assertFalse(self.cache.put(self.key, "stale", generation="anything"))
        self.assertTrue((self.directory / "disabled").exists())
        self.assertTrue(self.cache.clear())
        self.assertFalse((self.directory / "disabled").exists())
        self.assertFalse(self.cache.get(self.key).hit)

    def test_recreated_database_does_not_reuse_generation(self):
        token = self.cache.get(self.key).generation
        self.database.unlink()
        self.assertFalse(self.cache.put(self.key, "stale", generation=token))
        self.assertFalse(self.cache.put(self.key, "stale", generation=None))

    def test_private_permissions_and_wal_sidecars(self):
        self.directory.mkdir(mode=0o755)
        self.database.touch(mode=0o644)
        self.put(value="secret fixture")
        self.assertEqual(stat.S_IMODE(self.directory.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.database.stat().st_mode), 0o600)
        # Keep a reader open so WAL sidecars survive another cache connection.
        connection = sqlite3.connect(self.database)
        self.addCleanup(connection.close)
        connection.execute("SELECT * FROM messages").fetchall()
        self.put(value="next fixture")
        for suffix in ("-wal", "-shm"):
            sidecar = Path(str(self.database) + suffix)
            self.assertTrue(sidecar.exists())
            self.assertEqual(stat.S_IMODE(sidecar.stat().st_mode), 0o600)

    def test_xdg_path_and_relative_xdg_fallback(self):
        with patch.dict(os.environ, {"HOME": str(self.home), "XDG_CACHE_HOME": str(self.home / "xdg")}):
            self.put(cache=MessageCache(clock=lambda: self.now))
            self.assertTrue((self.home / "xdg/jitsmail/messages.sqlite3").exists())
        with patch.dict(os.environ, {"HOME": str(self.home), "XDG_CACHE_HOME": "relative"}):
            self.put(cache=MessageCache(clock=lambda: self.now))
            self.assertTrue((self.home / ".cache/jitsmail/messages.sqlite3").exists())

    def test_symlink_directory_database_and_sidecar_are_rejected(self):
        target = self.home / "target"
        target.mkdir()
        self.directory.symlink_to(target, target_is_directory=True)
        self.assertIsNone(self.cache.get(self.key).generation)
        self.assertEqual(list(target.iterdir()), [])
        self.directory.unlink()
        self.directory.mkdir()
        victim = target / "victim"
        victim.write_text("untouched")
        for path in (self.database, Path(str(self.database) + "-wal")):
            path.symlink_to(victim)
            self.assertIsNone(self.cache.get(self.key).generation)
            self.assertEqual(victim.read_text(), "untouched")
            path.unlink()

    def test_hardlinked_database_is_rejected(self):
        self.directory.mkdir()
        victim = self.home / "victim"
        victim.write_text("untouched")
        os.link(victim, self.database)
        self.assertIsNone(self.cache.get(self.key).generation)
        self.assertEqual(victim.read_text(), "untouched")

    def test_corrupt_database_and_filesystem_failure_fall_back(self):
        self.directory.mkdir()
        self.database.write_bytes(b"not sqlite")
        self.assertIsNone(self.cache.get(self.key).generation)
        self.assertFalse(self.cache.put(self.key, {}, generation="token"))
        self.assertFalse(self.cache.invalidate(self.key.context))
        self.assertFalse(self.cache.clear())
        with patch("message_cache.os.open", side_effect=PermissionError):
            self.assertIsNone(self.cache.get(self.key).generation)

    def test_corrupt_entry_is_removed_and_can_be_refetched(self):
        self.put(value="valid")
        with sqlite3.connect(self.database) as connection:
            connection.execute("UPDATE messages SET value='invalid json'")
        result = self.cache.get(self.key)
        self.assertFalse(result.hit)
        self.assertIsNotNone(result.generation)
        self.assertTrue(self.cache.put(self.key, "refetched", generation=result.generation))

    def test_locked_database_falls_back_and_recovers(self):
        self.put(value="valid")
        self.cache.timeout = 0.01
        with sqlite3.connect(self.database) as connection:
            connection.execute("BEGIN IMMEDIATE")
            self.assertIsNone(self.cache.get(self.key).generation)
            self.assertFalse(self.cache.clear())
        self.assertEqual(self.cache.get(self.key).value, "valid")

    def test_unknown_schema_is_not_overwritten(self):
        self.put(value="valid")
        with sqlite3.connect(self.database) as connection:
            connection.execute("PRAGMA user_version=999")
        self.assertIsNone(self.cache.get(self.key).generation)
        self.assertFalse(self.cache.clear())
        with sqlite3.connect(self.database) as connection:
            self.assertEqual(connection.execute("PRAGMA user_version").fetchone()[0], 999)
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM messages").fetchone()[0], 1)


if __name__ == "__main__":
    unittest.main()
