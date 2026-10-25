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
CONFIG_APPEARANCE_QML = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "ConfigAppearance.qml")
CONFIG_CONNECTION_QML = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "ConfigConnection.qml")
REQUEST_OPTIONS_QML = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "config", "RequestOptions.qml")
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


def test_mcp_commands_are_gone():
    package = os.path.join(os.path.dirname(HELPER_PY), "kdeaichat")
    source = ""
    for path in [HELPER_PY] + [os.path.join(package, n) for n in sorted(os.listdir(package)) if n.endswith(".py")]:
        with open(path, encoding="utf-8") as f:
            source += f.read()
    for name in ("mcp_web_search", "mcp_query", "mcp_discover"):
        assert '"%s":' % name not in source


def test_touchpad_scroll_handler_in_full_representation():
    chat_view = os.path.join(os.path.dirname(FULL_REP_QML), "chat", "ChatView.qml")
    with open(chat_view, encoding="utf-8") as f:
        content = f.read()

    assert "boundsBehavior: Flickable.DragAndOvershootBounds" in content
    assert "flickDeceleration: 1800" in content
    assert "maximumFlickVelocity: 6000" in content
    assert "WheelHandler" in content


def test_feature_settings_are_exposed_and_persisted():
    with open(CONFIG_APPEARANCE_QML, encoding="utf-8") as f:
        appearance = f.read()
    with open(CONFIG_CONNECTION_QML, encoding="utf-8") as f:
        connection = f.read()
    with open(REQUEST_OPTIONS_QML, encoding="utf-8") as f:
        request_options = f.read()
    with open(MAIN_QML, encoding="utf-8") as f:
        main_qml = f.read()

    # Saved by Plasma on Apply/OK, like every other setting.
    assert "property string cfg_customIcon" in appearance
    # The Connection page saves the request options through aliases.
    assert "property alias cfg_disableStreaming: requests.disableStreaming" in connection
    assert "property alias cfg_requestTimeout: requests.timeout" in connection
    assert "options.disableStreaming = !checked" in request_options
    assert "function isCustomIconImage" in appearance
    assert "function customIconImageSource" in appearance
    assert "FileDialog.OpenFile" in appearance
    assert "*.gif" in appearance
    assert "KIconThemes.IconDialog" in appearance
    assert "Plasmoid.icon:" in main_qml
    assert "function customIconIsImage" in main_qml
    assert "function customIconImageSource" in main_qml
    assert "plasmoid.configuration.disableStreaming !== true" in main_qml


def test_settings_pages_exist_and_cut_settings_are_gone():
    package = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents")
    with open(os.path.join(package, "config", "config.qml"), encoding="utf-8") as f:
        sources = re.findall(r'source:\s*"([^"]+)"', f.read())
    assert sources == ["ConfigConnection.qml", "ConfigChat.qml",
                       "ConfigSchedules.qml", "ConfigVoice.qml", "ConfigAppearance.qml"]
    for source in sources:
        assert os.path.isfile(os.path.join(package, "ui", source)), source

    # Cut in Phase 4 (docs/plan/07-cut-list.md): no setting and no reader left.
    entries = {elem.attrib.get("name") for elem in ET.parse(MAIN_XML).getroot().iter() if elem.tag.endswith("entry")}
    cut = ("uiLanguage", "appearanceMode", "showInteractiveGuides", "desktopSelectionEnabled")
    for name in cut:
        assert name not in entries, name
    for directory, _dirs, files in os.walk(package):
        for name in files:
            if name.endswith((".qml", ".js")):
                with open(os.path.join(directory, name), encoding="utf-8") as f:
                    text = f.read()
                for setting in cut:
                    assert setting not in text, f"{name} still reads {setting}"
