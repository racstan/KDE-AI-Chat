"""Runs tests/js/direct_tools.test.js (backends/DirectTools.js and the tool hooks of DirectBackend.js) in node."""
import os
import subprocess


def test_direct_tools():
    script = os.path.join(os.path.dirname(__file__), "js", "direct_tools.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
