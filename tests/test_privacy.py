"""Finding plaintext API keys and chat history left by older versions."""
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

from kdeaichat import privacy  # noqa: E402

HELPER = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui", "kde_ai_helper.py")

SECRET = "sk-very-secret-value"

def _write(path, text, mode=0o600):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(path, mode)


def test_kconfig_unescape():
    assert privacy._unescape(r"a\sb\nc\\d\x41") == "a b\nc\\dA"


def test_legacy_keyfile_read_and_remove():
    with tempfile.TemporaryDirectory() as cfg:
        path = os.path.join(cfg, "kdeaichatrc")
        _write(path, f"[General]\napiKey={SECRET}\nqwenApiKey=q\nmistralApiKey=\nunrelated=1\n")
        assert privacy.read_kdeaichatrc_keys(path) == {"openai": SECRET, "qwen": "q"}
        assert privacy.remove_kdeaichatrc(path) is True
        assert not os.path.exists(path)
        assert privacy.remove_kdeaichatrc(path) is False


def test_every_current_key_setting_has_a_legacy_mapping():
    main_xml = os.path.join(os.path.dirname(HELPER), "..", "config", "main.xml")
    with open(main_xml, encoding="utf-8") as f:
        import re
        declared = set(re.findall(r'entry name="(apiKey|[A-Za-z]+ApiKey)"', f.read()))
    assert declared <= set(privacy.LEGACY_KEY_PROVIDERS)


def test_qml_migration_knows_the_same_key_settings():
    import re
    path = os.path.join(os.path.dirname(HELPER), "store", "Migration.qml")
    with open(path, encoding="utf-8") as f:
        source = f.read()
    block = source[source.index("legacyKeyProviders: ({"):source.index("})", source.index("legacyKeyProviders: ({"))]
    qml_map = dict(re.findall(r'"([A-Za-z]+)": "([a-z_-]+)"', block))
    assert qml_map == privacy.LEGACY_KEY_PROVIDERS

