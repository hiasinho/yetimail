"""Offline tests: no command here connects to an email account."""

import contextlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import unittest
from unittest.mock import patch


HELPER = Path(__file__).resolve().parents[1] / "bin" / "jitsmail-helper"
helper = runpy.run_path(str(HELPER))


class HelperTest(unittest.TestCase):
    def invoke(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = helper["main"](list(args))
        lines = output.getvalue().splitlines()
        self.assertEqual(len(lines), 1)
        return status, json.loads(lines[0])

    def test_list_schema_and_default_account(self):
        # Shape confirmed using Himalaya 2.1's offline json-schema command.
        envelopes = [
            {"id": "42", "subject": "Hello", "from": [
                {"name": "Alex", "email": "alex@example.test"},
                {"name": None, "email": "sam@example.test"}],
             "date": "2026-01-15T10:30:00Z", "flags": [{"raw": "\\Seen", "iana": "seen"}]},
            {"id": "43", "date": None},
            {"id": "44", "flags": [{"raw": "$seen"}]},
            {"id": "45", "flags": [{"raw": "\\Flagged", "iana": "flagged"}]},
        ]
        with patch("subprocess.run", return_value=subprocess.CompletedProcess(
                [], 0, json.dumps({"envelopes": envelopes}).encode(), b"")) as run:
            status, result = self.invoke("list")
        self.assertEqual(status, 0)
        self.assertEqual(result["account"], "Default")
        self.assertEqual(result["messages"][0], {
            "id": "42", "subject": "Hello", "from": "Alex <alex@example.test>, sam@example.test",
            "date": "2026-01-15T10:30:00Z", "unread": False,
        })
        self.assertEqual(result["messages"][1], {
            "id": "43", "subject": "", "from": "", "date": "", "unread": True,
        })
        self.assertEqual([m["unread"] for m in result["messages"]], [False, True, False, True])
        self.assertEqual(run.call_args.args[0], [
            "himalaya", "--json", "envelope", "list", "--page-size", "50"])
        self.assertEqual(run.call_args.kwargs["timeout"], 30)
        self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertFalse(run.call_args.kwargs.get("shell", False))

    def test_internationalized_sender_addresses(self):
        envelopes = [{"id": "1", "from": [
            {"name": "Alex", "email": "用户@example.test"},
            {"name": "李", "email": "li@example.test"},
        ]}]
        with patch("subprocess.run", return_value=subprocess.CompletedProcess(
                [], 0, json.dumps({"envelopes": envelopes}).encode(), b"")):
            status, result = self.invoke("list")
        self.assertEqual(status, 0)
        self.assertEqual(result["messages"][0]["from"],
                         "Alex <用户@example.test>, 李 <li@example.test>")

    def test_read_argv_keeps_id_literal_and_never_marks_seen(self):
        with patch("subprocess.run", return_value=subprocess.CompletedProcess(
                [], 0, b"Subject: Hello\r\n\r\nBody\r\n", b"")) as run:
            status, result = self.invoke("--account", "work", "read", "--config", "/tmp/a b.toml",
                                         "--id=--seen; touch /tmp/no")
        self.assertEqual(status, 0)
        self.assertEqual(result, {"id": "--seen; touch /tmp/no", "subject": "Hello",
                                  "from": "", "to": "", "date": "", "body": "Body"})
        self.assertEqual(run.call_args.args[0], [
            "himalaya", "--config=/tmp/a b.toml", "--account=work", "message", "read",
            "--raw", "--", "--seen; touch /tmp/no"])
        self.assertNotIn("--seen", run.call_args.args[0])
        self.assertNotIn("--json", run.call_args.args[0])

    def test_errors_are_one_json_object(self):
        for failure in (FileNotFoundError(), subprocess.TimeoutExpired("himalaya", 30), OSError()):
            with self.subTest(failure=failure), patch("subprocess.run", side_effect=failure):
                status, result = self.invoke("list")
                self.assertEqual(status, 1)
                self.assertEqual(set(result), {"error"})
        with patch("subprocess.run", return_value=subprocess.CompletedProcess([], 2, b"", b"SECRET")):
            status, result = self.invoke("list")
            self.assertEqual(status, 1)
            self.assertNotIn("SECRET", result["error"])

    def test_bad_envelopes(self):
        for raw in (b"not json", b"[]", b'{}', b'{"envelopes":{}}',
                    b'{"envelopes":[{}]}', b'{"envelopes":[{"id":"x","flags":["Seen"]}]}'):
            with self.subTest(raw=raw), patch("subprocess.run", return_value=
                    subprocess.CompletedProcess([], 0, raw, b"")):
                status, result = self.invoke("list")
                self.assertEqual(status, 1)
                self.assertIn("error", result)

    def test_validation_never_starts_himalaya(self):
        with patch("subprocess.run") as run:
            for args in ((), ("read",), ("list", "--id", "1"), ("delete",), ("--unknown",)):
                status, result = self.invoke(*args)
                self.assertEqual(status, 1)
                self.assertIn("error", result)
            run.assert_not_called()

    def test_demo_round_trip_never_starts_himalaya(self):
        with patch("subprocess.run", side_effect=AssertionError("must remain offline")):
            status, listing = self.invoke("list", "--demo", "--config", "/does/not/exist")
            self.assertEqual(status, 0)
            self.assertEqual(listing["account"], "Demo")
            self.assertTrue(listing["messages"])
            for envelope in listing["messages"]:
                status, message = self.invoke("read", "--demo", "--id", envelope["id"])
                self.assertEqual(status, 0)
                self.assertEqual(message["subject"], envelope["subject"])
                self.assertTrue(message["body"])
                self.assertEqual(set(message), {"id", "subject", "from", "to", "date", "body"})
            status, listing = self.invoke("list", "--demo", "--account", "Custom")
            self.assertEqual(listing["account"], "Custom")
            status, error = self.invoke("read", "--demo", "--id", "missing")
            self.assertEqual(status, 1)
            self.assertIn("error", error)

    def test_mime_plain_preferred_and_attachments_excluded(self):
        raw = b'''Subject: =?utf-8?b?SGVsbG8g8J+Riw==?=
From: =?utf-8?q?Ren=C3=A9?= <rene@example.test>
To: you@example.test
Date: Thu, 15 Jan 2026 10:30:00 +0000
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary=outer

--outer
Content-Type: text/plain
Content-Disposition: attachment; filename=ignore.txt

SECRET ATTACHMENT
--outer
Content-Type: multipart/alternative; boundary=inner

--inner
Content-Type: text/html; charset=utf-8

<p>HTML NOT PREFERRED</p>
--inner
Content-Type: text/plain; charset=iso-8859-1
Content-Transfer-Encoding: quoted-printable

Caf=E9 plain
--inner--
--outer--
'''
        result = helper["parse_message"](raw, "1")
        self.assertEqual(result["subject"], "Hello 👋")
        self.assertEqual(result["from"], "René <rene@example.test>")
        self.assertEqual(result["body"], "Café plain")

    def test_html_is_inert_text(self):
        raw = b'''Content-Type: text/html; charset=utf-8

<html><head><title>Hidden title</title><style>hidden css</style></head>
<body><p>Hello &amp; welcome</p><script>fetch('https://tracker.test')</script>
<img src="https://tracker.test/pixel"><p>Second <b>line</b><br>Next</p>
<iframe src="https://tracker.test">hidden frame</iframe></body></html>'''
        self.assertEqual(helper["parse_message"](raw, "1")["body"],
                         "Hello & welcome\nSecond line\nNext")

    def test_base64_unknown_charset_and_attachment_only(self):
        raw = b"Content-Type: text/plain; charset=unknown-codec\nContent-Transfer-Encoding: base64\n\nSGVsbG8="
        self.assertEqual(helper["parse_message"](raw, "1")["body"], "Hello")
        raw = b"Content-Type: application/octet-stream\nContent-Transfer-Encoding: base64\n\nSGVsbG8="
        self.assertEqual(helper["parse_message"](raw, "1")["body"], "")

    def test_executable_demo(self):
        result = subprocess.run([str(HELPER), "list", "--demo"], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["messages"])
        self.assertEqual(result.stderr, b"")


if __name__ == "__main__":
    unittest.main()
