"""``run_schedule <id>``: what the systemd timer starts (kdeaichat-run@<id>.service).

The main principle: systemd wakes the job and Python decides. The job
loads the definition, asks ``should_run`` and records the decision in the
schedule's run-state file. It never writes the definitions.

!!! STUB (Phase 5 task t3 replaces it) !!!
This version only decides and records: a "run" decision is recorded with
status ``due-not-run`` (the occurrence counts as handled, so it is not
retried), but NO prompt is sent, no chat is written and no notification
is shown. The real per-mode run (direct / OpenCode / Pi, in the chat's own
mode) is the next task's job and plugs in at ``_run_prompt``.

Invocation: ``kde_ai_helper.py run_schedule <id>`` (a plain id, not a
base64 payload, because systemd passes the instance name ``%i``).
"""
import json
from typing import Any, Dict, Optional

from kdeaichat import schedule_store, schedule_units
from kdeaichat.schedule_model import ID_RE, iso, normalize_schedule, now_local
from kdeaichat.schedule_rules import has_future, should_run
from kdeaichat.schedule_runs import apply_decision, history_limit, load_run_state, run_state_lock, save_run_state


def _run_prompt(schedule: Dict[str, Any]) -> Optional[str]:
    """STUB: the real run comes in task t3. Returns None = "not run"."""
    return None


def run_schedule(sid: str, now=None, run=None) -> Dict[str, Any]:
    """Decide and record one wake-up; returns the decision (also printed by the command)."""
    if not isinstance(sid, str) or not ID_RE.match(sid):
        raise ValueError("invalid schedule id")
    now = now or now_local()
    # Read only: the job never writes definitions (nor migrates them).
    store = schedule_store.read_store() or schedule_store.empty_store()
    raw = schedule_store.find(store, sid)
    limit = history_limit(store.get("settings"))
    with run_state_lock(sid):
        state = load_run_state(sid)
        if raw is None:
            decision = {"action": "skip", "reason": "unknown-schedule", "occurrence": None, "late": False}
        else:
            try:
                schedule = normalize_schedule(raw, now=now)
            except ValueError as e:
                schedule = None
                decision = {"action": "skip", "reason": "invalid-schedule", "occurrence": None,
                            "late": False, "error": str(e)}
            if schedule is not None:
                decision = should_run(schedule, state, now)
                status = _run_prompt(schedule) if decision["action"] == "run" else None
                apply_decision(state, decision, iso(now), status)
                limit_hit = schedule.get("limitCount") and state["runCount"] >= schedule["limitCount"]
                if not state["finished"] and (limit_hit or not has_future(schedule, now)):
                    state["finished"], state["finishedAt"] = True, iso(now)
                    decision["finished"] = True
        if raw is not None:
            save_run_state(sid, state, limit)
    if decision.get("finished") or raw is None:   # done, or a stray timer for a deleted schedule
        schedule_units.disable_timer(sid, run)
    return decision


def cmd_run_schedule(payload: Dict[str, Any]) -> None:
    decision = run_schedule(str(payload.get("id", "")))
    print(json.dumps(decision))


COMMANDS = {"run_schedule": cmd_run_schedule}
