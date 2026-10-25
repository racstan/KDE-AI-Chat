"""Runs tests/js/provider_check.test.js (ProviderCheck.js) in node."""
import os
import subprocess


def test_provider_check():
    script = os.path.join(os.path.dirname(__file__), "js", "provider_check.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
