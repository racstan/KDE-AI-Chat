"""Runs tests/js/opencode_backend.test.js (backends/OpenCodeBackend.js) in node."""
import os
import subprocess


def test_opencode_backend():
    script = os.path.join(os.path.dirname(__file__), "js", "opencode_backend.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
