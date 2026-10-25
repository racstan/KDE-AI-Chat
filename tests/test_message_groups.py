"""Runs tests/js/message_groups.test.js (chat/MessageGroups.js) in node."""
import os
import subprocess


def test_message_groups():
    script = os.path.join(os.path.dirname(__file__), "js", "message_groups.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
