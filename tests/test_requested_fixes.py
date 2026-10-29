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
    assert "property alias cfg_customIcon: panelIcon.customIcon" in appearance
    with open(os.path.join(os.path.dirname(CONFIG_APPEARANCE_QML), "config", "IconSettings.qml"), encoding="utf-8") as f:
        icon_settings = f.read()
    # The Connection page saves the request options through aliases.
    assert "property alias cfg_disableStreaming: requests.disableStreaming" in connection
    assert "property alias cfg_requestTimeout: requests.timeout" in connection
    assert "options.disableStreaming = !checked" in request_options
    assert "FileDialog.OpenFile" in icon_settings
    assert "*.gif" in icon_settings
    assert "KIconThemes.IconDialog" in icon_settings
    assert "Plasmoid.icon:" in main_qml
    # The panel icon (still image, theme icon or animation) is chat/PanelIcon.qml.
    assert "compactRepresentation: Chat.PanelIcon" in main_qml
    with open(os.path.join(os.path.dirname(MAIN_QML), "chat", "PanelIcon.js"), encoding="utf-8") as f:
        panel_icon = f.read()
    assert "function isImageFile" in panel_icon
    assert "function fileUrl" in panel_icon
    with open(os.path.join(os.path.dirname(MAIN_QML), "chat", "DirectRequest.qml"), encoding="utf-8") as f:
        assert "plasmoid.configuration.disableStreaming !== true" in f.read()


def test_settings_pages_exist_and_cut_settings_are_gone():
    package = os.path.join(REPO_ROOT, "org.kde.plasma.kdeaichat", "contents")
    with open(os.path.join(package, "config", "config.qml"), encoding="utf-8") as f:
        sources = re.findall(r'source:\s*"([^"]+)"', f.read())
    assert sources == ["ConfigConnection.qml", "ConfigSpending.qml", "ConfigChat.qml", "ConfigPersonality.qml", "ConfigMemory.qml",
                       "ConfigSchedules.qml", "ConfigVoice.qml", "ConfigAppearance.qml", "ConfigDesktop.qml", "ConfigStorage.qml", "ConfigSupport.qml"]
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


def test_old_memory_settings_exist_only_for_the_migration():
    """enableMemory/userMemory (cut before 1.4.0) are declared only so
    store/MemoryMigration.qml can move them into the memory list and clear
    them, like the old key settings are for store/Migration.qml; nothing else
    reads them. Memory's own switch is memoryEnabled."""
    with open(MAIN_XML, encoding="utf-8") as f:
        xml = f.read()
    entries = {elem.attrib.get("name"): elem for elem in ET.fromstring(xml).iter() if elem.tag.endswith("entry")}
    assert entries["memoryEnabled"].attrib["type"] == "Bool"
    assert [e.text for e in entries["memoryEnabled"] if e.tag.endswith("default")] == ["true"]
    marker = xml.index("migration (store/MemoryMigration.qml) can move and clear them. -->")
    for name in ("enableMemory", "userMemory"):
        assert name in entries
        declared_at = xml.index('name="%s"' % name)
        between = xml[marker:declared_at]
        assert 0 < declared_at - marker and between.count("<!--") == 0 and between.count("<entry") <= 2, \
            name + " must sit right under the migration-only comment"
    ui = os.path.dirname(MAIN_QML)
    readers = []
    for folder, _dirs, files in os.walk(ui):
        for name in files:
            if name.endswith((".qml", ".js", ".py")):
                path = os.path.join(folder, name)
                with open(path, encoding="utf-8") as f:
                    if re.search(r"\b(userMemory|enableMemory)\b", f.read()):
                        readers.append(os.path.relpath(path, ui))
    # The migration reads them; the old-settings cleanup only deletes them once it's done.
    assert sorted(readers) == sorted([os.path.join("store", "MemoryMigration.qml"),
                                      os.path.join("kdeaichat", "config_cleanup.py")])
