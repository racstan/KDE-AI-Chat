"""Runs tests/js/personality.test.js (chat/Personality.js) in node."""
import os
import subprocess


def test_personality():
    script = os.path.join(os.path.dirname(__file__), "js", "personality.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr


def test_video_avatar_extensions_match_the_panel_icon():
    # Personality.js can't import PanelIcon.js (both are .pragma library), so it keeps its own list.
    import re
    ui = os.path.join(os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui", "chat")
    panel = open(os.path.join(ui, "PanelIcon.js")).read()
    personality = open(os.path.join(ui, "Personality.js")).read()
    listed = set(re.findall(r'"(\w+)"', re.search(r"VIDEO_EXTENSIONS = \[([^\]]*)\]", panel).group(1)))
    pattern = re.search(r"VIDEO_EXT = /(.*)/", personality).group(1)
    assert set(re.search(r"\(([^)]*)\)", pattern).group(1).split("|")) == listed
