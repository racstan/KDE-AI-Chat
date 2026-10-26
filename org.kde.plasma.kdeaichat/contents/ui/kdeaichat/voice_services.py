"""The per-user token of the local dictation service (voice/stt_service.py), and unit-file quoting."""
import fcntl
import os
import re
import secrets
import tempfile
from typing import Any, Dict

from kdeaichat.common import safe_path


def _voice_token_path() -> str:
    return os.path.expanduser("~/.local/share/kdeaichat/voice-http-token")


def ensure_voice_http_token(path: str = "") -> str:
    """Create/read the per-user token used by the local voice HTTP daemons."""
    token_path = safe_path(path or _voice_token_path())
    folder = os.path.dirname(token_path)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    try: os.chmod(folder, 0o700)
    except OSError: pass
    lock_path = token_path + ".lock"
    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.chmod(lock_path, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        try:
            with open(token_path, "r", encoding="ascii") as f:
                token = f.read().strip()
            if len(token) >= 32 and re.fullmatch(r"[A-Za-z0-9_-]+", token):
                os.chmod(token_path, 0o600)
                return token
        except (OSError, UnicodeError):
            pass

        token = secrets.token_urlsafe(32)
        fd, temporary = tempfile.mkstemp(prefix="." + os.path.basename(token_path) + ".", dir=folder)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="ascii") as f:
                f.write(token + "\n")
                f.flush()
                os.fsync(f.fileno())
            os.replace(temporary, token_path)
            os.chmod(token_path, 0o600)
        except Exception:
            try: os.close(fd)
            except OSError: pass
            try: os.unlink(temporary)
            except OSError: pass
            raise
        return token
    finally:
        try: fcntl.flock(lock_fd, fcntl.LOCK_UN)
        finally: os.close(lock_fd)


def _systemd_quote(value: str) -> str:
    """Quote one systemd unit value without allowing unit-file injection."""
    text = str(value)
    if not text or len(text) > 4096 or any(ord(ch) < 0x20 or ch == "\x7f" for ch in text):
        raise ValueError("unsafe path for systemd service")
    # systemd accepts C-style escapes in quoted values. Escape all syntax
    # characters instead of rejecting valid paths containing spaces or parens.
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%") + '"'


# No commands: dictation's unit is managed by stt_units.py (stt_sync_units),
# read aloud has no service (voice/ReadAloud.qml).
COMMANDS: Dict[str, Any] = {}
