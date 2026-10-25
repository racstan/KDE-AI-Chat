"""Runs tests/js/chat_title.test.js (chat/ChatTitle.js) in node."""
import os
import subprocess


def test_chat_title():
    script = os.path.join(os.path.dirname(__file__), "js", "chat_title.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
