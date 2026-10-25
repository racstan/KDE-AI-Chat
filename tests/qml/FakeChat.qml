// A stand-in for the widget root (main.qml) with what the chat view reads,
// for testing chat/ChatView.qml and its delegates offscreen.
import QtQuick
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/chat/EffectiveConfig.js" as EffectiveConfig
import "../../org.kde.plasma.kdeaichat/contents/ui/ProviderService.js" as ProviderService

QtObject {
    id: fake

    property var messages: []
    property Chat.MessageModel messageModel: Chat.MessageModel {}
    onMessagesChanged: messageModel.sync(messages)

    property int currentStreamIndex: -1
    property string currentStreamText: ""
    property string currentStreamReasoning: ""
    // main.qml's throttled streaming path: deltas wait in streamBuffer and
    // reach currentStreamText at most every 33 ms (applyDelta mirrors
    // main.qml's applyBackendEvent for text_delta/reasoning_delta/done).
    readonly property int maxMessageChars: 2000000
    property Chat.StreamBuffer streamBuffer: Chat.StreamBuffer { target: fake; maxChars: fake.maxMessageChars }
    function applyDelta(event) {
        if (event.type === "text_delta" || event.type === "reasoning_delta")
            streamBuffer.add(event.type === "text_delta" ? "text" : "reasoning", event.delta);
        else if (event.type === "done")
            streamBuffer.flush();
    }
    property string currentStreamExtractedReasoning: ""
    property int editingMessageIndex: -1
    property string editingDraft: ""
    property bool userScrolledUp: false
    property var msgListViewRef: null
    property bool loading: false
    property int playingMessageIndex: -1
    property var voiceManagerRef: null
    property bool voiceEnabled: false
    property bool voiceTtsEnabled: false
    property var calls: []

    // What chat/Composer.qml reads and calls.
    signal clearChatInput()
    property string chatInputText: ""
    property var composerRef: null
    property bool expanded: true
    property bool streamingResponse: false
    property var attachedFiles: []
    function focusInput() {
        Qt.callLater(function() {
            if (fake.composerRef)
                fake.composerRef.focusInput();
        });
    }
    function sendMessage() {
        record("send", [chatInputText]);
        chatInputText = "";
        clearChatInput();
    }
    function attachmentsReadyToSend() { return true; }
    function ensureWalletLoaded() {}
    function checkClipboardForAttachments() {}
    function readClipboardText() { return ""; }
    function removeAttachedFile() { record("removeFile", arguments); }
    function stopStreaming() { record("stop", arguments); }

    // What chat/ChatHeader.qml, RenameRow.qml and SessionList.qml read.
    property bool historyOnlyMode: false
    property bool hideOnWindowDeactivate: true
    property string currentSessionId: "a"
    property string currentSessionTitle: "Trip planning"
    property bool renamingCurrentChat: false
    property string currentChatRenameDraft: ""
    property string editingSessionId: ""
    property string editingSessionDraft: ""
    property var sessions: []
    function sessionSubtitle(s) { return (s.count || 0) + " messages"; }
    function switchSession(id) { record("switch", arguments); currentSessionId = id; }
    function renameCurrentSession() { record("renameCurrent", arguments); }
    function createSession() { record("create", arguments); }
    function jumpOneMessageAbove() {}
    function jumpOneMessageBelow() {}
    function clearCurrentOpenCodeSessionIfNeeded() {}
    function saveCurrentSessionState() {}
    function startSessionRename(id) { editingSessionId = id; }
    function saveSessionRename() { record("saveRename", arguments); editingSessionId = ""; }
    function cancelSessionRename() { editingSessionId = ""; }
    function setSessionArchived() { record("archive", arguments); }
    function deleteSession(id) {
        record("deleteSession", arguments);
        var index = sessions.findIndex(function(x) { return x.value === id; });
        if (index < 0) return;
        var rest = sessions.slice();
        var removed = rest.splice(index, 1)[0];
        sessions = rest;
        sessionDeleted(removed, index);
    }
    function persistSessions() { record("persist", arguments); }
    signal sessionDeleted(var session, int index)
    signal messagesDropped(string sessionId, var messages)

    // What chat/EmptyState.qml, ErrorActions and the composer's templates read.
    property bool openCodeMode: false
    property var openCodeAgentsList: []
    property var openCodeProvidersList: []
    property var openCodeModelsList: []
    property var openCodeVariants: ({})
    property var piThinkingModels: ({})
    property var piProviderCandidates: []
    property var piProviderModelMap: ({})
    property bool piModelsFetching: false
    property var piModelFetchWaiters: []
    property string openCodeAgent: ""
    property string openCodeWorkspaceCwd: ""
    property var openCodeAgentsDirectory: null
    property bool fetchingAgentsInProgress: false
    property int agentFetches: 0
    function currentOpenCodeSessionId() { return "ses_0123456789abcdef"; }
    function fetchOpenCodeAgents() { agentFetches++; }
    function openCodeBaseUrl() { return "http://127.0.0.1:1"; }
    // main.qml's applySessionSource (chat/ModeSync.qml), when a test sets modeSync.
    property var modeSync: null
    function applySessionSource(session) { return modeSync ? modeSync.apply(session) : ""; }
    function syncOpenCodeSessionHistory() {}
    // main.qml's chooseWorkspace: sets (or, with "", clears) the open chat's workspace.
    function chooseWorkspace(path) {
        record("chooseWorkspace", [path]);
        if (modeSync)
            modeSync.chooseWorkspace(path);
        else
            openCodeWorkspaceCwd = path;
    }
    property bool piMode: false
    // Shown above the chat when its mode can't be used (main.qml's modeNotice).
    property string modeNotice: ""
    function sessionIndexById(id) {
        for (var i = 0; i < sessions.length; i++) {
            if (sessions[i].value === id)
                return i;
        }
        return -1;
    }
    property var promptTemplates: []
    property string providerId: "openrouter"
    property string providerModel: "openrouter/auto"
    property string providerBaseUrl: "https://openrouter.ai/api/v1"
    function getEffectiveProvider() { return providerId; }
    function getProviderConfig() { return {"model": providerModel, "baseUrl": providerBaseUrl}; }
    function providerDisplayName(id) { return {"openrouter": "OpenRouter", "openai": "OpenAI", "ollama": "Ollama", "nvidia": "NVIDIA NIM"}[id] || id; }
    function openSettings() { record("openSettings", arguments); }

    // What chat/ChatBody.qml sets and ChatSettingsDialog.qml (the Chat info panel) reads.
    property bool historySidePanel: false
    property var walletApiKeys: ({})
    property var plasmoid: ({configuration: {}})
    // main.qml's effectiveConfig, on this fake's sessions and plasmoid.configuration.
    function effectiveConfig(id) {
        var session = null;
        for (var i = 0; i < sessions.length; i++) {
            if (sessions[i].value === (id || currentSessionId))
                session = sessions[i];
        }
        return EffectiveConfig.forSession(plasmoid.configuration, session, function(providerId) {
            return ProviderService.getProviderConfig(providerId, plasmoid.configuration).model;
        }, function(providerId) {
            return ProviderService.getProviderConfig(providerId, plasmoid.configuration).variant;
        });
    }
    function getSessionProperty(id, key, fallback) {
        for (var i = 0; i < sessions.length; i++) {
            if (sessions[i].value === id)
                return sessions[i][key] === undefined || sessions[i][key] === null ? fallback : sessions[i][key];
        }
        return fallback;
    }
    function setSessionProperty(id, key, value) {
        var change = {};
        change[key] = value;
        var updated = sessions.slice();
        for (var i = 0; i < updated.length; i++) {
            if (updated[i].value === id)
                updated[i] = Object.assign({}, updated[i], change);
        }
        sessions = updated;
    }
    function setSessionOverrides(id, overrides) {
        record("overrides", [id, overrides]);
        var updated = sessions.slice();
        for (var i = 0; i < updated.length; i++) {
            if (updated[i].value === id)
                updated[i] = Object.assign({}, updated[i], overrides);
        }
        sessions = updated;
        return true;
    }

    function messageDayKeyAt(i) { return "2026-10-25"; }
    function dayDividerLabelForIndex(i) { return "Today"; }
    function formatMessageTime(m, i) { return m.time || ""; }
    function formatTokensUsage(t, c) { return t.input + " in · " + t.output + " out"; }
    function fileIconName(name) { return "text-x-generic"; }
    function scrollToBottom(force) {
        if (userScrolledUp && !force) return;
        userScrolledUp = false;
        if (msgListViewRef) msgListViewRef.positionViewAtEnd();
    }
    function record(name, args) { calls = calls.concat([{name: name, args: Array.prototype.slice.call(args)}]); }
    function copyTextToClipboard() { record("copy", arguments); }
    function deleteMessage() { record("delete", arguments); }
    function retryFailedMessage() { record("retry", arguments); }
    function regenerateResponse() { record("regenerate", arguments); }
    function saveEditedMessage() { record("saveEdit", arguments); }
    function respondToPermission() { record("permission", arguments); }
    function respondToQuestion() { record("question", arguments); }
    function questionOptionSelected() { return false; }
    function toggleQuestionOption() { record("toggleOption", arguments); }
    function submitQuestionAnswer() { record("submitQuestion", arguments); }
}
