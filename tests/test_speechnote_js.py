"""Runs tests/js/speechnote.test.js (voice/SpeechNote.js and the Speech Note engine entries) in node."""
import os
import subprocess


def test_speechnote_js():
    script = os.path.join(os.path.dirname(__file__), "js", "speechnote.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
