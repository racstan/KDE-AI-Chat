"""Finding plaintext API keys and chat history left by older versions."""
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

from kdeaichat import privacy  # noqa: E402

HELPER = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui", "kde_ai_helper.py")

SECRET = "sk-very-secret-value"

APPLETSRC = f"""[Containments][3][Applets][40]
immutability=1
plugin=org.kde.plasma.kdeaichat

[Containments][3][Applets][40][Configuration][General]
mistralApiKey={SECRET}
qwenApiKey={SECRET}
groqApiKey=
chatSessionsJson=[{{"value":"a","messages":[{{"role":"user","content":"hi\\sthere"}}]}},{{"value":"b","messages":[]}}]
customProvidersJson=[{{"id":"custom_x","apiKey":"{SECRET}"}},{{"id":"custom_y","apiKey":""}}]

[Containments3Appletsts][38][Configuration][General]
chatSessionsJson=[{{"value":"old"}}]

[Containments][3][Applets][41]
plugin=org.kde.plasma.digitalclock

[Containments][3][Applets][41][Configuration][General]
showSeconds=true
"""


def _write(path, text, mode=0o600):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(path, mode)


def test_report_lists_key_names_and_chats_but_never_values():
    with tempfile.TemporaryDirectory() as cfg:
        _write(os.path.join(cfg, "plasma-org.kde.plasma.desktop-appletsrc"), APPLETSRC)
        _write(os.path.join(cfg, "kdeaichatrc"), f"[General]\napiKey={SECRET}\nanthropicApiKey=\n", 0o644)
        old = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = cfg
        try:
            report = privacy.report()
        finally:
            if old is None:
                os.environ.pop("XDG_CONFIG_HOME")
            else:
                os.environ["XDG_CONFIG_HOME"] = old

    assert SECRET not in json.dumps(report)
    live, orphan = report["appletConfig"]
    assert live["live"] is True
    assert live["keyNames"] == ["mistralApiKey", "qwenApiKey"]
    assert live["customProviderKeys"] == 1
    assert live["chatCount"] == 2
    assert orphan["live"] is False and orphan["chatCount"] == 1
    assert report["kdeaichatrc"]["keyNames"] == ["apiKey"]
    assert report["kdeaichatrc"]["mode"] == "0o644"


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


def test_helper_exposes_privacy_report():
    with tempfile.TemporaryDirectory() as cfg:
        env = dict(os.environ, XDG_CONFIG_HOME=cfg)
        out = subprocess.run([sys.executable, HELPER, "privacy_report", "e30="],
                             capture_output=True, text=True, env=env, check=True).stdout
    assert json.loads(out) == {"appletConfig": [], "kdeaichatrc": {
        "file": os.path.join(cfg, "kdeaichatrc"), "exists": False, "mode": None, "keyNames": []}}


def test_qml_migration_knows_the_same_key_settings():
    import re
    path = os.path.join(os.path.dirname(HELPER), "store", "Migration.qml")
    with open(path, encoding="utf-8") as f:
        source = f.read()
    block = source[source.index("legacyKeyProviders: ({"):source.index("})", source.index("legacyKeyProviders: ({"))]
    qml_map = dict(re.findall(r'"([A-Za-z]+)": "([a-z_-]+)"', block))
    assert qml_map == privacy.LEGACY_KEY_PROVIDERS
