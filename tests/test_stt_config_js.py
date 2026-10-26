"""Runs tests/js/stt_config.test.js (voice/SttConfig.js) in node."""
import os
import subprocess


def test_stt_config_js():
    script = os.path.join(os.path.dirname(__file__), "js", "stt_config.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
