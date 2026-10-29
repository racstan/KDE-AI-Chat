"""Validated helpers shared by the helper's command modules.

Path validation, atomic private writes and the schedule-store lock live here
so every command applies the same rules: the helper is the last trust
boundary for filesystem operations.
"""
import fcntl
import json
import os
import tempfile
from contextlib import contextmanager
from typing import Any

from kdeaichat import chats

MAX_FILE_BYTES = 50 * 1024 * 1024
MAX_SCHEDULE_STORE_BYTES = 5 * 1024 * 1024


def as_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "on")
    return default


def safe_path(value: Any, *, allow_empty: bool = False) -> str:
    """Return a normalized absolute user path or raise ``ValueError``.

    The QML side validates paths before putting them into an IPC command, but
    this helper is also callable directly and is the last trust boundary for
    filesystem operations.  Spaces and normal Unicode filenames are allowed;
    control characters and traversal components are not.
    """
    if value is None:
        if allow_empty:
            return ""
        raise ValueError("path is required")
    raw = str(value)
    if raw == "":
        if allow_empty:
            return ""
        raise ValueError("path is required")
    if len(raw) > 4096 or any(ch in raw for ch in ("\x00", "\n", "\r")):
        raise ValueError("invalid path")
    expanded = os.path.expanduser(raw)
    if not os.path.isabs(expanded):
        raise ValueError("path must be absolute")
    if any(part == ".." for part in expanded.split(os.sep)):
        raise ValueError("path traversal is not allowed")
    normalized = os.path.normpath(expanded)
    if any(part == ".." for part in normalized.split(os.sep)):
        raise ValueError("path traversal is not allowed")
    return normalized


def ensure_private_dir(path: str) -> str:
    """Create `path` (and missing parents) and make the folder itself 0700, even when it already existed
    with looser permissions (made by an older version or another program). Returns `path`."""
    os.makedirs(path, mode=0o700, exist_ok=True)
    try:
        if os.stat(path).st_uid == os.getuid():
            os.chmod(path, 0o700)
    except OSError:
        pass
    return path


@contextmanager
def private_log(path: str, max_bytes: int = 0):
    """Open a log file for appending, created 0600 in a 0700 folder (an existing one is tightened too).
    With `max_bytes`, a log already bigger than that is first moved to `<path>.1` (one old file is kept)."""
    ensure_private_dir(os.path.dirname(path))
    if max_bytes:
        try:
            if os.path.getsize(path) > max_bytes:
                os.replace(path, path + ".1")
                os.chmod(path + ".1", 0o600)
        except OSError:
            pass
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "ab") as log:
            fd = -1
            yield log
    finally:
        if fd >= 0:
            os.close(fd)


def atomic_write_text(path: str, content: str, mode: int = 0o600) -> None:
    """Atomically write a private text file and preserve its permissions."""
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", dir=folder or None)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
        os.chmod(path, mode)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def atomic_write_json(path: str, data: Any) -> None:
    atomic_write_text(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def schedules_path() -> str:
    return os.path.join(chats.data_root(), 'schedules.json')


@contextmanager
def schedule_store_lock():
    """Serialize writes of the schedule definitions (widget commands, the v1 migration)."""
    lock_path = schedules_path() + ".lock"
    folder = os.path.dirname(lock_path)
    if folder:
        os.makedirs(folder, mode=0o700, exist_ok=True)
        try: os.chmod(folder, 0o700)
        except OSError: pass
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)
