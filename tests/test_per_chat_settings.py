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
# The widget root's chat logic, split out of main.qml.
SESSIONS_QML = os.path.join(UI_DIR, "chat", "Sessions.qml")
ROOT_LOGIC = [MAIN_QML] + [os.path.join(UI_DIR, "chat", name) for name in (
    "Sessions.qml", "SessionTitles.qml", "SendController.qml", "DirectRequest.qml", "ReplyEvents.qml",
    "MessageEdits.qml", "ChatNavigation.qml", "Attachments.qml", "HelperCommands.qml", "SchedulerPoller.qml")]


def _read_root_logic():
    source = ""
    for path in ROOT_LOGIC:
        with open(path, encoding="utf-8") as f:
            source += f.read()
    return source
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
    main_source = _read_root_logic()
    with open(SESSIONS_QML, encoding="utf-8") as f:
        sessions_source = f.read()
    with open(CHAT_SETTINGS_DIALOG, encoding="utf-8") as f:
        dialog_source = f.read()
    with open(CHAT_SETTINGS_DRAFT, encoding="utf-8") as f:
        draft_source = f.read()
    with open(CHAT_OVERRIDES_FORM, encoding="utf-8") as f:
        form_source = f.read()

    assert "function setSessionOverrides(sessionId, overrides)" in sessions_source
    # Agent list loading lives in chat/OpenCodeMode.qml (every caller's
    # callback is answered) and backends/OpenCodeAgents.js (subagents and
    # hidden agents are left out; tested in tests/js/opencode_stability.test.js).
    with open(os.path.join(UI_DIR, "chat", "OpenCodeMode.qml"), encoding="utf-8") as f:
        opencode_source = f.read()
    with open(os.path.join(UI_DIR, "backends", "OpenCodeAgents.js"), encoding="utf-8") as f:
        agents_source = f.read()
    assert "mode._agentWaiters = mode._agentWaiters.concat([callback])" in opencode_source
    assert "sub[-_ ]?agent" in agents_source
    assert '"compaction", "explore", "general", "summary", "title"' in agents_source
    # No second, different agent list read from opencode.json behind the server's back.
    assert "runFallbackAgentFileFetch" not in main_source
    assert "#fetch-opencode-agents" not in main_source
    atomic_body = sessions_source.split("function setSessionOverrides(sessionId, overrides)", 1)[1].split(
        "function createSession", 1
    )[0]
    assert atomic_body.count("chat.sessions = updated") == 1
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
    assert "visible: form.draft.mode !== \"opencode\"" in form_source
    assert "setMode" not in form_source and "setMode" not in draft_source, "a chat's mode is not editable"
    assert "overrides.source" not in draft_source, "the panel never writes a chat's mode"
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
    assert "function effectiveConfig(sessionId) { return modeSync.effectiveConfig(sessionId); }" in main_source
    with open(os.path.join(UI_DIR, "chat", "ModeSync.qml"), encoding="utf-8") as f:
        assert "EffectiveConfig.forSession(config, session" in f.read()
    # No direct reads of a chat's model overrides left outside the resolver.
    root_logic = _read_root_logic()
    for key in ("chatProvider", "chatModel", "openCodeProvider", "openCodeModel", "piProvider", "piModel"):
        assert 'getSessionProperty(sessionId, "%s"' % key not in root_logic, key
    for name in ("OpenCodeMode.qml", "PiMode.qml"):
        with open(os.path.join(UI_DIR, "chat", name), encoding="utf-8") as f:
            source = f.read()
        assert "chat.effectiveConfig(sessionId)" in source, name
        assert '"chatModel"' not in source and '"openCodeModel"' not in source, name
