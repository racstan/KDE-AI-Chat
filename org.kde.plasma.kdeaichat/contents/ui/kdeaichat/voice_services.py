"""Voice service setup: the per-user HTTP token and the STT/TTS user units."""
import fcntl
import os
import re
import secrets
import shutil
import tempfile
from typing import Any, Dict

from kdeaichat.common import as_bool, atomic_write_text, safe_path

# contents/ui, where voice/voice_helper.py lives.
_UI_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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


def cmd_setup_venv_services(payload: Dict[str, Any]) -> None:
    """Install the voice services for STT and TTS systemd user units."""
    requested_venv = safe_path(payload.get("venvPy", "~/.local/share/kdeaichat/venv/bin/python3"))
    venv_py = requested_venv
    if not os.path.exists(venv_py) and venv_py.endswith("/bin/python3"):
        alternate = venv_py[:-len("python3")] + "python"
        if os.path.exists(alternate):
            venv_py = alternate
    if not os.path.exists(venv_py):
        venv_py = shutil.which("python3") or "/usr/bin/python3"
    venv_py = safe_path(venv_py)

    voice_helper = safe_path(os.path.join(_UI_DIR, "voice", "voice_helper.py"))
    token_path = safe_path(_voice_token_path())
    ensure_voice_http_token(token_path)

    sdir = os.path.expanduser("~/.config/systemd/user")
    os.makedirs(sdir, mode=0o700, exist_ok=True)

    espeak_env = ""
    espeak_path = payload.get("espeakPath", "")
    if espeak_path:
        # A custom executable/directory is optional. Refuse unsafe unit-file
        # input rather than attempting to interpret relative paths or control
        # characters.
        raw_espeak = safe_path(espeak_path)
        dir_path = raw_espeak if os.path.isdir(raw_espeak) else os.path.dirname(raw_espeak)
        if dir_path:
            env_path = f"PATH={dir_path}:{os.path.expanduser('~/.local/bin')}:/usr/local/bin:/usr/bin:/bin"
            espeak_env = "\nEnvironment=" + _systemd_quote(env_path)
            espeak_env += "\nEnvironment=" + _systemd_quote(f"PHONEMIZER_ESPEAK_PATH={dir_path}")

    venv_arg = _systemd_quote(venv_py)
    helper_arg = _systemd_quote(voice_helper)
    token_arg = _systemd_quote(token_path)

    def write_voice_unit(path: str, server_flag: str) -> None:
        content = f"""[Unit]
Description=KDE AI Chat {server_flag.upper().lstrip('-') } Daemon
After=network.target

[Service]
Type=simple
ExecStart={venv_arg} {helper_arg} {server_flag} --token-file {token_arg}
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1{espeak_env}

[Install]
WantedBy=default.target
"""
        atomic_write_text(path, content, mode=0o600)

    write_voice_unit(os.path.join(sdir, "kde-ai-stt.service"), "--stt-server")
    write_voice_unit(os.path.join(sdir, "kde-ai-tts.service"), "--tts-server")

    os.system("systemctl --user daemon-reload")
    voice_enabled = as_bool(payload.get("voiceEnabled", True), True)
    voice_tts_enabled = as_bool(payload.get("voiceTtsEnabled", True), True)
    if voice_enabled:
        os.system("systemctl --user enable --now kde-ai-stt.service 2>/dev/null")
    else:
        os.system("systemctl --user disable --now kde-ai-stt.service 2>/dev/null")

    if voice_enabled and voice_tts_enabled:
        os.system("systemctl --user enable --now kde-ai-tts.service 2>/dev/null")
    else:
        os.system("systemctl --user disable --now kde-ai-tts.service 2>/dev/null")
    print("VOICE_SERVICES_SETUP_OK")


COMMANDS = {
    "setup_venv_services": cmd_setup_venv_services,
}
