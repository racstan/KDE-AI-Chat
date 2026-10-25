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


def test_mcp_commands_are_gone():
    with open(HELPER_PY, encoding="utf-8") as f:
        source = f.read()
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
