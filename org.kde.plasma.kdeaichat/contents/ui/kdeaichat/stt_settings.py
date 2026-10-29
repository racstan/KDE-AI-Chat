"""Speech-to-text settings: validated from the widget's payload, never from a file.

The widget passes its plasmoid config (main.xml ``stt*`` entries) in each
helper command's payload. Secrets are never in the payload: the speech
server's key is read from KWallet (entry ``stt-remote``) inside the helper.
Only the speech server runs through these commands; Speech Note listens
through the ``speechnote_*`` commands.
"""
import os
import re
from typing import Any, Dict
from urllib.parse import urlsplit

from kdeaichat import chats

# "speechnote" is run by the widget through kdeaichat/speechnote.py; "remote" is the OpenAI-compatible speech server.
ENGINES = ("speechnote", "remote")
DEFAULT_ENGINE = "speechnote"
WALLET_ENTRY = "stt-remote"
_LANGUAGE = re.compile(r"^(auto|[a-z]{2,3}(-[A-Za-z]{2,4})?)\Z")


class SettingsError(ValueError):
    pass


def _text(payload: Dict[str, Any], key: str, default: str = "", limit: int = 4096) -> str:
    value = payload.get(key, default)
    text = str(default if value is None else value).strip()
    if len(text) > limit or any(ch in text for ch in ("\x00", "\n", "\r")):
        raise SettingsError("invalid value for " + key)
    return text


def check_url(text: str) -> str:
    if not text:
        return ""
    parts = urlsplit(text)
    if parts.scheme not in ("http", "https") or not parts.hostname or parts.username or parts.password:
        raise SettingsError("the URL must be http(s)://host/... without credentials")
    if parts.query or parts.fragment:
        raise SettingsError("the URL must not have a query or fragment")
    return text.rstrip("/")


def runtime_dir() -> str:
    """Private folder for recordings and the dictation state (tmpfs when there is a runtime dir)."""
    base = os.environ.get("XDG_RUNTIME_DIR") or ""
    folder = os.path.join(base, "kdeaichat") if base and os.path.isdir(base) else os.path.join(chats.data_root(), "run")
    os.makedirs(folder, mode=0o700, exist_ok=True)
    try:
        os.chmod(folder, 0o700)
    except OSError:
        pass
    return folder


def from_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Validated settings for one request; raises SettingsError."""
    engine = _text(payload, "sttEngine", DEFAULT_ENGINE, 32) or DEFAULT_ENGINE
    if engine not in ENGINES:
        raise SettingsError("unknown speech-to-text engine: " + engine)
    language = _text(payload, "sttLanguage", "auto", 16) or "auto"
    if not _LANGUAGE.match(language):
        raise SettingsError("unknown language code: " + language)
    return {
        "engine": engine,
        "language": language,
        "remote_url": check_url(_text(payload, "sttRemoteUrl")),
        "remote_model": _text(payload, "sttRemoteModel", "whisper-1", 200) or "whisper-1",
    }
