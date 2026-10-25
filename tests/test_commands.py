"""Runs tests/js/commands.test.js (chat/Commands.js, the slash commands) in node."""
import os
import subprocess


def test_commands():
    script = os.path.join(os.path.dirname(__file__), "js", "commands.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
