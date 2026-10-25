"""Runs tests/js/chat_export.test.js (chat/ChatExport.js) in node."""
import os
import subprocess


def test_chat_export():
    script = os.path.join(os.path.dirname(__file__), "js", "chat_export.test.js")
    env = dict(os.environ, TZ="UTC")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60, env=env)
    assert result.returncode == 0, result.stdout + result.stderr
