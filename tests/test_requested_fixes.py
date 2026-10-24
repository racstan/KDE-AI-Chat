import os
import json
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN_XML = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents", "config", "main.xml")
PROVIDER_SERVICE = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "ProviderService.js")
HELPER_PY = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "kde_ai_helper.py")
FULL_REP_QML = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "FullRepresentationContent.qml")
CONFIG_OTHER_QML = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "ConfigOther.qml")
MAIN_QML = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "main.qml")


def test_main_xml_contains_new_config_entries():
    tree = ET.parse(MAIN_XML)
    root = tree.getroot()
    entries = {elem.attrib.get("name"): elem for elem in root.iter() if elem.tag.endswith("entry")}
    
    assert "customIcon" in entries, "customIcon entry missing in main.xml"
    assert "disableStreaming" in entries, "disableStreaming entry missing in main.xml"
    assert "customProvidersJson" in entries, "customProvidersJson entry missing in main.xml"
    # MCP tools in direct mode were removed in 1.4.0 (harness mode provides tools).
    assert "mcpServersJson" not in entries
    assert "enableMcpTools" not in entries


def test_provider_service_custom_providers():
    with open(PROVIDER_SERVICE, encoding="utf-8") as f:
        source = re.sub(r"^\s*\.pragma\s+library\s*\n", "", f.read(), count=1)

    driver = """
    var cfg = {
        customProvidersJson: JSON.stringify([
            { id: "custom_1", name: "My LLM", type: "openai-compat", baseUrl: "https://myllm.org/v1", apiKey: "secret", model: "model-a" },
            { id: "custom_2", name: "Claude Proxy", type: "anthropic", baseUrl: "https://proxy.org", apiKey: "key2", model: "claude-custom" }
        ])
    };

    var supported = getSupportedProviders(cfg);
    console.log("SUPPORTED:" + JSON.stringify(supported));

    var name1 = getProviderDisplayName("custom_1", cfg);
    console.log("NAME1:" + name1);

    var conf1 = getProviderConfig("custom_1", cfg);
    console.log("CONF1:" + JSON.stringify(conf1));
    """

    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as script:
        script.write(source)
        script.write(driver)
        script_path = script.name

    try:
        res = subprocess.run(["node", script_path], capture_output=True, text=True, check=True)
        out = res.stdout
        assert "custom_1" in out
        assert "custom_2" in out
        assert "[Custom] My LLM" in out
        assert "https://myllm.org/v1" in out
    finally:
        os.unlink(script_path)


def test_custom_provider_settings_use_custom_endpoint_and_model_storage():
    with open(os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "ConfigGeneral.qml"), encoding="utf-8") as f:
        source = f.read()
    assert "function customProviderById(id)" in source
    assert "setCustomProviderProperty(p, \"model\", modelId || \"\")" in source
    assert "if (isCustomProviderId(p))" in source
    assert "text: page.editingCustomProviderId ? i18n(\"Save Provider\")" in source
    assert "document-edit" in source


def test_mcp_commands_are_gone():
    with open(HELPER_PY, encoding="utf-8") as f:
        source = f.read()
    for name in ("mcp_web_search", "mcp_query", "mcp_discover"):
        assert '"%s":' % name not in source


def test_touchpad_scroll_handler_in_full_representation():
    with open(FULL_REP_QML, encoding="utf-8") as f:
        content = f.read()

    assert "boundsBehavior: Flickable.DragAndOvershootBounds" in content
    assert "flickDeceleration: 1800" in content
    assert "maximumFlickVelocity: 6000" in content
    assert "WheelHandler" in content


def test_feature_settings_are_exposed_and_persisted():
    with open(CONFIG_OTHER_QML, encoding="utf-8") as f:
        config_other = f.read()
    with open(MAIN_QML, encoding="utf-8") as f:
        main_qml = f.read()

    assert "property alias cfg_customIcon: configPage.customIconValue" in config_other
    assert "cfg_disableStreaming: disableStreamingToggle.checked" in config_other
    assert "function isCustomIconImage" in config_other
    assert "function customIconImageSource" in config_other
    assert "function applyCustomIcon" in config_other
    assert "customIconFileDialog" in config_other
    assert "FileDialog.OpenFile" in config_other
    assert "*.gif" in config_other
    assert "plasmoid.configuration.customIcon = value" in config_other
    assert "plasmoid.configuration.disableStreaming = checked" in config_other
    assert "Plasmoid.icon:" in main_qml
    assert "function customIconIsImage" in main_qml
    assert "function customIconImageSource" in main_qml
    assert "plasmoid.configuration.disableStreaming !== true" in main_qml
    assert "if (plasmoid.configuration.disableStreaming === true)" in main_qml
    assert "root.openCodeEventXhr.abort()" in main_qml
    assert "root.openCodeMode && plasmoid.configuration.disableStreaming !== true" in main_qml
