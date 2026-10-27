"""Speech-to-text settings: validated from the widget's payload, never from a file.

The widget passes its plasmoid config (main.xml ``stt*`` entries) in each
helper command's payload, so nothing reads ``~/.config/kdeaichatrc`` any
more. Secrets are never in the payload: the remote engine's key is read
from KWallet (entry ``stt-remote``) inside the helper.
"""
import os
import re
import shlex
import shutil
from typing import Any, Dict, List
from urllib.parse import urlsplit

from kdeaichat import chats

# "speechnote" is run by the widget through kdeaichat/speechnote.py; here it only has a row in the engine list.
ENGINES = ("parakeet", "faster-whisper", "whisper-cpp", "remote", "command", "speechnote")
DEFAULT_ENGINE = "parakeet"
# "gpu" and "cuda" both mean the graphics card: CUDA for faster-whisper, Vulkan for Parakeet.
DEVICES = ("auto", "cpu", "cuda", "gpu")
LOCAL_SERVICE_ENGINES = ("parakeet", "faster-whisper")  # run by the on-demand service
PARAKEET_DEFAULT = "parakeet-unified-en-0.6b"
WALLET_ENTRY = "stt-remote"
DEFAULT_PORT = 9015
_LANGUAGE = re.compile(r"^(auto|[a-z]{2,3}(-[A-Za-z]{2,4})?)$")
_MODEL_NAME = re.compile(r"^[a-z0-9][a-z0-9.\-]{0,40}$")
WHISPER_CPP_BINARIES = ("whisper-cli", "whisper-cpp", "whisper.cpp")
PLACEHOLDERS = ("{wav}", "{lang}")


class SettingsError(ValueError):
    pass


def _text(payload: Dict[str, Any], key: str, default: str = "", limit: int = 4096) -> str:
    value = payload.get(key, default)
    text = str(default if value is None else value).strip()
    if len(text) > limit or any(ch in text for ch in ("\x00", "\n", "\r")):
        raise SettingsError("invalid value for " + key)
    return text


def _path(text: str) -> str:
    if not text:
        return ""
    path = os.path.normpath(os.path.expanduser(text))
    if not os.path.isabs(path) or ".." in text.split(os.sep):
        raise SettingsError("paths must be absolute: " + text[:80])
    return path


def check_url(text: str) -> str:
    if not text:
        return ""
    parts = urlsplit(text)
    if parts.scheme not in ("http", "https") or not parts.hostname or parts.username or parts.password:
        raise SettingsError("the URL must be http(s)://host/... without credentials")
    if parts.query or parts.fragment:
        raise SettingsError("the URL must not have a query or fragment")
    return text.rstrip("/")


def venv_dir(payload: Dict[str, Any]) -> str:
    return _path(_text(payload, "venv")) or os.path.join(chats.data_root(), "venv")


def venv_python(payload: Dict[str, Any]) -> str:
    folder = venv_dir(payload)
    for name in ("python3", "python"):
        candidate = os.path.join(folder, "bin", name)
        if os.path.exists(candidate):
            return candidate
    return ""


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


def port() -> int:
    try:
        return int(os.environ.get("KDEAICHAT_STT_PORT") or DEFAULT_PORT)
    except ValueError:
        return DEFAULT_PORT


def find_binary(configured: str, names=WHISPER_CPP_BINARIES) -> str:
    if configured:
        path = _path(configured) if "/" in configured else shutil.which(configured) or ""
        return path if path and os.path.isfile(path) and os.access(path, os.X_OK) else ""
    for name in names:
        found = shutil.which(name)
        if found:
            return found
    return ""


def command_argv(template: str, wav: str, language: str) -> List[str]:
    """The custom command as an argv list (no shell), with {wav} and {lang} filled in."""
    if not template:
        raise SettingsError("no command is set")
    try:
        words = shlex.split(template)
    except ValueError as e:
        raise SettingsError("the command can't be parsed: %s" % e) from None
    if not words or not any("{wav}" in w for w in words):
        raise SettingsError("the command must contain {wav} (the recording's path)")
    if "{" in words[0]:
        raise SettingsError("the program can't be a placeholder")
    program = find_binary(words[0], ())
    if not program:
        raise SettingsError("program not found or not executable: " + words[0][:80])
    filled = [program]
    for word in words[1:]:
        filled.append(word.replace("{wav}", wav).replace("{lang}", language))
    return filled


def from_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Validated settings for one request; raises SettingsError."""
    engine = _text(payload, "sttEngine", DEFAULT_ENGINE, 32) or DEFAULT_ENGINE
    if engine not in ENGINES:
        raise SettingsError("unknown speech-to-text engine: " + engine)
    device = _text(payload, "sttDevice", "auto", 8) or "auto"
    if device not in DEVICES:
        raise SettingsError("unknown device: " + device)
    language = _text(payload, "sttLanguage", "auto", 16) or "auto"
    if not _LANGUAGE.match(language):
        raise SettingsError("unknown language code: " + language)
    model = _text(payload, "sttModel", "small") or "small"
    if not _MODEL_NAME.match(model):
        model = _path(model)
    parakeet = _text(payload, "sttParakeetModel", PARAKEET_DEFAULT) or PARAKEET_DEFAULT
    if parakeet != PARAKEET_DEFAULT:
        parakeet = _path(parakeet)
        if not parakeet.endswith(".gguf"):
            raise SettingsError("the Parakeet model must be a .gguf file")
    return {
        "engine": engine,
        "model": model,
        "parakeet_model": parakeet,
        "device": device,
        "language": language,
        "allow_download": payload.get("allowDownload") is True,
        "whisper_cpp_binary": _text(payload, "sttWhisperCppBinary"),
        "whisper_cpp_model": _path(_text(payload, "sttWhisperCppModel")),
        "whisper_cpp_server": check_url(_text(payload, "sttWhisperCppServer")),
        "remote_url": check_url(_text(payload, "sttRemoteUrl")),
        "remote_model": _text(payload, "sttRemoteModel", "whisper-1", 200) or "whisper-1",
        "command": _text(payload, "sttCommand"),
        "venv": venv_dir(payload),
    }
