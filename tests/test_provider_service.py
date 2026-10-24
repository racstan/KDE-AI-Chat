"""Runs tests/js/provider_service.test.js (ProviderService.js) in node."""
import os
import subprocess


def test_provider_service():
    script = os.path.join(os.path.dirname(__file__), "js", "provider_service.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
