"""Runs tests/js/spoken_text.test.js (chat/SpokenText.js, the read-aloud glow) in node."""
import os
import subprocess


def test_spoken_text():
    script = os.path.join(os.path.dirname(__file__), "js", "spoken_text.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
