"""Runs tests/js/memory_list.test.js (config/MemoryList.js) in node."""
import os
import subprocess


def test_memory_list():
    script = os.path.join(os.path.dirname(__file__), "js", "memory_list.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
