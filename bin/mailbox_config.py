"""Fail-closed literal mailbox guard for Himalaya 2.1 (Linux).

The shared --mailbox option resolves aliases before backend IDs, with no escape.
Mirror the relevant config rules from Himalaya v2.1.0 config.rs/account/context.rs
and pimalaya-config 0.1.4 toml.rs. Never execute or expose credential values.
Unsupported path expansion, alias spelling, or ambiguous defaults are rejected.
"""

import os
from pathlib import Path
import re
import sys

try:
    import tomllib
except ImportError:
    tomllib = None  # Older Python retains default-Inbox access, but fails closed for raw IDs.


class MailboxConfigError(Exception):
    pass


def expanded_path(value):
    # pimalaya uses shellexpand (not a shell). Support its common forms, and
    # reject anything whose expansion we cannot reproduce with certainty.
    if not value:
        raise ValueError()
    if value.startswith("~"):
        if not value.startswith("~/"):
            raise ValueError()
        home = os.environ.get("HOME")
        if not home or not os.path.isabs(home):
            raise ValueError()
        value = home + value[1:]
    def variable(match):
        name = match[1] or match[2]
        if name not in os.environ:
            raise ValueError()
        return os.environ[name]
    value = re.sub(r"\$\{([A-Za-z_][A-Za-z_0-9]*)\}|\$([A-Za-z_][A-Za-z_0-9]*)", variable, value)
    if "$" in value or "\x00" in value:
        raise ValueError()
    return Path(value).resolve()


def config_paths(explicit):
    value = explicit if explicit is not None else os.environ.get("HIMALAYA_CONFIG")
    if value is not None:
        return [expanded_path(part) for part in value.split(":")]
    if not sys.platform.startswith("linux"):
        raise ValueError()
    # dirs::home_dir can fall back to passwd; reject instead of guessing when
    # HOME is absent. Tests always supply a private temporary HOME.
    home = os.environ.get("HOME")
    if not home or not os.path.isabs(home):
        raise ValueError()
    home = Path(home)
    xdg = os.environ.get("XDG_CONFIG_HOME", "")
    config = Path(xdg) if os.path.isabs(xdg) else home / ".config"
    for path in (config / "himalaya/config.toml", home / ".config/himalaya/config.toml", home / ".himalayarc"):
        if path.exists():
            return [path]
    raise ValueError()


def merge(base, other):
    if type(base) is not type(other):
        raise ValueError()
    if isinstance(base, dict):
        result = dict(base)
        for key, value in other.items():
            result[key] = merge(result[key], value) if key in result else value
        return result
    if isinstance(base, list):
        return base + other
    return other


def aliases(table):
    mailbox = table.get("mailbox", {})
    if not isinstance(mailbox, dict) or ("alias" in mailbox and "aliases" in mailbox):
        raise ValueError()
    values = mailbox.get("alias", mailbox.get("aliases", {}))
    if not isinstance(values, dict):
        raise ValueError()
    result = {}
    for key, value in values.items():
        # Non-ASCII lowercasing can differ between Rust/Python versions. Also
        # reject duplicate case variants: Rust HashMap iteration is unordered.
        if not key.isascii() or not isinstance(value, str) or key.lower() in result:
            raise ValueError()
        result[key.lower()] = value
    return result


def check_literal_mailbox(args):
    """Reject alias redirection, and same-folder moves, before backend access."""
    moving = getattr(args, "command", None) == "move"
    if not args.mailbox and not moving:
        return  # Intentional configured Inbox alias, not a discovered raw ID.
    try:
        if tomllib is None:
            raise ValueError()
        paths = config_paths(args.config)
        config = {}
        for path in paths:
            # Himalaya skips unreadable secondary files. Fail closed instead:
            # they might become readable between our check and its load.
            with path.open("rb") as source:
                config = merge(config, tomllib.load(source))
        accounts = config["accounts"]
        if not isinstance(accounts, dict):
            raise ValueError()
        name = args.account
        if name in (None, "", "default"):
            defaults = [value for value in accounts.values()
                        if isinstance(value, dict) and value.get("default") is True]
            if len(defaults) != 1:
                raise ValueError()
            account = defaults[0]
        else:
            account = accounts[name]
        if not isinstance(account, dict):
            raise ValueError()
        effective = aliases(config)
        effective.update(aliases(account))
        # IMAP reserves INBOX as case-insensitive (unlike other mailbox names).
        # Himalaya may list it as "Inbox" while the configured alias is "INBOX".
        # Only apply this equivalence when IMAP is the sole receiving backend;
        # opaque IDs in Gmail/JMAP/local stores must still match exactly.
        other_backends = ("gmail", "jmap", "msgraph", "maildir", "m2dir", "pimdir")
        imap_only = isinstance(account.get("imap", config.get("imap")), dict) and not any(
            key in account or key in config for key in other_backends)
        def same_folder(left, right):
            return left == right or (imap_only and left.lower() == right.lower() == "inbox")

        for mailbox in ([args.mailbox, args.destination] if moving else [args.mailbox]):
            if not mailbox:
                continue  # Only the source can intentionally use the inbox alias.
            target = effective.get(mailbox.lower(), mailbox)
            if not same_folder(mailbox, target):
                raise MailboxConfigError("Folder ID conflicts with a configured mailbox alias; refusing to access a different folder.")
        if moving:
            source = args.mailbox or effective["inbox"]
            if not source:
                raise ValueError()
            if same_folder(source, args.destination):
                raise MailboxConfigError("Source and destination folders must differ.")
    except (OSError, ValueError, KeyError, TypeError, RecursionError):
        raise MailboxConfigError("Cannot verify literal folder routing from Himalaya configuration; refusing this folder. Check config paths, account defaults, and mailbox aliases.") from None
