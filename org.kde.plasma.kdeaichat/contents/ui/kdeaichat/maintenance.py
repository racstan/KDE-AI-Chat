"""Chat export, and stopping the plasmashell watchdog of versions before 1.4.0."""
import base64
import json
import os
import signal
from typing import Any, Dict, List

from kdeaichat.common import MAX_FILE_BYTES, atomic_write_text, safe_path


def cmd_export_chat(payload: Dict[str, Any]) -> None:
    """Decode a base64 chat export and write it to ``filePath`` as UTF-8."""
    path = safe_path(payload.get("filePath", ""))
    data = base64.b64decode(str(payload.get("b64Content", "")), validate=True)
    if len(data) > MAX_FILE_BYTES:
        raise ValueError("chat export is too large")
    atomic_write_text(path, data.decode("utf-8"))
    print("OK")


def _legacy_watchdog_pids(helper_name: str = "kde_ai_helper.py") -> List[int]:
    """PIDs of monitors started by the removed plasmashell watchdog.

    Matched by exact command line (``... kde_ai_helper.py plasmashell_watchdog
    <payload>``) so a reused PID or an unrelated process is never signalled.
    """
    pids = []
    try:
        entries = os.listdir("/proc")
    except OSError:
        return pids
    for entry in entries:
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(os.path.join("/proc", entry, "cmdline"), "rb") as f:
                argv = [part.decode("utf-8", "replace") for part in f.read().split(b"\0") if part]
        except OSError:
            continue
        for i, arg in enumerate(argv[:-1]):
            if os.path.basename(arg) == helper_name and argv[i + 1] == "plasmashell_watchdog":
                pids.append(int(entry))
                break
    return pids


def cmd_stop_legacy_watchdog(payload: Dict[str, Any]) -> None:
    """Stop a plasmashell watchdog left running by a version before 1.4.0.

    That monitor survives widget upgrades and restarts plasmashell once its
    heartbeat file goes stale, which it always does now that nothing writes
    it. Stop it and remove its files.
    """
    stopped = []
    for pid in _legacy_watchdog_pids():
        try:
            os.kill(pid, signal.SIGTERM)
            stopped.append(pid)
        except OSError:
            pass
    folder = os.path.expanduser("~/.local/share/kdeaichat")
    for name in ("plasmashell-heartbeat", "plasmashell-watchdog.pid", "plasmashell-watchdog.last-restart"):
        try:
            os.unlink(os.path.join(folder, name))
        except OSError:
            pass
    print(json.dumps({"status": "ok", "stopped": stopped}))


COMMANDS = {
    "export_chat": cmd_export_chat,
    "stop_legacy_watchdog": cmd_stop_legacy_watchdog,
}
