"""Phase 6 removed the old voice stack; these keep it from coming back."""
import glob
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
UI = os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui")
MAIN_XML = os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "config", "main.xml")


def _sources(*patterns):
    for pattern in patterns:
        for path in glob.glob(os.path.join(UI, "**", pattern), recursive=True):
            with open(path, encoding="utf-8") as f:
                yield os.path.relpath(path, UI), f.read()


def test_old_voice_files_are_gone():
    for name in ("voice/voice_helper.py", "config/VoiceEngine.qml", "config/VoiceStatusGrid.qml"):
        assert not os.path.exists(os.path.join(UI, name)), name


def test_no_always_on_voice_servers_or_polling():
    for name, text in _sources("*.qml", "*.js"):
        for old in ("--stt-server", "--tts-server", "127.0.0.1:9015", "127.0.0.1:9016", "setup_venv_services",
                    "check_env", "install_espeak"):
            assert old not in text, "%s still uses %s" % (name, old)


def test_removed_settings_are_not_declared_or_used():
    with open(MAIN_XML, encoding="utf-8") as f:
        xml = f.read()
    for key in ("voiceVenvPath", "voiceEspeakPath", "voiceTtsVoice", "voiceTtsModelPath"):
        assert 'name="%s"' % key not in xml, key
        for name, text in _sources("*.qml", "*.js"):
            assert key not in text, "%s uses %s" % (name, key)


def test_dictation_switch_is_stt_enabled():
    # voiceEnabled is read only by the one-time migration.
    for name, text in _sources("*.qml", "*.js"):
        if re.search(r"\bvoiceEnabled\b", text) and name != "voice/SttConfig.js":
            assert "Dictation switch (migrated" in text, name + " uses voiceEnabled"
    with open(os.path.join(UI, "chat", "Composer.qml"), encoding="utf-8") as f:
        assert "composer.chat.sttEnabled" in f.read()


def test_no_voice_venv_or_gpu_path_setting_on_the_page():
    with open(os.path.join(UI, "ConfigVoice.qml"), encoding="utf-8") as f:
        page = f.read()
    for old in ("cfg_voiceVenvPath", "cfg_voiceGpuEnabled", "cfg_voiceEspeakPath", "cfg_voiceEnabled", "cfg_voiceSttModelPath"):
        assert old not in page, old
