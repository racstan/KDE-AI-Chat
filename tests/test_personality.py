"""Runs tests/js/personality.test.js (chat/Personality.js) in node."""
import os
import subprocess


def test_personality():
    script = os.path.join(os.path.dirname(__file__), "js", "personality.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
