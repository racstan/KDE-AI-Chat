"""Schedule commands, unit sync, run state and the run_schedule stub (temp folders, fake systemctl)."""
import base64
import datetime as dt
import json
import os
import subprocess
import sys
import threading

import pytest

from kdeaichat import schedule_job, schedule_runs, schedule_store, schedules
from kdeaichat.schedule_model import iso

from tests.conftest import UI_DIR

HELPER = os.path.join(UI_DIR, "kde_ai_helper.py")
OWNER = {"name": "Latest news", "chatId": "chat-news", "message": "Fetch the latest news since {{last_run}}",
         "rules": [{"kind": "weekly", "days": [1], "times": ["16:00"]},
                   {"kind": "weekly", "days": [2, 3, 4, 5, 6, 0], "times": ["15:00"]}]}


def call(cmd, payload, capsys):
    getattr(schedule_store, "cmd_" + cmd)(payload)
    return json.loads(capsys.readouterr().out)


def save(capsys, schedule):
    return call("schedule_save", {"schedule": schedule}, capsys)


def test_save_writes_definition_and_timer(sched_env, capsys):
    out = save(capsys, dict(OWNER, id="news-1"))
    assert out["ok"], out
    assert out["schedule"]["editedAt"] and out["units"]["written"] == ["news-1"]
    timer = os.path.join(sched_env.units, "kdeaichat-sched-news-1.timer")
    with open(timer) as f:
        text = f.read()
    assert "OnCalendar=Mon *-*-* 16:00:00\nOnCalendar=Tue..Sun *-*-* 15:00:00\n" in text
    assert os.path.exists(os.path.join(sched_env.units, "kdeaichat-run@.service"))
    assert sched_env.calls() == ["--user daemon-reload", "--user enable kdeaichat-sched-news-1.timer",
                                 "--user restart kdeaichat-sched-news-1.timer"]
    # saving again unchanged does not touch systemd; editedAt stays
    first = out["schedule"]["editedAt"]
    out = save(capsys, dict(out["schedule"], name="Renamed"))
    assert out["units"]["written"] == [] and len(sched_env.calls()) == 3
    assert out["schedule"]["editedAt"] == first and out["schedule"]["name"] == "Renamed"


def test_save_rejects_invalid_and_never(sched_env, capsys):
    assert save(capsys, dict(OWNER, rules=[{"kind": "minutes", "everyMinutes": 5}]))["ok"] is False
    out = save(capsys, dict(OWNER, rules=[{"kind": "once", "at": "2020-01-01T10:00"}]))
    assert out["ok"] is False and "never" in out["error"]
    assert call("schedule_save", {"schedule": "nope"}, capsys)["ok"] is False
    assert not os.path.exists(sched_env.units)


def test_disable_and_delete_remove_timers(sched_env, capsys):
    saved = save(capsys, dict(OWNER, id="news-2"))["schedule"]
    out = save(capsys, dict(saved, enabled=False))
    assert out["units"]["removed"] == ["news-2"]
    assert not os.path.exists(os.path.join(sched_env.units, "kdeaichat-sched-news-2.timer"))
    assert "--user disable --now kdeaichat-sched-news-2.timer" in sched_env.calls()
    assert "--user clean --what=state kdeaichat-sched-news-2.timer" in sched_env.calls()
    save(capsys, dict(saved, enabled=True))
    schedule_runs.save_run_state("news-2", {"runCount": 1, "history": []})
    out = call("schedule_delete", {"id": "news-2"}, capsys)
    assert out["removed"] == ["news-2"] and out["units"]["removed"] == ["news-2"]
    assert schedule_store.load_store()["schedules"] == []
    assert not os.path.exists(schedule_runs.run_state_path("news-2"))
    assert call("schedule_delete", {"id": "../x"}, capsys)["ok"] is False


def test_sync_removes_stray_units_and_enables(sched_env, capsys):
    save(capsys, dict(OWNER, id="keep"))
    stray = os.path.join(sched_env.units, "kdeaichat-sched-gone.timer")
    with open(stray, "w") as f:
        f.write("[Timer]\n")
    other = os.path.join(sched_env.units, "unrelated.timer")
    with open(other, "w") as f:
        f.write("[Timer]\n")
    out = call("schedules_sync", {}, capsys)
    assert out["ok"] and out["units"]["removed"] == ["gone"] and out["units"]["timers"] == ["keep"]
    assert not os.path.exists(stray) and os.path.exists(other)
    assert "--user enable --now kdeaichat-sched-keep.timer" in sched_env.calls()


def test_systemctl_failure_is_reported(sched_env, capsys, monkeypatch):
    monkeypatch.setenv("FAKE_SYSTEMCTL_EXIT", "1")
    out = save(capsys, dict(OWNER, id="news-3"))
    assert out["ok"] and out["units"]["errors"]


def test_list_and_preview(sched_env, capsys):
    save(capsys, dict(OWNER, id="news-4"))
    out = call("schedules_list", {}, capsys)
    item = out["schedules"][0]
    assert item["summary"] == "Mon 16:00; Tue–Sun 15:00" and len(item["nextRuns"]) == 3
    assert item["runState"]["runCount"] == 0 and "history" not in item["runState"]
    prev = call("schedule_preview", {"schedule": {"rules": [{"kind": "daily", "times": ["02:30"]}]}, "count": 5},
                capsys)
    assert prev["ok"] and len(prev["nextRuns"]) == 5 and prev["rules"] == ["Every day at 02:30"]
    assert any("02:00" in w for w in prev["warnings"])
    bad = call("schedule_preview", {"schedule": {"rules": [{"kind": "daily", "times": ["25:00"]}]}}, capsys)
    assert bad["ok"] is False and "HH:MM" in bad["error"]


def test_deleting_a_chat_removes_its_v2_schedules(sched_env, capsys):
    save(capsys, dict(OWNER, id="news-5"))
    save(capsys, dict(OWNER, id="other", chatId="chat-other"))
    schedules.cmd_delete_session_schedules({"sessionId": "chat-news"})
    assert [s["id"] for s in schedule_store.load_store()["schedules"]] == ["other"]


# ---- run state ------------------------------------------------------------------------

def test_run_state_retention_and_atomic_private_file(sched_env):
    state = schedule_runs.load_run_state("r-1")
    state["history"] = [{"at": str(i)} for i in range(80)] + ["junk"]
    schedule_runs.save_run_state("r-1", state, 50)
    loaded = schedule_runs.load_run_state("r-1")
    assert len(loaded["history"]) == 50 and loaded["history"][0] == {"at": "30"}
    path = schedule_runs.run_state_path("r-1")
    assert oct(os.stat(path).st_mode & 0o777) == "0o600"
    assert [n for n in os.listdir(os.path.dirname(path)) if n.startswith(".")] == []   # no temp files left
    assert schedule_runs.history_limit({"historyLimit": 5000}) == 1000
    with pytest.raises(ValueError):
        schedule_runs.run_state_path("../../etc/passwd")


def test_corrupt_run_state_reads_as_empty(sched_env):
    os.makedirs(schedule_runs.runs_dir(), exist_ok=True)
    with open(schedule_runs.run_state_path("r-2"), "w") as f:
        f.write("{not json")
    assert schedule_runs.load_run_state("r-2") == schedule_runs.empty_state()


def test_run_state_lock_serialises_writers(sched_env):
    def bump():
        for _ in range(25):
            with schedule_runs.run_state_lock("r-3"):
                st = schedule_runs.load_run_state("r-3")
                st["runCount"] += 1
                schedule_runs.save_run_state("r-3", st)
    threads = [threading.Thread(target=bump) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert schedule_runs.load_run_state("r-3")["runCount"] == 100


# ---- run_schedule stub ------------------------------------------------------------------

def stored(capsys, sid, **over):
    out = save(capsys, dict(OWNER, id=sid, **over))
    assert out["ok"], out
    return out["schedule"]


def test_stub_records_due_and_dedupes(sched_env, capsys):
    s = stored(capsys, "job-1")
    due = dt.datetime.fromisoformat(s["editedAt"]).replace(hour=0, minute=0, second=0) + dt.timedelta(days=8)
    occ = next(d for d in (due + dt.timedelta(hours=h) for h in range(24 * 8))
               if (d.weekday() == 0 and d.hour == 16) or (d.weekday() != 0 and d.hour == 15))
    decision = schedule_job.run_schedule("job-1", now=occ + dt.timedelta(seconds=20))
    assert decision["action"] == "run" and decision["occurrence"] == iso(occ)
    state = schedule_runs.load_run_state("job-1")
    assert state["lastScheduledFor"] == iso(occ) and state["lastStatus"] == "due-not-run"
    assert state["runCount"] == 0 and state["history"][-1]["status"] == "due-not-run"
    again = schedule_job.run_schedule("job-1", now=occ + dt.timedelta(seconds=50))
    assert again["reason"] == "already-ran" and len(schedule_runs.load_run_state("job-1")["history"]) == 1


def test_stub_records_missed_and_finishes_once(sched_env, capsys):
    at = (dt.datetime.now() + dt.timedelta(days=30)).replace(hour=10, minute=0, second=0, microsecond=0)
    s = stored(capsys, "job-2", rules=[{"kind": "once", "at": at.strftime("%Y-%m-%dT%H:%M")}])
    late = at + dt.timedelta(hours=3)
    decision = schedule_job.run_schedule("job-2", now=late)
    assert decision["reason"] == "missed-no-catchup" and decision["finished"] is True
    state = schedule_runs.load_run_state("job-2")
    assert state["finished"] and state["history"][-1]["status"] == "missed"
    assert sched_env.calls()[-1] == "--user disable --now kdeaichat-sched-job-2.timer"
    assert s["catchUp"]["enabled"] is False


def test_stub_unknown_schedule_stops_its_timer(sched_env, capsys):
    assert schedule_job.run_schedule("ghost")["reason"] == "unknown-schedule"
    assert sched_env.calls() == ["--user disable --now kdeaichat-sched-ghost.timer"]
    assert not os.path.exists(schedule_runs.run_state_path("ghost"))


def test_helper_run_schedule_takes_a_plain_id(sched_env, capsys):
    stored(capsys, "job-3")
    env = dict(os.environ)
    out = subprocess.run([sys.executable, HELPER, "run_schedule", "job-3"], capture_output=True, text=True,
                         env=env, timeout=60)
    assert out.returncode == 0, out.stdout + out.stderr
    assert json.loads(out.stdout)["action"] in ("run", "skip")
    assert schedule_runs.load_run_state("job-3")["lastCheck"] is not None
    payload = base64.b64encode(json.dumps({}).encode()).decode()
    listed = subprocess.run([sys.executable, HELPER, "schedules_list", payload], capture_output=True, text=True,
                            env=env, timeout=60)
    assert json.loads(listed.stdout)["schedules"][0]["id"] == "job-3"
