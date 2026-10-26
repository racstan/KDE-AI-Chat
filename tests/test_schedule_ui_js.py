"""Runs the node tests for the schedule editor's JS (config/ScheduleDraft.js, config/ScheduleDescribe.js)."""
import os
import subprocess

import pytest

JS = os.path.join(os.path.dirname(__file__), "js")


@pytest.mark.parametrize("name", ["schedule_draft.test.js", "schedule_describe.test.js"])
def test_schedule_ui_js(name):
    result = subprocess.run(["node", os.path.join(JS, name)], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
