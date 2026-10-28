"""Runs tests/js/activity.test.js (chat/Activity.js) in node."""
import os
import subprocess


def test_activity():
    script = os.path.join(os.path.dirname(__file__), "js", "activity.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
