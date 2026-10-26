"""The schedules master switch (``schedules_settings {paused}``)."""
import json
import os

from kdeaichat import schedule_store

OWNER = {"name": "Latest news", "chatId": "chat-news", "message": "Fetch the latest news",
         "rules": [{"kind": "weekly", "days": [1], "times": ["16:00"]},
                   {"kind": "weekly", "days": [2, 3, 4, 5, 6, 0], "times": ["15:00"]}]}


def call(cmd, payload, capsys):
    getattr(schedule_store, "cmd_" + cmd)(payload)
    return json.loads(capsys.readouterr().out)


def timer(env, sid):
    return os.path.join(env.units, f"kdeaichat-sched-{sid}.timer")


def test_pause_removes_timers_and_keeps_definitions(sched_env, capsys):
    assert call("schedule_save", {"schedule": dict(OWNER, id="news")}, capsys)["ok"]
    assert os.path.exists(timer(sched_env, "news"))

    out = call("schedules_settings", {"paused": True}, capsys)
    assert out["ok"] and out["settings"]["paused"] is True
    assert out["units"]["removed"] == ["news"] and out["units"]["timers"] == []
    assert not os.path.exists(timer(sched_env, "news"))
    listed = call("schedules_list", {}, capsys)
    assert listed["settings"]["paused"] is True and [s["id"] for s in listed["schedules"]] == ["news"]

    # Saving while paused keeps the definition but creates no timer.
    out = call("schedule_save", {"schedule": dict(OWNER, id="other")}, capsys)
    assert out["ok"] and out["units"]["timers"] == []
    assert not os.path.exists(timer(sched_env, "other"))

    out = call("schedules_settings", {"paused": False}, capsys)
    assert out["ok"] and out["settings"]["paused"] is False
    assert out["units"]["timers"] == ["news", "other"]
    assert os.path.exists(timer(sched_env, "news")) and os.path.exists(timer(sched_env, "other"))


def test_pause_needs_a_boolean(sched_env, capsys):
    assert call("schedules_settings", {"paused": "yes"}, capsys)["ok"] is False
    assert call("schedules_settings", {}, capsys)["ok"] is False
