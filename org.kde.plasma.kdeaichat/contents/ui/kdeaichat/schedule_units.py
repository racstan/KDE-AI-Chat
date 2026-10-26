"""Write, enable and remove the systemd user units for schedules.

``sync_units`` makes the unit folder match the definitions: one
``kdeaichat-sched-<id>.timer`` per schedule that can still fire, the shared
``kdeaichat-run@.service`` template, and nothing else named
``kdeaichat-sched-*``. Only changed files are rewritten, and systemctl is
only called for units that changed.

Both the unit folder and the systemctl program can be redirected so tests
never touch the real user manager: ``KDEAICHAT_UNIT_DIR`` and
``KDEAICHAT_SYSTEMCTL`` (or the ``unit_dir``/``systemctl`` arguments).
"""
import datetime as dt
import os
import re
import subprocess
from typing import Any, Callable, Dict, List, Optional

from kdeaichat.common import atomic_write_text
from kdeaichat.schedule_calendar import SERVICE_TEMPLATE, TIMER_PREFIX, service_text, timer_name, timer_text
from kdeaichat.schedule_rules import has_future, is_finished

Systemctl = Callable[[List[str]], int]
_TIMER_FILE = re.compile(r"^" + re.escape(TIMER_PREFIX) + r"([A-Za-z0-9-]{1,64})\.timer$")


def unit_dir() -> str:
    override = os.environ.get("KDEAICHAT_UNIT_DIR")
    if override:
        return override
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(config, "systemd", "user")


def systemctl(args: List[str]) -> int:
    """``systemctl --user <args>``; returns the exit code (127 if missing)."""
    program = os.environ.get("KDEAICHAT_SYSTEMCTL") or "systemctl"
    try:
        return subprocess.run([program, "--user", *args], capture_output=True, timeout=60).returncode
    except (OSError, subprocess.SubprocessError):
        return 127


def wants_timer(schedule: Dict[str, Any], run_state: Dict[str, Any], now: dt.datetime) -> bool:
    if not schedule.get("enabled", True) or schedule.get("archived") or is_finished(schedule, run_state):
        return False
    return bool(schedule.get("rules")) and has_future(schedule, now)


def _read(path: str) -> Optional[str]:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def sync_units(schedules: List[Dict[str, Any]], run_states: Dict[str, Dict[str, Any]], *,
               now: Optional[dt.datetime] = None, directory: Optional[str] = None,
               run: Optional[Systemctl] = None, helper: Optional[str] = None,
               ensure_enabled: bool = False) -> Dict[str, Any]:
    """Make the unit folder match ``schedules``; returns what changed.

    ``ensure_enabled`` also runs ``enable --now`` for unchanged timers (full sync).
    """
    now = now or dt.datetime.now().replace(microsecond=0)
    directory = directory or unit_dir()
    run = run or systemctl
    desired = {s["id"]: timer_text(s) for s in schedules if wants_timer(s, run_states.get(s["id"], {}), now)}
    existing = set()
    if os.path.isdir(directory):
        existing = {m.group(1) for m in map(_TIMER_FILE.match, os.listdir(directory)) if m}
    written: List[str] = []
    removed = sorted(existing - set(desired))
    errors: List[str] = []

    template_path = os.path.join(directory, SERVICE_TEMPLATE)
    template = service_text(helper)
    template_changed = bool(desired) and _read(template_path) != template
    if template_changed:
        atomic_write_text(template_path, template, mode=0o644)
    for sid, text in sorted(desired.items()):
        path = os.path.join(directory, timer_name(sid))
        if _read(path) != text:
            atomic_write_text(path, text, mode=0o644)
            written.append(sid)

    for sid in removed:
        name = timer_name(sid)
        run(["disable", "--now", name])
        run(["clean", "--what=state", name])
        try:
            os.remove(os.path.join(directory, name))
        except FileNotFoundError:
            pass
    if written or removed or template_changed:
        if run(["daemon-reload"]) != 0:
            errors.append("systemctl --user daemon-reload failed")
    for sid in written:
        name = timer_name(sid)
        if run(["enable", name]) != 0 or run(["restart", name]) != 0:
            errors.append(f"could not start {name}")
    if ensure_enabled:
        for sid in sorted(set(desired) - set(written)):
            if run(["enable", "--now", timer_name(sid)]) != 0:
                errors.append(f"could not start {timer_name(sid)}")
    return {"written": written, "removed": removed, "templateChanged": template_changed,
            "errors": errors, "timers": sorted(desired)}


def disable_timer(sid: str, run: Optional[Systemctl] = None) -> int:
    """Stop and disable one schedule's timer (used when a schedule finishes)."""
    return (run or systemctl)(["disable", "--now", timer_name(sid)])
