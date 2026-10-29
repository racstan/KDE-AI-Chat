"""Runs tests/js/direct_cache.test.js (backends/DirectCache.js and cache usage in DirectBackend.js) in node."""
import os
import subprocess


def test_direct_cache():
    script = os.path.join(os.path.dirname(__file__), "js", "direct_cache.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
