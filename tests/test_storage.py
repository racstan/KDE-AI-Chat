"""Settings -> Storage: sizes per item, symlink safety, what can be removed (kdeaichat/storage.py)."""
import base64
import json
import os
import subprocess
import sys

import pytest

UI_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI_DIR)

from kdeaichat import storage  # noqa: E402

KB = 1024 * 64


def write(path, size=KB):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"x" * size)


@pytest.fixture
def env(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("XDG_DATA_HOME", str(home / "data"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(home / "cache"))
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path / "run"))
    monkeypatch.setenv("HF_HUB_CACHE", str(tmp_path / "hf"))
    (tmp_path / "run").mkdir()
    units = tmp_path / "units"
    units.mkdir()
    monkeypatch.setenv("KDEAICHAT_UNIT_DIR", str(units))
    fake = tmp_path / "fake-systemctl"
    fake.write_text("#!/bin/sh\nexit 0\n")
    fake.chmod(0o755)
    monkeypatch.setenv("KDEAICHAT_SYSTEMCTL", str(fake))
    monkeypatch.setenv("KDEAICHAT_TTS_DIR", str(tmp_path / "run" / "kdeaichat-tts"))
    root = home / "data" / "kdeaichat"
    root.mkdir(parents=True)
    return tmp_path, home, root


def sizes(result):
    return {i["id"]: i["size"] for i in result["items"]}


def populate(root, tmp_path, home):
    write(str(root / "chats" / "applet-1" / "chat-a.ini"))
    write(str(root / "chats" / "applet-1" / "index.ini"))
    write(str(root / "chats" / "applet-1" / "images" / "c" / "m-0.png"), KB * 4)
    write(str(root / "memory.json"))
    write(str(root / "schedules.v2.json"))
    write(str(root / "schedule-runs" / "s.json"))
    write(str(root / "backups" / "appletsrc-1"), KB * 2)
    write(str(root / "pi-bridge.log"))
    write(str(root / "run" / "x"))
    write(str(tmp_path / "run" / "kdeaichat-tts" / "speech-1.wav"))
    write(str(root / "venv" / "bin" / "python"), KB * 8)
    write(str(root / "tts-models" / "kokoro" / "m.onnx"), KB * 8)
    write(str(root / "models" / "parakeet" / "p.gguf"), KB * 8)
    write(str(root / "voice-http-token"))


def test_sizes_per_item_and_total(env):
    tmp_path, home, root = env
    populate(root, tmp_path, home)
    result = storage.usage()
    s = sizes(result)
    assert s["pictures"] >= KB * 4 and s["pictures"] < KB * 6
    assert KB * 2 <= s["chats"] < KB * 4  # two chat files, the pictures are not in it
    assert KB <= s["memories"] < KB * 2
    assert KB * 2 <= s["schedules"] < KB * 4
    assert KB * 2 <= s["backups"] < KB * 3
    assert KB * 3 <= s["caches"] < KB * 4  # log, run/x, tts wav
    assert s["voice_old"] >= KB * 24
    assert KB <= s["other"] < KB * 2  # voice-http-token
    assert result["total"] == sum(s.values())
    assert result["partial"] is False
    assert {i["id"] for i in result["items"] if i["removable"]} == {"backups", "caches", "voice_old"}
    assert result["root"] == str(root)


def test_symlinks_are_not_followed(env):
    tmp_path, home, root = env
    outside = tmp_path / "outside"
    write(str(outside / "big.bin"), KB * 50)
    write(str(root / "backups" / "a"), KB)
    os.symlink(str(outside), str(root / "backups" / "link"))
    os.symlink(str(outside), str(root / "chats-link"))
    assert sizes(storage.usage())["backups"] < KB * 3
    assert sizes(storage.usage())["other"] < KB
    storage.remove("backups")
    assert (outside / "big.bin").exists()  # the link went, not what it pointed at
    assert not os.path.lexists(str(root / "backups" / "link"))


def test_unknown_and_protected_items_refused(env, capsys):
    tmp_path, home, root = env
    populate(root, tmp_path, home)
    for item in ("chats", "pictures", "memories", "schedules", "other", "../x", "", None, 7):
        storage.cmd_storage_remove({"item": item, "confirm": True})
        assert json.loads(capsys.readouterr().out)["type"] == "storage_error"
        with pytest.raises(ValueError):
            storage.remove(item if isinstance(item, str) else "x")
    assert (root / "memory.json").exists()
    assert (root / "chats" / "applet-1" / "chat-a.ini").exists()
    assert (root / "chats" / "applet-1" / "images" / "c" / "m-0.png").exists()


def test_remove_needs_confirm(env, capsys):
    tmp_path, home, root = env
    populate(root, tmp_path, home)
    storage.cmd_storage_remove({"item": "backups"})
    assert json.loads(capsys.readouterr().out)["type"] == "storage_error"
    assert (root / "backups" / "appletsrc-1").exists()


def test_remove_backups_frees_bytes_and_keeps_the_rest(env, capsys):
    tmp_path, home, root = env
    populate(root, tmp_path, home)
    before = storage.usage()
    storage.cmd_storage_remove({"item": "backups", "confirm": True})
    out = json.loads(capsys.readouterr().out)
    assert out["type"] == "storage_removed"
    assert out["freed"] == sizes(before)["backups"] - sizes(storage.usage())["backups"] > 0
    assert (root / "backups").is_dir() and not os.listdir(root / "backups")
    assert (root / "memory.json").exists() and (root / "chats" / "applet-1" / "index.ini").exists()


def test_remove_caches(env):
    tmp_path, home, root = env
    populate(root, tmp_path, home)
    write(str(home / "cache" / "kdeaichat" / "tts" / "a.wav"))
    out = storage.remove("caches")
    assert out["freed"] >= KB * 4
    assert not (root / "pi-bridge.log").exists() and not (root / "run" / "x").exists()
    assert not os.listdir(tmp_path / "run" / "kdeaichat-tts")
    assert (root / "voice-http-token").exists() and (root / "backups" / "appletsrc-1").exists()


def test_remove_old_voice_only_removes_its_folders(env):
    tmp_path, home, root = env
    populate(root, tmp_path, home)
    speech_note = home / ".var" / "app" / "net.mkiol.SpeechNote" / "cache" / "net.mkiol" / "dsnote" / "speech-models"
    write(str(speech_note / "model.bin"), KB * 9)
    handy = home / ".local" / "share" / "com.pais.handy" / "models"
    write(str(handy / "m.gguf"), KB)
    hf_other = tmp_path / "hf" / "models--someone--else"
    write(str(hf_other / "blob"), KB)
    out = storage.remove("voice_old")
    assert out["freed"] >= KB * 24
    for name in ("venv", "tts-models", "models"):
        assert not (root / name).exists()
    assert (root / "voice-http-token").exists() and (root / "memory.json").exists()
    assert (speech_note / "model.bin").exists() and (handy / "m.gguf").exists() and (hf_other / "blob").exists()


def test_old_voice_includes_recorded_hf_models_only(env):
    tmp_path, home, root = env
    from kdeaichat import voice_leftovers
    name = "small"
    folder = tmp_path / "hf" / ("models--" + voice_leftovers._REPOS[name].replace("/", "--"))
    write(str(folder / "blobs" / "b"), KB * 6)
    other = tmp_path / "hf" / "models--not--ours"
    write(str(other / "b"), KB * 6)
    assert sizes(storage.usage())["voice_old"] == 0  # present but never recorded: not ours
    # The old installer recorded what it downloaded; names outside its list (a tampered file) are ignored.
    write(str(root / "stt-downloads.json"), 0)
    (root / "stt-downloads.json").write_text(json.dumps({"models": {name: "x", "../../etc": "y", "not-a-model": "z"}}))
    assert voice_leftovers.recorded_models() == [name]
    assert sizes(storage.usage())["voice_old"] >= KB * 6
    storage.remove("voice_old")
    assert not folder.exists() and other.exists()


def test_removing_old_voice_stops_and_deletes_the_old_units_only(env, monkeypatch):
    tmp_path, home, root = env
    units = tmp_path / "units"
    units.mkdir(exist_ok=True)
    for name in ("kde-ai-stt.socket", "kde-ai-stt.service", "kde-ai-tts.service", "kdeaichat-sched-x.timer"):
        (units / name).write_text("[Unit]\n")
    monkeypatch.setenv("KDEAICHAT_UNIT_DIR", str(units))
    monkeypatch.setenv("KDEAICHAT_SYSTEMCTL", "true")
    out = storage.remove("voice_old")
    assert out["warnings"] == []
    assert sorted(os.listdir(units)) == ["kdeaichat-sched-x.timer"], "the schedule timer is not a voice unit"


def test_speech_note_never_counted_or_removed(env):
    tmp_path, home, root = env
    assert storage.usage()["speech_note"] == {"folder": "", "exists": False}
    models = home / "cache" / "net.mkiol" / "dsnote" / "speech-models"
    write(str(models / "big.bin"), KB * 40)
    result = storage.usage()
    assert result["speech_note"] == {"folder": str(models), "exists": True}
    assert result["total"] == 0
    for item in storage.REMOVABLE:
        storage.remove(item)
    assert (models / "big.bin").exists()


def test_time_cap_marks_partial(env):
    tmp_path, home, root = env
    populate(root, tmp_path, home)
    clock = iter(range(0, 1000, 20))
    meter = storage._Meter(cap=5, now=lambda: next(clock))
    assert storage.usage(meter)["partial"] is True


def test_hard_links_counted_once(env):
    tmp_path, home, root = env
    write(str(root / "backups" / "a"), KB * 2)
    os.link(str(root / "backups" / "a"), str(root / "backups" / "b"))
    assert sizes(storage.usage())["backups"] < KB * 3


def test_through_the_helper_command_line(env):
    tmp_path, home, root = env
    populate(root, tmp_path, home)
    helper = os.path.join(UI_DIR, "kde_ai_helper.py")
    payload = base64.b64encode(json.dumps({"item": "memories", "confirm": True}).encode()).decode()
    out = subprocess.run([sys.executable, helper, "storage_remove", payload], capture_output=True, text=True, env=os.environ)
    assert json.loads(out.stdout)["type"] == "storage_error"
    out = subprocess.run([sys.executable, helper, "storage_usage"], capture_output=True, text=True, env=os.environ)
    assert json.loads(out.stdout)["type"] == "storage_usage"
    assert (root / "memory.json").exists()
