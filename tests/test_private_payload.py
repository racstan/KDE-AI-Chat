"""Chat text for read aloud goes to the helper in a private file, not in argv."""
import base64
import json
import os
import re
import subprocess
import sys

import pytest

UI = os.path.join(os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI)
from kdeaichat import private_payload  # noqa: E402


def _write(folder, name, data):
    value = base64.urlsafe_b64encode(json.dumps(data).encode()).decode().rstrip("=")
    path = os.path.join(folder, name)
    with open(path, "w") as f:
        f.write("[General]\npayload=%s\n" % value)
    return path


def test_reads_and_deletes_the_file(tmp_path):
    folder = tmp_path / "run"
    folder.mkdir(mode=0o700)
    path = _write(str(folder), "kdeaichat-payload-helper-1-2.ini", {"text": "secret words ü"})
    assert private_payload.read("@kdeaichat-payload-helper-1-2.ini", str(folder)) == {"text": "secret words ü"}
    assert not os.path.exists(path)


@pytest.mark.parametrize("name", ["../x.ini", "kdeaichat-payload-a/b.ini", "other.ini", "kdeaichat-payload-.ini.bak"])
def test_refuses_other_names(tmp_path, name):
    with pytest.raises(private_payload.PayloadError):
        private_payload.read("@" + name, str(tmp_path))


def test_refuses_a_shared_folder_and_symlinks(tmp_path):
    shared = tmp_path / "shared"
    shared.mkdir()
    os.chmod(shared, 0o755)
    _write(str(shared), "kdeaichat-payload-1.ini", {"a": 1})
    with pytest.raises(private_payload.PayloadError):
        private_payload.read("@kdeaichat-payload-1.ini", str(shared))
    private = tmp_path / "private"
    private.mkdir(mode=0o700)
    target = _write(str(tmp_path), "target.ini", {"a": 1})
    os.symlink(target, private / "kdeaichat-payload-2.ini")
    with pytest.raises(private_payload.PayloadError):
        private_payload.read("@kdeaichat-payload-2.ini", str(private))
    assert os.path.exists(target)


def test_helper_takes_the_file_argument(tmp_path):
    folder = tmp_path / "run"
    folder.mkdir(mode=0o700)
    _write(str(folder), "kdeaichat-payload-9.ini", {"path": ""})
    env = dict(os.environ, XDG_RUNTIME_DIR=str(folder), KDEAICHAT_TTS_DIR=str(tmp_path / "tts"))
    out = subprocess.run([sys.executable, os.path.join(UI, "kde_ai_helper.py"), "tts_cleanup", "@kdeaichat-payload-9.ini"],
                         capture_output=True, text=True, env=env, timeout=30)
    assert out.returncode == 0, out.stdout + out.stderr
    assert json.loads(out.stdout)["ok"] is True
    assert not (folder / "kdeaichat-payload-9.ini").exists()


def test_helper_runner_is_private_by_default():
    with open(os.path.join(UI, "store", "HelperRunner.qml"), encoding="utf-8") as f:
        qml = f.read()
    assert "privateCommands" not in qml
    assert "var isPrivate = argvCommands.indexOf(command) < 0;" in qml
    listed = re.search(r"argvCommands: \[(.*?)\]", qml, re.S).group(1)
    for name in ("tts_synthesize", "speechnote_speak", "memory_add", "schedule_save", "image_save", "export_chat"):
        assert name not in listed
    assert "RuntimeLocation" in qml


def test_export_chat_writes_plain_content_and_refuses_too_much(tmp_path):
    from kdeaichat import maintenance
    target = tmp_path / "out.md"
    maintenance.cmd_export_chat({"filePath": str(target), "content": "x" * 300000 + "\u00fc"})
    assert target.read_text(encoding="utf-8") == "x" * 300000 + "\u00fc"
    with pytest.raises(ValueError):
        maintenance.cmd_export_chat({"filePath": str(tmp_path / "big.md"), "content": "y" * (maintenance.MAX_EXPORT_BYTES + 1)})
    assert not (tmp_path / "big.md").exists()


def test_a_large_payload_file_is_read(tmp_path):
    folder = tmp_path / "run"
    folder.mkdir(mode=0o700)
    _write(str(folder), "kdeaichat-payload-3.ini", {"content": "z" * 5_000_000})
    assert len(private_payload.read("@kdeaichat-payload-3.ini", str(folder))["content"]) == 5_000_000
