"""The occurrence engine, summaries and the run/skip decision (schedule_rules, schedule_text)."""
import datetime as dt

import pytest

from kdeaichat.schedule_model import normalize_schedule
from kdeaichat.schedule_rules import latest_occurrence, next_occurrences, should_run
from kdeaichat.schedule_text import rule_summary, summary, warnings

D = dt.datetime
NOW = D(2026, 10, 26, 8, 22)   # a Monday
OWNER_RULES = [{"kind": "weekly", "days": [1], "times": ["16:00"]},
               {"kind": "weekly", "days": [2, 3, 4, 5, 6, 0], "times": ["15:00"]}]


def sched(rules, **over):
    raw = {"id": "s-1", "chatId": "c", "message": "m", "rules": rules, "createdAt": "2026-10-01T00:00:00",
           "editedAt": "2026-10-01T00:00:00"}
    raw.update(over)
    return normalize_schedule(raw, now=NOW)


def nxt(s, after=NOW, n=4):
    return [m.isoformat(sep=" ", timespec="minutes") for m in next_occurrences(s, after, n)]


def test_owner_example(berlin):
    s = sched(OWNER_RULES)
    assert summary(s) == "Mon 16:00; Tue–Sun 15:00"
    assert nxt(s, n=8) == ["2026-10-26 16:00", "2026-10-27 15:00", "2026-10-28 15:00", "2026-10-29 15:00",
                           "2026-10-30 15:00", "2026-10-31 15:00", "2026-11-01 15:00", "2026-11-02 16:00"]


def test_every_two_days_across_month_end(berlin):
    s = sched([{"kind": "daily", "everyDays": 2, "times": ["15:00"]}], startDate="2026-10-29")
    assert summary(s) == "Every 2 days at 15:00"
    # not "Oct 29, Oct 31, Nov 1" like the old */2 cron
    assert nxt(s) == ["2026-10-29 15:00", "2026-10-31 15:00", "2026-11-02 15:00", "2026-11-04 15:00"]


def test_every_two_weeks_anchored_on_start(berlin):
    s = sched([{"kind": "weekly", "days": [1, 3], "times": ["09:00"], "everyWeeks": 2}], startDate="2026-10-26")
    assert nxt(s) == ["2026-10-26 09:00", "2026-10-28 09:00", "2026-11-09 09:00", "2026-11-11 09:00"]
    assert summary(s) == "Every 2 weeks: Mon, Wed 09:00"


def test_last_day_of_month(berlin):
    s = sched([{"kind": "monthly", "day": "last", "times": ["18:00"]}])
    assert nxt(s, D(2027, 1, 1)) == ["2027-01-31 18:00", "2027-02-28 18:00", "2027-03-31 18:00", "2027-04-30 18:00"]
    assert nxt(s, D(2028, 2, 1), 1) == ["2028-02-29 18:00"]
    assert rule_summary(s["rules"][0]) == "Monthly on the last day at 18:00"


def test_day_31_skips_short_months_and_warns(berlin):
    s = sched([{"kind": "monthly", "day": 31, "times": ["09:00"]}])
    assert nxt(s, D(2027, 1, 1), 3) == ["2027-01-31 09:00", "2027-03-31 09:00", "2027-05-31 09:00"]
    assert any("day 31" in w for w in warnings(s, NOW))


def test_every_three_months(berlin):
    s = sched([{"kind": "monthly", "day": 15, "times": ["09:00"], "everyMonths": 3}], startDate="2026-11-01")
    assert nxt(s, n=3) == ["2026-11-15 09:00", "2027-02-15 09:00", "2027-05-15 09:00"]


def test_hourly_window_and_minutes(berlin):
    s = sched([{"kind": "hourly", "everyHours": 3, "minute": 30, "from": 9, "to": 18}])
    assert nxt(s) == ["2026-10-26 09:30", "2026-10-26 12:30", "2026-10-26 15:30", "2026-10-26 18:30"]
    assert rule_summary(s["rules"][0]) == "Every 3 hours at :30 (09:00–18:59)"
    m = sched([{"kind": "minutes", "everyMinutes": 20}])
    assert nxt(m, n=3) == ["2026-10-26 08:40", "2026-10-26 09:00", "2026-10-26 09:20"]


def test_union_deduplicates_same_instant(berlin):
    s = sched([{"kind": "daily", "times": ["09:00"]}, {"kind": "weekly", "days": [1, 2], "times": ["09:00"]}])
    assert nxt(s, n=2) == ["2026-10-26 09:00", "2026-10-27 09:00"]


def test_cron_dom_or_dow(berlin):
    s = sched([{"kind": "cron", "expr": "0 9 1 * 1"}])
    assert nxt(s, n=4) == ["2026-10-26 09:00", "2026-11-01 09:00", "2026-11-02 09:00", "2026-11-09 09:00"]


def test_once_and_start_end_dates(berlin):
    s = sched([{"kind": "once", "at": "2026-11-03T14:30"}])
    assert nxt(s) == ["2026-11-03 14:30"]
    assert rule_summary(s["rules"][0]) == "Once on Tue 3 Nov 2026 at 14:30"
    d = sched([{"kind": "daily", "times": ["09:00"]}], startDate="2026-10-28", endDate="2026-10-29")
    assert nxt(d) == ["2026-10-28 09:00", "2026-10-29 09:00"]
    past = sched([{"kind": "once", "at": "2026-01-01T10:00"}])
    assert "This schedule never runs." in warnings(past, NOW)


def test_dst_gap_skipped_and_warned(berlin):
    s = sched([{"kind": "daily", "times": ["02:30"]}])
    # 2027-03-28 02:30 does not exist in Berlin (clocks jump 02:00 -> 03:00)
    assert nxt(s, D(2027, 3, 27, 8, 0), 2) == ["2027-03-29 02:30", "2027-03-30 02:30"]
    assert any("02:00 and 03:00" in w for w in warnings(s, NOW))
    once = sched([{"kind": "once", "at": "2027-03-28T02:30"}])
    assert nxt(once, D(2027, 1, 1)) == []
    # the repeated hour in October still runs once
    assert nxt(s, D(2026, 10, 24, 8, 0), 2) == ["2026-10-25 02:30", "2026-10-26 02:30"]


def test_latest_occurrence(berlin):
    s = sched(OWNER_RULES)
    assert latest_occurrence(s, D(2026, 10, 27, 15, 0)) == D(2026, 10, 27, 15, 0)
    assert latest_occurrence(s, D(2026, 10, 27, 14, 59)) == D(2026, 10, 26, 16, 0)


# ---- should_run --------------------------------------------------------------------------

def decide(s, now, **state):
    return should_run(s, state, now)


def test_due_on_time(berlin):
    d = decide(sched(OWNER_RULES), D(2026, 10, 26, 16, 0, 20))
    assert d == {"action": "run", "reason": "due", "occurrence": "2026-10-26T16:00:00", "late": False}


def test_already_ran_dedupes_a_double_wake(berlin):
    d = decide(sched(OWNER_RULES), D(2026, 10, 26, 16, 0, 40), lastScheduledFor="2026-10-26T16:00:00")
    assert (d["action"], d["reason"]) == ("skip", "already-ran")


def test_edited_after_occurrence_is_skipped(berlin):
    s = sched(OWNER_RULES, editedAt="2026-10-26T16:30:00")
    assert decide(s, D(2026, 10, 26, 16, 31))["reason"] == "edited-after"


def test_missed_without_catch_up(berlin):
    d = decide(sched(OWNER_RULES), D(2026, 10, 26, 18, 0))
    assert (d["action"], d["reason"], d["late"]) == ("skip", "missed-no-catchup", True)


def test_catch_up_inside_and_outside_window(berlin):
    s = sched(OWNER_RULES, catchUp={"enabled": True, "withinHours": 12})
    d = decide(s, D(2026, 10, 27, 3, 0))
    assert (d["action"], d["reason"], d["occurrence"]) == ("run", "catch-up", "2026-10-26T16:00:00")
    # several missed times collapse into the latest one
    d = decide(s, D(2026, 10, 29, 20, 0))
    assert (d["action"], d["occurrence"]) == ("run", "2026-10-29T15:00:00")
    d = decide(s, D(2026, 10, 27, 14, 0))   # 22 h late
    assert (d["action"], d["reason"]) == ("skip", "outside-catchup-window")


def test_every_n_guard_on_off_days(berlin):
    s = sched([{"kind": "daily", "everyDays": 2, "times": ["15:00"]}], startDate="2026-10-29")
    assert decide(s, D(2026, 10, 29, 15, 0))["action"] == "run"
    # systemd wakes daily; on the off day the latest occurrence is yesterday, already handled
    d = decide(s, D(2026, 10, 30, 15, 0), lastScheduledFor="2026-10-29T15:00:00")
    assert d["reason"] == "already-ran"


def test_start_end_disabled_finished_limit(berlin):
    rules = [{"kind": "daily", "times": ["09:00"]}]
    assert decide(sched(rules, startDate="2026-11-01"), D(2026, 10, 30, 9, 0))["reason"] == "before-start"
    assert decide(sched(rules, endDate="2026-10-20"), D(2026, 10, 30, 9, 0))["reason"] == "after-end"
    assert decide(sched(rules, enabled=False), D(2026, 10, 30, 9, 0))["reason"] == "disabled"
    assert decide(sched(rules), D(2026, 10, 30, 9, 0), finished=True)["reason"] == "finished"
    assert decide(sched(rules, limitCount=3), D(2026, 10, 30, 9, 0), runCount=3)["reason"] == "limit-reached"
    assert decide(sched([{"kind": "once", "at": "2026-12-01T10:00"}]), D(2026, 10, 30, 9, 0))["reason"] == "not-due"


def test_finished_is_rearmed_by_a_later_edit(berlin):
    rules = [{"kind": "daily", "times": ["09:00"]}]
    s = sched(rules, editedAt="2026-10-29T12:00:00")
    state = {"finished": True, "finishedAt": "2026-10-28T09:00:00"}
    assert should_run(s, state, D(2026, 10, 30, 9, 0))["action"] == "run"
    state["finishedAt"] = "2026-10-29T13:00:00"
    assert should_run(s, state, D(2026, 10, 30, 9, 0))["reason"] == "finished"


@pytest.mark.parametrize("days,text", [([1, 2, 3, 4, 5], "Mon–Fri"), ([0, 6], "Weekends"),
                                       ([0, 1, 2, 3, 4, 5, 6], "Every day"), ([1, 3, 5], "Mon, Wed, Fri"),
                                       ([5, 6, 0, 1], "Mon, Fri–Sun")])
def test_weekday_text(days, text):
    assert rule_summary({"kind": "weekly", "days": days, "times": ["09:00"], "everyWeeks": 1}) == f"{text} 09:00"
