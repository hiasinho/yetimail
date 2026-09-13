"""Optional processed-message cache; no mail/config access and no logging.

Typical use::

    cache = MessageCache()
    key = CacheKey(context_identity, mailbox, message_id, parser_version, fingerprint)
    result = cache.get(key)
    if result.hit:
        return result.value
    value = fetch_and_process_message()
    cache.put(key, value, generation=result.generation)

Context identity must include the effective account, configuration identity and
any backend UID-validity identity available to the caller. It must not contain
credentials. Mailboxes and IDs are exact, opaque strings. Increment the parser
version whenever the processed JSON representation changes. Demo callers should
bypass this module entirely.

A miss caused by storage failure has generation=None, disabling the subsequent
put. All mutations return success booleans; callers must continue without cache
on failure. Invalidation failures must not be treated as successful invalidation.
Generation tokens combine a global epoch with persistent scoped epochs.
Invalidation rejects affected in-flight puts only; clear rejects all old puts.
Capture the token BEFORE fetching. Scoped epochs must not be pruned: even a
cache miss may have a fetch in flight.

Limits count UTF-8 JSON payload bytes, not SQLite page/index/WAL overhead. Expiry
is measured from put (not last access). Maintenance runs on get/put; there is no
background worker. SQLite reuses freed pages; clear is logical, not secure erase.
"""

from contextlib import contextmanager
from dataclasses import dataclass
import json
import os
from pathlib import Path
import sqlite3
import stat
import time
import uuid


TTL_SECONDS = 30 * 24 * 60 * 60
MAX_BYTES = 100 * 1024 * 1024
MAX_ENTRY_BYTES = 5 * 1024 * 1024
_FAILURES = (OSError, sqlite3.Error, ValueError, TypeError, OverflowError, RecursionError)


@dataclass(frozen=True)
class CacheKey:
    context: str
    mailbox: str
    message_id: str
    parser_version: str
    fingerprint: str = ""

    def parts(self):
        parts = (self.context, self.mailbox, self.message_id, self.parser_version, self.fingerprint)
        if not all(isinstance(part, str) for part in parts):
            raise ValueError("Cache key components must be strings")
        return parts


@dataclass(frozen=True)
class CacheLookup:
    hit: bool = False
    value: object = None
    generation: str | None = None


class MessageCache:
    """Lazy, short-lived connections; safe to use from separate processes.

    directory overrides the private application directory for offline tests.
    Defaults to $XDG_CACHE_HOME/yetimail or ~/.cache/yetimail. Construction
    performs no filesystem operations. No connection is retained between calls.
    """

    database_name = "messages.sqlite3"
    disabled_name = "disabled"

    def __init__(self, directory=None, *, ttl_seconds=TTL_SECONDS,
                 max_bytes=MAX_BYTES, max_entry_bytes=MAX_ENTRY_BYTES,
                 clock=time.time, timeout=0.25):
        self.directory = Path(directory) if directory is not None else None
        self.ttl_seconds = ttl_seconds
        self.max_bytes = max_bytes
        self.max_entry_bytes = max_entry_bytes
        self.clock = clock
        self.timeout = timeout

    def _directory(self):
        if self.directory is not None:
            return self.directory
        xdg = os.environ.get("XDG_CACHE_HOME", "")
        if os.path.isabs(xdg):
            return Path(xdg) / "yetimail"
        return Path.home() / ".cache" / "yetimail"

    @staticmethod
    def _private(path, directory=False):
        info = path.lstat()
        expected = stat.S_ISDIR if directory else stat.S_ISREG
        if not expected(info.st_mode) or info.st_uid != os.getuid():
            raise OSError("Unsafe cache path")
        if not directory and info.st_nlink != 1:
            raise OSError("Unsafe cache file")
        path.chmod(0o700 if directory else 0o600)

    @contextmanager
    def _connect(self, *, allow_disabled=False):
        directory = self._directory()
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self._private(directory, directory=True)
        disabled = directory / self.disabled_name
        if not allow_disabled:
            try:
                self._private(disabled)
            except FileNotFoundError:
                pass
            else:
                raise OSError("Cache disabled after failed invalidation")
        path = directory / self.database_name
        fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        os.close(fd)
        self._private(path)
        # Reject preexisting unsafe sidecars before SQLite can open them.
        for suffix in ("-wal", "-shm", "-journal"):
            sidecar = Path(str(path) + suffix)
            try:
                self._private(sidecar)
            except FileNotFoundError:
                pass
        connection = sqlite3.connect(path, timeout=self.timeout)
        try:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute("BEGIN IMMEDIATE")
            # A failed invalidation may have disabled the cache while this
            # connection was waiting for the write lock.
            if not allow_disabled and disabled.exists():
                raise OSError("Cache disabled after failed invalidation")
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            if version not in (0, 1, 2):
                raise ValueError("Unsupported cache schema")
            if version == 1:
                # Old keys combine ID and listing nonce. They cannot be reused.
                connection.execute("DROP TABLE IF EXISTS messages")
                connection.execute("DROP TABLE IF EXISTS state")
            connection.execute("CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK(id=1), generation TEXT NOT NULL)")
            connection.execute("INSERT OR IGNORE INTO state VALUES (1, ?)", (uuid.uuid4().hex,))
            connection.execute("""CREATE TABLE IF NOT EXISTS messages (
                context TEXT NOT NULL, mailbox TEXT NOT NULL, message_id TEXT NOT NULL,
                parser_version TEXT NOT NULL, fingerprint TEXT NOT NULL,
                value TEXT NOT NULL, size INTEGER NOT NULL,
                created REAL NOT NULL, accessed INTEGER NOT NULL,
                PRIMARY KEY (context, mailbox, message_id, parser_version, fingerprint))""")
            connection.execute("""CREATE TABLE IF NOT EXISTS epochs (
                scope TEXT PRIMARY KEY, generation TEXT NOT NULL)""")
            connection.execute("PRAGMA user_version=2")
            yield connection
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()
            # SQLite normally inherits 0600 from the database. Tighten any
            # surviving sidecars too, without making cleanup a fatal failure.
            for suffix in ("-wal", "-shm", "-journal"):
                try:
                    self._private(Path(str(path) + suffix))
                except OSError:
                    pass

    @staticmethod
    def _generation(connection, key):
        scopes = [(key.context, None, None), (key.context, key.mailbox, None),
                  (key.context, None, key.message_id),
                  (key.context, key.mailbox, key.message_id)]
        tokens = [connection.execute("SELECT generation FROM state WHERE id=1").fetchone()[0]]
        for scope in scopes:
            row = connection.execute("SELECT generation FROM epochs WHERE scope=?",
                                     (json.dumps(scope),)).fetchone()
            tokens.append(row[0] if row else "")
        return json.dumps(tokens)

    @staticmethod
    def _tick(connection):
        return connection.execute("SELECT COALESCE(MAX(accessed), 0) + 1 FROM messages").fetchone()[0]

    def _prune(self, connection, now):
        connection.execute("DELETE FROM messages WHERE created <= ?", (now - self.ttl_seconds,))
        total = connection.execute("SELECT COALESCE(SUM(size), 0) FROM messages").fetchone()[0]
        if total > self.max_bytes:
            for rowid, size in connection.execute("SELECT rowid, size FROM messages ORDER BY accessed, rowid").fetchall():
                connection.execute("DELETE FROM messages WHERE rowid=?", (rowid,))
                total -= size
                if total <= self.max_bytes:
                    break

    def get(self, key):
        """Return a hit (including JSON null), miss, or unavailable miss."""
        try:
            parts = key.parts()
            with self._connect() as connection:
                self._prune(connection, self.clock())
                generation = self._generation(connection, key)
                row = connection.execute("""SELECT value FROM messages WHERE
                    context=? AND mailbox=? AND message_id=? AND parser_version=? AND fingerprint=?""", parts).fetchone()
                if row is None:
                    result = CacheLookup(generation=generation)
                else:
                    try:
                        value = json.loads(row[0])
                    except (ValueError, TypeError, RecursionError):
                        connection.execute("""DELETE FROM messages WHERE
                            context=? AND mailbox=? AND message_id=? AND parser_version=? AND fingerprint=?""", parts)
                        result = CacheLookup(generation=generation)
                    else:
                        connection.execute("""UPDATE messages SET accessed=? WHERE
                            context=? AND mailbox=? AND message_id=? AND parser_version=? AND fingerprint=?""",
                                           (self._tick(connection), *parts))
                        result = CacheLookup(True, value, generation)
            return result
        except _FAILURES:
            return CacheLookup()

    def put(self, key, value, *, generation):
        """Store JSON only if the pre-fetch generation still matches."""
        if generation is None:
            return False
        try:
            parts = key.parts()
            payload = json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
            size = len(payload.encode("utf-8"))
            if size > min(self.max_entry_bytes, self.max_bytes):
                return False
            with self._connect() as connection:
                if generation != self._generation(connection, key):
                    return False
                now = self.clock()
                connection.execute("""INSERT OR REPLACE INTO messages VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?, ?)""", (*parts, payload, size, now, self._tick(connection)))
                self._prune(connection, now)
            return True
        except _FAILURES:
            return False

    def replace_context(self, key, value, *, generation):
        """Atomically invalidate a context and store one replacement entry.

        The original pre-fetch generation must still match, so a concurrent
        mutation or explicit clear always wins over a stale refresh.
        """
        if generation is None:
            return False
        try:
            parts = key.parts()
            payload = json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
            size = len(payload.encode("utf-8"))
            if size > min(self.max_entry_bytes, self.max_bytes):
                return False
            with self._connect() as connection:
                if generation != self._generation(connection, key):
                    return False
                connection.execute("INSERT OR REPLACE INTO epochs VALUES (?, ?)",
                                   (json.dumps((key.context, None, None)), uuid.uuid4().hex))
                connection.execute("DELETE FROM messages WHERE context=?", (key.context,))
                now = self.clock()
                connection.execute("""INSERT OR REPLACE INTO messages VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?, ?)""", (*parts, payload, size, now, self._tick(connection)))
                self._prune(connection, now)
            return True
        except _FAILURES:
            return False

    def invalidate(self, context, mailbox=None, message_id=None):
        """Remove a context, mailbox, or message across ALL parser versions.

        None is a wildcard, never an empty string. A message without a mailbox
        invalidates that raw ID across aliases/mailboxes in the context.
        Advances its scoped epoch even when no matching entry exists.
        """
        if not isinstance(context, str):
            return False
        if any(value is not None and not isinstance(value, str) for value in (mailbox, message_id)):
            return False
        clauses, values = ["context=?"], [context]
        for column, value in (("mailbox", mailbox), ("message_id", message_id)):
            if value is not None:
                clauses.append(column + "=?")
                values.append(value)
        success = self._remove("DELETE FROM messages WHERE " + " AND ".join(clauses),
                               values, scope=(context, mailbox, message_id))
        if not success:
            self.disable()
        return success

    def disable(self):
        """Fail closed after an invalidation could not acquire SQLite."""
        try:
            directory = self._directory()
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            self._private(directory, directory=True)
            path = directory / self.disabled_name
            fd = os.open(path, os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
            os.close(fd)
            self._private(path)
            return True
        except _FAILURES:
            return False

    def clear(self):
        """Remove all entries, reject old tokens, and recover a disabled cache."""
        if not self._remove("DELETE FROM messages", (), allow_disabled=True):
            return False
        try:
            (self._directory() / self.disabled_name).unlink(missing_ok=True)
            return True
        except OSError:
            return False

    def _remove(self, statement, values, *, allow_disabled=False, scope=None):
        try:
            with self._connect(allow_disabled=allow_disabled) as connection:
                if scope is None:
                    connection.execute("UPDATE state SET generation=? WHERE id=1", (uuid.uuid4().hex,))
                    connection.execute("DELETE FROM epochs")
                else:
                    connection.execute("INSERT OR REPLACE INTO epochs VALUES (?, ?)",
                                       (json.dumps(scope), uuid.uuid4().hex))
                connection.execute(statement, values)
            return True
        except _FAILURES:
            return False


class FolderSnapshotCache(MessageCache):
    """Revalidated folder discovery snapshots, retained for up to 30 days.

    Separate storage keeps short-lived list pruning from expiring folders.
    Inherits private paths, bounded LRU storage and clear-generation checks.
    """

    database_name = "folders.sqlite3"
    disabled_name = "folders-disabled"

    def __init__(self, directory=None, **kwargs):
        kwargs.setdefault("max_bytes", 10 * 1024 * 1024)
        kwargs.setdefault("max_entry_bytes", 1024 * 1024)
        super().__init__(directory, **kwargs)


class ListSnapshotCache(MessageCache):
    """Revalidated normalized pages, isolated from the message-body cache.

    Reuses private SQLite handling, size limits, LRU and invalidation epochs.
    Long retention is safe because snapshots are displayed stale-while-refresh.
    """

    database_name = "lists.sqlite3"
    disabled_name = "lists-disabled"

    def __init__(self, directory=None, **kwargs):
        # Snapshots are stale-while-revalidate hints, never authoritative.
        kwargs.setdefault("ttl_seconds", 30 * 24 * 60 * 60)
        kwargs.setdefault("max_bytes", 10 * 1024 * 1024)
        kwargs.setdefault("max_entry_bytes", 1024 * 1024)
        super().__init__(directory, **kwargs)
