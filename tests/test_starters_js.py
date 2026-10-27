"""Runs tests/js/starters.test.js (chat/Starters.js) in node."""
import os
import subprocess


def test_starters_js():
    script = os.path.join(os.path.dirname(__file__), "js", "starters.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
