"""Regression tests for per-chat settings (on-the-fly provider/model switching and per-chat memory)."""

import json
import os
import re
import subprocess
import tempfile

UI_DIR = os.path.join(
    os.path.dirname(__file__),
    "..",
    "org.kde.plasma.kdeaichat",
    "contents",
    "ui",
)
PROVIDER_SERVICE = os.path.join(UI_DIR, "ProviderService.js")
MAIN_QML = os.path.join(UI_DIR, "main.qml")
CHAT_SETTINGS_DIALOG = os.path.join(UI_DIR, "ChatSettingsDialog.qml")
# The Chat info panel is split: the panel (CHAT_SETTINGS_DIALOG), its editable
# draft with the async refreshes, and the settings form.
CHAT_SETTINGS_DRAFT = os.path.join(UI_DIR, "chat", "ChatSettingsDraft.qml")
CHAT_OVERRIDES_FORM = os.path.join(UI_DIR, "chat", "ChatOverridesForm.qml")


def _read_js(path):
    with open(path, encoding="utf-8") as f:
        return re.sub(r"^\s*\.pragma\s+library\s*\n", "", f.read(), count=1)


def test_per_chat_settings_save_is_atomic_and_callbacks_are_scoped():
    """Protect the dialog from model churn and stale async refresh results."""
    with open(MAIN_QML, encoding="utf-8") as f:
        main_source = f.read()
    with open(CHAT_SETTINGS_DIALOG, encoding="utf-8") as f:
        dialog_source = f.read()
    with open(CHAT_SETTINGS_DRAFT, encoding="utf-8") as f:
        draft_source = f.read()
    with open(CHAT_OVERRIDES_FORM, encoding="utf-8") as f:
        form_source = f.read()

    assert "function setSessionOverrides(sessionId, overrides)" in main_source
    assert "property var openCodeAgentFetchWaiters" in main_source
    assert "function _notifyOpenCodeAgentFetchWaiters()" in main_source
    assert "openCodeAgentFetchWaiters = (root.openCodeAgentFetchWaiters || []).concat([callback])" in main_source
    assert "function isSubagent(name, metadata)" in main_source
    assert "sub[-_ ]?agent" in main_source
    assert '"compaction", "explore", "general", "summary", "title"' in main_source
    assert "item['name'] = n; item['id'] = n" in main_source
    atomic_body = main_source.split("function setSessionOverrides(sessionId, overrides)", 1)[1].split(
        "function getEffectiveProvider", 1
    )[0]
    assert atomic_body.count("root.sessions = updated") == 1
    assert "persistSessions();" in atomic_body

    assert "property int _generation" in draft_source
    assert "function _current(token)" in draft_source
    assert draft_source.count("_current(token)") >= 5
    assert "property Item hostItem" in dialog_source
    assert "property bool sidebarOpen" in dialog_source
    assert "anchors.right: parent ? parent.right : undefined" in dialog_source
    assert "function toggleForSession(sessionId)" in dialog_source
    assert "property bool loading" in draft_source
    assert "PiChatSettings" in form_source
    assert "thinking: form.draft.piThinking" in form_source
    for source in (dialog_source, draft_source, form_source):
        assert "configuration.piModel =" not in source, "a chat's settings must not change the global Pi default"
        assert "saveCurrentSessionState" not in source
    assert "rootRef.fetchPiModels" in draft_source
    assert "setSessionOverrides(sessionId, overrides)" in draft_source
    assert "visible: form.draft.shownMode !== \"opencode\"" in form_source
    assert "chatSettingsDialog.toggleForSession(root.currentSessionId)" in open(os.path.join(UI_DIR, "FullRepresentationContent.qml"), encoding="utf-8").read()


def test_per_chat_model_settings_are_opt_in_and_routed_through_one_function():
    """The two settings exist, default to "off" / "chat", and main.qml and the agent modes
    resolve a chat's mode, provider and model only through EffectiveConfig.js."""
    main_xml = os.path.join(UI_DIR, "..", "config", "main.xml")
    with open(main_xml, encoding="utf-8") as f:
        xml = f.read()
    assert re.search(r'<entry name="perChatModelSettings" type="Bool">\s*<default>false</default>', xml)
    assert re.search(r'<entry name="perChatPriority" type="String">\s*<default>chat</default>', xml)

    with open(MAIN_QML, encoding="utf-8") as f:
        main_source = f.read()
    assert "function effectiveConfig(sessionId)" in main_source
    assert "EffectiveConfig.forSession(plasmoid.configuration" in main_source
    # No direct reads of a chat's model overrides left outside the resolver.
    for key in ("chatProvider", "chatModel", "openCodeProvider", "openCodeModel", "piProvider", "piModel"):
        assert 'getSessionProperty(sessionId, "%s"' % key not in main_source, key
    for name in ("OpenCodeMode.qml", "PiMode.qml"):
        with open(os.path.join(UI_DIR, "chat", name), encoding="utf-8") as f:
            source = f.read()
        assert "chat.effectiveConfig(sessionId)" in source, name
        assert '"chatModel"' not in source and '"openCodeModel"' not in source, name
