"""Read aloud with engines that write sound files (voice/FileSpeech.qml plays them).

- ``tts_probe {}``: which of these engines can run here: ``{"piper": path}``
  ("" when no ``piper`` program is found).
- ``tts_synthesize {engine, text, options}``: writes one WAV for ``text`` and
  prints ``{"ok": true, "path": ...}`` or ``{"ok": false, "error": ...}``.
  Engines: ``piper`` (local binary + .onnx voice), ``remote`` (an
  OpenAI-compatible ``/audio/speech``; its key is read here from KWallet,
  entry ``tts-remote``, never passed in), ``command`` (the user's template,
  text on stdin, WAV on stdout or to ``{output}``; run without a shell),
  ``neural`` (the natural voice, Kokoro: ``tts_worker.py`` starts its
  service on demand). A failure carries ``code`` "not_installed" when the
  natural voice isn't set up, so the widget can use the system voice.
- ``tts_cleanup {path?}``: removes one played file, or every file older than
  ten minutes.

Files go to ``$XDG_RUNTIME_DIR/kdeaichat-tts`` (private, in memory), or
``~/.cache/kdeaichat/tts`` without a runtime dir. ``KDEAICHAT_TTS_DIR``
overrides it for tests.
"""
import json
import os
import shlex
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from typing import Any, Dict, List

from kdeaichat import schedule_wallet, tts_neural, tts_worker
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


def find_piper(binary: str = "") -> str:
    if binary:
        path = os.path.expanduser(binary)
        if os.sep in path:
            return path if os.path.isfile(path) and os.access(path, os.X_OK) else ""
        return shutil.which(path) or ""
    for name in ("piper", "piper-tts"):
        found = shutil.which(name)
        if found:
            return found
    local = os.path.expanduser("~/.local/bin/piper")
    return local if os.access(local, os.X_OK) else ""


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


def _run(argv: List[str], text: str, out_path: str, stdout_is_wav: bool) -> None:
    try:
        with open(out_path, "wb") as out:
            result = subprocess.run(argv, input=text.encode("utf-8"), stdout=out if stdout_is_wav else subprocess.DEVNULL,
                                    stderr=subprocess.PIPE, timeout=TIMEOUT)
    except FileNotFoundError:
        raise RuntimeError(f"program not found: {argv[0]}") from None
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"no sound after {TIMEOUT} seconds") from None
    if result.returncode != 0:
        last = result.stderr.decode("utf-8", "replace").strip().splitlines()[-1:] or [f"exit code {result.returncode}"]
        raise RuntimeError(last[0][:300])


def synth_piper(text: str, options: Dict[str, Any], out_path: str) -> None:
    binary = find_piper(str(options.get("voiceTtsPiperBinary", "") or ""))
    if not binary:
        raise RuntimeError("Piper is not installed (no piper program found)")
    model = safe_path(options.get("voiceTtsPiperModel", ""))
    if not os.path.isfile(model):
        raise RuntimeError("the Piper voice file was not found")
    argv = [binary, "--model", model, "--output_file", out_path,
            "--length_scale", f"{1 / _speed(options, 'voiceTtsPiperSpeed'):.3f}"]
    try:
        speaker = int(options.get("voiceTtsPiperSpeaker", 0) or 0)
    except (TypeError, ValueError):
        speaker = 0
    if speaker > 0:
        argv += ["--speaker", str(speaker)]
    _run(argv, text, out_path, stdout_is_wav=False)


def synth_command(text: str, options: Dict[str, Any], out_path: str) -> None:
    template = str(options.get("voiceTtsCommand", "") or "").strip()
    if not template or any(ch in template for ch in "\x00\n\r"):
        raise RuntimeError("no command is set")
    try:
        argv = shlex.split(template)
    except ValueError as e:
        raise RuntimeError(f"the command can't be read: {e}") from None
    uses_output = any("{output}" in arg for arg in argv)
    argv = [arg.replace("{output}", out_path) for arg in argv]
    argv[0] = os.path.expanduser(argv[0])
    _run(argv, text, out_path, stdout_is_wav=not uses_output)


def _remote_key() -> str:
    try:
        return schedule_wallet.read_key(WALLET_ENTRY)
    except schedule_wallet.WalletUnavailable:
        return ""  # a local server needs no key; a server that does says so


def synth_remote(text: str, options: Dict[str, Any], out_path: str) -> None:
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
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
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


def pause_after(text: str) -> int:
    """Silence (ms) after a chunk of the natural voice, which reads a sentence at a time."""
    end = text.rstrip()[-1:]
    return 350 if end in ".!?…" else 200 if end in ":;" else 150


def synth_neural(text: str, options: Dict[str, Any], out_path: str) -> None:
    tts_worker.synthesize(text, options, out_path, pause_after(text))


ENGINES = {"piper": synth_piper, "remote": synth_remote, "command": synth_command, "neural": synth_neural}


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
        engine(text[:MAX_TEXT], options, path)
        if not _is_wav(path):
            raise RuntimeError("the engine did not write a WAV file")
    except (RuntimeError, ValueError) as e:
        _remove(path)
        failure = {"ok": False, "error": str(e)}
        if isinstance(e, tts_worker.TtsError):
            failure["code"] = e.code
        return failure
    return {"ok": True, "path": path}


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


def cmd_tts_probe(payload: Dict[str, Any]) -> None:
    print(json.dumps({"ok": True, "piper": find_piper(str(payload.get("piperBinary", "") or ""))}))


def cmd_tts_synthesize(payload: Dict[str, Any]) -> None:
    print(json.dumps(synthesize(payload)))


def cmd_tts_cleanup(payload: Dict[str, Any]) -> None:
    try:
        print(json.dumps({"ok": True, "removed": cleanup(str(payload.get("path", "") or ""))}))
    except ValueError as e:
        print(json.dumps({"ok": False, "error": str(e)}))


COMMANDS = dict(tts_neural.COMMANDS, **{
    "tts_probe": cmd_tts_probe,
    "tts_synthesize": cmd_tts_synthesize,
    "tts_cleanup": cmd_tts_cleanup,
})
