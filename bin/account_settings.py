"""Offline account metadata, conservative editing, and private Yetimail labels."""

import copy
import hashlib
import re
import fcntl
import json
import os
from pathlib import Path
import secrets
import stat

from mailbox_config import aliases, config_paths, merge, tomllib


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


def configured_accounts(explicit, snapshot=None):
    try:
        config = {}
        if snapshot is not None:
            config = tomllib.loads(snapshot.decode("utf-8"))
        else:
            for path in config_paths(explicit):
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                with os.fdopen(fd, "rb") as source:
                    if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                        raise ValueError()
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
                           "receiving": receiving, "sending": sending,
                           "mailbox-mappings": {role: text(aliases(account).get(role, ""), 1024, True) for role in ROLES}})
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
                              "receiving": ["imap"], "sending": ["smtp"],
                              "revision": DEMO_REVISION, "editable": True, "editable-reason": "",
                              "mailbox-mappings": {role: "" for role in ROLES}}
                             for name in ("personal", "work")]}
    snapshot = None
    revision = ""
    editable = False
    try:
        directory, name = _config_directory(config)
        try:
            raw, _ = _read_config(directory, name)
            snapshot = raw
            document = tomllib.loads(raw.decode("utf-8"))
            _layout(raw, document)
            revision = hashlib.sha256(raw).hexdigest()
            editable = True
        finally:
            os.close(directory)
    except (OSError, ValueError, TypeError, KeyError, AttributeError, RecursionError):
        pass
    accounts = configured_accounts(config, snapshot)
    saved = labels()
    for account in accounts:
        account["label"] = saved.get(account["id"], "")
        account.update({"revision": revision, "editable": editable,
                        "editable-reason": "" if editable else EDIT_ERROR})
    return {"accounts": accounts}


def set_account_label(account_id, label, demo=False):
    account_id = validate_account(account_id)
    label = validate_label(label)
    if not demo:
        labels(account_id, label)
    return {"id": account_id, "label": label}


ROLES = ("inbox", "sent", "drafts", "trash", "archive")
DEMO_REVISION = "d" * 64
EDIT_ERROR = "Cannot edit this Himalaya configuration safely."
SAVE_ERROR = "Cannot save account settings safely; reopen Settings and try again."


def _config_parent(path):
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError()
    directory = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for component in path.parts[1:-1]:
            child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
            info = os.fstat(directory)
            if info.st_uid not in (0, os.getuid()) or (info.st_mode & 0o022 and not info.st_mode & stat.S_ISVTX):
                raise ValueError()
        info = os.fstat(directory)
        if info.st_uid != os.getuid() or info.st_mode & 0o022:
            raise ValueError()
        return directory
    except BaseException:
        os.close(directory)
        raise


def _config_directory(explicit):
    paths = config_paths(explicit)
    if len(paths) != 1:
        raise ValueError()
    path = paths[0]
    value = explicit if explicit is not None else os.environ.get("HIMALAYA_CONFIG")
    original = (Path(os.path.abspath(os.path.expanduser(os.path.expandvars(value))))
                if value is not None else path)

    # Dotfile managers commonly make config.toml itself a symlink. Validate its
    # containing directory without following links, then edit the resolved,
    # owner-controlled regular target. Symlinked directories stay rejected.
    original_directory = _config_parent(original)
    try:
        info = os.stat(original.name, dir_fd=original_directory, follow_symlinks=False)
        if stat.S_ISLNK(info.st_mode):
            if info.st_uid != os.getuid():
                raise ValueError()
            link = Path(os.readlink(original.name, dir_fd=original_directory))
            if ".." in link.parts:
                raise ValueError()
            target = link if link.is_absolute() else original.parent / link
            target = Path(os.path.abspath(target))
            # Explicit paths were canonicalized by config_paths. A mismatch
            # means the target traversed another symlink, which we do not trust.
            if value is not None and target != path:
                raise ValueError()
            path = target
        elif original != path:
            raise ValueError()
    finally:
        os.close(original_directory)

    return _config_parent(path), path.name


def _read_config(directory, name):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    with os.fdopen(fd, "rb") as source:
        info = os.fstat(source.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_nlink != 1 or info.st_mode & 0o022):
            raise ValueError()
        raw = source.read(MAX_FILE_SIZE + 1)
    if len(raw) > MAX_FILE_SIZE:
        raise ValueError()
    return raw, info


def _restore_backup(directory, backup_name, name, info):
    os.replace(backup_name, name, src_dir_fd=directory, dst_dir_fd=directory)
    fd = os.open(name, os.O_WRONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    try:
        os.fchown(fd, info.st_uid, info.st_gid)
        os.fchmod(fd, stat.S_IMODE(info.st_mode))
        os.fsync(fd)
    finally:
        os.close(fd)


def _key_path(key):
    value = tomllib.loads(key + " = 0")
    result = []
    while isinstance(value, dict) and len(value) == 1:
        name, value = next(iter(value.items()))
        result.append(name)
    if value != 0:
        raise ValueError()
    return tuple(result)


def _layout(raw, document):
    # Deliberately bounded TOML subset: explicit account tables and single-line
    # assignments. Parsing each statement prevents apparent headers in strings
    # from being mistaken for editable fields. Unknown statements stay verbatim.
    lines = raw.decode("utf-8").splitlines(keepends=True)
    tables = {}
    fields = {}
    table = ()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("["):
            match = re.fullmatch(r"\[([^\[\]]+)\]\s*(?:#.*)?", stripped)
            if not match:
                raise ValueError()
            table = _key_path(match[1])
            if table in tables:
                raise ValueError()
            tables[table] = index
            continue
        # Find the assignment delimiter outside quoted key text.
        match = re.match(r'((?:[^="\']|"(?:[^"\\]|\\.)*"|\'[^\']*\')+)=', line)
        if not match:
            raise ValueError()
        key = _key_path(match[1].strip())
        parsed = tomllib.loads(line)
        value = parsed
        for component in key:
            value = value[component]
        path = table + key
        if path in fields:
            raise ValueError()
        # Locate trailing comments by testing complete value prefixes. This
        # handles # inside strings without touching credential text.
        start = match.end()
        end = len(line.rstrip("\r\n"))
        for position in range(start, end):
            if line[position] == "#":
                try:
                    if tomllib.loads(line[:position]) == parsed:
                        end = position
                        break
                except ValueError:
                    pass
        while end > start and line[end - 1].isspace():
            end -= 1
        while start < end and line[start].isspace():
            start += 1
        fields[path] = (index, start, end)
    for name, account in document["accounts"].items():
        base = ("accounts", name)
        if base not in tables or not isinstance(account, dict):
            raise ValueError()
        mappings = aliases(account)
        if any(key != key.lower() for key in account.get("mailbox", {}).get("alias", account.get("mailbox", {}).get("aliases", {}))):
            raise ValueError()
        for key in ("email", "display-name", "default"):
            if key in account and base + (key,) not in fields:
                raise ValueError()
        spelling = "aliases" if "aliases" in account.get("mailbox", {}) else "alias"
        for role in mappings:
            if base + ("mailbox", spelling, role) not in fields:
                raise ValueError()
        # Inline mailbox tables cannot be extended without rewriting them.
        if base + ("mailbox",) in fields or base + ("mailbox", spelling) in fields:
            raise ValueError()
    return lines, tables, fields


def _render(raw, document, account_id, email, display_name, default, mappings):
    lines, tables, fields = _layout(raw, document)
    expected = copy.deepcopy(document)
    account = expected["accounts"][account_id]
    changes = {}
    base = ("accounts", account_id)
    for key, value in (("email", email), ("display-name", display_name), ("default", default)):
        account[key] = value
        changes[base + (key,)] = value
    if default:
        for name, other in expected["accounts"].items():
            if name != account_id and other.get("default", False):
                other["default"] = False
                changes[("accounts", name, "default")] = False
    if sum(other.get("default", False) is True for other in expected["accounts"].values()) > 1:
        raise ValueError()
    mailbox = account.get("mailbox", {})
    spelling = "aliases" if "aliases" in mailbox else "alias"
    current = mailbox.get(spelling, {})
    for role, value in mappings.items():
        path = base + ("mailbox", spelling, role)
        if value:
            account.setdefault("mailbox", {}).setdefault(spelling, {})[role] = value
            changes[path] = value
        elif role in current:
            del current[role]
            changes[path] = None
    additions = {}
    for path, value in changes.items():
        encoded = json.dumps(value, ensure_ascii=False) if value is not None else ""
        if path in fields:
            index, start, end = fields[path]
            if value is None:
                # Preserve a trailing comment even when removing its assignment.
                lines[index] = lines[index][end:].lstrip() or "\n"
            else:
                lines[index] = lines[index][:start] + encoded + lines[index][end:]
        else:
            parent = path[:-1]
            while parent not in tables:
                parent = parent[:-1]
                if not parent:
                    raise ValueError()
            index = tables[parent] + 1
            key = ".".join(json.dumps(part, ensure_ascii=False) for part in path[len(parent):])
            additions.setdefault(index, []).append(key + " = " + encoded + "\n")
    for index in sorted(additions, reverse=True):
        lines[index:index] = additions[index]
    result = "".join(lines).encode("utf-8")
    if len(result) > MAX_FILE_SIZE or tomllib.loads(result.decode("utf-8")) != expected:
        raise ValueError()
    return result


def save_account(account_id, revision, email, display_name, default, mappings, config=None, demo=False):
    directory = None
    temporary = None
    try:
        validate_account(account_id)
        email = text(email, 1024, True)
        display_name = text(display_name, 1024, True)
        if type(default) is not bool or set(mappings) != set(ROLES):
            raise ValueError()
        mappings = {role: text(value, 1024, True) for role, value in mappings.items()}
        if demo:
            result = account_overview(demo=True)
            account = next(a for a in result["accounts"] if a["id"] == account_id)
            if revision != DEMO_REVISION:
                raise ValueError()
            for other in result["accounts"]:
                if default:
                    other["default"] = False
            account.update({"email": email, "display-name": display_name, "default": default,
                            "mailbox-mappings": mappings})
            return result
        if not isinstance(revision, str) or not re.fullmatch("[0-9a-f]{64}", revision):
            raise ValueError()
        # Read labels before locking the config directory. The Himalaya config
        # may itself live in Yetimail's private directory, whose advisory lock
        # is also used by the label store.
        saved_labels = labels()
        directory, name = _config_directory(config)
        fcntl.flock(directory, fcntl.LOCK_EX)
        raw, info = _read_config(directory, name)
        if hashlib.sha256(raw).hexdigest() != revision:
            raise ValueError()
        document = tomllib.loads(raw.decode("utf-8"))
        updated = _render(raw, document, account_id, email, display_name, default, mappings)
        accounts = configured_accounts(config, updated)
        new_revision = hashlib.sha256(updated).hexdigest()
        for entry in accounts:
            entry.update({"label": saved_labels.get(entry["id"], ""),
                          "revision": new_revision, "editable": True, "editable-reason": ""})
        for backup in (True, False):
            target = (".yetimail-backup-" if backup else ".yetimail-save-") + secrets.token_hex(16)
            temporary = target
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
            with os.fdopen(fd, "wb") as output:
                output.write(raw if backup else updated)
                output.flush()
                if not backup:
                    os.fchown(output.fileno(), info.st_uid, info.st_gid)
                    os.fchmod(output.fileno(), stat.S_IMODE(info.st_mode))
                os.fsync(output.fileno())
            if backup:
                os.fsync(directory)
                backup_name = target
                temporary = None
        latest, latest_info = _read_config(directory, name)
        if latest != raw or (latest_info.st_dev, latest_info.st_ino, latest_info.st_mode) != (info.st_dev, info.st_ino, info.st_mode):
            raise ValueError()
        os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
        temporary = None
        committed, committed_info = _read_config(directory, name)
        if (committed != updated or (committed_info.st_uid, committed_info.st_gid,
                stat.S_IMODE(committed_info.st_mode)) != (info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode))):
            _restore_backup(directory, backup_name, name, info)
            os.fsync(directory)
            raise ValueError()
        try:
            os.fsync(directory)
        except OSError:
            # Restore the durable pre-save image if directory persistence fails.
            # If storage also prevents rollback, leave that image for recovery.
            _restore_backup(directory, backup_name, name, info)
            os.fsync(directory)
            raise
        return {"accounts": accounts}
    except (OSError, ValueError, TypeError, KeyError, AttributeError, StopIteration, RecursionError, AccountSettingsError):
        raise AccountSettingsError(SAVE_ERROR) from None
    finally:
        if directory is not None:
            if temporary is not None:
                try:
                    os.unlink(temporary, dir_fd=directory)
                except OSError:
                    pass
            os.close(directory)
