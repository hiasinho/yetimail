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
            "himalaya", "--json", "envelope", "list", "--page-size", "50", "--page", "1"])
        self.assertEqual(result["page"], 1)
        self.assertFalse(result["hasNext"])
        self.assertEqual(run.call_args.kwargs["timeout"], 30)
        self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertFalse(run.call_args.kwargs.get("shell", False))

    def test_pagination_command_and_conservative_next_page(self):
        for count in (0, 13, 50):
            with self.subTest(count=count), patch("subprocess.run", return_value=
                    subprocess.CompletedProcess([], 0, json.dumps({"envelopes": [
                        {"id": str(i)} for i in range(count)]}).encode(), b"")) as run:
                status, result = self.invoke("list", "--page", "3", "--account", "work")
                self.assertEqual(status, 0)
                self.assertEqual(result["page"], 3)
                self.assertEqual(result["hasNext"], count == 50)
                self.assertEqual(len(result["messages"]), count)
                self.assertEqual(run.call_args.args[0], ["himalaya", "--account=work",
                    "--json", "envelope", "list", "--page-size", "50", "--page", "3"])

    def test_mark_commands_require_explicit_account_and_keep_id_literal(self):
        for flag, operation, seen in (("--seen", "add", True), ("--unseen", "remove", False)):
            with self.subTest(flag=flag), patch("subprocess.run", return_value=
                    subprocess.CompletedProcess([], 0, b"", b"")) as run:
                status, result = self.invoke("mark", "--account=--work", "--config", "/tmp/a b",
                                             "--id=--flag; dangerous", flag)
                self.assertEqual(status, 0)
                self.assertEqual(result, {"id": "--flag; dangerous", "seen": seen})
                self.assertEqual(run.call_args.args[0], ["himalaya", "--config=/tmp/a b",
                    "--account=--work", "flag", operation, "--flag", "seen", "--", "--flag; dangerous"])
                self.assertFalse(run.call_args.kwargs.get("shell", False))

    def test_mark_failure_does_not_report_success_or_private_details(self):
        with patch("subprocess.run", return_value=
                subprocess.CompletedProcess([], 3, b"SECRET", b"PRIVATE")):
            status, result = self.invoke("mark", "--id", "1", "--account", "work", "--seen")
        self.assertEqual(status, 1)
        self.assertEqual(result, {"error": "Himalaya failed (exit 3)"})

    def test_pagination_and_mark_validation(self):
        cases = [
            ("list", "--page", value) for value in ("0", "-1", "abc", "1.5", "")
        ] + [
            ("read", "--id", "1", "--page", "1"),
            ("list", "--seen"), ("read", "--id", "1", "--unseen"),
            ("mark", "--id", "1", "--seen"),
            ("mark", "--id", "1", "--seen", "--account", ""),
            ("mark", "--id", "1", "--seen", "--account", "  "),
            ("mark", "--account", "work", "--seen"),
            ("mark", "--account", "work", "--id", "1"),
            ("mark", "--account", "work", "--id", "1", "--seen", "--unseen"),
            ("mark", "--account", "work", "--id", "1", "--seen", "--page", "1"),
        ]
        with patch("subprocess.run") as run:
            for args in cases:
                for demo in ((), ("--demo",)):
                    with self.subTest(args=args, demo=demo):
                        status, result = self.invoke(*args, *demo)
                        self.assertEqual(status, 1)
                        self.assertEqual(set(result), {"error"})
            run.assert_not_called()

    def test_demo_pages_and_explicit_mark_are_offline(self):
        with patch("subprocess.run", side_effect=AssertionError("must remain offline")):
            pages = [self.invoke("list", "--demo", "--page", str(page))[1]
                     for page in (1, 2, 3)]
            self.assertEqual([p["page"] for p in pages], [1, 2, 3])
            self.assertEqual([len(p["messages"]) for p in pages], [50, 13, 0])
            self.assertEqual([p["hasNext"] for p in pages], [True, False, False])
            ids = [m["id"] for page in pages for m in page["messages"]]
            self.assertEqual(len(set(ids)), 63)
            for id in (ids[0], ids[-1]):
                self.assertEqual(self.invoke("read", "--demo", "--id", id)[0], 0)
                for flag, seen in (("--seen", True), ("--unseen", False)):
                    status, result = self.invoke("mark", "--demo", "--account", "Demo", "--id", id, flag)
                    self.assertEqual(status, 0)
                    self.assertEqual(result, {"id": id, "seen": seen})
            status, result = self.invoke("mark", "--demo", "--account", "Demo", "--id", "missing", "--seen")
            self.assertEqual(status, 1)
            self.assertEqual(result, {"error": "Demo message not found"})

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
                                  "from": "", "to": "", "date": "", "body": "Body", "links": []})
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
                self.assertEqual(set(message), {"id", "subject", "from", "to", "date", "body", "links"})
                if envelope["id"] == "demo-1":
                    self.assertEqual(message["links"], [{"label": "example.com", "url":
                        "https://example.com/welcome?source=jitsmail-demo"}])
                    self.assertIn("[1]", message["body"])
                else:
                    self.assertEqual(message["links"], [])
            status, listing = self.invoke("list", "--demo", "--account", "Custom")
            self.assertEqual(listing["account"], "Custom")
            status, error = self.invoke("read", "--demo", "--id", "missing")
            self.assertEqual(status, 1)
            self.assertIn("error", error)

    def test_mime_html_preferred_and_attachments_excluded(self):
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

<p>HTML <a href="https://example.test/read">Read more</a></p>
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
        self.assertEqual(result["body"], "HTML Read more [1]")
        self.assertEqual(result["links"], [{"label": "Read more", "url": "https://example.test/read"}])

    def test_html_is_inert_text(self):
        raw = b'''Content-Type: text/html; charset=utf-8

<html><head><title>Hidden title</title><style>hidden css</style></head>
<body><p>Hello &amp; welcome</p><script>fetch('https://tracker.test')</script>
<img src="https://tracker.test/pixel"><p>Second <b>line</b><br>Next</p>
<iframe src="https://tracker.test">hidden frame</iframe></body></html>'''
        self.assertEqual(helper["parse_message"](raw, "1")["body"],
                         "Hello & welcome\nSecond line\nNext")

    def parse_body(self, body, content_type="text/html"):
        return helper["parse_message"](
            (f"Content-Type: {content_type}; charset=utf-8\n\n" + body).encode(), "1")

    def test_plaintext_links_preserve_prose_order_and_deduplicate(self):
        result = self.parse_body(
            "Hello!\n\nRead https://example.test/path?token=abc&x=1, then "
            "<http://other.test/a>. Again https://example.test/path?token=abc&x=1!\nBye.",
            "text/plain")
        self.assertEqual(result["body"], "Hello!\n\nRead [1], then <[2]>. Again [1]!\nBye.")
        self.assertEqual(result["links"], [
            {"label": "example.test", "url": "https://example.test/path?token=abc&x=1"},
            {"label": "other.test", "url": "http://other.test/a"},
        ])

    def test_plaintext_balanced_delimiters_and_trailing_punctuation(self):
        result = self.parse_body(
            "(https://example.test/wiki/Thing_(detail)). "
            "[https://example.test/a]; https://example.test/b?! "
            "https://[::1]:8080/a.", "text/plain")
        self.assertEqual(result["body"], "([1]). [[2]]; [3]?! [4].")
        self.assertEqual([link["url"] for link in result["links"]], [
            "https://example.test/wiki/Thing_(detail)", "https://example.test/a",
            "https://example.test/b", "https://[::1]:8080/a",
        ])

    def test_plaintext_explicit_delimiters_preserve_destination_punctuation(self):
        for opening, closing in (("<", ">"), ('"', '"'), ("'", "'")):
            for punctuation in ("!", "?", ".", ",", ";", ":", ")", "]", "}", "?!"):
                with self.subTest(delimiter=opening, punctuation=punctuation):
                    url = "https://example.test/reset?token=abc" + punctuation
                    result = self.parse_body(
                        f"Reset {opening}{url}{closing}. Done.", "text/plain")
                    self.assertEqual(result["body"], f"Reset {opening}[1]{closing}. Done.")
                    self.assertEqual(result["links"], [{"label": "example.test", "url": url}])

    def test_html_bare_urls_are_extracted_after_joining_inline_text(self):
        result = self.parse_body(
            '<p>Reset https://example.test/<b>reset?token=abc</b>.</p>'
            '<p>Again https<span>://example.</span>test/reset?token=abc '
            '<a href="https://other.test/">Other</a> '
            'https://last.test/<em>path</em>?x=1&amp;y=2.</p>')
        self.assertEqual(result["body"], "Reset [1].\nAgain [1] Other [2] [3].")
        self.assertEqual(result["links"], [
            {"label": "example.test", "url": "https://example.test/reset?token=abc"},
            {"label": "Other", "url": "https://other.test/"},
            {"label": "last.test", "url": "https://last.test/path?x=1&y=2"},
        ])

    def test_html_joined_text_keeps_blocks_separate_and_hidden_content_excluded(self):
        result = self.parse_body(
            '<p>https://example.test/<span hidden>tracking</span><b>help</b></p>'
            '<p>details</p>https://other.test/<br>not-a-path')
        self.assertEqual(result["body"], "[1]\ndetails\n[2]\nnot-a-path")
        self.assertEqual(result["links"], [
            {"label": "example.test", "url": "https://example.test/help"},
            {"label": "other.test", "url": "https://other.test/"},
        ])

    def test_html_anchor_mixed_prose_and_url_retains_prose(self):
        label = "Account suspended; visit https://example.test/help for details"
        result = self.parse_body(
            f'<a href="https://example.test/help">{label}</a>')
        self.assertEqual(result["body"], "Account suspended; visit [1] for details [1]")
        self.assertEqual(result["links"], [{"label": label, "url": "https://example.test/help"}])
        result = self.parse_body(
            f'<a href="https://other.test/action">{label}</a>')
        self.assertEqual(result["body"], "Account suspended; visit [2] for details [1]")
        self.assertEqual(result["links"], [
            {"label": label, "url": "https://other.test/action"},
            {"label": "example.test", "url": "https://example.test/help"},
        ])

    def test_html_anchor_labels_nested_markup_entities_and_duplicates(self):
        result = self.parse_body(
            '<p>See <a href="https://example.test/?a=1&amp;b=2">Read <b>the</b> &amp; learn</a>.</p>'
            '<p><a href="https://example.test/?a=1&amp;b=2">Again</a> or '
            'https://other.test/docs.</p>')
        self.assertEqual(result["body"], "See Read the & learn [1].\nAgain [1] or [2].")
        self.assertEqual(result["links"], [
            {"label": "Read the & learn", "url": "https://example.test/?a=1&b=2"},
            {"label": "other.test", "url": "https://other.test/docs"},
        ])

    def test_html_url_labels_empty_anchors_and_unclosed_anchor(self):
        url = "https://example.test/" + "long-token" * 100
        result = self.parse_body(
            f'<a href="{url}">{url}</a> '
            '<a href="http://other.test/path"></a> '
            '<a href="https://last.test/">Unclosed <em>label</em>')
        self.assertEqual(result["body"], "[1] [2] Unclosed label [3]")
        self.assertEqual(result["links"], [
            {"label": "example.test", "url": url},
            {"label": "other.test", "url": "http://other.test/path"},
            {"label": "Unclosed label", "url": "https://last.test/"},
        ])

    def test_non_web_and_malformed_anchor_destinations_are_not_actionable(self):
        urls = ["javascript:alert(1)", "data:text/html,hello", "file:///tmp/test",
                "mailto:you@example.test", "ftp://example.test", "//example.test/a",
                "/relative", "#fragment", "https://", "https:///missing-host",
                "https://[broken", "https://example.test:bad/", "https://example.test:99999/",
                "https://user:password@example.test/", "https://example.test/a&#10;b",
                "https://example.test/a b", "https://example.test\\evil.test/"]
        for url in urls:
            with self.subTest(url=url):
                result = self.parse_body(f'<a href="{url}">Readable label</a>')
                self.assertEqual(result["body"], "Readable label")
                self.assertEqual(result["links"], [])

    def test_html_hides_tracking_images_and_hidden_subtrees(self):
        result = self.parse_body('''<p>Visible</p>
<script>https://script.test/</script><style>https://style.test/</style>
<img src="https://pixel.test/" alt="https://alt.test/">
<div hidden><div><a href="https://hidden.test/">Hidden</a></div>Hidden too</div>
<span style="display: none !important"><b>https://css.test/</b></span>
<span style="color:red; visibility: hidden;">https://invisible.test/</span>
<div aria-hidden="true"><img src="https://pixel.test/">Invisible</div>
<template><a href="https://template.test/">Template</a></template>
<p><a href="https://visible.test/">Visible link</a></p>''')
        self.assertEqual(result["body"], "Visible\nVisible link [1]")
        self.assertEqual(result["links"], [{"label": "Visible link", "url": "https://visible.test/"}])

    def test_html_exact_targets_keep_punctuation_and_https_case(self):
        result = self.parse_body('<a href="HTTPS://example.test/a?!">Go</a>')
        self.assertEqual(result["body"], "Go [1]")
        self.assertEqual(result["links"], [{"label": "Go", "url": "HTTPS://example.test/a?!"}])

    def test_plaintext_charset_and_transfer_decoding_before_link_extraction(self):
        raw = (b"Content-Type: text/plain; charset=iso-8859-1\n"
               b"Content-Transfer-Encoding: quoted-printable\n\n"
               b"Caf=E9 https://example.test/?a=3D1&b=3D2")
        result = helper["parse_message"](raw, "1")
        self.assertEqual(result["body"], "Café [1]")
        self.assertEqual(result["links"], [{"label": "example.test", "url": "https://example.test/?a=1&b=2"}])

    def test_base64_unknown_charset_and_attachment_only(self):
        raw = b"Content-Type: text/plain; charset=unknown-codec\nContent-Transfer-Encoding: base64\n\nSGVsbG8="
        self.assertEqual(helper["parse_message"](raw, "1")["body"], "Hello")
        raw = b"Content-Type: application/octet-stream\nContent-Transfer-Encoding: base64\n\nSGVsbG8="
        result = helper["parse_message"](raw, "1")
        self.assertEqual(result["body"], "")
        self.assertEqual(result["links"], [])

    def test_executable_demo(self):
        result = subprocess.run([str(HELPER), "list", "--demo"], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["messages"])
        self.assertEqual(result.stderr, b"")


if __name__ == "__main__":
    unittest.main()
