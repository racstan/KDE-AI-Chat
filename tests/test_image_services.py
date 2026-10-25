"""Runs tests/js/image_services.test.js (AI Horde and Pollinations backends, shared HTTP bits) in node."""
import json
import os
import re
import subprocess

ROOT = os.path.join(os.path.dirname(__file__), "..")
PACKAGE = os.path.join(ROOT, "org.kde.plasma.kdeaichat")


def test_image_services():
    script = os.path.join(os.path.dirname(__file__), "js", "image_services.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr


def test_horde_client_agent_fallback_is_the_metadata_website():
    """The widget passes plasmoid.metaData's version and website; the fallback must say the same."""
    with open(os.path.join(PACKAGE, "metadata.json"), encoding="utf-8") as f:
        website = json.load(f)["KPlugin"]["Website"]
    with open(os.path.join(PACKAGE, "contents/ui/backends/HordeBackend.js"), encoding="utf-8") as f:
        source = f.read()
    assert re.search(r'var REPO_URL = "([^"]+)";', source).group(1) == website
