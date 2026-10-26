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
