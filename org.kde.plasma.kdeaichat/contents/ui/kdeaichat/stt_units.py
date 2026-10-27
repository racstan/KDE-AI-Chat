"""The local dictation service's systemd user units, and removing the old always-on one.

``sync`` runs at every widget start (idempotent, only calls systemctl for
what changed):

1. The pre-1.4 ``kde-ai-stt.service`` (``voice_helper.py --stt-server``,
   ``Restart=always``, enabled at login, a Whisper model loaded all day) is
   disabled, stopped and deleted in every case.
2. With dictation on and a local engine chosen (Parakeet or faster-whisper,
   its venv installed),
   ``kde-ai-stt.socket`` listens on 127.0.0.1:9015 and starts
   ``kde-ai-stt.service`` (``voice/stt_service.py``) on the first request;
   the service exits after ``sttIdleMinutes`` (default 5) idle minutes.
3. Otherwise the new units are disabled and removed too: with dictation off
   no voice unit, socket or process exists.

Unit folder and systemctl follow ``KDEAICHAT_UNIT_DIR`` /
``KDEAICHAT_SYSTEMCTL`` like the schedule units (tests, dev sandbox).
"""
import os
import signal
from typing import Any, Callable, Dict, List, Optional

from kdeaichat import procs, schedule_units, voice_services
from kdeaichat.common import atomic_write_text
from kdeaichat.stt_engines import token_path
from kdeaichat.stt_settings import DEFAULT_ENGINE, DEFAULT_PORT, LOCAL_SERVICE_ENGINES, venv_python

SOCKET = "kde-ai-stt.socket"
SERVICE = "kde-ai-stt.service"
IDLE_SECONDS = 300
_UI_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_LEGACY_MARKERS = ("--stt-server", "Restart=always")


def service_script() -> str:
    return os.path.join(_UI_DIR, "voice", "stt_service.py")


def idle_seconds(payload: Dict[str, Any]) -> int:
    """``sttIdleMinutes`` (1-120, default 5): how long the model stays loaded after the last use."""
    try:
        minutes = int(payload.get("sttIdleMinutes", 5))
    except (TypeError, ValueError):
        minutes = 5
    return 60 * max(1, min(120, minutes))


def socket_text(port: int = DEFAULT_PORT) -> str:
    return f"""[Unit]
Description=KDE AI Chat speech-to-text socket (starts the service on demand)

[Socket]
ListenStream=127.0.0.1:{port}
Accept=no

[Install]
WantedBy=sockets.target
"""


def service_text(python: str, script: str, token: str, idle: int = IDLE_SECONDS) -> str:
    q = voice_services._systemd_quote
    return f"""[Unit]
Description=KDE AI Chat speech-to-text (Parakeet / faster-whisper, exits when idle)
Requires={SOCKET}
After={SOCKET}

[Service]
Type=simple
ExecStart={q(python)} {q(script)} --token-file {q(token)} --idle-timeout {idle}
Environment=PYTHONUNBUFFERED=1
NoNewPrivileges=yes
Restart=no
"""


def _read(path: str) -> Optional[str]:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def is_legacy(text: Optional[str]) -> bool:
    return bool(text) and any(marker in text for marker in _LEGACY_MARKERS) and "stt_service.py" not in text


def legacy_pids(allow_kill: bool = False) -> List[int]:
    """Old servers started by hand (``voice_helper.py --stt-server``), matched by exact argv.

    A sandbox (dev run, tests) with its own unit folder (``KDEAICHAT_UNIT_DIR``)
    leaves the user's processes alone unless ``allow_kill`` is set.
    """
    if os.environ.get("KDEAICHAT_UNIT_DIR") and not allow_kill:
        return []
    pids = []
    for entry in os.listdir("/proc"):
        if entry.isdigit() and int(entry) != os.getpid():
            argv = procs.cmdline(int(entry))
            if any(os.path.basename(a) == "voice_helper.py" and argv[i + 1] == "--stt-server"
                   for i, a in enumerate(argv[:-1])):
                pids.append(int(entry))
    return pids


def _remove(directory: str, names: List[str]) -> List[str]:
    removed = []
    for name in names:
        for path in (os.path.join(directory, name), os.path.join(directory, "default.target.wants", name),
                     os.path.join(directory, "sockets.target.wants", name)):
            if os.path.lexists(path):
                try:
                    os.unlink(path)
                    removed.append(path)
                except OSError:
                    pass
    return removed


def sync(payload: Dict[str, Any], directory: Optional[str] = None,
         run: Optional[Callable[[List[str]], int]] = None, allow_kill: bool = False) -> Dict[str, Any]:
    directory = directory or schedule_units.unit_dir()
    run = run or schedule_units.systemctl
    service_path = os.path.join(directory, SERVICE)
    socket_path = os.path.join(directory, SOCKET)
    result: Dict[str, Any] = {"legacy_removed": False, "installed": False, "removed": False, "changed": False}

    current = _read(service_path)
    legacy_enabled = os.path.lexists(os.path.join(directory, "default.target.wants", SERVICE))
    if is_legacy(current) or legacy_enabled:
        run(["disable", "--now", SERVICE])
        _remove(directory, [SERVICE])
        result["legacy_removed"] = result["changed"] = True
        current = None
    for pid in legacy_pids(allow_kill):
        try:
            os.kill(pid, signal.SIGTERM)
            result["legacy_removed"] = True
        except OSError:
            pass

    enabled = payload.get("sttEnabled") is True
    engine = str(payload.get("sttEngine") or DEFAULT_ENGINE)
    python = venv_python(payload)
    want = enabled and engine in LOCAL_SERVICE_ENGINES and bool(python) and os.path.isfile(service_script())

    if want:
        token = token_path()
        voice_services.ensure_voice_http_token(token)
        wanted = {socket_path: socket_text(),
                  service_path: service_text(python, service_script(), token, idle_seconds(payload))}
        changed = [p for p, text in wanted.items() if _read(p) != text]
        for path in changed:
            atomic_write_text(path, wanted[path], mode=0o644)
        socket_enabled = os.path.lexists(os.path.join(directory, "sockets.target.wants", SOCKET))
        if changed or result["legacy_removed"]:
            run(["daemon-reload"])
        if changed or not socket_enabled:
            if service_path in changed:
                run(["stop", SERVICE])  # an idle-running copy picks up the new unit on its next start
            run(["enable", "--now", SOCKET])
            result["changed"] = True
        result["installed"] = True
    elif current is not None or _read(socket_path) is not None:
        run(["disable", "--now", SOCKET, SERVICE])
        _remove(directory, [SOCKET, SERVICE])
        run(["daemon-reload"])
        result["removed"] = result["changed"] = True
    elif result["legacy_removed"]:
        run(["daemon-reload"])
    result["reason"] = ("" if want else "dictation is off" if not enabled else
                        "another engine is chosen" if engine not in LOCAL_SERVICE_ENGINES
                        else engine + " is not installed")
    return result
