"""Voice disk usage, removing only what we installed, the download record, and Piper voices on disk."""
import json
import os

import pytest

from kdeaichat import stt_commands, stt_http, stt_units, voice_data


def touch(path, size=2_000_000):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"x" * size)


def ct2(folder, size=2_000_000):
    touch(os.path.join(folder, "model.bin"), size)
    touch(os.path.join(folder, "config.json"), 2)


@pytest.fixture
def env(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("XDG_DATA_HOME", str(home / "data"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(home / "cache"))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(home / "config"))
    monkeypatch.setenv("HF_HUB_CACHE", str(tmp_path / "hf"))
    units = tmp_path / "units"
    units.mkdir()
    monkeypatch.setenv("KDEAICHAT_UNIT_DIR", str(units))
    fake = tmp_path / "fake-systemctl"
    fake.write_text("#!/bin/sh\necho \"$@\" >> \"%s\"\n" % (tmp_path / "systemctl.log"))
    fake.chmod(0o755)
    monkeypatch.setenv("KDEAICHAT_SYSTEMCTL", str(fake))
    return tmp_path


def venv_path(env):
    return env / "home" / "data" / "kdeaichat" / "venv"


def make_venv(env, torch=True):
    site = venv_path(env) / "lib" / "python3.13" / "site-packages"
    touch(str(venv_path(env) / "bin" / "python3"), 10)
    touch(str(site / "faster_whisper" / "__init__.py"), 1_000_000)
    touch(str(site / "ctranslate2" / "lib.so"), 3_000_000)
    touch(str(site / "nvidia" / "cublas" / "lib" / "libcublas.so"), 4_000_000)
    touch(str(site / "nvidia" / "cudnn" / "lib" / "libcudnn.so"), 4_000_000)
    if torch:
        touch(str(site / "torch" / "lib" / "libtorch.so"), 10_000_000)
        touch(str(site / "torch-2.5.1.dist-info" / "RECORD"), 1_000_000)
        touch(str(site / "nvidia" / "cusparse" / "lib" / "libcusparse.so"), 5_000_000)
        touch(str(site / "nvidia_cusparse_cu12-12.3.dist-info" / "RECORD"), 1_000_000)
        touch(str(site / "spacy" / "x.py"), 2_000_000)
        touch(str(site / "kokoro_onnx" / "x.py"), 1_000_000)
    os.symlink("/usr/bin/python3", str(venv_path(env) / "bin" / "python"))  # not followed
    return site


def run(command, payload, capsys):
    voice_data.COMMANDS[command](payload)
    return json.loads(capsys.readouterr().out.strip().splitlines()[-1])


def test_voice_data_reports_venv_bloat_and_only_our_models(env, capsys):
    make_venv(env)
    hf = env / "hf"
    ct2(str(hf / "models--Systran--faster-whisper-small" / "snapshots" / "a"), 3_000_000)
    ct2(str(hf / "models--Systran--faster-whisper-base" / "snapshots" / "b"))  # foreign
    voice_data.record_download("small")
    voice_data.record_download("tiny")  # recorded but no longer on disk
    assert os.stat(voice_data.record_path()).st_mode & 0o777 == 0o600

    data = run("voice_data", {}, capsys)["faster_whisper"]
    assert data["venv"] == str(venv_path(env)) and data["venv_exists"] and data["has_torch"]
    assert data["venv_mb"] == 32
    assert data["rebuild_frees_mb"] == 20  # torch 11 + cusparse 6 + spacy 2 + kokoro 1; cublas/cudnn stay
    assert [(m["name"], m["repo"], m["mb"]) for m in data["models"]] == [("small", "Systran/faster-whisper-small", 3)]
    assert data["models"][0]["path"] == str(hf / "models--Systran--faster-whisper-small")
    assert data["models_mb"] == 3 and data["total_mb"] == 35


def test_slim_venv_and_no_venv(env, capsys):
    make_venv(env, torch=False)
    data = run("voice_data", {}, capsys)["faster_whisper"]
    assert not data["has_torch"] and data["rebuild_frees_mb"] == 0
    import shutil
    shutil.rmtree(venv_path(env))
    data = run("voice_data", {}, capsys)["faster_whisper"]
    assert data == dict(data, venv_exists=False, venv_mb=0, has_torch=False, models=[], total_mb=0)


def test_remove_needs_confirm_and_a_known_engine(env, capsys):
    make_venv(env)
    assert run("voice_data_remove", {}, capsys)["type"] == "voice_data_error"
    assert run("voice_data_remove", {"confirm": "true"}, capsys)["type"] == "voice_data_error"
    assert run("voice_data_remove", {"confirm": True, "engine": "piper"}, capsys)["type"] == "voice_data_error"
    assert venv_path(env).is_dir() and not (env / "systemctl.log").exists()


def test_remove_deletes_venv_units_and_only_recorded_models(env, capsys):
    make_venv(env)
    units = env / "units"
    (units / "kde-ai-stt.socket").write_text("[Socket]\n")
    (units / "kde-ai-stt.service").write_text("[Service]\nExecStart=x stt_service.py\n")
    hf = env / "hf"
    ours = hf / "models--Systran--faster-whisper-small"
    foreign = hf / "models--Systran--faster-whisper-base"
    ct2(str(ours / "snapshots" / "a"), 3_000_000)
    ct2(str(foreign / "snapshots" / "b"))
    other = hf / "models--someone--whisper-ct2-de"
    ct2(str(other / "snapshots" / "c"))
    speech_note = env / "home" / "cache" / "net.mkiol" / "dsnote" / "speech-models" / "multilang_fasterwhisper_small"
    ct2(str(speech_note))
    voice_data.record_download("small")

    reply = run("voice_data_remove", {"engine": "faster-whisper", "confirm": True}, capsys)
    assert reply["type"] == "voice_data_removed" and reply["freed_mb"] == 35
    assert reply["removed"] == [str(venv_path(env)), str(ours)]
    assert not venv_path(env).exists() and not ours.exists()
    assert foreign.is_dir() and other.is_dir() and speech_note.is_dir()
    assert not (units / "kde-ai-stt.socket").exists() and not (units / "kde-ai-stt.service").exists()
    assert "disable --now kde-ai-stt.socket kde-ai-stt.service" in (env / "systemctl.log").read_text()
    assert voice_data.read_record() == {}


def test_rebuild_keeps_models(env, capsys):
    make_venv(env)
    ours = env / "hf" / "models--Systran--faster-whisper-small"
    ct2(str(ours / "snapshots" / "a"))
    voice_data.record_download("small")
    reply = run("voice_data_remove", {"confirm": True, "keepModels": True}, capsys)
    assert reply["removed"] == [str(venv_path(env))] and ours.is_dir()
    assert voice_data.read_record() == {"small": "Systran/faster-whisper-small"}


def test_remove_refuses_a_symlinked_venv(env, capsys):
    target = env / "elsewhere"
    touch(str(target / "keep.txt"), 10)
    os.makedirs(venv_path(env).parent)
    os.symlink(str(target), str(venv_path(env)))
    reply = run("voice_data_remove", {"confirm": True}, capsys)
    assert reply["type"] == "voice_data_error" and "symlink" in reply["error"]
    assert (target / "keep.txt").exists() and os.path.islink(venv_path(env))


def test_sync_never_kills_processes_in_a_sandbox(env, monkeypatch):
    monkeypatch.setattr(stt_units.procs, "cmdline", lambda pid: pytest.fail("scanned /proc"))
    assert stt_units.legacy_pids() == []
    stt_units.sync({"sttEnabled": False})


def test_download_records_only_models_that_were_not_on_disk(env, monkeypatch):
    hf = env / "hf"
    calls = []

    def fake_call(path, request, token, port, timeout=0):
        calls.append(request["model"])
        ct2(str(hf / ("models--Systran--faster-whisper-" + request["model"]) / "snapshots" / "z"))
        return {"type": "stt_downloaded", "model": request["model"], "path": "x"}

    monkeypatch.setattr(stt_http, "service_call", fake_call)
    ct2(str(hf / "models--Systran--faster-whisper-base" / "snapshots" / "pre"))  # the user had it already
    out = []
    monkeypatch.setattr(stt_commands, "_emit", out.append)
    stt_commands.COMMANDS["stt_download_model"]({"sttModel": "base"})
    stt_commands.COMMANDS["stt_download_model"]({"sttModel": "tiny"})
    assert calls == ["base", "tiny"] and [o["type"] for o in out] == ["stt_downloaded", "stt_downloaded"]
    assert voice_data.read_record() == {"tiny": "Systran/faster-whisper-tiny"}


def piper(folder, name, meta=None):
    touch(os.path.join(folder, name + ".onnx"), 1_000_000)
    with open(os.path.join(folder, name + ".onnx.json"), "w") as f:
        f.write(json.dumps(meta) if meta is not None else "not json")


def test_piper_voices_from_speech_note_and_piper_folders(env, capsys):
    home = env / "home"
    native = home / "cache" / "net.mkiol" / "dsnote" / "speech-models"
    piper(str(native / "en_piper_lessac_medium"), "en_US-lessac-medium",
          {"language": {"code": "en_US"}, "audio": {"quality": "medium"}})
    touch(str(native / "en_piper_broken" / "voice.onnx"), 10)  # no .onnx.json: skipped
    ct2(str(native / "multilang_fasterwhisper_small"))  # not a Piper voice
    flatpak = home / ".var" / "app" / "net.mkiol.SpeechNote" / "cache" / "net.mkiol" / "dsnote" / "speech-models"
    piper(str(flatpak / "de_piper_thorsten_high"), "de_DE-thorsten-high", {"language": {}, "audio": {}})
    piper(str(home / "data" / "piper" / "en" / "en_GB" / "alan"), "en_GB-alan-low")  # unparseable json
    piper(str(home / "data" / "piper-voices"), "fr_FR-siwis-x_low",
          {"language": {"code": "fr_FR"}, "audio": {"quality": "x_low"}})
    piper(str(home / "data" / "piper" / "a" / "b" / "c" / "d"), "too-deep")  # 4 levels down
    os.symlink(str(home / "data" / "piper-voices"), str(home / "data" / "piper" / "link"))  # not followed

    voices = run("tts_piper_voices", {}, capsys)["voices"]
    summary = [(v["source"], v["name"], v["language"], v["quality"]) for v in voices]
    assert summary == [
        ("Piper", "en_GB-alan-low", "en_GB", "low"),
        ("Piper", "fr_FR-siwis-x_low", "fr_FR", "x_low"),
        ("Speech Note", "en_US-lessac-medium", "en_US", "medium"),
        ("Speech Note (Flatpak)", "de_DE-thorsten-high", "de_DE", "high"),
    ]
    assert voices[2]["path"] == str(native / "en_piper_lessac_medium" / "en_US-lessac-medium.onnx")
    assert all(v["mb"] == 1 for v in voices)
