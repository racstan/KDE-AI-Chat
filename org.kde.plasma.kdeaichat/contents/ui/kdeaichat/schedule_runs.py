"""Per-schedule run state, written only by the background job.

``~/.local/share/kdeaichat/schedule-runs/<id>.json``::

    {"version": 1, "lastRunAt": iso|null, "lastSuccessAt": iso|null, "lastScheduledFor": iso|null,
     "runCount": 0, "lastStatus": str|null, "finished": false, "finishedAt": iso|null,
     "lastCheck": {"at": iso, "reason": str}|null,
     "history": [{"at": iso, "scheduledFor": iso|null, "status": str, "reason": str}]}

One file per schedule keeps the job's writes away from the widget's
definitions (no shared lock, no stale overwrite). Each file has its own
flock (``<id>.json.lock``) around read/modify/write, and writes are atomic.
The history is trimmed to the store's ``historyLimit`` on every write.
"""
import fcntl
import json
import os
from contextlib import contextmanager
from typing import Any, Dict, Iterator, List, Optional

from kdeaichat import chats
from kdeaichat.common import atomic_write_json
from kdeaichat.schedule_model import DEFAULT_HISTORY_LIMIT, ID_RE

MAX_RUN_STATE_BYTES = 2 * 1024 * 1024
MAX_HISTORY_LIMIT = 1000


def runs_dir() -> str:
    return os.path.join(chats.data_root(), "schedule-runs")


def run_state_path(sid: str) -> str:
    if not isinstance(sid, str) or not ID_RE.match(sid):
        raise ValueError("invalid schedule id")
    return os.path.join(runs_dir(), f"{sid}.json")


def empty_state() -> Dict[str, Any]:
    return {"version": 1, "lastRunAt": None, "lastSuccessAt": None, "lastScheduledFor": None, "runCount": 0,
            "lastStatus": None, "finished": False, "finishedAt": None, "lastCheck": None, "history": []}


def load_run_state(sid: str) -> Dict[str, Any]:
    """The state for ``sid``; a missing or unreadable file gives an empty state."""
    path = run_state_path(sid)
    state = empty_state()
    try:
        if os.path.getsize(path) > MAX_RUN_STATE_BYTES:
            return state
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return state
    if isinstance(data, dict):
        for key in state:
            if key in data and key != "version":
                state[key] = data[key]
    if not isinstance(state["history"], list):
        state["history"] = []
    try:
        state["runCount"] = max(0, int(state["runCount"] or 0))
    except (TypeError, ValueError):
        state["runCount"] = 0
    state["finished"] = state["finished"] is True
    return state


def history_limit(settings: Optional[Dict[str, Any]]) -> int:
    try:
        value = int((settings or {}).get("historyLimit", DEFAULT_HISTORY_LIMIT))
    except (TypeError, ValueError):
        value = DEFAULT_HISTORY_LIMIT
    return min(MAX_HISTORY_LIMIT, max(1, value))


def save_run_state(sid: str, state: Dict[str, Any], limit: int = DEFAULT_HISTORY_LIMIT) -> None:
    """Atomically write the state, keeping only the newest ``limit`` history entries."""
    out = dict(state)
    out["version"] = 1
    history: List[Any] = [h for h in out.get("history") or [] if isinstance(h, dict)]
    out["history"] = history[-max(1, limit):]
    os.makedirs(runs_dir(), mode=0o700, exist_ok=True)
    atomic_write_json(run_state_path(sid), out)


@contextmanager
def run_state_lock(sid: str) -> Iterator[None]:
    """Exclusive lock for one schedule's run state (job vs. job, job vs. migration)."""
    path = run_state_path(sid) + ".lock"
    os.makedirs(runs_dir(), mode=0o700, exist_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def remove_run_state(sid: str) -> None:
    """Delete a schedule's run state (under its lock), then the lock file."""
    with run_state_lock(sid):
        try:
            os.remove(run_state_path(sid))
        except FileNotFoundError:
            pass
    try:
        os.remove(run_state_path(sid) + ".lock")
    except FileNotFoundError:
        pass


# Decisions that use up their occurrence and belong in the history.
MISSED = ("missed-no-catchup", "outside-catchup-window")


def apply_decision(state: Dict[str, Any], decision: Dict[str, Any], now_iso: str) -> Dict[str, Any]:
    """Record a ``should_run`` decision in ``state`` (returns it).

    A run is recorded as ``running`` straight away, so its occurrence counts
    as handled even if the job dies during the run (never sent twice);
    ``finish_run`` then records the outcome.
    """
    reason = decision["reason"]
    occurrence = decision.get("occurrence")
    if decision["action"] == "run":
        state["lastScheduledFor"] = occurrence
        state["lastStatus"] = "running"
        state["history"].append({"at": now_iso, "scheduledFor": occurrence, "status": "running", "reason": reason})
    elif reason in MISSED:
        state["lastScheduledFor"] = occurrence
        state["lastStatus"] = "missed"
        state["history"].append({"at": now_iso, "scheduledFor": occurrence, "status": "missed", "reason": reason})
    state["lastCheck"] = {"at": now_iso, "reason": reason}
    return state


def finish_run(state: Dict[str, Any], occurrence: Optional[str], status: str, now_iso: str) -> Dict[str, Any]:
    """Record a run's outcome: "ok", "error: …" (both count as runs) or "skipped: …" (does not)."""
    entry = next((h for h in reversed(state["history"])
                  if isinstance(h, dict) and h.get("status") == "running" and h.get("scheduledFor") == occurrence), None)
    if entry is None:
        entry = {"at": now_iso, "scheduledFor": occurrence, "reason": "due"}
        state["history"].append(entry)
    entry["status"] = status
    entry["finishedAt"] = now_iso
    state["lastStatus"] = status
    if not status.startswith("skipped"):
        state["lastRunAt"] = now_iso
        state["runCount"] = int(state.get("runCount") or 0) + 1
    if status == "ok":
        state["lastSuccessAt"] = now_iso
    return state
