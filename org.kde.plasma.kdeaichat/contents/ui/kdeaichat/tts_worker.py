"""Talks to the natural-voice service (``voice/tts_service.py``) for read aloud.

The service runs in the read-aloud venv and is started here, on the first
sentence to speak: detached from the helper, listening on a Unix socket in
the private speech folder (``tts.out_dir()``, 0700). It exits by itself
after ``IDLE_SECONDS`` without a request, so nothing runs while read aloud
is idle and there is no unit, port or token. Two helpers starting it at once
are serialised by a lock file; a socket left by a crashed copy is replaced.

``KDEAICHAT_TTS_FAKE=1`` starts the service with its tone generator instead
of the model (tests, dev runs).
"""
import fcntl
import json
import os
import socket
import subprocess
import time
from typing import Any, Dict, Optional

from kdeaichat import tts_neural

IDLE_SECONDS = 120
START_SECONDS = 30      # for the service to listen (the model loads on the first request)
REQUEST_SECONDS = 120   # one sentence, including loading the model the first time
_UI_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class TtsError(RuntimeError):
    """A read-aloud failure; ``code`` "not_installed" lets the widget use the system voice instead."""

    def __init__(self, message: str, code: str = "failed"):
        super().__init__(message)
        self.code = code


def service_script() -> str:
    return os.path.join(_UI_DIR, "voice", "tts_service.py")


def socket_path(folder: str) -> str:
    return os.path.join(folder, "kokoro.sock")


def _request(path: str, data: Dict[str, Any], timeout: float) -> Dict[str, Any]:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        conn.settimeout(timeout)
        conn.connect(path)
        conn.sendall((json.dumps(data) + "\n").encode("utf-8"))
        reply = b""
        while not reply.endswith(b"\n"):
            chunk = conn.recv(65536)
            if not chunk:
                break
            reply += chunk
    try:
        result = json.loads(reply.decode("utf-8"))
    except (ValueError, UnicodeError):
        raise TtsError("the natural voice gave no answer") from None
    return result if isinstance(result, dict) else {"ok": False, "error": "bad answer"}


def alive(folder: str) -> bool:
    try:
        return _request(socket_path(folder), {"op": "status"}, 2).get("ok") is True
    except (OSError, TtsError):
        return False


def _start(folder: str, python: str) -> None:
    argv = [python, "-I", service_script(), "--socket", socket_path(folder), "--out-dir", folder,
            "--idle-timeout", str(IDLE_SECONDS)]
    if os.environ.get("KDEAICHAT_TTS_FAKE") == "1":
        argv.append("--fake")
    log = open(os.path.join(folder, "service.log"), "ab")
    try:
        # Detached and with no pipe to the helper, so the widget's helper call ends at once.
        subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True,
                         close_fds=True, cwd=folder)
    finally:
        log.close()


def ensure_running(folder: str, python: str, wait: float = START_SECONDS) -> None:
    if alive(folder):
        return
    with open(os.path.join(folder, "service.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if alive(folder):
            return
        _start(folder, python)
        deadline = time.monotonic() + wait
        while time.monotonic() < deadline:
            if alive(folder):
                return
            time.sleep(0.05)
    raise TtsError("the natural voice did not start (see %s)" % os.path.join(folder, "service.log"))


def synthesize(text: str, options: Dict[str, Any], out_path: str, pause_ms: int = 0) -> Dict[str, Any]:
    """Writes ``out_path`` (in the speech folder) with the natural voice."""
    python = tts_neural.venv_python()
    if not python or not tts_neural.packages_installed():
        raise TtsError("the natural voice is not installed", "not_installed")
    files = tts_neural.model_files()
    if not files:
        raise TtsError("the natural voice model is not downloaded", "not_installed")
    folder = os.path.dirname(out_path)
    ensure_running(folder, python)
    voice = str(options.get("voiceTtsNeuralVoice") or tts_neural.DEFAULT_VOICE)
    try:
        speed = float(options.get("voiceTtsNeuralSpeed") or 1)
    except (TypeError, ValueError):
        speed = 1.0
    request = {"op": "synthesize", "text": text, "voice": voice, "speed": speed, "out": out_path,
               "pause_ms": pause_ms, "model": files["model"], "voices": files["voices"]}
    try:
        reply = _request(socket_path(folder), request, REQUEST_SECONDS)
    except socket.timeout:
        raise TtsError("the natural voice took too long") from None
    except OSError as e:
        raise TtsError("the natural voice can't be reached: %s" % (e.strerror or e)) from None
    if reply.get("ok") is not True:
        raise TtsError(str(reply.get("error") or "the natural voice failed"))
    return reply


def stop(folder: str) -> bool:
    """Asks a running service to exit now (read aloud switched off, or its data removed)."""
    try:
        return _request(socket_path(folder), {"op": "stop"}, 5).get("ok") is True
    except (OSError, TtsError):
        return False


def status(folder: str) -> Optional[Dict[str, Any]]:
    try:
        return _request(socket_path(folder), {"op": "status"}, 2)
    except (OSError, TtsError):
        return None
