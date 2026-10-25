"""Runs tests/js/message_content.test.js (chat/MessageContent.js) in node."""
import os
import subprocess


def test_message_content():
    script = os.path.join(os.path.dirname(__file__), "js", "message_content.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
