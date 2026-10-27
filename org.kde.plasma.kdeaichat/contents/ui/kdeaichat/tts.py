"""Read aloud with a speech server, which writes sound files (voice/FileSpeech.qml plays them).

- ``tts_synthesize {engine: "remote", text, options}``: writes one WAV for ``text`` and
  prints ``{"ok": true, "path": ...}`` or ``{"ok": false, "error": ...}``. ``remote`` is an
  OpenAI-compatible ``/audio/speech`` server; its key is read here from KWallet, entry
  ``tts-remote``, never passed in. (Speech Note and the system voice are run by the widget itself.)
- ``tts_cleanup {path?}``: removes one played file, or every file older than ten minutes.

Files go to ``$XDG_RUNTIME_DIR/kdeaichat-tts`` (private, in memory), or
``~/.cache/kdeaichat/tts`` without a runtime dir. ``KDEAICHAT_TTS_DIR``
overrides it for tests.
"""
import json
import os
import tempfile
import time
import urllib.error
import urllib.request
from typing import Any, Dict

from kdeaichat import http_safe, schedule_wallet
from kdeaichat.common import safe_path

TIMEOUT = 120
MAX_TEXT = 20000
MAX_AUDIO = 50 * 1024 * 1024
WALLET_ENTRY = "tts-remote"


def out_dir() -> str:
    override = os.environ.get("KDEAICHAT_TTS_DIR")
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if override:
        path = override
    elif runtime and os.path.isdir(runtime):
        path = os.path.join(runtime, "kdeaichat-tts")
    else:
        path = os.path.expanduser("~/.cache/kdeaichat/tts")
    os.makedirs(path, mode=0o700, exist_ok=True)
    os.chmod(path, 0o700)
    return path


def _new_wav() -> str:
    fd, path = tempfile.mkstemp(prefix="speech-", suffix=".wav", dir=out_dir())
    os.close(fd)
    return path


def _is_wav(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            head = f.read(12)
    except OSError:
        return False
    return head[:4] == b"RIFF" and head[8:12] == b"WAVE"


def _speed(options: Dict[str, Any], key: str) -> float:
    try:
        value = float(options.get(key, 1) or 1)
    except (TypeError, ValueError):
        value = 1.0
    return max(0.5, min(2.0, value))


def _remote_key() -> str:
    try:
        return schedule_wallet.read_key(WALLET_ENTRY)
    except schedule_wallet.WalletUnavailable:
        return ""  # a local server needs no key; a server that does says so


def synth_remote(text: str, options: Dict[str, Any], out_path: str) -> Dict[str, Any]:
    base = str(options.get("voiceTtsRemoteUrl", "") or "").strip().rstrip("/")
    if not base.startswith(("http://", "https://")) or any(ch.isspace() for ch in base):
        raise RuntimeError("the server URL must start with http:// or https://")
    url = base if base.endswith("/audio/speech") else base + "/audio/speech"
    body = {"model": str(options.get("voiceTtsRemoteModel", "") or "tts-1"), "input": text,
            "voice": str(options.get("voiceTtsRemoteVoice", "") or "alloy"), "response_format": "wav",
            "speed": _speed(options, "voiceTtsRemoteSpeed")}
    request = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), method="POST",
                                     headers={"Content-Type": "application/json", "Accept": "audio/wav"})
    key = _remote_key()
    if key:
        request.add_header("Authorization", "Bearer " + key)
    try:
        with http_safe.urlopen(request, timeout=TIMEOUT) as response:
            data = response.read(MAX_AUDIO + 1)
    except urllib.error.HTTPError as e:
        detail = e.read(300).decode("utf-8", "replace").strip()
        hint = " (is the API key saved?)" if e.code in (401, 403) else ""
        raise RuntimeError(f"the server answered {e.code}{hint}: {detail}"[:300]) from None
    except (urllib.error.URLError, OSError) as e:
        raise RuntimeError(f"the server can't be reached: {getattr(e, 'reason', e)}") from None
    if len(data) > MAX_AUDIO:
        raise RuntimeError("the server sent too much audio")
    with open(out_path, "wb") as f:
        f.write(data)
    return {"warning": http_safe.INSECURE_KEY_WARNING} if key and http_safe.insecure_key_url(url) else {}


ENGINES = {"remote": synth_remote}


def synthesize(payload: Dict[str, Any]) -> Dict[str, Any]:
    engine = ENGINES.get(str(payload.get("engine", "")))
    text = str(payload.get("text", "") or "").strip()
    options = payload.get("options") if isinstance(payload.get("options"), dict) else {}
    if engine is None:
        return {"ok": False, "error": "unknown read-aloud engine"}
    if not text:
        return {"ok": False, "error": "nothing to read"}
    path = _new_wav()
    try:
        extra = engine(text[:MAX_TEXT], options, path) or {}
        if not _is_wav(path):
            raise RuntimeError("the engine did not write a WAV file")
    except (RuntimeError, ValueError) as e:
        _remove(path)
        return {"ok": False, "error": str(e)}
    return {"ok": True, "path": path, **extra}


def _remove(path: str) -> bool:
    try:
        os.remove(path)
        return True
    except OSError:
        return False


def cleanup(path: str = "", max_age: float = 600) -> int:
    folder = out_dir()
    if path:
        real = os.path.realpath(safe_path(path))
        return int(os.path.dirname(real) == os.path.realpath(folder) and real.endswith(".wav") and _remove(real))
    removed = 0
    now = time.time()
    for name in os.listdir(folder):
        full = os.path.join(folder, name)
        try:
            old = now - os.lstat(full).st_mtime > max_age
        except OSError:
            continue
        if name.endswith(".wav") and old and _remove(full):
            removed += 1
    return removed


def cmd_tts_synthesize(payload: Dict[str, Any]) -> None:
    print(json.dumps(synthesize(payload)))


def cmd_tts_cleanup(payload: Dict[str, Any]) -> None:
    try:
        print(json.dumps({"ok": True, "removed": cleanup(str(payload.get("path", "") or ""))}))
    except ValueError as e:
        print(json.dumps({"ok": False, "error": str(e)}))


COMMANDS = {
    "tts_synthesize": cmd_tts_synthesize,
    "tts_cleanup": cmd_tts_cleanup,
}
