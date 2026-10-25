"""Runs tests/js/image_extract.test.js (chat/ImageExtract.js and Security.validateImageUrl) in node."""
import os
import subprocess


def test_image_extract():
    script = os.path.join(os.path.dirname(__file__), "js", "image_extract.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
