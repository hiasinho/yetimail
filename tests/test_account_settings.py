"""Account settings regression tests: isolated HOME, configs, and no subprocesses."""

import contextlib
from concurrent.futures import ThreadPoolExecutor
import io
import json
import os
from pathlib import Path
import runpy
import stat
import tempfile
import unittest
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / "bin/yetimail-helper"
helper = runpy.run_path(str(HELPER))
import account_settings as settings


class AccountSettingsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.config_home = self.home / "config"
        self.env = patch.dict(os.environ, {"HOME": str(self.home), "XDG_CONFIG_HOME": str(self.config_home)}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.backend = patch("subprocess.run", side_effect=AssertionError("No backend access permitted"))
        self.backend.start()
        self.addCleanup(self.backend.stop)
        self.config = self.home / "fixture.toml"
        self.config.write_text('[accounts.work]\nemail="work@example.test"\ndefault=true\n[accounts.work.imap]\nlogin="PRIVATE_LOGIN"\n')
        self.label_file = self.config_home / "yetimail" / settings.LABEL_FILE

    def invoke(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = helper["main"](list(args))
        return code, json.loads(output.getvalue())

    def overview(self):
        return self.invoke("accounts", "--config", str(self.config))

    def test_merged_allowlisted_metadata_and_no_config_mutations(self):
        self.config.write_text('''email="fallback@example.test"
display-name="Fallback"
[accounts.work]
default=true
email="work@example.test"
[accounts.work.imap]
host="PRIVATE_HOST"
login="PRIVATE_LOGIN"
[accounts.work.imap.auth]
type="password"
cmd="PRIVATE_CMD"
password="PRIVATE_PASSWORD"
[accounts.work.smtp]
url="PRIVATE_URL"
token="PRIVATE_TOKEN"
[accounts.personal]
email="personal@example.test"
[accounts.personal.maildir]
root-dir="PRIVATE_PATH"
''')
        extra = self.home / "extra.toml"
        extra.write_text('[accounts.work]\ndisplay-name="Work Name"\n[accounts.work.imap.auth]\ncmd="REPLACED_SECRET"\n')
        original = self.config.read_bytes()
        settings.set_account_label("work", " Office ")
        code, result = self.invoke("accounts", "--config", str(self.config) + ":" + str(extra))
        self.assertEqual(code, 0, result)
        self.assertEqual(result["accounts"][0], {"id": "work", "label": "Office", "email": "work@example.test",
                         "display-name": "Work Name", "default": True, "receiving": ["imap"], "sending": ["smtp"]})
        self.assertEqual(result["accounts"][1]["display-name"], "Fallback")
        serialized = json.dumps(result)
        for secret in ("PRIVATE", "REPLACED_SECRET", "auth", "login", "password", "cmd", "token", "root-dir"):
            self.assertNotIn(secret, serialized)
        self.assertEqual(self.config.read_bytes(), original)

    def test_default_config_resolution_and_environment_merge(self):
        default = self.config_home / "himalaya/config.toml"
        default.parent.mkdir(parents=True)
        default.write_bytes(self.config.read_bytes())
        self.assertEqual(self.invoke("accounts")[0], 0)
        extra = self.home / "extra.toml"
        extra.write_text('[accounts.work]\ndisplay-name="Merged"\n')
        with patch.dict(os.environ, {"HIMALAYA_CONFIG": str(self.config) + ":" + str(extra)}):
            self.assertEqual(self.invoke("accounts")[1]["accounts"][0]["display-name"], "Merged")
        self.assertFalse(self.label_file.parent.exists())

    def test_malformed_configs_are_generic_and_do_not_leak(self):
        for content in ('PRIVATE_SECRET invalid', 'accounts="PRIVATE_SECRET"', '[accounts]\nwork=1',
                        '[accounts.work]\nemail=5', '[accounts.work]\ndefault="PRIVATE_SECRET"',
                        '[accounts.work]\nimap="PRIVATE_SECRET"', '[accounts.work]\nemail="a\\nb"'):
            with self.subTest(content=content):
                self.config.write_text(content)
                code, result = self.overview()
                self.assertEqual(code, 1)
                self.assertEqual(result, {"error": "Cannot read account metadata from Himalaya configuration."})
        self.config.write_bytes(b'\xffPRIVATE_SECRET')
        self.assertEqual(self.overview()[0], 1)
        self.config.unlink()
        self.assertEqual(self.overview()[0], 1)

    def test_incompatible_merge_fails_closed(self):
        extra = self.home / "extra.toml"
        extra.write_text('[accounts.work]\nemail=42\n')
        self.assertEqual(self.invoke("accounts", "--config", str(self.config) + ":" + str(extra))[0], 1)
        self.assertEqual(self.invoke("accounts", "--config", str(self.config) + ":/missing")[0], 1)

    def test_labels_persist_trim_remove_and_preserve_other_accounts(self):
        self.assertEqual(self.invoke("account-label", "--account", "work", "--label", "  Office  "),
                         (0, {"id": "work", "label": "Office"}))
        inode = self.label_file.stat().st_ino
        settings.set_account_label("personal", "Home")
        self.assertNotEqual(inode, self.label_file.stat().st_ino)
        self.assertEqual(settings.labels(), {"work": "Office", "personal": "Home"})
        self.assertEqual(self.overview()[1]["accounts"][0]["label"], "Office")
        settings.set_account_label("work", "   ")
        self.assertEqual(settings.labels(), {"personal": "Home"})
        self.assertEqual(self.overview()[1]["accounts"][0]["label"], "")
        self.assertEqual(stat.S_IMODE(self.label_file.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.label_file.parent.stat().st_mode), 0o700)
        self.assertEqual(sorted(p.name for p in self.label_file.parent.iterdir()), [settings.LABEL_FILE])
        self.assertEqual(self.invoke("account-label", "--account=-work", "--label=--Personal"),
                         (0, {"id": "-work", "label": "--Personal"}))

    def test_label_and_account_validation(self):
        for value in (None, 4, False, [], {}, "x" * 81, "a\nb", "a\x00b", "a\x7fb"):
            with self.subTest(value=value), self.assertRaises(settings.AccountSettingsError):
                settings.set_account_label("work", value)
        for account in (None, 4, "", " ", " work", "a\nb", "x" * 257):
            with self.subTest(account=account), self.assertRaises(settings.AccountSettingsError):
                settings.set_account_label(account, "label")
        self.assertFalse(self.config_home.exists())
        self.assertEqual(settings.set_account_label("日本", "é" * 80)["label"], "é" * 80)

    def test_unsafe_label_files_fail_without_overwriting(self):
        settings.set_account_label("work", "Office")
        for content in ('not json PRIVATE', '[]', '{"work": 5}', '{"work":""}', '{"work":" untrimmed "}',
                        '{"work":"First","work":"Duplicate"}'):
            self.label_file.write_text(content)
            self.assertEqual(self.overview()[0], 1)
            self.assertEqual(self.invoke("account-label", "--account", "work", "--label", "New")[0], 1)
            self.assertEqual(self.label_file.read_text(), content)
        self.label_file.write_text('{}')
        self.label_file.chmod(0o644)
        self.assertEqual(self.overview()[0], 1)
        self.assertEqual(self.invoke("account-label", "--account", "work", "--label", "New")[0], 1)
        self.assertEqual(stat.S_IMODE(self.label_file.stat().st_mode), 0o644)

    def test_symlink_hardlink_fifo_and_directory_safety(self):
        settings.set_account_label("work", "Office")
        target = self.home / "target"
        target.write_text('{}')
        target.chmod(0o600)
        self.label_file.unlink()
        self.label_file.symlink_to(target)
        self.assertEqual(self.overview()[0], 1)
        self.assertEqual(self.invoke("account-label", "--account", "work", "--label", "New")[0], 1)
        self.assertEqual(target.read_text(), '{}')
        self.label_file.unlink()
        os.link(target, self.label_file)
        self.assertEqual(self.overview()[0], 1)
        self.label_file.unlink()
        os.mkfifo(self.label_file, 0o600)
        self.assertEqual(self.overview()[0], 1)
        self.label_file.unlink()
        self.label_file.parent.chmod(0o777)
        self.assertEqual(self.overview()[0], 1)
        self.label_file.parent.chmod(0o700)
        self.label_file.parent.rmdir()
        self.label_file.parent.symlink_to(self.home, target_is_directory=True)
        self.assertEqual(self.overview()[0], 1)
        self.assertEqual(self.invoke("account-label", "--account", "work", "--label", "New")[0], 1)

    def test_config_directory_symlink_and_permissions(self):
        target = self.home / "other"
        target.mkdir()
        self.config_home.symlink_to(target, target_is_directory=True)
        self.assertEqual(self.overview()[0], 1)
        self.config_home.unlink()
        self.config_home.mkdir(mode=0o777)
        self.config_home.chmod(0o777)
        self.assertEqual(self.overview()[0], 1)
        with patch("account_settings.os.getuid", return_value=-1):
            self.config_home.chmod(0o700)
            self.assertEqual(self.overview()[0], 1)

    def test_concurrent_updates_preserve_all_labels(self):
        with ThreadPoolExecutor(max_workers=8) as executor:
            list(executor.map(lambda number: settings.set_account_label(str(number), "Label " + str(number)), range(24)))
        self.assertEqual(settings.labels(), {str(number): "Label " + str(number) for number in range(24)})

    def test_oversized_files_fail_closed(self):
        self.config.write_bytes(b"#" + b"x" * settings.MAX_FILE_SIZE)
        self.assertEqual(self.overview()[0], 1)
        settings.set_account_label("work", "Office")
        self.label_file.write_bytes(b" " * (settings.MAX_FILE_SIZE + 1))
        with self.assertRaises(settings.AccountSettingsError):
            settings.labels()

    def test_failed_atomic_replace_preserves_original_and_cleans_temp(self):
        settings.set_account_label("work", "Original")
        with patch("account_settings.os.replace", side_effect=OSError("PRIVATE")):
            self.assertEqual(self.invoke("account-label", "--account", "work", "--label", "New"),
                             (1, {"error": "Cannot access private Yetimail account labels safely."}))
        self.assertEqual(settings.labels(), {"work": "Original"})
        self.assertEqual(list(self.label_file.parent.iterdir()), [self.label_file])

    def test_demo_never_reads_config_or_label_files(self):
        with patch("account_settings.config_paths", side_effect=AssertionError("Config accessed")), \
                patch("account_settings.labels", side_effect=AssertionError("Labels accessed")), \
                patch.dict(helper["main"].__globals__, check_literal_mailbox=lambda args: self.fail("Mailbox check")):
            self.assertEqual(self.invoke("accounts", "--config", "/must-not-read", "--demo")[0], 0)
            self.assertEqual(self.invoke("account-label", "--account", "work", "--label", " Demo ", "--demo"),
                             (0, {"id": "work", "label": "Demo"}))
        self.assertFalse(self.config_home.exists())

    def test_metadata_skips_mailbox_checks_and_label_write_skips_config(self):
        with patch.dict(helper["main"].__globals__, check_literal_mailbox=lambda args: self.fail("Mailbox check")):
            self.assertEqual(self.overview()[0], 0)
            with patch("account_settings.config_paths", side_effect=AssertionError("Config accessed")):
                self.assertEqual(self.invoke("account-label", "--account", "work", "--label", "Office")[0], 0)

    def test_account_labels_reads_only_local_storage_without_mutation(self):
        settings.set_account_label("work", "Office")
        settings.set_account_label("unconfigured", "Other")
        before = self.label_file.read_bytes()
        before_stat = self.label_file.stat()
        with patch("account_settings.config_paths", side_effect=AssertionError("Config accessed")), \
                patch.dict(helper["main"].__globals__, check_literal_mailbox=lambda args: self.fail("Mailbox check")):
            self.assertEqual(self.invoke("account-labels", "--config", "/must-not-read"),
                             (0, {"labels": {"work": "Office", "unconfigured": "Other"}}))
        self.assertEqual(self.label_file.read_bytes(), before)
        self.assertEqual(self.label_file.stat().st_ino, before_stat.st_ino)
        self.assertEqual(self.label_file.stat().st_mtime_ns, before_stat.st_mtime_ns)

    def test_account_labels_missing_storage_returns_empty_without_creating(self):
        with patch("account_settings.config_paths", side_effect=AssertionError("Config accessed")):
            self.assertEqual(self.invoke("account-labels"), (0, {"labels": {}}))
            self.assertFalse(self.config_home.exists())
            self.label_file.parent.mkdir(parents=True, mode=0o700)
            self.assertEqual(self.invoke("account-labels"), (0, {"labels": {}}))
            self.assertEqual(list(self.label_file.parent.iterdir()), [])

    def test_account_labels_unsafe_storage_returns_generic_error(self):
        settings.set_account_label("work", "Office")
        self.label_file.chmod(0o644)
        self.assertEqual(self.invoke("account-labels"),
                         (1, {"error": "Cannot access private Yetimail account labels safely."}))
        self.assertEqual(stat.S_IMODE(self.label_file.stat().st_mode), 0o644)

    def test_account_labels_demo_bypasses_filesystem(self):
        with patch("account_settings.config_paths", side_effect=AssertionError("Config accessed")), \
                patch("account_settings.labels", side_effect=AssertionError("Labels accessed")), \
                patch("account_settings.os.open", side_effect=AssertionError("Filesystem accessed")), \
                patch("pathlib.Path.open", side_effect=AssertionError("Filesystem accessed")):
            self.assertEqual(self.invoke("account-labels", "--demo", "--config", "/must-not-read"),
                             (0, {"labels": {}}))
        self.assertFalse(self.config_home.exists())

    def test_cli_rejects_inappropriate_options_before_access(self):
        options = [("--mailbox", ""), ("--mailbox", "Inbox"), ("--id", "1"), ("--destination", "Trash"),
                   ("--attachment", "anything"), ("--cache-identity", "a" * 64), ("--force",),
                   ("--page", "1"), ("--seen",), ("--unseen",)]
        with patch("account_settings.config_paths", side_effect=AssertionError("Config accessed")), \
                patch("account_settings.labels", side_effect=AssertionError("Labels accessed")):
            for command in (("accounts",), ("account-labels",), ("account-labels", "--demo"),
                            ("account-label", "--account", "work", "--label", "Office")):
                for option in options:
                    with self.subTest(command=command, option=option):
                        self.assertEqual(self.invoke(*command, *option)[0], 1)
            for args in (("accounts", "--label", "x"), ("accounts", "--account", "work"),
                         ("account-labels", "--account", "work"), ("account-labels", "--label", "x"),
                         ("account-labels", "--account", ""), ("account-labels", "--label", ""),
                         ("account-labels", "--demo", "--account", "work"),
                         ("account-labels", "--demo", "--label", "x"),
                         ("account-label",), ("account-label", "--account", "work"),
                         ("account-label", "--label", "x"), ("list", "--label", "x"),
                         ("cache-clear", "--label", "x"), ("account-label", "--account", " ", "--label", "x")):
                self.assertEqual(self.invoke(*args)[0], 1)


if __name__ == "__main__":
    unittest.main()
