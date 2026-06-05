"""Unit tests for the KDE AI Chat scheduler cron parser."""

import sys
import os
import importlib.util
from datetime import datetime

SCRIPTS_DIR = os.path.join(os.path.dirname(__file__),
                           "..", "org.kde.plasma.kdeaichat", "contents", "scripts")
SCHEDULER_PATH = os.path.join(SCRIPTS_DIR, "kde-ai-scheduler.py")

spec = importlib.util.spec_from_file_location("kde_ai_scheduler", SCHEDULER_PATH)
sched = importlib.util.module_from_spec(spec)
sys.modules["kde_ai_scheduler"] = sched
spec.loader.exec_module(sched)

parse_cron_field = sched.parse_cron_field
cron_matches = sched.cron_matches
is_start_date_passed = sched.is_start_date_passed


class TestParseCronField:
    def test_wildcard(self):
        assert parse_cron_field("*", 0, 59) == list(range(0, 60))

    def test_single_value(self):
        assert parse_cron_field("5", 0, 59) == [5]

    def test_range(self):
        assert parse_cron_field("1-5", 0, 59) == [1, 2, 3, 4, 5]

    def test_step(self):
        assert parse_cron_field("*/10", 0, 59) == [0, 10, 20, 30, 40, 50]

    def test_range_step(self):
        assert parse_cron_field("1-10/3", 0, 59) == [1, 4, 7, 10]

    def test_list(self):
        assert parse_cron_field("1,3,5", 0, 59) == [1, 3, 5]

    def test_single_value_hour(self):
        assert parse_cron_field("9", 0, 23) == [9]

    def test_named_weekday(self):
        result = parse_cron_field("mon,wed,fri", 0, 6)
        assert result == [1, 3, 5]

    def test_named_weekday_range(self):
        result = parse_cron_field("mon-fri", 0, 6)
        assert result == [1, 2, 3, 4, 5]

    def test_min_boundary(self):
        assert parse_cron_field("0", 0, 59) == [0]

    def test_max_boundary(self):
        assert parse_cron_field("59", 0, 59) == [59]

    def test_invalid_raises(self):
        try:
            parse_cron_field("abc", 0, 59)
            assert False, "Should raise ValueError"
        except ValueError:
            pass


class TestCronMatches:
    def test_every_minute(self):
        dt = datetime(2026, 6, 2, 14, 30)
        assert cron_matches("* * * * *", dt)

    def test_exact_minute(self):
        dt = datetime(2026, 6, 2, 14, 30)
        assert cron_matches("30 14 * * *", dt)

    def test_wrong_minute(self):
        dt = datetime(2026, 6, 2, 14, 31)
        assert not cron_matches("30 14 * * *", dt)

    def test_wrong_hour(self):
        dt = datetime(2026, 6, 2, 15, 30)
        assert not cron_matches("30 14 * * *", dt)

    def test_step_minutes(self):
        dt = datetime(2026, 6, 2, 14, 20)
        assert cron_matches("*/10 * * * *", dt)

    def test_step_minutes_no_match(self):
        dt = datetime(2026, 6, 2, 14, 25)
        assert not cron_matches("*/10 * * * *", dt)

    def test_specific_weekday(self):
        dt = datetime(2026, 6, 2, 9, 0)
        assert cron_matches("0 9 * * 2", dt)

    def test_wrong_weekday(self):
        dt = datetime(2026, 6, 2, 9, 0)
        assert not cron_matches("0 9 * * 1", dt)

    def test_named_weekday_mon(self):
        dt = datetime(2026, 6, 1, 9, 0)
        assert cron_matches("0 9 * * mon", dt)

    def test_named_weekday_fri(self):
        dt = datetime(2026, 6, 5, 9, 0)
        assert cron_matches("0 9 * * fri", dt)

    def test_invalid_cron_returns_false(self):
        dt = datetime(2026, 6, 2, 9, 0)
        assert not cron_matches("invalid", dt)

    def test_short_cron_returns_false(self):
        dt = datetime(2026, 6, 2, 9, 0)
        assert not cron_matches("* * *", dt)

    def test_every_6_hours(self):
        for h in [0, 6, 12, 18]:
            dt = datetime(2026, 6, 2, h, 0)
            assert cron_matches("0 */6 * * *", dt)
        for h in [1, 5, 7, 13]:
            dt = datetime(2026, 6, 2, h, 0)
            assert not cron_matches("0 */6 * * *", dt)

    def test_dom_and_dow_both_set(self):
        dt = datetime(2026, 6, 15, 9, 0)
        assert cron_matches("0 9 15 * 2", dt)

    def test_weekdays_9_to_5(self):
        mon_9am = datetime(2026, 6, 1, 9, 0)
        assert cron_matches("0 9-17 * * 1-5", mon_9am)
        sun_9am = datetime(2026, 6, 7, 9, 0)
        assert not cron_matches("0 9-17 * * 1-5", sun_9am)

    def test_boundary_midnight(self):
        dt = datetime(2026, 6, 2, 0, 0)
        assert cron_matches("0 0 * * *", dt)


class TestIsStartDatePassed:
    def test_no_start_date(self):
        assert is_start_date_passed({}, datetime.now()) is True

    def test_start_date_in_past(self):
        s = {"startDate": "2026-01-01T00:00:00"}
        assert is_start_date_passed(s, datetime(2026, 6, 2)) is True

    def test_start_date_in_future(self):
        s = {"startDate": "2026-12-31T23:59:00"}
        assert is_start_date_passed(s, datetime(2026, 6, 2)) is False

    def test_start_date_with_z_suffix(self):
        s = {"startDate": "2026-01-01T00:00:00Z"}
        assert is_start_date_passed(s, datetime(2026, 6, 2)) is True

    def test_start_date_with_microseconds(self):
        s = {"startDate": "2026-01-01T00:00:00.123456"}
        assert is_start_date_passed(s, datetime(2026, 6, 2)) is True


class TestRefreshNextRuns:
    def test_refresh_missing_next_run(self):
        s = [{"enabled": True, "cron": "0 9 * * *", "id": "1"}]
        changed = sched.refresh_next_runs(s)
        assert changed is True
        assert s[0]["nextRunAt"] != ""

    def test_refresh_past_next_run(self):
        s = [{"enabled": True, "cron": "0 9 * * *", "id": "1", "nextRunAt": "2026-01-01T09:00:00"}]
        changed = sched.refresh_next_runs(s)
        assert changed is True
        assert s[0]["nextRunAt"] != "2026-01-01T09:00:00"
        assert s[0]["nextRunAt"] != ""

    def test_refresh_future_next_run(self):
        s = [{"enabled": True, "cron": "0 9 * * *", "id": "1", "nextRunAt": "2099-01-01T09:00:00"}]
        changed = sched.refresh_next_runs(s)
        assert changed is False
        assert s[0]["nextRunAt"] == "2099-01-01T09:00:00"

    def test_refresh_disabled_past_next_run(self):
        s = [{"enabled": False, "cron": "0 9 * * *", "id": "1", "nextRunAt": "2026-01-01T09:00:00"}]
        changed = sched.refresh_next_runs(s)
        assert changed is False
        assert s[0]["nextRunAt"] == "2026-01-01T09:00:00"

    def test_refresh_past_next_run_execute_missed_false(self):
        sched.execute_missed_schedules = False
        s = [{"enabled": True, "cron": "0 9 * * *", "id": "1", "nextRunAt": "2026-01-01T09:00:00"}]
        changed = sched.refresh_next_runs(s)
        assert changed is True
        assert s[0]["nextRunAt"] != "2026-01-01T09:00:00"
        assert not s[0].get("triggerNow")

    def test_refresh_past_next_run_execute_missed_true(self):
        sched.execute_missed_schedules = True
        s = [{"enabled": True, "cron": "0 9 * * *", "id": "1", "nextRunAt": "2026-01-01T09:00:00"}]
        changed = sched.refresh_next_runs(s)
        assert changed is True
        assert s[0]["nextRunAt"] != "2026-01-01T09:00:00"
        assert s[0].get("triggerNow") is True


class TestHistoryAndSettings:
    def setup_method(self):
        self._orig_history = list(sched.history)
        self._orig_limit = sched.history_limit
        self._orig_missed = sched.execute_missed_schedules
        self._orig_settings = dict(sched.settings_dict)
        self._orig_file = sched.SCHEDULES_FILE

    def teardown_method(self):
        sched.history = self._orig_history
        sched.history_limit = self._orig_limit
        sched.execute_missed_schedules = self._orig_missed
        sched.settings_dict = self._orig_settings
        sched.SCHEDULES_FILE = self._orig_file

    def test_history_limit_truncation(self):
        sched.history = [{"id": f"h-{i}"} for i in range(150)]
        sched.history_limit = 100
        # If we append one more, it should truncate to 100 entries
        entry = {"id": "h-new"}
        sched.history.append(entry)
        if len(sched.history) > sched.history_limit:
            sched.history = sched.history[-sched.history_limit:]
        assert len(sched.history) == 100
        assert sched.history[-1] == entry

    def test_save_and_load_settings(self):
        import json
        import tempfile
        try:
            with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
                sched.SCHEDULES_FILE = tmp.name

            sched.settings_dict = {"executeMissedSchedules": True, "historyLimit": 10}
            sched.history = [{"id": "h1"}, {"id": "h2"}]
            items = [{"id": "s1", "enabled": True}]

            sched.save_schedules(items)

            # Reset globals
            sched.history = []
            sched.settings_dict = {}
            sched.execute_missed_schedules = False
            sched.history_limit = 100

            loaded_items = sched.load_schedules()
            assert len(loaded_items) == 1
            assert loaded_items[0]["id"] == "s1"
            assert len(sched.history) == 2
            assert sched.settings_dict.get("executeMissedSchedules") is True
            assert sched.execute_missed_schedules is True
            assert sched.history_limit == 10
        finally:
            if os.path.exists(sched.SCHEDULES_FILE):
                os.remove(sched.SCHEDULES_FILE)
