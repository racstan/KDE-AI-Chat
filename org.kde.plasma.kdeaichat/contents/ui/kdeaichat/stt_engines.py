"""Speech-to-text engine adapters: each turns a WAV file into text.

* ``faster-whisper``: the on-demand local service (``voice/stt_service.py``,
  socket-activated ``kde-ai-stt.socket``), asked over loopback with the token.
* ``whisper-cpp``: the user's ``whisper-cli`` with a ggml model, or a
  whisper.cpp server URL.
* ``remote``: an OpenAI-compatible ``/audio/transcriptions`` URL; the key is
  read from KWallet (entry ``stt-remote``) here, never passed in argv.
* ``command``: the user's command template with ``{wav}`` (and ``{lang}``),
  run without a shell; it prints the text.

``available`` tells the settings UI which engines can work on this machine.
"""
import glob
import os
import subprocess
import time
from typing import Any, Callable, Dict, List
from urllib.parse import urlsplit

from kdeaichat import schedule_units, schedule_wallet, stt_http, voice_services
from kdeaichat.stt_http import EngineError
from kdeaichat.stt_settings import (ENGINES, WALLET_ENTRY, SettingsError, command_argv, find_binary, port,
                                    venv_python)

RUN_TIMEOUT = 300
MAX_OUTPUT = 256 * 1024
_NOISE = ("[BLANK_AUDIO]", "[ Silence ]", "[silence]", "(silence)")


def token_path() -> str:
    from kdeaichat import chats
    return os.path.join(chats.data_root(), "voice-http-token")


def _clean(text: str) -> str:
    for noise in _NOISE:
        text = text.replace(noise, " ")
    return " ".join(text.split())


def _run(argv: List[str], timeout: float = RUN_TIMEOUT) -> str:
    try:
        result = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise EngineError("%s took longer than %d seconds" % (os.path.basename(argv[0]), timeout), "timeout") from None
    except OSError as e:
        raise EngineError("can't run %s: %s" % (os.path.basename(argv[0]), e.strerror or e), "not_found") from None
    if result.returncode != 0:
        tail = result.stderr.decode("utf-8", "replace").strip().splitlines()[-2:]
        raise EngineError("%s failed (exit %d)%s" % (os.path.basename(argv[0]), result.returncode,
                                                    (": " + " ".join(tail)[:300]) if tail else ""), "failed")
    return result.stdout[:MAX_OUTPUT].decode("utf-8", "replace")


def faster_whisper(wav: str, s: Dict[str, Any], start_socket: Callable[[], int] = None) -> Dict[str, Any]:
    token = voice_services.ensure_voice_http_token(token_path())
    request = {"wav": wav, "model": s["model"], "device": s["device"], "language": s["language"],
               "allow_download": s["allow_download"]}
    try:
        return stt_http.service_call("/transcribe", request, token, port())
    except EngineError as e:
        if e.code != "unreachable":
            raise
    # Not listening: the socket unit may be stopped. Start it once and try again.
    (start_socket or (lambda: schedule_units.systemctl(["start", "kde-ai-stt.socket"])))()
    time.sleep(0.3)
    try:
        return stt_http.service_call("/transcribe", request, token, port())
    except EngineError as e:
        if e.code == "unreachable":
            raise EngineError("The faster-whisper service is not set up. Install it in Settings → Voice.",
                              "not_installed") from None
        raise


def whisper_cpp(wav: str, s: Dict[str, Any]) -> Dict[str, Any]:
    if s["whisper_cpp_server"]:
        return stt_http.whisper_cpp_server(wav, s)
    binary = find_binary(s["whisper_cpp_binary"])
    if not binary:
        raise EngineError("whisper-cli was not found. Install whisper.cpp or set its path.", "not_installed")
    model = s["whisper_cpp_model"]
    if not model or not os.path.isfile(model):
        raise EngineError("Choose a whisper.cpp ggml model file.", "not_configured")
    language = s["language"].split("-")[0]
    out = _run([binary, "-m", model, "-f", wav, "-nt", "-np", "-l", language])
    return {"text": _clean(out), "model": os.path.basename(model)}


def remote(wav: str, s: Dict[str, Any], read_key: Callable[[str], str] = None) -> Dict[str, Any]:
    try:
        key = (read_key or schedule_wallet.read_key)(WALLET_ENTRY)
    except schedule_wallet.WalletUnavailable as e:
        # A server on this computer usually needs no key; anything else does.
        if urlsplit(s["remote_url"]).hostname not in ("localhost", "127.0.0.1", "::1"):
            raise EngineError("Can't read the speech server's key: %s." % e.reason, "wallet") from None
        key = ""
    return stt_http.remote(wav, s, key)


def command(wav: str, s: Dict[str, Any]) -> Dict[str, Any]:
    try:
        argv = command_argv(s["command"], wav, s["language"])
    except SettingsError as e:
        raise EngineError(str(e), "not_configured") from None
    return {"text": _clean(_run(argv))}


ADAPTERS = {"faster-whisper": faster_whisper, "whisper-cpp": whisper_cpp, "remote": remote, "command": command}


def transcribe(wav: str, settings: Dict[str, Any]) -> Dict[str, Any]:
    """{"type": "stt_result", "text", "engine", ...} or {"type": "stt_error", "error", "code"}."""
    engine = settings["engine"]
    started = time.monotonic()
    try:
        reply = dict(ADAPTERS[engine](wav, settings))
    except EngineError as e:
        return {"type": "stt_error", "engine": engine, "error": str(e), "code": e.code}
    reply.update({"type": "stt_result", "engine": engine, "seconds": round(time.monotonic() - started, 2)})
    reply["text"] = str(reply.get("text", "")).strip()
    return reply


def _faster_whisper_installed(settings: Dict[str, Any]) -> bool:
    py = venv_python({"venv": settings["venv"]})
    if not py:
        return False
    return bool(glob.glob(os.path.join(settings["venv"], "lib", "python3*", "site-packages", "faster_whisper")))


def nvidia_gpu() -> bool:
    return os.path.exists("/proc/driver/nvidia/version") or os.path.exists("/dev/nvidia0")


def can_make_venv() -> bool:
    """Whether a venv for faster-whisper can be made here (python3 with venv and pip)."""
    import importlib.util
    return importlib.util.find_spec("venv") is not None and importlib.util.find_spec("ensurepip") is not None


def available(settings: Dict[str, Any]) -> List[Dict[str, Any]]:
    """One entry per engine: id, available (works now), selectable (can be finished
    on the settings page: installed, or a URL/command entered) and reason."""
    rows: List[Dict[str, Any]] = []
    fw = _faster_whisper_installed(settings)
    venv_ok = fw or can_make_venv()
    rows.append({"id": "faster-whisper", "available": fw, "selectable": venv_ok, "local": True, "gpu": nvidia_gpu(),
                 "installed": fw,
                 "reason": "" if fw else "not installed (one-click install, size shown first)" if venv_ok
                 else "Python's venv module is missing (install python3-venv)"})
    binary = find_binary(settings["whisper_cpp_binary"])
    model = settings["whisper_cpp_model"]
    if settings["whisper_cpp_server"]:
        rows.append({"id": "whisper-cpp", "available": True, "selectable": True, "local": True,
                     "reason": "server " + settings["whisper_cpp_server"]})
    else:
        reason = ("" if binary and model and os.path.isfile(model) else
                  "whisper-cli not found" if not binary else "needs a ggml model file")
        rows.append({"id": "whisper-cpp", "available": not reason, "selectable": bool(binary), "local": True,
                     "binary": binary, "reason": reason})
    rows.append({"id": "remote", "available": bool(settings["remote_url"]), "selectable": True, "local": False,
                 "reason": "" if settings["remote_url"] else "needs a server URL"})
    try:
        command_argv(settings["command"], "/tmp/x.wav", "auto")
        reason = ""
    except SettingsError as e:
        reason = str(e)
    rows.append({"id": "command", "available": not reason, "selectable": True, "local": True, "reason": reason})
    assert [r["id"] for r in rows] == list(ENGINES)
    return rows
