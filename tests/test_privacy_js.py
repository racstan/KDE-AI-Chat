"""Runs tests/js/privacy.test.js (chat/Privacy.js) in node."""
import os
import subprocess


def test_privacy_js():
    script = os.path.join(os.path.dirname(__file__), "js", "privacy.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
