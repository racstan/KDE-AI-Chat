"""Runs tests/js/memory_recall.test.js (chat/MemoryRecall.js) in node."""
import os
import subprocess


def test_memory_recall():
    script = os.path.join(os.path.dirname(__file__), "js", "memory_recall.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
