"""Upgrade: the pre-1.4.0 polling scheduler is stopped and removed, once; timers come from the new store."""
import json
import os
import subprocess
import sys
import time

from kdeaichat import schedules


def _old_install(sched_env):
    os.makedirs(os.path.join(sched_env.data, "pending"))
    os.makedirs(os.path.join(sched_env.data, "results"))
    with open(os.path.join(sched_env.data, "pending", "sched-1-1.json"), "w") as f:
        json.dump({"chatId": "c", "message": "m"}, f)
    script = os.path.join(sched_env.data, "kde-ai-scheduler.py")
    with open(script, "w") as f:
        f.write("import time\ntime.sleep(60)\n")
    os.makedirs(sched_env.units)
    with open(os.path.join(sched_env.units, "kde-ai-scheduler.service"), "w") as f:
        f.write("[Service]\nExecStart=/usr/bin/python3 " + script + "\n")
    with open(os.path.join(sched_env.data, "schedules.json"), "w") as f:
        json.dump({"version": 1, "schedules": [{"id": "a1", "name": "x", "enabled": True, "message": "hi"}]}, f)
    return script


def test_cleanup_stops_and_removes_the_old_daemon_once(sched_env, capsys):
    script = _old_install(sched_env)
    daemon = subprocess.Popen([sys.executable, script])      # started by hand (the old nohup fallback)
    bystander = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", script + ".other"])
    try:
        time.sleep(0.3)
        schedules.cmd_schedules_startup({})
        out = json.loads(capsys.readouterr().out)
        legacy = out["legacy"]
        assert legacy["unit"] and legacy["script"] and legacy["killed"] == 1 and legacy["droppedTriggers"] == 1
        assert sorted(legacy["removedDirs"]) == ["pending", "results"]
        assert daemon.wait(timeout=5) is not None and bystander.poll() is None
        assert sched_env.calls()[:3] == ["--user disable --now kde-ai-scheduler.service", "--user daemon-reload",
                                         "--user reset-failed kde-ai-scheduler.service"]
        for gone in ("kde-ai-scheduler.py", "pending", "results"):
            assert not os.path.exists(os.path.join(sched_env.data, gone))
        assert not os.path.exists(os.path.join(sched_env.units, "kde-ai-scheduler.service"))
        # migrated: the bare old entry is a disabled draft, so no timer
        with open(os.path.join(sched_env.data, "schedules.v2.json")) as f:
            store = json.load(f)
        assert store["schedules"][0]["id"] == "a1" and store["schedules"][0]["enabled"] is False
        assert out["ok"] is True and out["units"]["timers"] == []
        # second start: nothing to do, systemctl not called again
        calls = len(sched_env.calls())
        schedules.cmd_schedules_startup({})
        again = json.loads(capsys.readouterr().out)
        assert again["legacy"]["changed"] is False and len(sched_env.calls()) == calls
    finally:
        for p in (daemon, bystander):
            if p.poll() is None:
                p.kill()


def test_startup_writes_timers_for_migrated_schedules(sched_env, capsys):
    os.makedirs(sched_env.data)
    with open(os.path.join(sched_env.data, "schedules.json"), "w") as f:
        json.dump({"version": 1, "schedules": [{
            "id": "d1", "name": "Daily", "enabled": True, "message": "hi", "chatId": "c1", "taskType": "repeat",
            "schedType": "days", "schedEvery": 1, "startDate": "2026-01-01T09:00:00", "cron": "0 9 */1 * *"}]}, f)
    schedules.cmd_schedules_startup({})
    out = json.loads(capsys.readouterr().out)
    assert out["units"]["timers"] == ["d1"] and out["legacy"]["changed"] is False
    assert os.path.exists(os.path.join(sched_env.units, "kdeaichat-sched-d1.timer"))


def test_delete_session_schedules_uses_the_new_store(sched_env, capsys):
    os.makedirs(sched_env.data)
    with open(os.path.join(sched_env.data, "schedules.v2.json"), "w") as f:
        json.dump({"version": 2, "settings": {}, "schedules": [{"id": "k1", "chatId": "gone", "enabled": False},
                                                               {"id": "k2", "chatId": "kept", "enabled": False}]}, f)
    schedules.cmd_delete_session_schedules({"sessionId": "gone"})
    assert json.loads(capsys.readouterr().out)["removed"] == ["k1"]
    with open(os.path.join(sched_env.data, "schedules.v2.json")) as f:
        assert [s["id"] for s in json.load(f)["schedules"]] == ["k2"]
