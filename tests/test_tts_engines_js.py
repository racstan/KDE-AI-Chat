"""Runs tests/js/tts_engines.test.js (voice/TtsEngines.js, chat/ReadAloudAction.js) in node."""
import os
import subprocess


def test_tts_engines_js():
    script = os.path.join(os.path.dirname(__file__), "js", "tts_engines.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
