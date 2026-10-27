"""cleanup_old_settings on fixture appletsrc files: only our group, only finished migrations, idempotent."""
import datetime as dt
import json
import os
import re
import subprocess
import sys

import pytest

from kdeaichat import applet_config, config_cleanup, privacy

from tests.conftest import UI_DIR

HELPER = os.path.join(UI_DIR, "kde_ai_helper.py")
MAIN_XML = os.path.join(os.path.dirname(UI_DIR), "config", "main.xml")

APPLETSRC = """[ActionPlugins][0]
RightButton;NoModifier=org.kde.contextmenu

[Containments][1]
activityId=abc
formfactor=2
plugin=org.kde.panel

[Containments][1][Applets][42]
immutability=1
plugin=org.kde.plasma.kdeaichat

[Containments][1][Applets][42][Configuration]
PreloadWeight=42
popupHeight=600

[Containments][1][Applets][42][Configuration][General]
autoRestartPlasmaShell=true
apiKey=
openRouterApiKey=sk-or-still-here
customIcon=dialog-messages
enableMcpTools=true
mcpServersJson=[{"name":"x"}]
userMemory=
enableMemory=true
voiceEnabled=true
voiceLanguage=de
sttSettingsMigrated=true
chatSessionsJson=
schedulerEnabled[$i]=true
language=de
providersJson=[{"id":"openrouter"}]

[Containments][1][Applets][43]
plugin=org.kde.plasma.digitalclock

[Containments][1][Applets][43][Configuration][General]
autoRestartPlasmaShell=true
language=de
userMemory=

[Containments][2][Applets][7][Configuration][General]
autoRestartPlasmaShell=true
"""

EXPECTED_REMOVED = ["apiKey", "autoRestartPlasmaShell", "chatSessionsJson", "enableMcpTools", "enableMemory",
                    "language", "mcpServersJson", "schedulerEnabled", "userMemory", "voiceEnabled", "voiceLanguage"]


@pytest.fixture
def cfg(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    (tmp_path / "config").mkdir()
    path = tmp_path / "config" / "plasma-org.kde.plasma.desktop-appletsrc"
    path.write_text(APPLETSRC)
    path.chmod(0o600)
    return path


def _group_lines(text, group):
    out, current = [], None
    for line in text.splitlines():
        if line.startswith("["):
            current = line
        elif current == group and line:
            out.append(line)
    return out


def test_removes_only_finished_and_dropped_keys_of_our_group(cfg, tmp_path):
    now = dt.datetime(2026, 10, 26, 9, 30, 0)
    result = config_cleanup.cleanup("42", now=now)
    assert result["status"] == "removed" and result["file"] == str(cfg)
    assert result["removed"] == EXPECTED_REMOVED
    text = cfg.read_text()
    assert _group_lines(text, "[Containments][1][Applets][42][Configuration][General]") == [
        "openRouterApiKey=sk-or-still-here", "customIcon=dialog-messages", "sttSettingsMigrated=true",
        'providersJson=[{"id":"openrouter"}]']
    # Everything else is byte for byte the same: only those lines of our group are gone.
    head, ours, tail = APPLETSRC.partition("[Containments][1][Applets][42][Configuration][General]\n")
    body, sep, rest = tail.partition("\n[")
    kept = [line for line in body.split("\n") if line.split("=")[0].split("[$")[0] not in EXPECTED_REMOVED]
    assert text == head + ours + "\n".join(kept) + sep + rest
    # The other applet's and the unowned group's keys are untouched.
    assert "autoRestartPlasmaShell=true\nlanguage=de\nuserMemory=\n" in text
    assert text.endswith("[Containments][2][Applets][7][Configuration][General]\nautoRestartPlasmaShell=true\n")
    # Mode kept, backup made (private), no lock left.
    assert cfg.stat().st_mode & 0o777 == 0o600
    backup = tmp_path / "data" / "kdeaichat" / "backups" / "appletsrc-20261026-093000"
    assert result["backup"] == str(backup) and backup.read_text() == APPLETSRC
    assert backup.stat().st_mode & 0o777 == 0o600
    assert (backup.parent.stat().st_mode & 0o777) == 0o700
    assert not os.path.exists(str(cfg) + ".lock")


def test_idempotent(cfg):
    config_cleanup.cleanup("42")
    after = cfg.read_text()
    mtime = cfg.stat().st_mtime_ns
    again = config_cleanup.cleanup("42")
    assert again == {"status": "clean", "file": str(cfg), "removed": []}
    assert cfg.read_text() == after and cfg.stat().st_mtime_ns == mtime


def test_pending_migrations_keep_their_keys(cfg):
    text = APPLETSRC.replace("userMemory=\n", "userMemory=- likes tea\n", 1) \
        .replace("sttSettingsMigrated=true\n", "", 1).replace("chatSessionsJson=\n", "chatSessionsJson=[{\"value\":\"1\"}]\n", 1)
    cfg.write_text(text)
    removed = config_cleanup.cleanup("42")["removed"]
    assert "userMemory" not in removed and "enableMemory" not in removed
    assert "voiceEnabled" not in removed and "voiceLanguage" not in removed
    assert "chatSessionsJson" not in removed and "openRouterApiKey" not in removed
    assert "autoRestartPlasmaShell" in removed and "apiKey" in removed
    after = cfg.read_text()
    assert "userMemory=- likes tea" in after and "voiceEnabled=true" in after


def test_other_applets_and_unknown_ids(cfg):
    original = cfg.read_text()
    assert config_cleanup.cleanup("43")["status"] == "not-found"      # not our plugin
    assert config_cleanup.cleanup("7")["status"] == "not-found"       # no plugin line
    assert config_cleanup.cleanup("99")["status"] == "not-found"
    assert config_cleanup.cleanup("../x")["status"] == "error"
    assert cfg.read_text() == original


def test_windowed_config_and_crlf(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    (tmp_path / "config").mkdir()
    path = tmp_path / "config" / "plasmawindowedrc"
    text = ("[Containments][5][Applets][1]\r\nplugin=org.kde.plasma.kdeaichat.dev\r\n\r\n"
            "[Containments][5][Applets][1][Configuration][General]\r\nuseKWallet=true\r\nmodel=gpt\r\n")
    path.write_bytes(text.encode())
    assert config_cleanup.cleanup("1")["removed"] == ["useKWallet"]
    assert path.read_bytes() == text.replace("useKWallet=true\r\n", "").encode()


def test_waits_for_a_held_lock_and_clears_a_stale_one(cfg, monkeypatch):
    monkeypatch.setattr(config_cleanup, "LOCK_WAIT", 0.3)
    lock = str(cfg) + ".lock"
    with open(lock, "w") as f:
        f.write(f"{os.getpid()}\nplasmashell\n{os.uname().nodename}\n")
    assert config_cleanup.cleanup("42")["status"] == "busy"
    assert cfg.read_text() == APPLETSRC and os.path.exists(lock)
    # A lock of a process that's gone (QLockFile's stale rule) is taken over.
    dead = subprocess.Popen([sys.executable, "-c", "pass"])
    dead.wait()
    with open(lock, "w") as f:
        f.write(f"{dead.pid}\nplasmashell\n{os.uname().nodename}\n")
    assert config_cleanup.cleanup("42")["status"] == "removed"
    assert not os.path.exists(lock)


def test_keeps_five_backups(cfg, tmp_path):
    for i in range(7):
        cfg.write_text(APPLETSRC)
        config_cleanup.cleanup("42", now=dt.datetime(2026, 10, 26, 9, 0, i))
    names = sorted(os.listdir(tmp_path / "data" / "kdeaichat" / "backups"))
    assert names == [f"appletsrc-20261026-0900{i:02d}" for i in range(2, 7)]


def test_through_the_helper(cfg):
    import base64
    arg = base64.b64encode(json.dumps({"appletId": "42"}).encode()).decode()
    out = subprocess.run([sys.executable, HELPER, "cleanup_old_settings", arg], capture_output=True, text=True,
                         timeout=60, env=dict(os.environ))
    assert out.returncode == 0, out.stderr
    assert json.loads(out.stdout)["removed"] == EXPECTED_REMOVED


def test_lists_match_main_xml_and_migrations():
    declared = set(applet_config.defaults(MAIN_XML))
    # Dropped keys are really gone from main.xml; migration-only keys are still declared.
    assert not (config_cleanup.DROPPED & declared)
    assert config_cleanup.OLD_KEYS <= declared and config_cleanup.OLD_DICTATION <= declared
    assert {"userMemory", "enableMemory", "chatSessionsJson", "sttSettingsMigrated"} <= declared
    assert config_cleanup.OLD_KEYS == set(privacy.LEGACY_KEY_PROVIDERS)
    # SttConfig.js copies exactly these old dictation keys.
    with open(os.path.join(UI_DIR, "voice", "SttConfig.js")) as f:
        stt = f.read()
    assert set(re.findall(r"\b(voice(?:Enabled|Language))\b", stt)) == \
        config_cleanup.OLD_DICTATION


REMOVED_VOICE_ENGINE_KEYS = (
    "sttModel sttParakeetModel sttDevice sttWhisperCppBinary sttWhisperCppModel sttWhisperCppServer sttCommand "
    "sttIdleMinutes voiceGpuEnabled voiceSttModel voiceSttModelPath voiceTtsNeuralVoice voiceTtsNeuralSpeed "
    "voiceTtsKokoroLanguage voiceTtsKokoroVoice voiceTtsKokoroRate voiceTtsFliteVoice voiceTtsFliteRate "
    "voiceTtsFlitePitch voiceTtsPiperModel voiceTtsPiperSpeaker voiceTtsPiperSpeed voiceTtsCommand").split()


def test_settings_of_the_removed_voice_engines_are_cleaned_up():
    declared = set(applet_config.defaults(MAIN_XML))
    for key in REMOVED_VOICE_ENGINE_KEYS:
        assert key in config_cleanup.DROPPED, key
        assert key not in declared, key
    # The settings the remaining engines use are still declared and never removed.
    for key in ("sttEnabled", "sttEngine", "sttLanguage", "sttRemoteUrl", "sttRemoteModel", "sttSpeechNoteModel",
                "voiceTtsEngine", "voiceTtsSystemVoice", "voiceTtsRemoteUrl", "voiceTtsSpeechNoteModel", "voiceAutoSend"):
        assert key in declared and key not in config_cleanup.DROPPED, key
    text = APPLETSRC.replace("customIcon=dialog-messages\n", "customIcon=dialog-messages\n" + "".join(
        "%s=x\n" % k for k in REMOVED_VOICE_ENGINE_KEYS) + "sttEngine=parakeet\nsttRemoteUrl=http://localhost:8000/v1\n")
    group, removed, new_text = config_cleanup.plan(text, "42")
    assert set(REMOVED_VOICE_ENGINE_KEYS) <= set(removed)
    kept = new_text
    assert "sttEngine=parakeet" in kept, "the engine itself stays: the widget moves it to Speech Note at start"
    assert "sttRemoteUrl=http://localhost:8000/v1" in kept
    assert not any(line.split("=")[0] in REMOVED_VOICE_ENGINE_KEYS for line in kept.splitlines())
