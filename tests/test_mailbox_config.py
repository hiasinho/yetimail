"""Alias-collision regressions: only private temporary TOML, never real config."""

import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

helper = runpy.run_path(str(Path(__file__).resolve().parents[1] / "bin/jitsmail-helper"))
from mailbox_config import MailboxConfigError, check_literal_mailbox


class MailboxConfigTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        self.environment = patch.dict(os.environ, {"HOME": str(self.home)}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.config = self.home / "primary.toml"
        self.config.write_text('[accounts.work]\ndefault = true\n')

    def check(self, mailbox="Sent", account="work", config=None):
        check_literal_mailbox(SimpleNamespace(mailbox=mailbox, account=account,
                                             config=str(self.config) if config is None else config))

    def test_global_alias_collision_and_exact_identity(self):
        self.config.write_text('[mailbox.alias]\nsent = "Sent Items"\n[accounts.work]\ndefault = true\n')
        for mailbox in ("Sent", "SENT", "sent"):
            with self.subTest(mailbox=mailbox), self.assertRaisesRegex(MailboxConfigError, "conflicts"):
                self.check(mailbox)
        self.check("Sent Items")
        self.check("opaque/日本")
        self.check("")
        self.config.write_text('[mailbox.alias]\nSent = "Sent"\n[accounts.work]\n')
        self.check("Sent")
        with self.assertRaisesRegex(MailboxConfigError, "conflicts"):
            self.check("SENT")

    def test_imap_inbox_case_variants_are_the_same_mailbox(self):
        self.config.write_text('[accounts.work.imap]\nhost="mail.example.test"\n'
                               '[accounts.work.mailbox.alias]\ninbox="INBOX"\nsent="SENT"\n')
        for mailbox in ("Inbox", "INBOX", "inbox", "iNbOx"):
            self.check(mailbox)
        with self.assertRaisesRegex(MailboxConfigError, "conflicts"):
            self.check("Sent")
        self.config.write_text('[accounts.work.imap]\nhost="mail.example.test"\n'
                               '[accounts.work.mailbox.alias]\ninbox="Other Inbox"\n')
        with self.assertRaisesRegex(MailboxConfigError, "conflicts"):
            self.check("Inbox")

    def test_inbox_case_equivalence_requires_unambiguous_imap(self):
        for backend in ("gmail", "jmap", "msgraph", "maildir", "m2dir", "pimdir"):
            for imap in ("", '[accounts.work.imap]\nhost="mail.example.test"\n'):
                self.config.write_text(imap + f'[accounts.work.{backend}]\n'
                                       '[accounts.work.mailbox.alias]\ninbox="INBOX"\n')
                with self.subTest(backend=backend, imap=bool(imap)), self.assertRaisesRegex(MailboxConfigError, "conflicts"):
                    self.check("Inbox")
        self.config.write_text('[accounts.work.mailbox.alias]\ninbox="INBOX"\n')
        with self.assertRaisesRegex(MailboxConfigError, "conflicts"):
            self.check("Inbox")

    def test_account_overrides_global_case_insensitively(self):
        self.config.write_text('[mailbox.alias]\nsent = "Wrong"\ntrash = "Wrong trash"\n'
                               '[accounts.work.mailbox.aliases]\nSENT = "Sent"\n'
                               '[accounts.other.mailbox.alias]\nsent = "Other"\n')
        self.check()
        with self.assertRaisesRegex(MailboxConfigError, "conflicts"):
            self.check("trash")
        with self.assertRaisesRegex(MailboxConfigError, "conflicts"):
            self.check(account="other")

    def test_merge_env_and_expanded_paths(self):
        self.config.write_text('[mailbox.alias]\nsent = "Wrong"\n[accounts.work]\ndefault = true\n')
        extra = self.home / "extra.toml"
        extra.write_text('[mailbox.alias]\nsent = "Sent"\n')
        os.environ["JITSMAIL_FIXTURE"] = str(extra)
        os.environ["HIMALAYA_CONFIG"] = "~/primary.toml:${JITSMAIL_FIXTURE}"
        args = SimpleNamespace(mailbox="Sent", account=None, config=None)
        check_literal_mailbox(args)
        # Explicit config takes precedence over HIMALAYA_CONFIG.
        with self.assertRaisesRegex(MailboxConfigError, "conflicts"):
            self.check()
        extra.write_text('[mailbox.alias]\nsent = "Wrong again"\n')
        with self.assertRaisesRegex(MailboxConfigError, "conflicts"):
            check_literal_mailbox(args)

    def test_merge_type_conflicts_and_missing_secondary_fail_closed(self):
        extra = self.home / "extra.toml"
        self.config.write_text('[accounts.work]\nmailbox.alias.sent="Sent"\n')
        extra.write_text('[accounts.work]\nmailbox.alias.sent=42\n')
        with self.assertRaisesRegex(MailboxConfigError, "Cannot verify"):
            self.check(config=str(self.config) + ":" + str(extra))
        extra.unlink()
        with self.assertRaisesRegex(MailboxConfigError, "Cannot verify"):
            self.check(config=str(self.config) + ":" + str(extra))

    def test_no_toml_parser_preserves_only_default_inbox(self):
        with patch("mailbox_config.tomllib", None):
            self.check("")
            with self.assertRaisesRegex(MailboxConfigError, "Cannot verify"):
                self.check()

    def test_default_account_rules(self):
        self.config.write_text('[accounts.work]\ndefault = true\nmailbox.alias.sent = "Wrong"\n'
                               '[accounts.other]\nmailbox.alias.sent = "Sent"\n')
        for name in (None, "", "default"):
            with self.subTest(name=name), self.assertRaisesRegex(MailboxConfigError, "conflicts"):
                self.check(account=name)
        self.check(account="other")
        for content in ('[accounts.work]\n', '[accounts.work]\ndefault=true\n[accounts.other]\ndefault=true\n'):
            self.config.write_text(content)
            with self.assertRaisesRegex(MailboxConfigError, "Cannot verify"):
                self.check(account=None)

    def test_default_locations_in_linux_priority_order(self):
        xdg = self.home / "xdg"
        os.environ["XDG_CONFIG_HOME"] = str(xdg)
        paths = [xdg / "himalaya/config.toml", self.home / ".config/himalaya/config.toml", self.home / ".himalayarc"]
        args = SimpleNamespace(mailbox="Sent", account=None, config=None)
        for path in paths:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('[accounts.work]\ndefault=true\nmailbox.alias.sent="Wrong"\n')
        for path in paths:
            with self.assertRaisesRegex(MailboxConfigError, "conflicts"):
                check_literal_mailbox(args)
            path.unlink()
        with self.assertRaisesRegex(MailboxConfigError, "Cannot verify"):
            check_literal_mailbox(args)

    def test_unsupported_or_ambiguous_config_fails_closed(self):
        for content in ('bad toml !', '[accounts.work.mailbox.alias]\nsent=42\n',
                        '[accounts.work.mailbox.alias]\nsent="Sent"\nSENT="Wrong"\n',
                        '[accounts.work.mailbox.alias]\n"sént"="Sent"\n',
                        '[accounts.work.mailbox]\nalias={}\naliases={}\n',
                        '[accounts.other]\n'):
            self.config.write_text(content)
            with self.subTest(content=content), self.assertRaisesRegex(MailboxConfigError, "Cannot verify"):
                self.check()
        for path in ("", "${MISSING}/config", "${HOME:-/fallback}/config", "~someone/config",
                     str(self.config) + ":/missing-secondary"):
            with self.subTest(path=path), self.assertRaisesRegex(MailboxConfigError, "Cannot verify"):
                self.check(config=path)

    def test_all_operations_reject_before_subprocess_or_attachment_save(self):
        self.config.write_text('[accounts.work]\ndefault=true\nmailbox.alias.sent="Sent Items"\n')
        attachment = helper["DEMO_MESSAGES"][0]["attachments"][0]["id"]
        cases = [("list",), ("read", "--id", "same"),
                 ("mark", "--id", "same", "--seen"),
                 ("save", "--id", "same", "--attachment", attachment)]
        with patch("subprocess.run", side_effect=AssertionError("backend must not run")), patch.dict(
                helper["main"].__globals__, save_attachment=lambda *args: self.fail("must not save")):
            for command in cases:
                output = io.StringIO()
                with self.subTest(command=command), contextlib.redirect_stdout(output):
                    status = helper["main"]([*command, "--mailbox", "Sent", "--account", "work",
                                             "--config", str(self.config)])
                self.assertEqual(status, 1)
                self.assertIn("conflicts", json.loads(output.getvalue())["error"])
                self.assertNotIn("Sent Items", output.getvalue())


if __name__ == "__main__":
    unittest.main()
