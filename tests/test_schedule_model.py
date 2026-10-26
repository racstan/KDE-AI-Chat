"""Validation of schedule definitions (kdeaichat/schedule_model.py)."""
import datetime as dt

import pytest

from kdeaichat import schedule_cron
from kdeaichat.schedule_model import normalize_rule, normalize_schedule, timing_changed

NOW = dt.datetime(2026, 10, 26, 8, 22)


def base(**over):
    s = {"id": "s-1", "name": "News", "chatId": "chat-1", "message": "hello",
         "rules": [{"kind": "weekly", "days": [1], "times": ["16:00"]}]}
    s.update(over)
    return s


def test_owner_example_normalizes():
    s = normalize_schedule(base(rules=[{"kind": "weekly", "days": [1], "times": ["16:00"]},
                                       {"kind": "weekly", "days": [2, 3, 4, 5, 6, 0], "times": ["15:00"]}]), now=NOW)
    assert s["rules"][1] == {"kind": "weekly", "days": [0, 2, 3, 4, 5, 6], "times": ["15:00"], "everyWeeks": 1}
    assert s["catchUp"] == {"enabled": False, "withinHours": 12}
    assert s["editedAt"] == s["createdAt"] == "2026-10-26T08:22:00"
    assert s["enabled"] is True and s["notify"] is True and s["limitCount"] is None


def test_unknown_keys_are_dropped_and_times_sorted():
    s = normalize_schedule(base(evil="x", rules=[{"kind": "daily", "times": ["15:00", "09:00", "09:00"], "x": 1}]),
                           now=NOW)
    assert "evil" not in s
    assert s["rules"] == [{"kind": "daily", "times": ["09:00", "15:00"], "everyDays": 1}]


@pytest.mark.parametrize("rule", [
    {"kind": "once", "at": "2027-02-30T10:00"},          # impossible date
    {"kind": "once", "at": "2027-02-03 10:00"},          # wrong format
    {"kind": "daily", "times": ["24:00"]},
    {"kind": "daily", "times": ["9:00"]},
    {"kind": "daily", "times": []},
    {"kind": "daily", "times": ["09:00"], "everyDays": 0},
    {"kind": "weekly", "days": [7], "times": ["09:00"]},
    {"kind": "weekly", "days": [], "times": ["09:00"]},
    {"kind": "weekly", "days": [True], "times": ["09:00"]},
    {"kind": "monthly", "day": 32, "times": ["09:00"]},
    {"kind": "monthly", "day": "first", "times": ["09:00"]},
    {"kind": "monthly", "day": 1, "times": ["09:00"], "everyMonths": 13},
    {"kind": "hourly", "everyHours": 5},                 # only divisors of 24
    {"kind": "hourly", "everyHours": 2, "from": 18, "to": 8},
    {"kind": "minutes", "everyMinutes": 5},              # 15-minute minimum
    {"kind": "minutes", "everyMinutes": 60},
    {"kind": "cron", "expr": "*/5 * * * *"},             # more often than 15 min
    {"kind": "cron", "expr": "0 9 * *"},
    {"kind": "cron", "expr": "0 25 * * *"},
    {"kind": "yearly"},
])
def test_invalid_rules_rejected(rule):
    with pytest.raises(ValueError):
        normalize_rule(rule)


@pytest.mark.parametrize("rule", [
    {"kind": "once", "at": "2026-11-03T14:30"},
    {"kind": "hourly", "everyHours": 3, "minute": 30, "from": 9, "to": 18},
    {"kind": "minutes", "everyMinutes": 15},
    {"kind": "monthly", "day": "last", "times": ["18:00"]},
    {"kind": "cron", "expr": "*/20 8-17 * * 1-5"},
    {"kind": "cron", "expr": "0 9 1 * mon"},
    {"kind": "cron", "expr": "45 23 * * 0"},
])
def test_valid_rules(rule):
    assert normalize_rule(rule)["kind"] == rule["kind"]


def test_cron_gap_counts_the_hour_wrap():
    with pytest.raises(ValueError):
        schedule_cron.parse("0,50 * * * *")       # 50 -> next hour's 00 is 10 minutes
    schedule_cron.parse("0,50 9 * * *")           # single hour: no wrap


@pytest.mark.parametrize("over", [
    {"id": "bad id!"}, {"id": "x" * 65}, {"chatId": "../etc"}, {"message": "   "}, {"chatId": ""},
    {"rules": []}, {"startDate": "2026-13-01"}, {"startDate": "2026-11-05", "endDate": "2026-11-01"},
    {"limitCount": -1}, {"catchUp": {"enabled": True, "withinHours": 0}}, {"catchUp": "yes"},
    {"rules": [{"kind": "daily", "times": ["09:00"]}] * 21}, {"message": "x" * 100001},
])
def test_invalid_schedules_rejected(over):
    with pytest.raises(ValueError):
        normalize_schedule(base(**over), now=NOW)


def test_disabled_draft_may_be_incomplete():
    s = normalize_schedule({"enabled": False, "name": "draft"}, now=NOW)
    assert s["rules"] == [] and s["chatId"] == "" and len(s["id"]) == 36


def test_catchup_bool_and_window():
    assert normalize_schedule(base(catchUp=True), now=NOW)["catchUp"] == {"enabled": True, "withinHours": 12}
    assert normalize_schedule(base(catchUp={"enabled": True, "withinHours": 3}), now=NOW)["catchUp"]["withinHours"] == 3


def test_timing_changed():
    old = normalize_schedule(base(), now=NOW)
    assert not timing_changed(old, dict(old, name="Renamed", message="other"))
    assert timing_changed(old, dict(old, rules=[{"kind": "daily", "times": ["09:00"], "everyDays": 1}]))
    assert timing_changed(old, dict(old, enabled=False))
    assert timing_changed(None, old)
