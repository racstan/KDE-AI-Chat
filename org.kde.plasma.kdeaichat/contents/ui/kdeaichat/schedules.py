"""Schedule commands the chat widget itself runs.

- ``delete_session_schedules {sessionId}``: a deleted chat takes its schedules along.
- ``schedules_startup {}``: run once each time the widget starts. Removes what
  the pre-1.4.0 scheduler left behind, migrates schedules.json to
  schedules.v2.json if that hasn't happened yet, and makes the systemd timers
  match the definitions (also rewriting the run@ template when the widget's
  install path changed). Idempotent and cheap when there is nothing to do:
  systemctl is only called for units that changed.

The pre-1.4.0 scheduler was a daemon polling every 5 s
(``~/.local/share/kdeaichat/kde-ai-scheduler.py``, unit
``kde-ai-scheduler.service``) dropping trigger files into ``pending/`` that
the widget polled for every 3 s; ``results/`` was never used. All of it is
stopped and removed. Leftover triggers can't be delivered any more (each
schedule now runs by itself in its chat), so they are deleted and counted.
"""
import json
import os
import shutil
import signal
from typing import Any, Dict, List

from kdeaichat import chats, schedule_store, schedule_units

LEGACY_UNIT = "kde-ai-scheduler.service"
LEGACY_SCRIPT = "kde-ai-scheduler.py"


def _legacy_daemon_pids(script: str) -> List[int]:
    """Our processes running the copied daemon script (exact path), from /proc."""
    pids = []
    uid = os.getuid()
    for name in os.listdir("/proc") if os.path.isdir("/proc") else []:
        if not name.isdigit():
            continue
        try:
            if os.stat(f"/proc/{name}").st_uid != uid:
                continue
            with open(f"/proc/{name}/cmdline", "rb") as f:
                argv = f.read().split(b"\0")
        except OSError:
            continue
        if any(arg.decode("utf-8", "replace") == script for arg in argv[:3]):
            pids.append(int(name))
    return pids


def cleanup_legacy(run=None) -> Dict[str, Any]:
    """Stop and remove the old scheduler daemon, its unit, pending/ and results/."""
    run = run or schedule_units.systemctl
    root = chats.data_root()
    done: Dict[str, Any] = {"unit": False, "script": False, "killed": 0, "droppedTriggers": 0, "removedDirs": []}
    unit = os.path.join(schedule_units.unit_dir(), LEGACY_UNIT)
    if os.path.lexists(unit):
        run(["disable", "--now", LEGACY_UNIT])
        os.remove(unit)
        run(["daemon-reload"])
        run(["reset-failed", LEGACY_UNIT])
        done["unit"] = True
    script = os.path.join(root, LEGACY_SCRIPT)
    for pid in _legacy_daemon_pids(script):   # also one started by hand (the old nohup fallback)
        try:
            os.kill(pid, signal.SIGTERM)
            done["killed"] += 1
        except OSError:
            pass
    if os.path.lexists(script):
        os.remove(script)
        done["script"] = True
    for name in ("pending", "results"):
        path = os.path.join(root, name)
        if os.path.islink(path):
            os.remove(path)
        elif os.path.isdir(path):
            if name == "pending":
                done["droppedTriggers"] = sum(1 for f in os.listdir(path) if f.endswith(".json"))
            shutil.rmtree(path, ignore_errors=True)
        else:
            continue
        done["removedDirs"].append(name)
    done["changed"] = bool(done["unit"] or done["script"] or done["killed"] or done["removedDirs"])
    return done


def cmd_schedules_startup(payload: Dict[str, Any]) -> None:
    legacy = cleanup_legacy()
    units = schedule_store.sync_all(ensure_enabled=legacy["changed"])
    print(json.dumps({"ok": not units["errors"], "legacy": legacy, "units": units}))


def cmd_delete_session_schedules(payload: Dict[str, Any]) -> None:
    """Remove every schedule whose ``chatId`` matches ``sessionId``."""
    session_id = str(payload.get("sessionId", ""))
    if session_id:
        removed = schedule_store.delete_schedules(lambda s: s.get("chatId") == session_id)
        print(json.dumps({"ok": True, "removed": removed["removed"]}))


COMMANDS = {
    "delete_session_schedules": cmd_delete_session_schedules,
    "schedules_startup": cmd_schedules_startup,
}
