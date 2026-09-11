"""Offline account metadata and private Yetimail labels (no backend commands)."""

import fcntl
import json
import os
from pathlib import Path
import secrets
import stat

from mailbox_config import config_paths, merge, tomllib


class AccountSettingsError(Exception):
    pass


MAX_LABEL_LENGTH = 80
MAX_FILE_SIZE = 1024 * 1024
LABEL_FILE = "account-labels.json"


def text(value, maximum, allow_empty=False):
    if not isinstance(value, str):
        raise ValueError()
    value = value.strip()
    if (not value and not allow_empty) or len(value) > maximum or any(
            ord(char) < 32 or 127 <= ord(char) <= 159 for char in value):
        raise ValueError()
    return value


def validate_label(value):
    try:
        return text(value, MAX_LABEL_LENGTH, True)
    except ValueError:
        raise AccountSettingsError("Label must be text of at most 80 characters without controls.") from None


def validate_account(value):
    try:
        result = text(value, 256)
        if result != value:
            raise ValueError()
        return result
    except ValueError:
        raise AccountSettingsError("A nonempty account ID without controls is required.") from None


def configured_accounts(explicit):
    try:
        config = {}
        for path in config_paths(explicit):
            with path.open("rb") as source:
                raw = source.read(MAX_FILE_SIZE + 1)
            if len(raw) > MAX_FILE_SIZE:
                raise ValueError()
            config = merge(config, tomllib.loads(raw.decode("utf-8")))
        accounts = config["accounts"]
        if not isinstance(accounts, dict):
            raise ValueError()
        result = []
        for account_id, account in accounts.items():
            validate_account(account_id)
            if not isinstance(account, dict):
                raise ValueError()
            effective = dict(config)
            effective.update(account)
            # Backend names are constants, never values taken from auth, login,
            # commands, local paths, URLs, or arbitrary backend configuration.
            receiving = [name for name in ("imap", "gmail", "jmap", "msgraph", "maildir", "m2dir", "pimdir", "notmuch")
                         if name in effective]
            sending = [name for name in ("smtp", "sendmail", "gmail", "jmap", "msgraph")
                       if name in effective]
            for name in set(receiving + sending):
                if not isinstance(effective[name], dict):
                    raise ValueError()
            email = text(effective.get("email", ""), 1024, True)
            display_name = text(effective.get("display-name", ""), 1024, True)
            default = account.get("default", False)
            if not isinstance(default, bool):
                raise ValueError()
            result.append({"id": account_id, "label": "", "email": email,
                           "display-name": display_name, "default": default,
                           "receiving": receiving, "sending": sending})
        return result
    except (OSError, ValueError, TypeError, KeyError, RecursionError, AttributeError, AccountSettingsError):
        raise AccountSettingsError("Cannot read account metadata from Himalaya configuration.") from None


def _directory(create):
    home = os.environ.get("HOME", "")
    xdg = os.environ.get("XDG_CONFIG_HOME", "")
    if not os.path.isabs(xdg):
        if not os.path.isabs(home):
            raise ValueError()
        xdg = os.path.join(home, ".config")
    # Walk using directory descriptors: no symlink component is followed,
    # including when a directory is replaced concurrently.
    parts = Path(xdg).parts[1:] + ("yetimail",)
    if ".." in parts:
        raise ValueError()
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for index, part in enumerate(parts):
            try:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    os.close(fd)
                    return None
                try:
                    os.mkdir(part, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
            info = os.fstat(fd)
            if index >= len(parts) - 2 and (info.st_uid != os.getuid() or info.st_mode & 0o022):
                raise ValueError()
            if index == len(parts) - 1 and info.st_mode & 0o077:
                raise ValueError()
        return fd
    except BaseException:
        os.close(fd)
        raise


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError()
        result[key] = value
    return result


def _read_labels(directory):
    try:
        fd = os.open(LABEL_FILE, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    except FileNotFoundError:
        return {}
    with os.fdopen(fd, "rb") as source:
        info = os.fstat(source.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o177 or info.st_nlink != 1):
            raise ValueError()
        raw = source.read(MAX_FILE_SIZE + 1)
    if len(raw) > MAX_FILE_SIZE:
        raise ValueError()
    labels = json.loads(raw, object_pairs_hook=_unique_object)
    if not isinstance(labels, dict):
        raise ValueError()
    for key, value in labels.items():
        validate_account(key)
        if validate_label(value) != value or not value:
            raise ValueError()
    return labels


def labels(account_id=None, label=None):
    """Read, or atomically update under a directory lock; never repair unsafe files."""
    directory = None
    temporary = None
    try:
        directory = _directory(account_id is not None)
        if directory is None:
            return {}
        fcntl.flock(directory, fcntl.LOCK_EX if account_id is not None else fcntl.LOCK_SH)
        values = _read_labels(directory)
        if account_id is not None:
            if label:
                values[account_id] = label
            else:
                values.pop(account_id, None)
            raw = json.dumps(values, ensure_ascii=True).encode("utf-8")
            if len(raw) > MAX_FILE_SIZE:
                raise ValueError()
            temporary = ".labels-" + secrets.token_hex(16)
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=directory)
            with os.fdopen(fd, "wb") as output:
                output.write(raw)
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, LABEL_FILE, src_dir_fd=directory, dst_dir_fd=directory)
            temporary = None
            os.fsync(directory)
        return values
    except (OSError, ValueError, TypeError, RecursionError, AccountSettingsError):
        raise AccountSettingsError("Cannot access private Yetimail account labels safely.") from None
    finally:
        if directory is not None:
            if temporary is not None:
                try:
                    os.unlink(temporary, dir_fd=directory)
                except OSError:
                    pass
            os.close(directory)


def account_labels(demo=False):
    """Return only local friendly labels, without consulting mail configuration."""
    return {"labels": {} if demo else labels()}


def account_overview(config=None, demo=False):
    if demo:
        return {"accounts": [{"id": name, "label": "", "email": name + "@example.test",
                              "display-name": "Demo " + name.title(), "default": name == "personal",
                              "receiving": ["imap"], "sending": ["smtp"]}
                             for name in ("personal", "work")]}
    accounts = configured_accounts(config)
    saved = labels()
    for account in accounts:
        account["label"] = saved.get(account["id"], "")
    return {"accounts": accounts}


def set_account_label(account_id, label, demo=False):
    account_id = validate_account(account_id)
    label = validate_label(label)
    if not demo:
        labels(account_id, label)
    return {"id": account_id, "label": label}
