"""Runs tests/js/projects.test.js (chat/Projects.js and the project layer of chat/EffectiveConfig.js) in node."""
import os
import subprocess


def test_projects():
    script = os.path.join(os.path.dirname(__file__), "js", "projects.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
