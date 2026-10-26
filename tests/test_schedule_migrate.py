"""Migration of the old single-cron schedules.json (v1) to schedules.v2.json."""
import datetime as dt
import json
import os
import shutil

from kdeaichat import schedule_migrate, schedule_store
from kdeaichat.schedule_runs import load_run_state

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")
NOW = dt.datetime(2026, 10, 26, 8, 22)
ONCE, DONE, DAILY, FORTNIGHT, QUARTER, TWO_H, FIVE_H, OFTEN, EDITED = (
    f"{d * 8}-{d * 4}-4{d * 3}-8{d * 3}-{d * 12}" for d in "123456789")


def load(name):
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as f:
        return json.load(f)


def by_id(store):
    return {s["id"]: s for s in store["schedules"]}


def test_build_cron_matches_the_old_dialog(berlin):
    data = load("schedules-v1-dialog.json")
    for s in data["schedules"]:
        if s.get("taskType") == "repeat" and s["id"] != EDITED:
            assert schedule_migrate.build_cron_v1(s) == s["cron"], s["name"]


def test_dialog_fixture_migrates_from_picked_fields(berlin):
    store, states = schedule_migrate.migrate_data(load("schedules-v1-dialog.json"), NOW)
    s = by_id(store)
    assert store["version"] == 2 and store["settings"] == {"historyLimit": 30}
    assert s[ONCE]["rules"] == [{"kind": "once", "at": "2026-11-03T14:30"}]        # UTC -> Berlin (CET)
    assert s[ONCE]["startDate"] is None and s[ONCE]["createdAt"] == "2026-10-20T08:00:00"
    assert s[DAILY]["rules"] == [{"kind": "daily", "times": ["09:30"], "everyDays": 1}]
    assert s[DAILY]["limitCount"] == 10 and s[DAILY]["notify"] is False
    assert s[DAILY]["startDate"] == "2026-10-20"
    # every N weeks was ignored by the old cron; now it is kept
    assert s[FORTNIGHT]["rules"] == [{"kind": "weekly", "days": [1, 3], "times": ["09:30"], "everyWeeks": 2}]
    assert s[QUARTER]["rules"] == [{"kind": "monthly", "day": 31, "times": ["09:30"], "everyMonths": 3}]
    # hourly keeps the start minute now
    assert s[TWO_H]["rules"] == [{"kind": "hourly", "everyHours": 2, "minute": 15, "from": 0, "to": 23}]
    assert s[FIVE_H]["rules"] == [{"kind": "cron", "expr": "15 */5 * * *"}]
    assert s[OFTEN]["rules"] == [{"kind": "minutes", "everyMinutes": 15}]
    assert s[OFTEN]["needsReview"] is True and s[OFTEN]["enabled"] is False
    assert s[EDITED]["rules"] == [{"kind": "cron", "expr": "0 9 1 * 1"}] and s[EDITED]["enabled"] is True
    assert s[DONE]["archived"] is True and s[DONE]["enabled"] is False
    for item in store["schedules"]:
        assert item["editedAt"] == "2026-10-26T08:22:00"
        assert item["catchUp"] == {"enabled": True, "withinHours": 12}   # old executeMissedSchedules
        assert "cron" not in item and "nextRunAt" not in item and "runCount" not in item
    assert len(store["schedules"]) == 10 and len(set(s)) == 10
    assert "bad id!" not in s
    # run state moved out of the definitions
    assert states[DAILY]["runCount"] == 2 and states[DAILY]["lastRunAt"] == "2026-10-22T09:30:01"
    assert [h["at"] for h in states[DAILY]["history"]] == ["2026-10-21T09:30:01", "2026-10-22T09:30:01"]
    assert states[DONE]["finished"] is True and states[DONE]["finishedAt"] == "2026-10-26T08:22:00"
    assert states[ONCE]["finished"] is False


def test_owner_structure_becomes_disabled_drafts(berlin):
    """The owner's real file: entries with only id, name, enabled and message."""
    store, states = schedule_migrate.migrate_data(load("schedules-v1-owner-structure.json"), NOW)
    assert [s["id"] for s in store["schedules"]] == ["a-bcd", "b-c", "c-def", "d-e", "e-fgh"]
    for s in store["schedules"]:
        assert s["enabled"] is False and s["needsReview"] is True and s["rules"] == []
        assert s["chatId"] == "" and s["catchUp"]["enabled"] is False
    assert store["settings"] == {"historyLimit": 50}
    assert all(st["runCount"] == 0 and not st["finished"] for st in states.values())


def test_list_format_and_garbage_are_tolerated(berlin):
    store, _ = schedule_migrate.migrate_data([{"id": "x-1"}, "junk", None], NOW)
    assert [s["id"] for s in store["schedules"]] == ["x-1"]
    store, _ = schedule_migrate.migrate_data("not a store", NOW)
    assert store["schedules"] == []


def test_migration_files_once_with_backup(sched_env, berlin):
    os.makedirs(sched_env.data, exist_ok=True)
    legacy = os.path.join(sched_env.data, "schedules.json")
    shutil.copy(os.path.join(FIXTURES, "schedules-v1-dialog.json"), legacy)
    with open(legacy, "rb") as f:
        original = f.read()
    store = schedule_store.load_store(NOW)
    assert len(store["schedules"]) == 10
    # the old daemon's file is untouched; a backup copy exists; v2 is a new file
    with open(legacy, "rb") as f:
        assert f.read() == original
    with open(os.path.join(sched_env.data, "schedules.v1.json"), "rb") as f:
        assert f.read() == original
    assert oct(os.stat(schedule_store.store_path()).st_mode & 0o777) == "0o600"
    assert load_run_state(DAILY)["runCount"] == 2
    # idempotent: a second load does not migrate again, even if the old file changes
    with open(legacy, "w") as f:
        json.dump({"schedules": []}, f)
    again = schedule_store.load_store(dt.datetime(2026, 10, 27, 9, 0))
    assert again == store
    # migration never touches systemd
    assert sched_env.calls() == [] and not os.path.exists(sched_env.units)


def test_migration_keeps_existing_run_state(sched_env, berlin):
    from kdeaichat.schedule_runs import save_run_state
    os.makedirs(sched_env.data, exist_ok=True)
    shutil.copy(os.path.join(FIXTURES, "schedules-v1-dialog.json"), os.path.join(sched_env.data, "schedules.json"))
    save_run_state(DAILY, {"runCount": 7, "history": []})
    schedule_store.load_store(NOW)
    assert load_run_state(DAILY)["runCount"] == 7


def test_no_old_file_gives_empty_store(sched_env):
    store = schedule_store.load_store(NOW)
    assert store["schedules"] == [] and store["version"] == 2
    assert not os.path.exists(os.path.join(sched_env.data, "schedules.v1.json"))
