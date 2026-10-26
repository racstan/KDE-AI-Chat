"""``run_schedule <id>``: what the systemd timer starts (kdeaichat-run@<id>.service).

The main principle: systemd wakes the job and Python decides. The job
loads the definition, asks ``should_run`` and records the decision in the
schedule's run-state file. It never writes the definitions.

A "run" decision is recorded at once as ``running`` (the occurrence counts
as handled, so a second wake-up or a crash never runs it twice), then the
run-state lock is released while the prompt runs (schedule_exec: the chat's
own mode, the reply into the chat, a notification), and the outcome is
recorded under the lock again: "ok", "error: …" or "skipped: …".

Invocation: ``kde_ai_helper.py run_schedule <id>`` (a plain id, not a
base64 payload, because systemd passes the instance name ``%i``).
"""
import json
from typing import Any, Dict

from kdeaichat import schedule_exec, schedule_store, schedule_units
from kdeaichat.schedule_model import ID_RE, iso, normalize_schedule, now_local
from kdeaichat.schedule_rules import has_future, should_run
from kdeaichat.schedule_runs import (apply_decision, finish_run, history_limit, load_run_state, run_state_lock,
                                     save_run_state)


def _run_prompt(schedule: Dict[str, Any], state: Dict[str, Any], now) -> str:
    """Runs the prompt; returns the status. Tests replace it."""
    return schedule_exec.run_prompt(schedule, state.get("lastSuccessAt"), now)


def _check_finished(schedule: Dict[str, Any], state: Dict[str, Any], now, decision: Dict[str, Any]) -> None:
    limit_hit = schedule.get("limitCount") and state["runCount"] >= schedule["limitCount"]
    if not state["finished"] and (limit_hit or not has_future(schedule, now)):
        state["finished"], state["finishedAt"] = True, iso(now)
        decision["finished"] = True


def run_schedule(sid: str, now=None, run=None) -> Dict[str, Any]:
    """Decide, run and record one wake-up; returns the decision (also printed by the command)."""
    if not isinstance(sid, str) or not ID_RE.match(sid):
        raise ValueError("invalid schedule id")
    now = now or now_local()
    # Read only: the job never writes definitions (nor migrates them).
    store = schedule_store.read_store() or schedule_store.empty_store()
    raw = schedule_store.find(store, sid)
    limit = history_limit(store.get("settings"))
    schedule = None
    with run_state_lock(sid):
        state = load_run_state(sid)
        if raw is None:
            decision = {"action": "skip", "reason": "unknown-schedule", "occurrence": None, "late": False}
        else:
            try:
                schedule = normalize_schedule(raw, now=now)
            except ValueError as e:
                decision = {"action": "skip", "reason": "invalid-schedule", "occurrence": None,
                            "late": False, "error": str(e)}
            if schedule is not None:
                decision = should_run(schedule, state, now)
                apply_decision(state, decision, iso(now))
                if decision["action"] != "run":
                    _check_finished(schedule, state, now, decision)
        if raw is not None:
            save_run_state(sid, state, limit)
    if schedule is not None and decision["action"] == "run":
        status = _run_prompt(schedule, state, now)
        decision["status"] = status
        with run_state_lock(sid):
            state = load_run_state(sid)
            finish_run(state, decision.get("occurrence"), status, iso(now_local()))
            _check_finished(schedule, state, now, decision)
            save_run_state(sid, state, limit)
    if decision.get("finished") or raw is None:   # done, or a stray timer for a deleted schedule
        schedule_units.disable_timer(sid, run)
    return decision


def cmd_run_schedule(payload: Dict[str, Any]) -> None:
    decision = run_schedule(str(payload.get("id", "")))
    print(json.dumps(decision))


COMMANDS = {"run_schedule": cmd_run_schedule}
