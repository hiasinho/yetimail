"""Attachment security tests; only temporary homes and mocked backend calls."""
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from email import policy
from email.message import EmailMessage
from email.parser import BytesParser

helper = runpy.run_path(str(Path(__file__).resolve().parents[1] / "bin/yetimail-helper"))
import attachments


class AttachmentTest(unittest.TestCase):
    def message(self, name="notes.txt", data=b"Hello", mime="text/plain"):
        part = EmailMessage()
        part.set_type(mime)
        part.add_header("Content-Disposition", "attachment", filename=name)
        part.set_payload(data)
        return part

    def invoke(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = helper["main"](list(args))
        return code, json.loads(output.getvalue())

    def test_decoding_and_private_unique_files(self):
        message = BytesParser(policy=policy.default).parsebytes(
            b'Content-Type: application/octet-stream\nContent-Disposition: attachment; filename="a.bin"\n'
            b'Content-Transfer-Encoding: base64\n\nAAEC/w==')
        identifier = attachments.metadata(message)[0]["id"]
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, HOME=home):
            first = Path(attachments.save(message, identifier)["path"])
            second = Path(attachments.save(message, identifier)["path"])
            self.assertEqual(first.read_bytes(), b"\0\1\2\xff")
            self.assertEqual(second.read_bytes(), first.read_bytes())
            self.assertNotEqual(first, second)
            self.assertEqual(first.stat().st_mode & 0o777, 0o600)
            self.assertEqual(first.parent, Path(home) / "Downloads")

    def test_hostile_filenames_and_symlink_collisions(self):
        names = ["../../outside.txt", "/etc/passwd", r"C:\outside\notes.txt", "..", ".", "",
                 "--option.txt", "bad\n\x00\u202efile.txt", "日" * 300 + ".txt", "$(touch pwned).txt"]
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, HOME=home):
            for name in names:
                # Control bytes can't be inserted by EmailMessage's header API;
                # exercise the filename sanitizer directly as well.
                safe = attachments.safe_filename(name)
                self.assertNotIn("/", safe)
                self.assertNotIn("\\", safe)
                self.assertFalse(safe.startswith((".", "-")))
                self.assertLess(len(safe.encode()), 200)
                self.assertFalse(any(ord(c) < 32 for c in safe))
            message = self.message("../../outside.txt")
            identifier = attachments.metadata(message)[0]["id"]
            downloads = Path(home) / "Downloads"
            downloads.mkdir()
            victim = Path(home) / "victim"
            victim.write_text("untouched")
            (downloads / "outside.txt").symlink_to(victim)
            result = attachments.save(message, identifier)
            self.assertEqual(victim.read_text(), "untouched")
            self.assertEqual(Path(result["path"]).name, "outside (1).txt")
            self.assertEqual(Path(result["path"]).parent, downloads)

    def test_downloads_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, HOME=home):
            target = Path(home) / "other"
            target.mkdir()
            (Path(home) / "Downloads").symlink_to(target)
            message = self.message()
            with self.assertRaises(attachments.AttachmentError):
                attachments.save(message, attachments.metadata(message)[0]["id"])
            self.assertEqual(list(target.iterdir()), [])

    def test_untrusted_directory_and_write_failure(self):
        message = self.message()
        identifier = attachments.metadata(message)[0]["id"]
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, HOME=home):
            directory = Path(home) / "Downloads"
            directory.mkdir()
            directory.chmod(0o777)
            with self.assertRaises(attachments.AttachmentError):
                attachments.save(message, identifier)
            self.assertEqual(list(directory.iterdir()), [])
            directory.chmod(0o700)
            original_fdopen = os.fdopen
            class FailingOutput:
                def __init__(self, fd):
                    self.output = original_fdopen(fd, "wb")
                def __enter__(self):
                    return self
                def write(self, data):
                    self.output.write(data[:1])
                    raise OSError("PRIVATE disk diagnostic")
                def __exit__(self, *args):
                    self.output.close()
            with patch("attachments.os.fdopen", side_effect=lambda fd, mode: FailingOutput(fd)):
                with self.assertRaisesRegex(attachments.AttachmentError, "Could not save attachment"):
                    attachments.save(message, identifier)
            self.assertEqual(list(directory.iterdir()), [], "partial file cleaned up")

    def test_changed_missing_and_duplicate_attachments(self):
        message = self.message()
        identifier = attachments.metadata(message)[0]["id"]
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, HOME=home):
            for changed in (self.message(data=b"Changed"), self.message(name="other.txt"), self.message(mime="application/octet-stream")):
                with self.assertRaises(attachments.AttachmentError):
                    attachments.save(changed, identifier)
            self.assertFalse((Path(home) / "Downloads").exists())
        outer = EmailMessage()
        outer.make_mixed()
        outer.attach(message)
        outer.attach(self.message())
        info = attachments.metadata(outer)
        self.assertNotEqual(info[0]["id"], info[1]["id"])

    def test_runnable_and_unsupported_types_are_save_only(self):
        for name, mime, data in [
            ("run.sh", "text/plain", b"echo hello"),
            ("run.desktop", "text/plain", b"[Desktop Entry]\nExec=evil"),
            ("run.txt", "text/plain", b"  #!/bin/sh\necho hi"),
            ("run.txt", "text/plain", b"# comment\n[Desktop Entry]\nExec=evil"),
            ("run.txt", "text/plain", b"\x7fELF..."),
            ("run.pdf", "application/pdf", b"MZ..."),
            ("run.pdf.sh", "application/pdf", b"%PDF-1.0"),
            ("run.py", "text/x-python", b"print('hi')"),
            ("run.html", "text/html", b"<script>evil()</script>"),
            ("run.svg", "image/svg+xml", b"<svg/>"),
            ("run.txt", "application/x-executable", b"hello"),
            ("run.pdf", "application/pdf", b"not a pdf"),
        ]:
            with self.subTest(name=name, data=data):
                self.assertFalse(attachments.can_open(name, mime, data))
        for name, mime, data in [("notes.txt", "text/plain", b"Hello"),
                                 ("doc.PDF", "application/pdf", b"%PDF-1.7"),
                                 ("photo.png", "image/png", b"\x89PNG\r\n\x1a\n")]:
            self.assertTrue(attachments.can_open(name, mime, data))

    def test_attached_email_saved_without_nested_extraction(self):
        raw = b'Content-Type: message/rfc822\nContent-Disposition: attachment; filename="mail.eml"\n\nSubject: Hello\n\nNested body'
        message = BytesParser(policy=policy.default).parsebytes(raw)
        info = attachments.metadata(message)
        self.assertEqual(len(info), 1)
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, HOME=home):
            saved = attachments.save(message, info[0]["id"])
            self.assertIn(b"Subject: Hello", Path(saved["path"]).read_bytes())
            self.assertFalse(saved["openable"])

    def test_save_cli_is_read_only_scoped_and_never_opens(self):
        raw = self.message().as_bytes()
        identifier = helper["parse_message"](raw, "x")["attachments"][0]["id"]
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, HOME=home), patch(
                "subprocess.run", return_value=subprocess.CompletedProcess([], 0, raw, b"")) as run:
            code, result = self.invoke("save", "--account=--work", "--config=/tmp/a b", "--id=--seen; evil", "--attachment", identifier)
            self.assertEqual(code, 0, result)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0], ["himalaya", "--config=/tmp/a b", "--account=--work", "message", "read", "--raw", "--", "--seen; evil"])
            self.assertEqual(result["id"], "--seen; evil")
            self.assertTrue(Path(result["path"]).is_file())

    def test_validation_and_demo_do_not_start_backend(self):
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, HOME=home), patch("subprocess.run") as run:
            for args in [("save",), ("save", "--id", "1"), ("save", "--id", "1", "--attachment", "../1"),
                         ("read", "--id", "1", "--attachment", "1")]:
                self.assertEqual(self.invoke(*args)[0], 1)
            code, message = self.invoke("read", "--demo", "--id", "demo-1")
            code, result = self.invoke("save", "--demo", "--id", "demo-1", "--attachment", message["attachments"][0]["id"])
            self.assertEqual(code, 0, result)
            self.assertEqual(Path(result["path"]).read_text(), "Welcome to Yetimail! This is an offline demo attachment.\n")
            run.assert_not_called()
