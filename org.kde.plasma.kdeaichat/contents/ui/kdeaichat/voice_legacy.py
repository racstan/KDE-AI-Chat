"""Removes what the old built-in voice engines left running: their systemd user units and processes.

Before 1.4.0 the widget ran its own speech models: an always-on ``kde-ai-tts.service`` (read aloud),
an always-on ``kde-ai-stt.service`` and, later, the socket-activated ``kde-ai-stt.socket`` with its
service (dictation), plus a Kokoro worker. All speech now goes through Speech Note, so
``voice_startup`` (run once at widget start when one of those unit files exists) stops and disables
the units, deletes their files and stops servers started by hand. The old venvs and models stay on
disk: Settings → Storage deletes them after a confirmation (it calls ``cleanup_old_units`` and
``stop_kokoro_worker`` again for the running parts).

Idempotent and cheap: with no unit file and no such process it does nothing. The unit folder and
systemctl can be redirected (``KDEAICHAT_UNIT_DIR``, ``KDEAICHAT_SYSTEMCTL``) like the schedule units;
with ``KDEAICHAT_UNIT_DIR`` set (tests, dev sandbox) other processes are left alone.
"""
import json
import os
import signal
import socket
import tempfile
from typing import Any, Callable, Dict, List, Optional

from kdeaichat import procs, schedule_units

LEGACY_UNITS = ("kde-ai-stt.socket", "kde-ai-stt.service", "kde-ai-tts.service")
_SERVER_FLAGS = ("--tts-server", "--stt-server")   # voice_helper.py servers of the oldest versions
_WANTS = ("default.target.wants", "sockets.target.wants")


def _server_pids() -> List[int]:
    """Our processes running ``voice_helper.py --tts-server`` / ``--stt-server``, from /proc."""
    pids = []
    uid = os.getuid()
    for name in os.listdir("/proc") if os.path.isdir("/proc") else []:
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            if os.stat(f"/proc/{name}").st_uid != uid:
                continue
        except OSError:
            continue
        argv = procs.cmdline(int(name))
        if any(a in _SERVER_FLAGS for a in argv) and any(os.path.basename(a) == "voice_helper.py" for a in argv):
            pids.append(int(name))
    return pids


def _unit_paths(directory: str, name: str) -> List[str]:
    return [os.path.join(directory, name)] + [os.path.join(directory, wants, name) for wants in _WANTS]


def stop_kokoro_worker(folder: str) -> bool:
    """Asks an idle Kokoro worker (the old natural voice) to exit; it listens on ``kokoro.sock`` in ``folder``."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(3)
            conn.connect(os.path.join(folder, "kokoro.sock"))
            conn.sendall(b'{"op": "stop"}\n')
        return True
    except OSError:
        return False


def cleanup_old_units(run: Optional[Callable[[List[str]], int]] = None, allow_kill: bool = False) -> Dict[str, Any]:
    run = run or schedule_units.systemctl
    directory = schedule_units.unit_dir()
    done: Dict[str, Any] = {"units": [], "killed": 0, "marker": False}
    present = [n for n in LEGACY_UNITS if any(os.path.lexists(p) for p in _unit_paths(directory, n))]
    if present:
        run(["disable", "--now"] + present)
        for name in present:
            for path in _unit_paths(directory, name):
                if os.path.lexists(path):
                    try:
                        os.unlink(path)
                    except OSError:
                        pass
        run(["daemon-reload"])
        run(["reset-failed"] + present)
        done["units"] = present
    sandboxed = bool(os.environ.get("KDEAICHAT_UNIT_DIR")) and not allow_kill
    for pid in [] if sandboxed else _server_pids():
        try:
            os.kill(pid, signal.SIGTERM)
            done["killed"] += 1
        except OSError:
            pass
    marker = os.path.join(tempfile.gettempdir(), "kdeaichat_stop_tts")
    if not sandboxed and os.path.isfile(marker) and not os.path.islink(marker):
        try:
            os.remove(marker)
            done["marker"] = True
        except OSError:
            pass
    done["changed"] = bool(done["units"] or done["killed"] or done["marker"])
    return done


def cmd_voice_startup(payload: Dict[str, Any]) -> None:
    print(json.dumps({"ok": True, "legacy": cleanup_old_units()}))


COMMANDS = {
    "voice_startup": cmd_voice_startup,
}
