"""Runs tests/js/chat_stats.test.js (chat/ChatStats.js) in node."""
import os
import subprocess


def test_chat_stats():
    script = os.path.join(os.path.dirname(__file__), "js", "chat_stats.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
