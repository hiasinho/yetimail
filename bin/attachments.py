"""Inert MIME extraction and exclusive, private Downloads writes (no opener)."""
import hashlib
import os
from pathlib import Path
import re
import unicodedata
from email import policy


class AttachmentError(Exception):
    pass


def parts(message):
    pending = [message]
    while pending:
        part = pending.pop()
        if part.get_content_disposition() == "attachment" or part.get_filename() is not None:
            yield part
        elif part.get_content_maintype() == "multipart":
            pending.extend(reversed(list(part.iter_parts())))


def payload(part):
    data = part.get_payload(decode=True)
    if data is not None:
        return data
    if part.get_content_type() == "message/rfc822" and isinstance(part.get_payload(), list):
        return b"\r\n".join(child.as_bytes(policy=policy.SMTP) for child in part.get_payload())
    if part.is_multipart():
        return part.as_bytes(policy=policy.SMTP)
    raise AttachmentError("Attachment payload could not be decoded")


def safe_filename(name):
    name = re.split(r"[/\\]", name)[-1]
    name = "".join("_" if unicodedata.category(c).startswith("C") else c for c in name)
    name = name.strip(" .")
    if not name or name.startswith("-"):
        name = "attachment" + ("-" + name if name else "")
    suffix = Path(name).suffix
    suffix = suffix if len(suffix.encode("utf-8")) <= 16 else ""
    stem = name[:-len(suffix)] if suffix else name
    return stem.encode("utf-8")[:160].decode("utf-8", "ignore") + suffix


def can_open(name, mime, data):
    # Conservative allowlist; neither sender MIME nor filename is sufficient.
    if data.lstrip().startswith((b"#!", b"[Desktop Entry]", b"MZ", b"\x7fELF")):
        return False
    signatures = {
        ".pdf": ("application/pdf", b"%PDF-"),
        ".png": ("image/png", b"\x89PNG\r\n\x1a\n"),
        ".jpg": ("image/jpeg", b"\xff\xd8\xff"),
        ".jpeg": ("image/jpeg", b"\xff\xd8\xff"),
        ".gif": ("image/gif", b"GIF8"),
    }
    suffix = Path(name).suffix.lower()
    if suffix in signatures:
        expected_mime, magic = signatures[suffix]
        return mime == expected_mime and data.startswith(magic)
    if suffix == ".txt" and mime == "text/plain":
        try:
            text = data.decode("utf-8")
            return "[Desktop Entry]" not in text and all(c in "\t\r\n" or ord(c) >= 32 for c in text)
        except UnicodeError:
            pass
    return False


def record(part, index):
    data = payload(part)
    name = part.get_filename() or "attachment"
    mime = part.get_content_type()
    digest = hashlib.sha256(name.encode("utf-8") + b"\0" + mime.encode() + b"\0" + data).hexdigest()
    return {"id": f"{index}-{digest}", "name": name, "type": mime,
            "size": len(data) if part.get_payload(decode=True) is not None else None,
            "openable": can_open(safe_filename(name), mime, data)}


def metadata(message):
    return [record(part, index) for index, part in enumerate(parts(message), 1)]


def save(message, attachment_id):
    for index, part in enumerate(parts(message), 1):
        info = record(part, index)
        if info["id"] != attachment_id:
            continue
        data = payload(part)
        name = safe_filename(info["name"])
        directory = Path.home() / "Downloads"
        try:
            directory.mkdir(mode=0o700, exist_ok=True)
            # Pin the directory; reject a symlink at Downloads. Existing files,
            # including symlinks, are never overwritten or followed.
            directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                directory_stat = os.fstat(directory_fd)
                if directory_stat.st_uid != os.getuid() or directory_stat.st_mode & 0o022:
                    raise AttachmentError("Downloads must be owned by you and not writable by other users")
                suffix = Path(name).suffix
                stem = name[:-len(suffix)] if suffix else name
                for attempt in range(10000):
                    filename = name if attempt == 0 else f"{stem} ({attempt}){suffix}"
                    try:
                        fd = os.open(filename, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                     0o600, dir_fd=directory_fd)
                        break
                    except FileExistsError:
                        continue
                else:
                    raise AttachmentError("Too many files with this attachment name")
                try:
                    with os.fdopen(fd, "wb") as output:
                        output.write(data)
                except OSError:
                    os.unlink(filename, dir_fd=directory_fd)
                    raise
            finally:
                os.close(directory_fd)
        except OSError:
            raise AttachmentError("Could not save attachment in ~/Downloads") from None
        return {"attachment": attachment_id, "path": str(directory / filename),
                "openable": info["openable"]}
    raise AttachmentError("Attachment changed or is missing; reload the message")
