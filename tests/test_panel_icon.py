"""The animated panel icon: the helper's panel_icon_check (kdeaichat/panel_icon.py)
and the page/icon logic in chat/PanelIcon.js (run in node)."""
import json
import os
import subprocess
import sys

import pytest

UI = os.path.join(os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI)

from kdeaichat import panel_icon  # noqa: E402

FIXTURE_GIF = os.path.join(os.path.dirname(__file__), "fixtures", "panel-icon.gif")


def test_gif_fixture_is_checked_as_animated():
    reply = panel_icon.check(os.path.abspath(FIXTURE_GIF))
    assert reply == {"ok": True, "exists": True, "size": os.path.getsize(FIXTURE_GIF), "kind": "animated"}


def test_kind_comes_from_the_contents_then_the_extension(tmp_path):
    mp4 = tmp_path / "clip.bin"
    mp4.write_bytes(b"\x00\x00\x00\x18ftypisom" + b"\x00" * 64)
    assert panel_icon.check(str(mp4))["kind"] == "video"
    webm = tmp_path / "clip.webm"
    webm.write_bytes(b"not really")
    assert panel_icon.check(str(webm))["kind"] == "video"
    webp = tmp_path / "a.dat"
    webp.write_bytes(b"RIFF\x00\x00\x00\x00WEBPVP8X")
    assert panel_icon.check(str(webp))["kind"] == "animated"
    text = tmp_path / "notes.txt"
    text.write_text("hello")
    assert panel_icon.check(str(text))["kind"] == ""


def test_missing_and_unsafe_paths(tmp_path):
    assert panel_icon.check(str(tmp_path / "gone.gif")) == {"ok": True, "exists": False, "size": 0, "kind": ""}
    assert panel_icon.check(str(tmp_path)) == {"ok": True, "exists": False, "size": 0, "kind": ""}
    for bad in ("", "relative/robot.gif", "/home/me/../etc/passwd", "/tmp/a\nb.gif"):
        reply = panel_icon.check(bad)
        assert reply["ok"] is False and reply["error"]


def test_helper_runs_the_command(tmp_path):
    import base64
    payload = base64.b64encode(json.dumps({"path": os.path.abspath(FIXTURE_GIF)}).encode()).decode()
    result = subprocess.run([sys.executable, os.path.join(UI, "kde_ai_helper.py"), "panel_icon_check", payload],
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["kind"] == "animated"


def _js(snippet):
    with open(os.path.join(UI, "chat", "PanelIcon.js"), encoding="utf-8") as f:
        source = f.read().replace(".pragma library", "")
    result = subprocess.run(["node", "-e", source + "\nconsole.log(JSON.stringify(" + snippet + "));"],
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


@pytest.mark.parametrize("mode,file,expected", [
    ("icon", "/a/robot.gif", "icon"),
    ("animated", "/a/robot.gif", "animated"),
    ("animated", "/a/robot.WEBP", "animated"),
    ("animated", "", "icon"),
    ("animated", "/a/clip.mp4", "icon"),
    ("video", "/a/clip.webm", "video"),
    ("video", "/a/robot.gif", "icon"),
    ("sparkles", "/a/robot.gif", "icon"),
])
def test_effective_mode(mode, file, expected):
    assert _js("effectiveMode(%s, %s)" % (json.dumps(mode), json.dumps(file))) == expected


def test_verdict_limits():
    mb = 1024 * 1024
    assert _js('verdict({exists: true, size: 1000, kind: "animated"}, "animated")') == {"ok": True, "warn": False, "reason": ""}
    assert _js('verdict({exists: true, size: %d, kind: "animated"}, "animated")' % (6 * mb))["warn"] is True
    assert _js('verdict({exists: true, size: %d, kind: "animated"}, "animated")' % (20 * mb))["ok"] is True
    assert _js('verdict({exists: true, size: %d, kind: "animated"}, "animated")' % (20 * mb + 1))["reason"] == "too-large"
    assert _js('verdict({exists: true, size: 10, kind: "video"}, "animated")')["reason"] == "kind"
    assert _js('verdict({exists: false}, "video")')["reason"] == "missing"
    assert _js('verdict({error: "invalid path"}, "video")')["reason"] == "unreadable"
    assert _js("megabytes(%d)" % (25 * mb)) == "25.0"


def test_should_play():
    base = {"mode": "animated", "failed": False, "visible": True, "locked": False, "hoverOnly": False, "hovered": False}
    assert _js("shouldPlay(%s)" % json.dumps(base)) is True
    for change in ({"mode": "icon"}, {"failed": True}, {"visible": False}, {"locked": True}, {"hoverOnly": True}):
        assert _js("shouldPlay(%s)" % json.dumps(dict(base, **change))) is False, change
    assert _js("shouldPlay(%s)" % json.dumps(dict(base, hoverOnly=True, hovered=True))) is True


def test_image_file_and_url():
    assert _js('isImageFile("bot-symbolic")') is False
    assert _js('isImageFile("/home/me/robot.GIF")') is True
    assert _js('fileUrl("/home/me/my robot#1.gif")') == "file:///home/me/my%20robot%231.gif"
    assert _js('fileUrl("file:///x.gif")') == "file:///x.gif"
