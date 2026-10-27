"""Runs tests/js/chat_search.test.js (chat/ChatSearch.js: search across all chats) in node."""
import os
import subprocess


def test_chat_search():
    script = os.path.join(os.path.dirname(__file__), "js", "chat_search.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
