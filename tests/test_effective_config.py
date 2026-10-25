"""Runs tests/js/effective_config.test.js (chat/EffectiveConfig.js) in node."""
import os
import subprocess


def test_effective_config():
    script = os.path.join(os.path.dirname(__file__), "js", "effective_config.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
