import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import "ProviderService.js" as ProviderService
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid
import QtCore
import "Security.js" as Sec
import "store" as Store
import "backends/DirectBackend.js" as DirectBackend
import "backends/AgentEvents.js" as AgentEvents
import "chat/PromptTemplates.js" as PromptTemplates
import "chat" as Chat

PlasmoidItem {
    id: root

    // The icon value may be a KDE icon name or an image file path chosen in
    // Settings → Other (see customIconIsImage below).
    Plasmoid.icon: (plasmoid && plasmoid.configuration && plasmoid.configuration.customIcon) ? plasmoid.configuration.customIcon : "dialog-messages"

    property var sessions: []
    property string currentSessionId: ""
    property string currentSessionTitle: ""
    property var messages: []
    property string currentStreamKey: ""
    // The view's row-by-row copy of `messages` (see chat/MessageModel.qml).
    property Chat.MessageModel messageModel: Chat.MessageModel {}
    // Stream deltas wait here and reach currentStreamText/Reasoning at most every 33 ms.
    property Chat.StreamBuffer streamBuffer: Chat.StreamBuffer { target: root; maxChars: root.maxMessageChars }
    property var attachedFiles: []
    property bool historyOnlyMode: false
    property bool loading: false
    property var activeXhr: null
    property int requestGeneration: 0
    property string activeRequestSessionId: ""
    property var pendingAttachmentRequests: ({})
    property int attachmentRequestCounter: 0
    property bool schedulerPollInFlight: false
    property string schedulerResumeSessionId: ""
    property bool streamingResponse: false
    property string currentStreamText: ""
    property string currentStreamReasoning: ""
    property string currentStreamExtractedReasoning: ""
    readonly property int maxMessageChars: 2000000
    property int currentStreamIndex: -1
    property int playingMessageIndex: -1
    property int editingMessageIndex: -1
    property string editingDraft: ""
    property string editingSessionId: ""
    property string editingSessionDraft: ""
    property bool renamingCurrentChat: false
    property string currentChatRenameDraft: ""
    property bool openCodeMode: plasmoid.configuration.useOpenCode
    property bool piMode: plasmoid.configuration.usePi
    property string openCodeAgent: plasmoid.configuration.openCodeAgent || ""
    property string openCodeWorkspaceCwd: plasmoid.configuration.openCodeWorkspaceCwd || ""
    property bool openCodeUseAgentModel: plasmoid.configuration.openCodeUseAgentModel !== false
    property var openCodeAgentsList: []
    property var openCodeProvidersList: []
    property var openCodeModelsList: []
    property var piProviderCandidates: []
    property var piProviderModelMap: ({})
    property bool piModelsFetching: false
    property var piModelFetchWaiters: []
    property bool fetchingAgentsInProgress: false
    property bool fetchingOpenCodeConfig: false
    property var openCodeAgentFetchWaiters: []
    property bool voiceEnabled: plasmoid.configuration.voiceEnabled === true
    property bool voiceTtsEnabled: plasmoid.configuration.voiceTtsEnabled === true
    property string compiledSystemPrompt: ""
    // Root-level proxies so root-scope functions can reach UI elements in fullRepresentation
    property string chatInputText: ""
    property var msgListViewRef: null
    property var composerRef: null
    property bool userScrolledUp: false
    property bool titleGenerationInProgress: false
    property string titleGenerationSessionId: ""
    // Token counts reported for the reply being streamed.
    property var currentStreamUsage: ({})
    property int queueCounter: 0
    // Popup size: the live size while chat/ResizeHandle.qml drags (0 otherwise), else the saved one.
    property int livePopupWidth: 0
    property int livePopupHeight: 0
    readonly property int popupPreferredWidth: livePopupWidth > 0 ? livePopupWidth : (plasmoid.configuration.customPopupWidth > 0 ? plasmoid.configuration.customPopupWidth : 760)
    readonly property int popupPreferredHeight: livePopupHeight > 0 ? livePopupHeight : (plasmoid.configuration.customPopupHeight > 0 ? plasmoid.configuration.customPopupHeight : 760)
    property bool keysLoaded: false
    // providerId -> API key, read from KWallet (the only place keys are kept).
    readonly property var walletApiKeys: wallet.keys
    property bool _initialLoadDone: false
    property string sessionHistoryLoadError: ""
    // One-line notice about the 1.4.0 move of keys and chats.
    property string privacyNotice: storage.notice
    readonly property var wallet: storage.wallet
    readonly property var chatStore: storage.chatStore
    readonly property var store: storage
    property bool sessionHistoryLoadBlocked: false

    signal clearChatInput()
    // A chat was deleted (chat/UndoNotice.qml offers to bring it back).
    signal sessionDeleted(var session, int index)
    readonly property var promptTemplates: PromptTemplates.parse(plasmoid.configuration.promptTemplates)

    function openSettings() {
        Plasmoid.internalAction("configure").trigger();
    }

    Store.Storage {
        id: storage
        configuration: plasmoid.configuration
        helperPath: root.getHelperPath()
        // Chats are stored per widget instance, as they were in the config.
        chatDirectory: decodeURIComponent(String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)).replace(/^file:\/\//, ""))
            + "/kdeaichat/chats/applet-" + plasmoid.id
        currentSessions: function() { return root.sessionHistoryLoadBlocked ? null : root.sessions; }
        onSavesReleased: root.persistSessions()
    }

    Chat.OpenCodeMode {
        id: openCode
        chat: root
    }

    Chat.PiMode {
        id: piAgent
        chat: root
    }

    VoiceManager {
        id: voiceManager

        onTextRecognized: function(text) {
            if (voiceManager.autoSend) {
                root.chatInputText = text;
                root.sendMessage();
            } else {
                root.chatInputText += (root.chatInputText ? " " : "") + text;
            }
        }

        onErrorOccurred: function(errorText) {
            console.error("Voice Error: " + errorText);
            // Optionally show a notification
            let message = Sec.sanitizeForShell(errorText || "Unknown voice error");
            root.fileReaderDs.connectSource("notify-send -i dialog-error " + Sec.quoteForShell("Voice Error") + " " + Sec.quoteForShell(message) + " #voice-error");
        }
    }

    // Expose voiceManager as a root property so dynamically loaded children
    // (e.g. FullRepresentationContent via Loader) can access it via root.voiceManager
    property var voiceManagerRef: voiceManager

    function ensureWalletLoaded() {
        if (!keysLoaded) {
            keysLoaded = true;
            wallet.load();
        }
    }

    function scheduleWalletReload() {
        walletReloadTimer.restart();
    }

    // chat/Composer.qml registers itself here while the popup content exists.
    function focusInput() {
        Qt.callLater(function() {
            if (root.composerRef)
                root.composerRef.focusInput();
        });
    }

    function fetchPiModels(callback) {
        if (callback)
            root.piModelFetchWaiters = (root.piModelFetchWaiters || []).concat([callback]);
        if (root.piModelsFetching)
            return;
        root.piModelsFetching = true;
        piDiscoveryDs.connectSource("python3 " + Sec.quoteForShell(root.getHelperPath()) + " get_pi_models #pi-models-" + Date.now());
    }

    function triggerInitialLoad() {
        if (_initialLoadDone)
            return ;

        _initialLoadDone = true;
        startupTimer.stop(); // Stop background timer if we triggered early
        // Load sessions immediately so UI has chat list / current chat ready
        loadSessions();
        storage.chatsLoaded();
        // Defer wallet and sys info slightly so initial layout/rendering is unblocked
        lazyWalletTimer.start();
    }

    function pad2(v) {
        return v < 10 ? ("0" + v) : String(v);
    }

    function nowTime(ts) {
        var d = ts ? new Date(ts) : new Date();
        return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
    }

    function formatDateTime(ts) {
        return new Date(ts).toLocaleString(undefined, {
            "year": "numeric",
            "month": "short",
            "day": "2-digit",
            "hour": "2-digit",
            "minute": "2-digit"
        });
    }

    function makeSessionId() {
        return "s-" + Date.now() + "-" + Math.floor(Math.random() * 100000);
    }

    // Normalises `stored` (chats read from the chat store) or, when it is
    // null, the chat history older versions kept in the widget's config.
    function parseSessions(stored) {
        root.sessionHistoryLoadError = "";
        root.sessionHistoryLoadBlocked = false;
        var raw = stored ? "" : String(plasmoid.configuration.chatSessionsJson || "[]");
        if (raw.length > 25000000) {
            root.sessionHistoryLoadError = "Stored chat history is too large to load safely.";
            root.sessionHistoryLoadBlocked = true;
            return [];
        }
        try {
            var arr = stored || JSON.parse(raw);
            if (!Array.isArray(arr)) return [];
            var valid = [];
            var seenIds = {};
            for (var i = 0; i < arr.length; i++) {
                if (!arr[i] || typeof arr[i] !== "object") continue;
                var session = arr[i];
                session.value = Sec.validateSessionId(session.value) || makeSessionId();
                while (seenIds[session.value]) session.value = makeSessionId();
                seenIds[session.value] = true;
                if (!Array.isArray(session.messages)) session.messages = [];
                session.messages = session.messages.filter(function(message) {
                    return message && typeof message === "object";
                });
                if (session.archived === undefined) session.archived = false;
                if (["provider", "opencode", "pi"].indexOf(session.source) < 0)
                    session.source = session.openCodeSessionId ? "opencode" : "provider";
                for (var j = 0; j < session.messages.length; j++) {
                    var message = session.messages[j];
                    if (message.content === undefined || message.content === null)
                        message.content = "";
                    else if (typeof message.content !== "string")
                        message.content = String(message.content);
                    if (message.content.length > root.maxMessageChars) {
                        message.content = message.content.substring(0, root.maxMessageChars) + "\n[message truncated]";
                        if (!root.sessionHistoryLoadError)
                            root.sessionHistoryLoadError = "One or more stored messages exceeded the safe display limit and were truncated.";
                    }
                    if (!message.at) message.at = session.updatedAt || session.createdAt || Date.now();
                    if (!message.time) message.time = nowTime(message.at);
                }
                if (!session.updatedAt) session.updatedAt = session.createdAt || Date.now();
                valid.push(session);
            }
            return valid;
        } catch (e) {
            root.sessionHistoryLoadError = "Stored chat history could not be parsed. It was left untouched.";
            root.sessionHistoryLoadBlocked = true;
            return [];
        }
    }

    function persistSessions() {
        if (root.sessionHistoryLoadBlocked)
            return;
        try {
            storage.save(root.sessions);
            plasmoid.configuration.lastSessionId = root.currentSessionId;
        } catch (e) {
            console.error("KDE AI Chat: failed to persist sessions:", e);
        }
    }

    function sortSessionsByUpdated() {
        var copy = root.sessions.slice();
        copy.sort(function(a, b) {
            if (!!a.archived !== !!b.archived)
                return a.archived ? 1 : -1;

            return (b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0);
        });
        root.sessions = copy;
    }

    function sessionSubtitle(sessionData) {
        var parts = [];
        if (sessionData.source === "opencode")
            parts.push("OpenCode");

        if (sessionData.archived)
            parts.push("Archived");

        parts.push("Updated " + root.formatDateTime(sessionData.updatedAt || sessionData.createdAt || Date.now()));
        return parts.join(" · ");
    }

    function sessionIndexById(sessionId) {
        for (var i = 0; i < root.sessions.length; i++) {
            if (root.sessions[i].value === sessionId)
                return i;

        }
        return -1;
    }

    // Session overrides are deliberately stored on the session object rather
    // than in global plasmoid configuration.  This makes provider/model
    // changes apply to the current chat immediately without affecting other
    // chats.
    function getSessionProperty(sessionId, key, defaultValue) {
        var idx = sessionIndexById(sessionId || root.currentSessionId);
        if (idx < 0 || !root.sessions[idx] || root.sessions[idx][key] === undefined || root.sessions[idx][key] === null)
            return defaultValue;
        return root.sessions[idx][key];
    }

    function setSessionProperty(sessionId, key, value) {
        var idx = sessionIndexById(sessionId || root.currentSessionId);
        if (idx < 0)
            return;
        var updated = root.sessions.slice();
        var session = Object.assign({}, updated[idx]);
        session[key] = value;
        updated[idx] = session;
        root.sessions = updated;
        if (session.value === root.currentSessionId) {
            // Keep the live mode in sync with a setting saved in the dialog.
            if (key === "source") {
                root.openCodeMode = value === "opencode";
                root.piMode = value === "pi";
            }
        }
        persistSessions();
    }

    // Apply a dialog's complete draft in one model update.  Per-chat settings
    // are shown in the history sidebar, so assigning root.sessions once is
    // important: a dozen individual writes otherwise rebuild that ListView
    // a dozen times and can make plasmashell appear hung.
    function setSessionOverrides(sessionId, overrides) {
        var idx = sessionIndexById(sessionId || root.currentSessionId);
        if (idx < 0 || !overrides)
            return false;

        var updated = root.sessions.slice();
        var session = Object.assign({}, updated[idx]);
        var previousSource = session.source || "provider";
        var changed = false;
        for (var key in overrides) {
            if (!Object.prototype.hasOwnProperty.call(overrides, key))
                continue;
            if (session[key] !== overrides[key])
                changed = true;
            session[key] = overrides[key];
        }
        if (!changed)
            return true;
        if (session.source !== "opencode" && previousSource === "opencode")
            session.openCodeSessionId = "";
        if (session.value === root.currentSessionId) {
            session.messages = root.messages.slice();
            session.text = root.currentSessionTitle || session.text;
        }

        updated[idx] = session;
        root.sessions = updated;
        if (session.value === root.currentSessionId) {
            root.openCodeMode = session.source === "opencode";
            root.piMode = session.source === "pi";
            root.openCodeAgent = session.openCodeAgent || "";
            root.openCodeWorkspaceCwd = session.openCodeWorkspaceCwd || "";
        }
        persistSessions();
        return true;
    }

    function getEffectiveProvider(sessionId) {
        var override = String(getSessionProperty(sessionId, "chatProvider", "") || "").trim();
        return override || plasmoid.configuration.provider || ProviderService.getSupportedProviders(plasmoid.configuration)[0] || "openai";
    }

    function configuredSessionSource() {
        if (plasmoid.configuration.useOpenCode === true)
            return "opencode";
        if (plasmoid.configuration.usePi === true)
            return "pi";
        return "provider";
    }

    function applySessionSource(session) {
        var source = session && session.source ? String(session.source) : configuredSessionSource();
        if (source !== "opencode" && source !== "pi")
            source = "provider";
        root.openCodeMode = source === "opencode";
        root.piMode = source === "pi";
        root.openCodeAgent = session && session.openCodeAgent !== undefined
            ? String(session.openCodeAgent || "") : String(plasmoid.configuration.openCodeAgent || "");
        root.openCodeWorkspaceCwd = session && session.openCodeWorkspaceCwd !== undefined
            ? String(session.openCodeWorkspaceCwd || "") : String(plasmoid.configuration.openCodeWorkspaceCwd || "");
        return source;
    }

    function requestIsCurrent(sessionId, generation) {
        return !!sessionId && root.currentSessionId === sessionId
            && root.activeRequestSessionId === sessionId
            && root.requestGeneration === generation;
    }

    function invalidateActiveRequest(processQueue) {
        root.requestGeneration++;
        root.activeRequestSessionId = "";
        if (root.activeXhr) {
            try { root.activeXhr.abort(); } catch (e) {}
            root.activeXhr = null;
        }
        root.resetProviderStreamingState();
        root.loading = false;
        if (processQueue)
            processNextQueuedMessage();
    }

    function beginRequest(sessionId) {
        root.requestGeneration++;
        root.activeRequestSessionId = sessionId;
        return root.requestGeneration;
    }

    function createSession(switchToNew) {
        if (switchToNew && root.loading)
            invalidateActiveRequest(false);
        var s = {
            "value": makeSessionId(),
            "text": "New Chat",
            "createdAt": Date.now(),
            "updatedAt": Date.now(),
            "archived": false,
            "source": configuredSessionSource(),
            "openCodeSessionId": "",
            "messages": []
        };
        root.sessions = [s].concat(root.sessions);
        if (switchToNew) {
            root.currentSessionId = s.value;
            root.currentSessionTitle = s.text;
            root.messages = [];
            applySessionSource(s);
        root.playingMessageIndex = -1;
        if (voiceManager && voiceManager.isPlaying) { voiceManager.stopTTS(); }
            root.currentStreamIndex = -1;
            root.currentStreamText = "";
            root.streamBuffer.clear();
            root.currentStreamReasoning = "";
            root.currentStreamExtractedReasoning = "";
            root.streamingResponse = false;
            root.editingMessageIndex = -1;
            root.editingDraft = "";
            root.editingSessionId = "";
            root.editingSessionDraft = "";
            root.renamingCurrentChat = false;
            root.currentChatRenameDraft = "";
            root.historyOnlyMode = false;
            root.focusInput();
        }
        persistSessions();
    }

    function resetUnreadableSessionHistory() {
        root.sessionHistoryLoadError = "";
        root.sessionHistoryLoadBlocked = false;
        root.sessions = [];
        createSession(true);
    }

    function loadSessions() {
        root.sessions = parseSessions(chatStore.loadAll());
        if (root.sessions.length === 0)
            createSession(true);

        var preferred = plasmoid.configuration.lastSessionId || "";
        var idx = sessionIndexById(preferred);
        if (idx < 0)
            idx = 0;

        root.currentSessionId = root.sessions[idx].value;
        root.currentSessionTitle = root.sessions[idx].text;
        root.messages = root.sessions[idx].messages || [];
        applySessionSource(root.sessions[idx]);
        sortSessionsByUpdated();
    }

    function saveCurrentSessionState(touchUpdatedAt) {
        var idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var s = Object.assign({
        }, updated[idx]);
        s.text = root.currentSessionTitle || "New Chat";
        s.messages = root.messages;
        if (touchUpdatedAt !== false)
            s.updatedAt = Date.now();

        updated[idx] = s;
        root.sessions = updated;
        if (touchUpdatedAt !== false)
            sortSessionsByUpdated();

        persistSessions();
    }

    function setCurrentSessionSource(source) {
        var idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var item = Object.assign({
        }, updated[idx]);
        item.source = source || "provider";
        item.archived = false;
        updated[idx] = item;
        root.sessions = updated;
        persistSessions();
    }

    function setSessionArchived(sessionId, archived) {
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var item = Object.assign({
        }, updated[idx]);
        item.archived = !!archived;
        item.updatedAt = Date.now();
        updated[idx] = item;
        root.sessions = updated;
        sortSessionsByUpdated();
        persistSessions();
    }

    function switchSession(sessionId) {
        if (!sessionId || sessionId === root.currentSessionId)
            return ;

        // A response must never be allowed to write into the newly selected
        // session. Invalidate callbacks before changing the active model.
        invalidateActiveRequest(false);
        saveCurrentSessionState(false);
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        root.currentSessionId = root.sessions[idx].value;
        root.currentSessionTitle = root.sessions[idx].text;
        root.messages = root.sessions[idx].messages || [];
        applySessionSource(root.sessions[idx]);
        root.playingMessageIndex = -1;
        if (voiceManager && voiceManager.isPlaying) { voiceManager.stopTTS(); }
        root.currentStreamIndex = -1;
        root.currentStreamText = "";
        root.streamBuffer.clear();
        root.currentStreamReasoning = "";
        root.currentStreamExtractedReasoning = "";
        root.streamingResponse = false;
        root.editingMessageIndex = -1;
        root.editingDraft = "";
        root.editingSessionId = "";
        root.editingSessionDraft = "";
        root.renamingCurrentChat = false;
        root.currentChatRenameDraft = "";
        persistSessions();
        scrollToBottom(true);
        root.focusInput();
        if (!root.loading)
            Qt.callLater(root.processNextQueuedMessage);
    }

    function renameCurrentSession(newTitle) {
        var title = (newTitle || "").trim();
        if (title === "")
            title = "New Chat";

        root.currentSessionTitle = title;
        saveCurrentSessionState(true);
    }

    function startSessionRename(sessionId) {
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        root.editingSessionId = sessionId;
        root.editingSessionDraft = root.sessions[idx].text || "";
    }

    function cancelSessionRename() {
        root.editingSessionId = "";
        root.editingSessionDraft = "";
    }

    function saveSessionRename(sessionId) {
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        var title = (root.editingSessionDraft || "").trim();
        if (title === "")
            title = "New Chat";

        var updated = root.sessions.slice();
        var s = Object.assign({
        }, updated[idx]);
        s.text = title;
        s.updatedAt = Date.now();
        updated[idx] = s;
        root.sessions = updated;
        if (root.currentSessionId === sessionId)
            root.currentSessionTitle = title;

        sortSessionsByUpdated();
        persistSessions();
        cancelSessionRename();
    }

    function deleteSession(sessionId) {
        if (root.sessions.length <= 1)
            return ;

        if (sessionId === root.currentSessionId)
            invalidateActiveRequest(false);
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var removed = updated.splice(idx, 1)[0];
        root.sessions = updated;
        root.sessionDeleted(removed, idx);
        var helper = getHelperPath();
        if (helper) {
            var deletePayload = Sec.base64Encode(JSON.stringify({"sessionId": sessionId}));
            fileReaderDs.connectSource("python3 " + Sec.quoteForShell(helper) + " delete_session_schedules " + Sec.rawShellSnippetQuote(deletePayload) + " #delete-session-schedules-" + Date.now());
        }
        if (root.currentSessionId === sessionId) {
            var next = root.sessions[0];
            root.currentSessionId = next.value;
            root.currentSessionTitle = next.text;
            root.messages = next.messages || [];
            applySessionSource(next);
        }
        cancelSessionRename();
        persistSessions();
    }

    function deleteMessage(index) {
        var copy = root.messages.slice();
        if (index < 0 || index >= copy.length)
            return ;

        copy.splice(index, 1);
        root.messages = copy;
        root.editingMessageIndex = -1;
        root.editingDraft = "";
        clearCurrentOpenCodeSessionIfNeeded();
        saveCurrentSessionState(true);
    }

    function saveEditedMessage() {
        var i = root.editingMessageIndex;
        if (i < 0 || i >= root.messages.length)
            return ;

        if ((root.messages[i].role || "") === "error") {
            root.editingMessageIndex = -1;
            root.editingDraft = "";
            return ;
        }
        // Cancel any active streaming/loading requests first
        stopStreaming();
        var role = root.messages[i].role || "";
        var isQueued = role === "queued";
        var copy = isQueued ? root.messages.slice() : root.messages.slice(0, i + 1);
        var item = Object.assign({
        }, copy[i]);
        item.content = root.editingDraft;
        item.at = Date.now();
        item.time = nowTime(item.at);
        copy[i] = item;
        root.messages = copy;
        root.editingMessageIndex = -1;
        root.editingDraft = "";
        clearCurrentOpenCodeSessionIfNeeded();
        saveCurrentSessionState(true);
        // Re-run from edited user prompt so assistant response reflects the new text.
        if (role === "user") {
            root.userScrolledUp = false;
            sendMessageByIndex(i);
        }
    }

    function openCodeBaseUrl() {
        var raw = String(plasmoid.configuration.openCodeUrl || "http://127.0.0.1:4096/v1").trim();
        var valid = Sec.validateHttpUrl(raw);
        if (!valid) return "";
        return valid.replace(/\/v1\/?$/, "").replace(/\/$/, "");
    }

    function currentOpenCodeSessionId(sessionId) {
        var idx = sessionIndexById(sessionId || root.currentSessionId);
        if (idx < 0)
            return "";

        return Sec.validateRemoteSessionId(root.sessions[idx].openCodeSessionId || "");
    }

    function setCurrentOpenCodeSessionId(remoteSessionId, sessionId) {
        var idx = sessionIndexById(sessionId || root.currentSessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var item = Object.assign({
        }, updated[idx]);
        item.openCodeSessionId = Sec.validateRemoteSessionId(remoteSessionId || "");
        updated[idx] = item;
        root.sessions = updated;
        persistSessions();
    }

    function clearCurrentOpenCodeSessionIfNeeded() {
        if (!root.openCodeMode)
            return ;

        setCurrentOpenCodeSessionId("");
    }

    function syncOpenCodeSessionHistory() {
        var sessionId = root.currentSessionId;
        var generation = beginRequest(sessionId);
        var remoteSessionId = currentOpenCodeSessionId(sessionId);
        if (!remoteSessionId) {
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            return;
        }
        root.loading = true;
        var xhr = new XMLHttpRequest();
        root.activeXhr = xhr;
        try { xhr.open("GET", openCodeBaseUrl() + "/session/" + encodeURIComponent(remoteSessionId) + "/message", true); } catch (e) {
            root.loading = false;
            root.activeXhr = null;
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            pushErrorMessage("Sync failed: invalid OpenCode endpoint.");
            return;
        }
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (!requestIsCurrent(sessionId, generation))
                return;
            root.loading = false;
            root.activeXhr = null;
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    if (xhr.responseText.length > 10000000)
                        throw new Error("OpenCode history response is too large");
                    var arr = JSON.parse(xhr.responseText);
                    if (Array.isArray(arr)) {
                        var newMsgs = [];
                        for (var i = 0; i < Math.min(arr.length, 500); i++) {
                            var item = arr[i] || {};
                            var info = item.info || {};
                            var parts = item.parts || [];
                            var role = info.role || "user";
                            var modelLabel = (info.providerID && info.modelID) ? (info.providerID + "/" + info.modelID) : (info.modelID || "OpenCode");
                            var combinedText = "";
                            var ctx = [];
                            for (var p = 0; p < parts.length; p++) {
                                var part = parts[p] || {};
                                if (part.type === "text") {
                                    combinedText += part.text || part.content || "";
                                } else if (part.type === "tool-invocation") {
                                    var toolName = part.toolName || part.tool || "";
                                    var toolArgs = part.args || part.input || {};
                                    if (toolName !== "") {
                                        var desc = toolName;
                                        if (toolArgs.filePath || toolArgs.path || toolArgs.file)
                                            desc += ": " + (toolArgs.filePath || toolArgs.path || toolArgs.file);
                                        else if (toolArgs.command)
                                            desc += ": " + String(toolArgs.command).substring(0, 60);
                                        ctx.push(desc);
                                    }
                                }
                            }
                            if (combinedText.length > root.maxMessageChars)
                                combinedText = combinedText.substring(0, root.maxMessageChars) + "\n[history message truncated]";
                            var normalizedTokens = {};
                            if (item.tokens) {
                                var rawTokens = item.tokens || {};
                                normalizedTokens.input = rawTokens.input !== undefined ? rawTokens.input : (rawTokens.prompt_tokens !== undefined ? rawTokens.prompt_tokens : (rawTokens.input_tokens !== undefined ? rawTokens.input_tokens : undefined));
                                normalizedTokens.output = rawTokens.output !== undefined ? rawTokens.output : (rawTokens.completion_tokens !== undefined ? rawTokens.completion_tokens : (rawTokens.output_tokens !== undefined ? rawTokens.output_tokens : undefined));
                                if (rawTokens.reasoning !== undefined) normalizedTokens.reasoning = rawTokens.reasoning;
                                if (rawTokens.cache !== undefined) normalizedTokens.cache = rawTokens.cache;
                            }
                            var ts = info.createdAt ? new Date(info.createdAt).getTime() : Date.now();
                            newMsgs.push({
                                "role": role,
                                "content": combinedText || "(empty)",
                                "model": role === "user" ? "You" : modelLabel,
                                "id": info.id || ("msg-" + i),
                                "at": ts,
                                "time": nowTime(ts),
                                "contextItems": ctx,
                                "tokens": normalizedTokens.input !== undefined ? normalizedTokens : undefined,
                                "cost": item.cost || undefined,
                                "openCodeSessionId": remoteSessionId
                            });
                        }
                        if (newMsgs.length > 0) {
                            var idx = sessionIndexById(root.currentSessionId);
                            if (idx >= 0) {
                                root.messages = newMsgs;
                                var updated = root.sessions.slice();
                                var sItem = Object.assign({}, updated[idx]);
                                sItem.messages = newMsgs;
                                updated[idx] = sItem;
                                root.sessions = updated;
                                saveCurrentSessionState(true);
                                scrollToBottom();
                            }
                        }
                    }
                } catch (err) {
                    pushErrorMessage("Failed to parse synced messages: " + err);
                }
            } else {
                pushErrorMessage("Sync failed: OpenCode returned HTTP " + xhr.status);
            }
        };
        xhr.onerror = function() {
            if (!requestIsCurrent(sessionId, generation)) return;
            root.loading = false;
            root.activeXhr = null;
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            pushErrorMessage("Sync failed: Could not reach OpenCode server at " + openCodeBaseUrl());
        };
        try { xhr.send(); } catch (e) {
            if (requestIsCurrent(sessionId, generation)) {
                root.loading = false;
                root.activeXhr = null;
                root.activeRequestSessionId = "";
                root.requestGeneration++;
                pushErrorMessage("Sync failed: " + e);
            }
        }
    }

    function _notifyOpenCodeAgentFetchWaiters() {
        var waiters = root.openCodeAgentFetchWaiters || [];
        root.openCodeAgentFetchWaiters = [];
        for (var i = 0; i < waiters.length; i++) {
            if (waiters[i])
                Qt.callLater(waiters[i]);
        }
    }

    function normalizeOpenCodeAgents(payload) {
        var values = [];
        function isSubagent(name, metadata) {
            var mode = metadata && (metadata.mode || metadata.agentMode || metadata.type || metadata.kind);
            if (mode && /sub[-_ ]?agent|internal/i.test(String(mode)))
                return true;
            if (metadata && (metadata.hidden === true || metadata.internal === true || metadata.isSubagent === true))
                return true;
            // OpenCode exposes these implementation agents through /agent as
            // well. They are not selectable top-level agent profiles.
            return ["compaction", "explore", "general", "summary", "title"].indexOf(String(name).toLowerCase()) >= 0;
        }
        function add(value, keyName) {
            var name = typeof value === "string" ? value : (value && (value.id || value.name || value.value || value.text));
            name = name || keyName || "";
            if (isSubagent(name, value))
                return;
            if (name && typeof name === "string" && name.length <= 128 && values.indexOf(name) < 0 && values.length < 100)
                values.push(name);
        }
        function read(value) {
            if (!value)
                return;
            if (Array.isArray(value)) {
                for (var i = 0; i < value.length; i++) add(value[i]);
                return;
            }
            if (typeof value !== "object") {
                add(value);
                return;
            }
            var known = ["agents", "agent", "data", "items", "all", "connected"];
            var found = false;
            for (var k = 0; k < known.length; k++) {
                if (value[known[k]] !== undefined) {
                    read(value[known[k]]);
                    found = true;
                }
            }
            if (!found) {
                var keys = Object.keys(value);
                for (var j = 0; j < keys.length; j++) {
                    if (keys[j] !== "default" && keys[j] !== "default_agent")
                        add(value[keys[j]], keys[j]);
                }
            }
        }
        read(payload);
        var result = [];
        for (var n = 0; n < values.length; n++)
            result.push({ "text": values[n], "value": values[n] });
        return result;
    }

    function _finishOpenCodeAgents(list, defaultAgent) {
        root.openCodeAgentsList = list || [];
        var selectedAgent = "";
        for (var i = 0; i < root.openCodeAgentsList.length; i++) {
            if (root.openCodeAgentsList[i].value === defaultAgent || root.openCodeAgentsList[i].value === root.openCodeAgent) {
                selectedAgent = root.openCodeAgentsList[i].value;
                break;
            }
        }
        if (!selectedAgent && root.openCodeAgentsList.length > 0)
            selectedAgent = root.openCodeAgentsList[0].value;
        if (selectedAgent)
            root.openCodeAgent = selectedAgent;
        root.fetchingAgentsInProgress = false;
        _notifyOpenCodeAgentFetchWaiters();
    }

    function fetchOpenCodeAgents(callback) {
        if (root.fetchingAgentsInProgress) {
            if (callback)
                root.openCodeAgentFetchWaiters = (root.openCodeAgentFetchWaiters || []).concat([callback]);
            return null;
        }
        root.fetchingAgentsInProgress = true;
        root.openCodeAgentFetchWaiters = callback ? [callback] : [];

        var baseUrl = openCodeBaseUrl();
        if (!baseUrl) {
            _finishOpenCodeAgents([], "");
            return null;
        }
        var agentEndpoint = baseUrl + "/agent";

        var xhr = new XMLHttpRequest();
        xhr.open("GET", agentEndpoint, true);
        xhr.timeout = 1000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    if (xhr.responseText.length > 2000000)
                        throw new Error("agent response is too large");
                    var data = JSON.parse(xhr.responseText);
                    var agentList = normalizeOpenCodeAgents(data);
                    if (agentList.length > 0) {
                        _finishOpenCodeAgents(agentList, data.default_agent || data.default || "");
                        return;
                    }
                } catch (e) {}
            }
            runFallbackAgentFileFetch();
        };
        xhr.ontimeout = function() {
            runFallbackAgentFileFetch();
        };
        xhr.onerror = function() {
            runFallbackAgentFileFetch();
        };
        try {
            xhr.send();
        } catch (err) {
            runFallbackAgentFileFetch();
        }
    }

    function fetchOpenCodeProvidersAndModels(callback) {
        // Treat every refresh as a snapshot. Keeping the previous arrays when
        // the server returns an empty/error response made the sidebar claim a
        // refresh while visibly showing stale provider/model choices.
        root.openCodeProvidersList = [];
        root.openCodeModelsList = [];
        var baseUrl = openCodeBaseUrl();
        if (!baseUrl) {
            root.openCodeProvidersList = [];
            root.openCodeModelsList = [];
            root.fetchingOpenCodeConfig = false;
            if (callback) callback();
            return;
        }
        var endpoints = [baseUrl + "/config/providers", baseUrl + "/provider"];
        var endpointIndex = 0;
        function requestNext() {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", endpoints[endpointIndex], true);
            xhr.timeout = 2000;
            var requestFinished = false;
            var finish = function(success) {
                if (requestFinished) return;
                requestFinished = true;
                if (success || endpointIndex >= endpoints.length - 1) {
                    if (callback) callback();
                    return;
                }
                endpointIndex++;
                requestNext();
            };
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status >= 200 && xhr.status < 300) {
                    try {
                        if (xhr.responseText.length > 2000000)
                            throw new Error("provider response is too large");
                        var data = JSON.parse(xhr.responseText);
                        var allProvs = data.providers || data.all || data.connected || [];
                        var provList = [];
                        var modelList = [];
                        for (var i = 0; i < allProvs.length; i++) {
                            var p = allProvs[i];
                            var providerId = p && (p.id || p.name);
                            if (providerId) {
                                provList.push({ "id": providerId, "name": p.name || providerId });
                                if (p.models && typeof p.models === "object") {
                                    var mKeys = Object.keys(p.models);
                                    for (var j = 0; j < mKeys.length; j++)
                                        modelList.push(providerId + "/" + mKeys[j]);
                                }
                            }
                        }
                        root.openCodeProvidersList = provList;
                        root.openCodeModelsList = modelList;
                        finish(provList.length > 0);
                        return;
                    } catch (e) {}
                }
                finish(false);
            };
            xhr.ontimeout = function() { finish(false); };
            xhr.onerror = function() { finish(false); };
            try { xhr.send(); } catch (e) { finish(false); }
        }
        requestNext();
    }

    function runFallbackAgentFileFetch() {
        var cmd = "python3 -c \""
            + "import json, os, glob; "
            + "paths = [os.path.expanduser('~/.config/opencode/opencode.json'), './opencode.json']; "
            + "agents = []; default = ''; "
            + "for p in paths:\n"
            + "    if os.path.exists(p):\n"
            + "        try:\n"
            + "            d = json.load(open(p))\n"
            + "            ag = d.get('agent', {})\n"
            + "            if isinstance(ag, dict):\n"
            + "                for n, spec in ag.items():\n"
            + "                    item = dict(spec) if isinstance(spec, dict) else {}\n"
            + "                    item['name'] = n; item['id'] = n; agents.append(item)\n"
            + "            if d.get('default_agent'): default = d.get('default_agent')\n"
            + "        except Exception: pass\n"
            + "unique = {}; "
            + "for item in agents:\n"
            + "    key = item.get('id') or item.get('name') if isinstance(item, dict) else item\n"
            + "    if key and key not in unique: unique[key] = item\n"
            + "agents = list(unique.values()); "
            + "print(json.dumps({'agents': agents, 'default': default}))"
            + "\" #fetch-opencode-agents";
        fileReaderDs.connectSource(cmd);
    }

    function resetProviderStreamingState() {
        streamBuffer.flush();
        if (root.currentStreamIndex >= 0 && root.currentStreamIndex < root.messages.length) {
            var copy = root.messages.slice();
            var current = copy[root.currentStreamIndex] = Object.assign({}, copy[root.currentStreamIndex]);
            if (current && current.role === "assistant") {
                if (root.currentStreamText)
                    current.content = root.currentStreamText;
                if (root.currentStreamReasoning)
                    current.reasoning = root.currentStreamReasoning;
                if (!current.content && !current.reasoning)
                    copy.splice(root.currentStreamIndex, 1);
                root.messages = copy;
            }
        }
        root.currentStreamIndex = -1;
        root.currentStreamText = "";
        root.currentStreamReasoning = "";
        root.currentStreamExtractedReasoning = "";
        root.streamingResponse = false;
    }

    // The one scroll rule: the chat view follows new content while
    // userScrolledUp is false (see FullRepresentationContent's msgList).
    // force: jump to the latest message even if the user scrolled up.
    function scrollToBottom(force) {
        if (root.userScrolledUp && !force)
            return;
        root.userScrolledUp = false;
        if (root.msgListViewRef)
            root.msgListViewRef.positionViewAtEnd();
    }

    function messageTimestampAt(index) {
        if (index < 0 || index >= root.messages.length)
            return Date.now();

        var m = root.messages[index] || {
        };
        return m.at || Date.now();
    }

    function messageDayKeyAt(index) {
        var d = new Date(messageTimestampAt(index));
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }

    function dayBucketLabel(ts) {
        var target = new Date(ts);
        var now = new Date();
        var today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        var targetDay = new Date(target.getFullYear(), target.getMonth(), target.getDate());
        var daysDiff = Math.floor((today.getTime() - targetDay.getTime()) / 8.64e+07);
        if (daysDiff === 0)
            return "Today";

        if (daysDiff === 1)
            return "Yesterday";

        if (daysDiff === 2)
            return "Day before yesterday";

        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return months[target.getMonth()] + " " + pad2(target.getDate()) + ", " + target.getFullYear();
    }

    function countMessagesForDayKey(dayKey) {
        var count = 0;
        for (var i = 0; i < root.messages.length; i++) {
            if (messageDayKeyAt(i) === dayKey)
                count++;

        }
        return count;
    }

    function dayDividerLabelForIndex(index) {
        var key = messageDayKeyAt(index);
        return dayBucketLabel(messageTimestampAt(index)) + " (" + countMessagesForDayKey(key) + ")";
    }

    function formatMessageTime(message, index) {
        if (message && message.time)
            return message.time;

        return nowTime(messageTimestampAt(index));
    }

    function jumpOneMessageAbove() {
        if (!root.msgListViewRef || root.messages.length === 0)
            return ;

        var currentTop = -1;
        for (var offset = 15; offset <= 100; offset += 20) {
            currentTop = root.msgListViewRef.indexAt(30, root.msgListViewRef.contentY + offset);
            if (currentTop >= 0)
                break;

        }
        if (currentTop < 0)
            currentTop = root.messages.length;

        var target = -1;
        for (var i = currentTop - 1; i >= 0; i--) {
            var msg = root.messages[i];
            if (msg && msg.role === "user") {
                target = i;
                break;
            }
        }
        if (target >= 0) {
            root.userScrolledUp = true;
            root.msgListViewRef.positionViewAtIndex(target, ListView.Beginning);
        } else {
            root.userScrolledUp = true;
            root.msgListViewRef.positionViewAtBeginning();
        }
    }

    function jumpOneMessageBelow() {
        if (!root.msgListViewRef || root.messages.length === 0)
            return ;

        var currentTop = -1;
        for (var offset = 15; offset <= 100; offset += 20) {
            currentTop = root.msgListViewRef.indexAt(30, root.msgListViewRef.contentY + offset);
            if (currentTop >= 0)
                break;

        }
        if (currentTop < 0)
            currentTop = -1;

        var target = -1;
        for (var i = currentTop + 1; i < root.messages.length; i++) {
            var msg = root.messages[i];
            if (msg && msg.role === "user") {
                target = i;
                break;
            }
        }
        if (target >= 0) {
            var isLastUser = true;
            for (var j = target + 1; j < root.messages.length; j++) {
                if (root.messages[j] && root.messages[j].role === "user") {
                    isLastUser = false;
                    break;
                }
            }
            if (isLastUser) {
                if (root.userScrolledUp) {
                    root.userScrolledUp = false;
                    root.scrollToBottom();
                }
            } else {
                root.userScrolledUp = true;
                root.msgListViewRef.positionViewAtIndex(target, ListView.Beginning);
            }
        } else {
            if (root.userScrolledUp) {
                root.userScrolledUp = false;
                root.scrollToBottom();
            }
        }
    }

    function formatTokensUsage(tokens, cost) {
        if (!tokens)
            return "";

        var parts = [];
        if (tokens.input !== undefined)
            parts.push("Input: " + tokens.input);

        if (tokens.output !== undefined)
            parts.push("Output: " + tokens.output);

        if (tokens.reasoning !== undefined && tokens.reasoning > 0)
            parts.push("Reasoning: " + tokens.reasoning);

        if (tokens.cache && (tokens.cache.read > 0 || tokens.cache.write > 0))
            parts.push("Cache R/W: " + tokens.cache.read + "/" + tokens.cache.write);

        var res = parts.join(" | ");
        if (cost !== undefined && cost > 0)
            res += " | Cost: $" + cost.toFixed(5);

        return res;
    }

    function pushErrorMessage(text) {
        var ts = Date.now();
        root.messages = root.messages.concat([{
            "role": "error",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": ""
        }]);
        scrollToBottom();
        saveCurrentSessionState(true);
    }

    function retryFailedMessage(index) {
        if (index < 0 || index >= root.messages.length) return;
        var role = root.messages[index].role || "";
        if (role !== "error") return;
        
        var lastUserIdx = -1;
        for (var i = index - 1; i >= 0; i--) {
            var r = root.messages[i].role || "";
            if (r === "user" || r === "queued") {
                lastUserIdx = i;
                break;
            }
        }
        
        if (lastUserIdx >= 0) {
            stopStreaming();
            var copy = root.messages.slice(0, lastUserIdx + 1);
            root.messages = copy;
            clearCurrentOpenCodeSessionIfNeeded();
            saveCurrentSessionState(true);
            root.userScrolledUp = false;
            sendMessageByIndex(lastUserIdx);
        }
    }

    function regenerateResponse(index, promptModifier) {
        if (index <= 0 || index >= root.messages.length) return;
        var role = root.messages[index].role || "";
        if (role !== "assistant" && role !== "opencode_assistant") return;
        
        var lastUserIdx = index - 1;
        var userRole = root.messages[lastUserIdx].role || "";
        if (userRole !== "user" && userRole !== "queued") return;
        
        stopStreaming();
        var copy = root.messages.slice(0, lastUserIdx + 1);
        
        if (promptModifier) {
            var item = Object.assign({}, copy[lastUserIdx]);
            item.content = item.content + "\n\n" + promptModifier;
            item.at = Date.now();
            item.time = nowTime(item.at);
            copy[lastUserIdx] = item;
        }
        
        root.messages = copy;
        clearCurrentOpenCodeSessionIfNeeded();
        saveCurrentSessionState(true);
        root.userScrolledUp = false;
        sendMessageByIndex(lastUserIdx);
    }

    function appendUserMessage(text, role, attachments) {
        var ts = Date.now();
        root.messages = root.messages.concat([{
            "role": role || "user",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": role === "queued" ? (++root.queueCounter) : 0,
            "attachments": attachments || []
        }]);
        saveCurrentSessionState(true);

    }

    function validateCurrentSendTarget() {
        if (root.openCodeMode)
            return validateOpenCodeConfig(root.currentSessionId);
        if (root.piMode)
            return "";

        var provider = root.getEffectiveProvider ? root.getEffectiveProvider(root.currentSessionId) : (plasmoid.configuration.provider || "openai");
        var providerCfg = getProviderConfig(provider, root.currentSessionId);
        return validateProviderConfig(provider, providerCfg);
    }

    function sendMessageByIndex(index) {
        root.currentStreamIndex = -1;
        root.currentStreamText = "";
        root.streamBuffer.clear();
        root.currentStreamReasoning = "";
        root.currentStreamExtractedReasoning = "";
        root.streamingResponse = false;

        var source = root.messages[index] || {
        };
        var text = (source.content || "").trim();
        var hasAttachments = source.attachments && source.attachments.length > 0;
        if (!text && !hasAttachments)
            return ;

        var validationError = validateCurrentSendTarget();
        if (validationError !== "") {
            pushErrorMessage(validationError);
            return ;
        }
        if ((source.role || "") === "queued") {
            var copy = root.messages.slice();
            var queued = Object.assign({
            }, copy[index]);
            queued.role = "user";
            queued.at = Date.now();
            queued.time = nowTime(queued.at);
            copy[index] = queued;
            root.messages = copy;
            saveCurrentSessionState(true);
        }
        var requestSessionId = root.currentSessionId;
        var requestSource = root.openCodeMode ? "opencode" : (root.piMode ? "pi" : "provider");
        setCurrentSessionSource(requestSource);
        var requestGeneration = beginRequest(requestSessionId);
        if (root.openCodeMode) {
            openCode.send(requestSessionId, requestGeneration);
            return ;
        }
        if (root.piMode) {
            piAgent.send(requestSessionId, requestGeneration);
            return ;
        }
        var provider = root.getEffectiveProvider(requestSessionId);
        doDirectRequest(getProviderConfig(provider, requestSessionId), requestSessionId, requestGeneration);
    }

    function processNextQueuedMessage() {
        if (root.loading)
            return ;

        for (var i = 0; i < root.messages.length; i++) {
            if ((root.messages[i].role || "") === "queued") {
                sendMessageByIndex(i);
                return ;
            }
        }
        // A scheduled trigger belongs to its target chat even when that chat
        // is not currently visible. Rotate through scheduled queues only when
        // the active request is idle; ordinary user queues stay attached to
        // their original chat and are never cancelled by this scan.
        for (var s = 0; s < root.sessions.length; s++) {
            var session = root.sessions[s] || {};
            if (session.value === root.currentSessionId) continue;
            var messages = Array.isArray(session.messages) ? session.messages : [];
            for (var m = 0; m < messages.length; m++) {
                if (messages[m] && messages[m].role === "queued" && messages[m].scheduled) {
                    if (!root.schedulerResumeSessionId)
                        root.schedulerResumeSessionId = root.currentSessionId;
                    root.switchSession(session.value);
                    return ;
                }
            }
        }
        if (root.schedulerResumeSessionId && root.schedulerResumeSessionId !== root.currentSessionId) {
            var resumeId = root.schedulerResumeSessionId;
            root.schedulerResumeSessionId = "";
            if (root.sessionIndexById(resumeId) >= 0) {
                root.switchSession(resumeId);
                return ;
            }
        }
        root.schedulerResumeSessionId = "";
    }

    function _cleanGeneratedTitle(value) {
        var title = String(value || "").replace(/```[\s\S]*?```/g, "").trim();
        title = title.replace(/^['"`]+|['"`]+$/g, "").replace(/\s+/g, " ").trim();
        if (title.length > 80)
            title = title.substring(0, 77).replace(/\s+\S*$/, "") + "…";
        return title;
    }

    function maybeGenerateChatTitle() {
        if (plasmoid.configuration.autoNameChats === false || root.openCodeMode
                || root.titleGenerationInProgress || !root.currentSessionId)
            return;
        var currentTitle = (root.currentSessionTitle || "").trim().toLowerCase();
        if (currentTitle !== "" && currentTitle !== "new chat")
            return;

        var firstUser = "";
        var assistantCount = 0;
        for (var i = 0; i < root.messages.length; i++) {
            if (!firstUser && root.messages[i].role === "user")
                firstUser = String(root.messages[i].content || "").trim();
            if (root.messages[i].role === "assistant")
                assistantCount++;
        }
        if (!firstUser || assistantCount === 0)
            return;

        var sessionId = root.currentSessionId;
        var cfg = getProviderConfig(root.getEffectiveProvider(sessionId), sessionId);
        if (!cfg || !cfg.model || !cfg.baseUrl || (!cfg.allowEmptyKey && !cfg.apiKey))
            return;
        root.titleGenerationInProgress = true;
        root.titleGenerationSessionId = sessionId;

        var xhr = new XMLHttpRequest();
        var endpoint = String(cfg.baseUrl).replace(/\/$/, "");
        var isAnthropic = cfg.type === "anthropic";
        if (isAnthropic) {
            if (!endpoint.endsWith("/messages")) endpoint += "/messages";
        } else {
            endpoint += "/chat/completions";
        }
        var finished = false;
        function finish() {
            if (finished) return;
            finished = true;
            root.titleGenerationInProgress = false;
            root.titleGenerationSessionId = "";
        }
        xhr.timeout = 8000;
        xhr.ontimeout = finish;
        xhr.onerror = finish;
        try {
            xhr.open("POST", endpoint, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            if (isAnthropic) {
                xhr.setRequestHeader("x-api-key", cfg.apiKey);
                xhr.setRequestHeader("anthropic-version", "2023-06-01");
            } else if (cfg.apiKey) {
                xhr.setRequestHeader("Authorization", "Bearer " + cfg.apiKey);
            }
            if (cfg.headers) {
                for (var headerName in cfg.headers)
                    if (Object.prototype.hasOwnProperty.call(cfg.headers, headerName) && cfg.headers[headerName])
                        xhr.setRequestHeader(headerName, cfg.headers[headerName]);
            }
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status >= 200 && xhr.status < 300 && root.currentSessionId === sessionId) {
                    try {
                        if (xhr.responseText.length > 1000000)
                            throw new Error("title response is too large");
                        var response = JSON.parse(xhr.responseText);
                        var raw = isAnthropic
                            ? ((response.content && response.content[0] && response.content[0].text) || "")
                            : (((response.choices || [])[0] || {}).message || {}).content || "";
                        var title = _cleanGeneratedTitle(raw);
                        if (title && (root.currentSessionTitle || "New Chat").trim().toLowerCase() === "new chat") {
                            root.currentSessionTitle = title;
                            saveCurrentSessionState(false);
                        }
                    } catch (e) {}
                }
                finish();
            };
            var prompt = "Create a concise 3-6 word title for this conversation. Return only the title, no quotes or punctuation.\n\nUser message:\n" + firstUser.substring(0, 1200);
            var body = isAnthropic ? {
                model: cfg.model,
                max_tokens: 32,
                messages: [{ role: "user", content: prompt }]
            } : {
                model: cfg.model,
                stream: false,
                messages: [
                    { role: "system", content: "You name chats concisely." },
                    { role: "user", content: prompt }
                ]
            };
            xhr.send(JSON.stringify(body));
        } catch (e) {
            finish();
        }
    }

    // The plasmashell watchdog was removed in 1.4.0. A monitor started by an
    // older version keeps running across upgrades and would restart
    // plasmashell once heartbeats stop, so stop it once at startup if its
    // files are still there.
    function stopLegacyWatchdog() {
        var helper = getHelperPath();
        if (!helper)
            return;
        var dataDir = String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)).replace(/^file:\/\//, "");
        var pidFile = decodeURIComponent(dataDir) + "/kdeaichat/plasmashell-watchdog.pid";
        var heartbeat = decodeURIComponent(dataDir) + "/kdeaichat/plasmashell-heartbeat";
        var cmd = "if [ -e " + Sec.quoteForShell(pidFile) + " ] || [ -e " + Sec.quoteForShell(heartbeat) + " ]; then python3 "
            + Sec.quoteForShell(helper) + " stop_legacy_watchdog; fi";
        fileReaderDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #plasmashell-watchdog-" + Date.now());
    }

    function providerDisplayName(providerId) {
        return ProviderService.getProviderDisplayName(providerId, plasmoid.configuration);
    }

    function validateOpenCodeConfig(sessionId) {
        var missing = [];
        if (!openCodeBaseUrl())
            missing.push("a valid OpenCode HTTP(S) URL");
        var provider = String(getSessionProperty(sessionId, "openCodeProvider", plasmoid.configuration.openCodeProvider || "") || "").trim();
        var model = String(getSessionProperty(sessionId, "openCodeModel", plasmoid.configuration.openCodeModel || "") || "").trim();
        var agent = String(getSessionProperty(sessionId, "openCodeAgent", root.openCodeAgent || "") || "").trim();
        if (!provider && !agent)
            missing.push("OpenCode provider or agent");
        if (!model && !agent)
            missing.push("OpenCode model or agent");
        if (missing.length > 0)
            return "Cannot send yet. Configure: " + missing.join(", ") + ".";
        return "";
    }

    function validateProviderConfig(providerId, cfg) {
        if (!cfg)
            return "Provider configuration missing.";

        var name = providerDisplayName(providerId);
        if (cfg.found === false)
            return "The provider \"" + name + "\" isn't set up any more. Add it in Widget Settings → General → Providers, or pick another provider in this chat's settings.";
        var missing = [];
        if (!providerId)
            missing.push("provider");

        if (!cfg.baseUrl && cfg.type !== "anthropic")
            missing.push("base URL");

        if (!cfg.model)
            missing.push("model");

        if (cfg.type === "anthropic" && !cfg.apiKey)
            missing.push("API key");

        if (cfg.type !== "anthropic" && !cfg.allowEmptyKey && !cfg.apiKey)
            missing.push("API key");

        if (missing.length > 0)
            return "Cannot send message with " + name + ". Missing: " + missing.join(", ") + ". Please open Widget Settings (Configure KDE AI Chat) to set your API key or model."
                + (missing.indexOf("API key") !== -1 && !wallet.usable && wallet.status !== "unknown" ? " " + wallet.statusMessage() : "");

        return "";
    }

    function sendMessage() {
        ensureWalletLoaded();
        try {
            var text = (root.chatInputText || "").trim();
            var attachments = root.attachedFiles || [];

            text = PromptTemplates.expand(text, root.promptTemplates);

            if (text.length > 200000) {
                pushErrorMessage("Message is too large. Keep messages under 200,000 characters.");
                return;
            }
            if (text === "" && attachments.length === 0)
                return ;
            if (!attachmentsReadyToSend()) {
                pushErrorMessage("Please wait for attached files to finish loading before sending.");
                return;
            }

            for (var cleanupIndex = 0; cleanupIndex < attachments.length; cleanupIndex++)
                cleanupTemporaryAttachment(attachments[cleanupIndex].path || "");
            root.attachedFiles = [];
            root.chatInputText = "";
            root.clearChatInput();
            if (root.loading) {
                appendUserMessage(text, "queued", attachments);
                return ;
            }
            appendUserMessage(text, "user", attachments);
            sendMessageByIndex(root.messages.length - 1);
        } catch (err) {
            root.loading = false;
            root.activeXhr = null;
            pushErrorMessage("Send failed: " + err);
            processNextQueuedMessage();
        }
    }

    function getProviderConfig(provider, sessionId) {
        var providerId = provider || getEffectiveProvider(sessionId || root.currentSessionId);
        var cfg = ProviderService.getProviderConfig(providerId, plasmoid.configuration);
        cfg.baseUrl = Sec.validateHttpUrl(cfg.baseUrl);
        // Keys come from KWallet. A plaintext value left by an older version is
        // only used while KWallet is unavailable, until it can be migrated.
        var walletKey = String(root.walletApiKeys[providerId] || "").trim();
        cfg.apiKey = walletKey || (wallet.usable ? "" : String(cfg.apiKey || "").trim());
        var sessionModel = String(getSessionProperty(sessionId || root.currentSessionId, "chatModel", "") || "").trim();
        if (sessionModel)
            cfg.model = sessionModel;
        return cfg;
    }

    function buildEffectiveSystemPrompt(sessionId) {
        var enabled = getSessionProperty(sessionId, "chatSystemPromptEnabled", true) !== false;
        if (!enabled)
            return "";
        var parts = [];
        if (plasmoid.configuration.enableSystemPrompt !== false && compiledSystemPrompt)
            parts.push(compiledSystemPrompt);
        var chatPrompt = String(getSessionProperty(sessionId, "chatSystemPrompt", "") || "").trim();
        if (chatPrompt)
            parts.push("--- Chat-specific instructions ---\n" + chatPrompt + "\n--- End chat-specific instructions ---");
        var responseLength = Number(getSessionProperty(sessionId, "responseLength", 0)) || 0;
        var instructions = ["", "Keep the response short and focused, around 256 output tokens unless the task requires more.", "Give a balanced response, around 1024 output tokens at most.", "Give a detailed response, around 4096 output tokens at most.", "Give a comprehensive response, up to roughly 8192 output tokens when useful."];
        if (responseLength > 0 && responseLength < instructions.length)
            parts.push("Response length preference: " + instructions[responseLength]);
        return parts.join("\n\n");
    }

    function responseMaxTokens(sessionId, defaultValue) {
        var selected = Number(getSessionProperty(sessionId, "responseLength", 0)) || 0;
        var limits = [defaultValue || 0, 512, 1024, 4096, 8192];
        return selected >= 0 && selected < limits.length ? limits[selected] : (defaultValue || 0);
    }

    function limitContextMessages(messageRoles) {
        var list = Array.isArray(messageRoles) ? messageRoles.slice() : [];
        var configured = Number(plasmoid.configuration.contextMessageLimit);
        var maxMessages = configured >= 0 ? Math.min(100, configured + 1) : 100;
        if (list.length > maxMessages)
            list = list.slice(list.length - maxMessages);
        var totalChars = 0;
        var firstKept = list.length;
        for (var i = list.length - 1; i >= 0; i--) {
            var size = 0;
            try { size = JSON.stringify(list[i]).length; } catch (e) { size = String(list[i].content || "").length; }
            if (totalChars + size > 6000000 && firstKept < list.length)
                break;
            totalChars += size;
            firstKept = i;
        }
        return list.slice(firstKept);
    }

    // The messages of `sessionId` (not necessarily the chat on screen).
    function sessionMessages(sessionId) {
        if (sessionId === root.currentSessionId)
            return root.messages;
        var idx = sessionIndexById(sessionId);
        return idx >= 0 ? (root.sessions[idx].messages || []) : [];
    }

    // System prompt and conversation for a direct API request.
    function buildDirectRequestParts(sessionId, apiType) {
        var source = sessionMessages(sessionId);
        var conversation = [];
        for (var i = 0; i < source.length; i++) {
            if (source[i].role === "user" || source[i].role === "assistant")
                conversation.push(source[i]);
        }
        conversation = limitContextMessages(conversation);
        var messages = [];
        for (var j = 0; j < conversation.length; j++) {
            var rm = conversation[j];
            var hasAttachments = rm.role === "user" && rm.attachments && rm.attachments.length > 0;
            messages.push({"role": rm.role, "content": hasAttachments ? buildMessageContent(rm.content, rm.attachments, apiType) : rm.content});
        }
        return {"system": buildEffectiveSystemPrompt(sessionId), "messages": messages};
    }

    // Sends a direct API request and applies its events to the chat.
    function doDirectRequest(cfg, sessionId, generation) {
        var apiType = cfg.type === "anthropic" ? "anthropic" : "openai";
        var parts = buildDirectRequestParts(sessionId, apiType);
        var model = cfg.model || "";
        root.currentStreamUsage = ({});
        root.loading = true;
        root.activeXhr = DirectBackend.send({
            "type": apiType,
            "baseUrl": cfg.baseUrl,
            "apiKey": cfg.apiKey,
            "model": model,
            "headers": cfg.headers,
            "system": parts.system,
            "messages": parts.messages,
            "maxTokens": responseMaxTokens(sessionId, DirectBackend.DEFAULT_MAX_TOKENS),
            "stream": plasmoid.configuration.disableStreaming !== true,
            "timeoutMs": plasmoid.configuration.requestTimeout > 0 ? plasmoid.configuration.requestTimeout * 1000 : 0,
            "xhrFactory": function() { return new XMLHttpRequest(); },
            "onEvent": function(event) {
                if (requestIsCurrent(sessionId, generation))
                    applyBackendEvent(event, model);
            }
        });
    }

    // Starts the reply bubble for the request being streamed, if needed.
    function ensureStreamingMessage(model) {
        if (root.currentStreamIndex >= 0)
            return;
        var ts = Date.now();
        root.currentStreamKey = "m-stream-" + ts;
        root.messages = root.messages.concat([{"id": root.currentStreamKey, "role": "assistant", "content": "", "reasoning": "", "time": nowTime(ts), "at": ts, "model": model}]);
        root.currentStreamIndex = root.messages.length - 1;
        root.streamingResponse = true;
    }

    // Updates fields of an existing message: update(copyOfMessage).
    function updateMessageAt(index, update) {
        if (index < 0 || index >= root.messages.length)
            return;
        var msgs = root.messages.slice();
        var copy = Object.assign({}, msgs[index]);
        update(copy);
        msgs[index] = copy;
        root.messages = msgs;
    }

    function findRequestMessage(role, idField, id) {
        for (var i = root.messages.length - 1; i >= 0; i--)
            if (root.messages[i].role === role && root.messages[i][idField] === id)
                return i;
        return -1;
    }

    // Applies one backend event (DirectBackend.js / OpenCodeBackend.js / PiBackend.js) to the chat.
    function applyBackendEvent(event, model, extra) {
        if (AgentEvents.isReplyEvent(event.type)) {
            // Shown in the reply's Context list until Phase 4's tool cards.
            ensureStreamingMessage(model);
            updateMessageAt(root.currentStreamIndex, function(msg) { AgentEvents.applyToReply(msg, event); });
        } else if (event.type === "permission_request" || event.type === "question_request") {
            var isPermission = event.type === "permission_request";
            if (findRequestMessage(event.type, isPermission ? "permissionId" : "questionId", event.id) >= 0)
                return;
            root.messages = root.messages.concat([isPermission ? AgentEvents.permissionMessage(event, extra, Date.now())
                                                               : AgentEvents.questionMessage(event, extra, Date.now())]);
            triggerNotificationSound();
            saveCurrentSessionState(true);
        } else if (event.type === "permission_resolved") {
            updateMessageAt(findRequestMessage("permission_request", "permissionId", event.id), function(msg) {
                msg.status = event.reply === "reject" ? "denied" : "allowed";
            });
        } else if (event.type === "question_resolved") {
            updateMessageAt(findRequestMessage("question_request", "questionId", event.id), function(msg) {
                if (msg.status !== "answered" && msg.status !== "dismissed") msg.status = event.status;
            });
        } else if (event.type === "text_delta" || event.type === "reasoning_delta") {
            ensureStreamingMessage(model);
            root.streamBuffer.add(event.type === "text_delta" ? "text" : "reasoning", event.delta);
        } else if (event.type === "usage") {
            var usage = Object.assign({}, root.currentStreamUsage);
            if (event.input !== undefined) usage.input = event.input;
            if (event.output !== undefined) usage.output = event.output;
            if (event.cost !== undefined) usage.cost = (usage.cost || 0) + event.cost;
            root.currentStreamUsage = usage;
        } else if (event.type === "error") {
            resetProviderStreamingState();
            pushErrorMessage(event.message);
        } else if (event.type === "done") {
            streamBuffer.flush();
            var completed = event.reason === "complete";
            if (completed && root.currentStreamIndex >= 0) {
                var msgs = root.messages.slice();
                var reply = Object.assign({}, msgs[root.currentStreamIndex]);
                reply.content = root.currentStreamText || (reply.tools ? "" : "(empty response)");
                reply.reasoning = root.currentStreamReasoning;
                if (root.currentStreamUsage.input !== undefined || root.currentStreamUsage.output !== undefined)
                    reply.tokens = {"input": root.currentStreamUsage.input || 0, "output": root.currentStreamUsage.output || 0};
                if (root.currentStreamUsage.cost)
                    reply.cost = root.currentStreamUsage.cost;
                msgs[root.currentStreamIndex] = reply;
                root.messages = msgs;
            } else if (completed) {
                pushErrorMessage("The model returned an empty response.");
            }
            root.currentStreamIndex = -1;
            resetProviderStreamingState();
            root.loading = false;
            root.activeXhr = null;
            root.activeRequestSessionId = "";
            root.requestGeneration++;
            if (completed) {
                try { triggerNotificationSound(); } catch (notifyErr) { console.error("Notification failed:", notifyErr); }
            }
            try { saveCurrentSessionState(true); } catch (saveErr) { console.error("Session save failed:", saveErr); }
            if (completed)
                maybeGenerateChatTitle();
            processNextQueuedMessage();
        }
    }

    // The agent (OpenCode or Pi) that asked a permission or question.
    function harnessFor(role, idField, id) {
        var index = findRequestMessage(role, idField, id);
        return index >= 0 && root.messages[index].harness === "pi" ? piAgent : openCode;
    }

    // always: also allow it from now on (OpenCode only).
    function respondToPermission(permissionId, approved, always) {
        harnessFor("permission_request", "permissionId", permissionId).respondToPermission(permissionId, approved, always === true);
    }

    function respondToQuestion(questionId, answerValue, isReject) {
        harnessFor("question_request", "questionId", questionId).respondToQuestion(questionId, answerValue, isReject);
    }

    function triggerNotificationSound() {
        if (plasmoid.configuration.playNotificationSound) {
            soundDs.connectSource("pw-play /usr/share/sounds/ocean/stereo/message-new-instant.oga || paplay /usr/share/sounds/ocean/stereo/message-new-instant.oga || aplay /usr/share/sounds/freedesktop/stereo/bell.oga || canberra-gtk-play -i message-new-instant");
        }

        if (voiceManager && voiceManager.enabled && (voiceManager.ttsAuto || voiceManager.callModeActive)) {
            // Find the last assistant message
            for (var i = root.messages.length - 1; i >= 0; i--) {
                if (root.messages[i].role === "assistant") {
                    var text = (root.messages[i].content || "").trim();
                    if (text) {
                        root.playingMessageIndex = i;
                        voiceManager.playTTS(text);
                    }
                    break;
                }
            }
        }
    }

    function _questionMessageIndex(questionId) {
        for (var i = 0; i < root.messages.length; i++)
            if (root.messages[i].role === "question_request" && root.messages[i].questionId === questionId)
                return i;
        return -1;
    }

    function questionOptionSelected(questionId, questionIndex, label) {
        var idx = _questionMessageIndex(questionId);
        if (idx < 0) return false;
        var selected = root.messages[idx].selectedAnswers || [];
        var row = selected[questionIndex];
        return Array.isArray(row) && row.indexOf(String(label || "")) >= 0;
    }

    function toggleQuestionOption(questionId, questionIndex, label, multiple) {
        var idx = _questionMessageIndex(questionId);
        if (idx < 0) return;
        var copy = root.messages.slice();
        var item = Object.assign({}, copy[idx]);
        var selected = Array.isArray(item.selectedAnswers) ? item.selectedAnswers.slice() : [];
        var row = Array.isArray(selected[questionIndex]) ? selected[questionIndex].slice() : [];
        var value = String(label || "");
        if (multiple) {
            var existing = row.indexOf(value);
            if (existing >= 0) row.splice(existing, 1); else row.push(value);
        } else {
            row = [value];
        }
        selected[questionIndex] = row;
        item.selectedAnswers = selected;
        copy[idx] = item;
        root.messages = copy;
        saveCurrentSessionState(true);
    }

    // Collect selected options from the question UI and submit the answer.
    function submitQuestionAnswer(questionId, questions, customField) {
        var idx = _questionMessageIndex(questionId);
        if (idx < 0) return;
        var customText = customField ? String(customField.text || "").trim() : "";
        if (!questions || questions.length === 0) {
            if (customText) respondToQuestion(questionId, customText, false);
            return;
        }
        var selected = root.messages[idx].selectedAnswers || [];
        var answers = [];
        var hasAnswer = false;
        var firstEmpty = -1;
        for (var i = 0; i < questions.length; i++) {
            var row = Array.isArray(selected[i]) ? selected[i].slice() : [];
            if (row.length > 0) hasAnswer = true;
            else if (firstEmpty < 0) firstEmpty = i;
            answers.push(row);
        }
        if (customText) {
            if (firstEmpty >= 0) answers[firstEmpty] = [customText];
            else if (answers.length > 0) answers[answers.length - 1].push(customText);
            hasAnswer = true;
        }
        if (hasAnswer)
            respondToQuestion(questionId, answers, false);
    }

    function stopStreaming() {
        invalidateActiveRequest(false);
        try { saveCurrentSessionState(true); } catch (e) { console.error("Stop save failed:", e); }
        processNextQueuedMessage();
    }

    function fileIconName(filename) {
        var ext = filename.split('.').pop().toLowerCase();
        if (ext === 'pdf')
            return 'document-pdf';

        if (ext === 'csv')
            return 'text-csv';

        if (ext === 'docx' || ext === 'doc')
            return 'document-word';

        if (ext === 'md' || ext === 'txt')
            return 'text-plain';

        return 'document-text';
    }

    function attachmentsReadyToSend() {
        for (var i = 0; i < root.attachedFiles.length; i++) {
            if (root.attachedFiles[i].loading || root.attachedFiles[i].error)
                return false;
        }
        return true;
    }

    function cleanupTemporaryAttachment(path) {
        var value = String(path || "");
        if (value.indexOf("/tmp/kdeaichat_clip_") !== 0 && value.indexOf("/tmp/kdeaichat_shot_") !== 0)
            return;
        var extractor = getDocExtractorPath();
        var safePath = Sec.validateFilePath(value);
        if (extractor && safePath)
            fileReaderDs.connectSource("python3 " + Sec.quoteForShell(extractor) + " --cleanup " + Sec.quoteForShell(safePath) + " #cleanup-attachment-" + Date.now());
    }

    function removeAttachedFile(index) {
        var files = root.attachedFiles.slice();
        if (index < 0 || index >= files.length)
            return;
        var removedPath = files[index].path || "";
        cleanupTemporaryAttachment(removedPath);
        var pending = Object.assign({}, root.pendingAttachmentRequests || {});
        var keys = Object.keys(pending);
        for (var p = 0; p < keys.length; p++) {
            var entry = pending[keys[p]] || {};
            var path = typeof entry === "string" ? entry : entry.path;
            if (path === removedPath) {
                if (typeof entry === "object" && entry.source) {
                    try { fileReaderDs.disconnectSource(entry.source); } catch (e) {}
                }
                delete pending[keys[p]];
            }
        }
        root.pendingAttachmentRequests = pending;
        files.splice(index, 1);
        root.attachedFiles = files;
    }

    function getDocExtractorPath() {
        var urlStr = String(Qt.resolvedUrl("doc_extractor.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        var path = decodeURIComponent(urlStr);
        return path.endsWith("/contents/ui/doc_extractor.py") ? path : "";
    }

    function attachFile(fileUrl) {
        var localPath = String(fileUrl);
        if (localPath.indexOf("file://") === 0)
            localPath = localPath.substring(7);

        localPath = decodeURIComponent(localPath);
        var files = root.attachedFiles.slice();
        if (files.length >= 10) {
            pushErrorMessage("You can attach at most 10 files per message.");
            return;
        }
        for (var i = 0; i < files.length; i++) {
            if (files[i].path === localPath)
                return ;

        }
        var filename = localPath.substring(localPath.lastIndexOf("/") + 1);
        var newFile = {
            "path": localPath,
            "name": filename,
            "loading": true,
            "error": "",
            "type": "",
            "content": "",
            "mimeType": "",
            "size": 0
        };
        files.push(newFile);
        root.attachedFiles = files;
        var docExtractorPath = getDocExtractorPath();
        var safePath = Sec.validateFilePath(localPath);
        if (!docExtractorPath || !safePath) {
            files.pop();
            root.attachedFiles = files;
            pushErrorMessage("Unable to attach this file: unsupported or unsafe path.");
            return;
        }
        var marker = "extract-file-" + (++root.attachmentRequestCounter) + "-" + Date.now();
        var pending = Object.assign({}, root.pendingAttachmentRequests || {});
        var cmd = "timeout 60s python3 " + Sec.quoteForShell(docExtractorPath) + " " + Sec.quoteForShell(safePath);
        var source = cmd + " #" + marker;
        pending[marker] = {"path": safePath, "source": source};
        root.pendingAttachmentRequests = pending;
        fileReaderDs.connectSource(source);
    }

    function buildMessageContent(text, attachments, apiType) {
        var docs = [];
        var imgs = [];
        var skippedImageCount = 0;
        var imageChars = 0;
        for (var i = 0; i < attachments.length; i++) {
            var att = attachments[i] || {};
            if (att.type === "image") {
                var imageSize = String(att.content || "").length;
                if (imageChars + imageSize <= 20000000) {
                    imgs.push(att);
                    imageChars += imageSize;
                } else {
                    skippedImageCount++;
                }
            } else if (att.type === "text")
                docs.push(att);
        }
        var compiledPrompt = skippedImageCount > 0
            ? "[" + skippedImageCount + " image attachment(s) omitted because the request image limit was reached.]\n"
            : "";
        for (var d = 0; d < docs.length; d++) {
            if (compiledPrompt.length > 5000000)
                break;
            compiledPrompt += "[Attached File: " + String(docs[d].name || "file") + " (" + Math.round((docs[d].size || 0) / 1024) + " KB)]\n";
            compiledPrompt += "--- START OF FILE CONTENT ---\n";
            var remainingDocChars = Math.max(0, 5000000 - compiledPrompt.length - 40);
            var docContent = String(docs[d].content || "");
            if (docContent.length > remainingDocChars)
                docContent = docContent.substring(0, remainingDocChars) + "\n[file content truncated]";
            compiledPrompt += docContent + "\n";
            compiledPrompt += "--- END OF FILE CONTENT ---\n\n";
        }
        compiledPrompt += text;
        if (imgs.length === 0)
            return compiledPrompt;

        var contentList = [];
        if (compiledPrompt.trim() !== "")
            contentList.push({
                "type": "text",
                "text": compiledPrompt
            });

        for (var imgIdx = 0; imgIdx < imgs.length; imgIdx++) {
            var image = imgs[imgIdx];
            if (apiType === "anthropic")
                contentList.push({
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": image.mimeType || "image/jpeg",
                        "data": image.content
                    }
                });
            else
                contentList.push({
                    "type": "image_url",
                    "image_url": {
                        "url": "data:" + (image.mimeType || "image/jpeg") + ";base64," + image.content
                    }
                });
        }
        return contentList;
    }

    function checkClipboardForAttachments() {
        var docExtractorPath = getDocExtractorPath();
        if (!docExtractorPath) {
            pushErrorMessage("Attachment extractor is not available in the installed widget.");
            return;
        }
        var cmd = "timeout 20s python3 " + Sec.quoteForShell(docExtractorPath) + " --clipboard";
        fileReaderDs.connectSource(cmd + " #clipboard-attachments");
    }

    function readClipboardText() {
        clipboardHelper.text = "";
        clipboardHelper.paste();
        return clipboardHelper.text;
    }

    function copyTextToClipboard(textToCopy) {
        clipboardHelper.text = textToCopy || "";
        clipboardHelper.selectAll();
        clipboardHelper.copy();
    }

    function performExportChat(filePath) {
        var isMarkdown = filePath.toLowerCase().endsWith(".md") || filePath.toLowerCase().endsWith(".markdown");
        var content = "";
        var sessionTitle = root.currentSessionTitle || "Untitled Session";
        var now = new Date();
        var dateStr = now.toLocaleDateString() + " " + now.toLocaleTimeString();
        if (isMarkdown) {
            content += "# 💬 KDE AI Chat: " + sessionTitle + "\n";
            content += "*Exported on " + dateStr + "*\n\n";
            content += "---\n\n";
            for (var i = 0; i < root.messages.length; i++) {
                var m = root.messages[i];
                if (m.role === "user") {
                    content += "<div align=\"right\">\n\n";
                    content += "### 👤 **User** (" + (m.time || "") + ")\n";
                    content += m.content + "\n\n";
                    content += "</div>\n\n";
                    content += "---\n\n";
                } else if (m.role === "assistant") {
                    var modelName = m.model || plasmoid.configuration.model || "Assistant";
                    content += "<div align=\"left\">\n\n";
                    content += "### 🤖 **" + modelName + "** (" + (m.time || "") + ")\n";
                    content += m.content + "\n\n";
                    content += "</div>\n\n";
                    content += "---\n\n";
                } else if (m.role === "error") {
                    content += "<div align=\"left\">\n\n";
                    content += "### ❌ **System Error** (" + (m.time || "") + ")\n";
                    content += "> " + m.content + "\n\n";
                    content += "</div>\n\n";
                    content += "---\n\n";
                }
            }
        } else {
            content += "==================================================\n";
            content += "💬 KDE AI Chat: " + sessionTitle + "\n";
            content += "Exported on: " + dateStr + "\n";
            content += "==================================================\n\n";
            var rightAlignTxt = function rightAlignTxt(text, width) {
                if (!width)
                    width = 80;

                var lines = text.split("\n");
                for (var j = 0; j < lines.length; j++) {
                    var trimmed = lines[j].trim();
                    if (trimmed.length === 0) {
                        lines[j] = "";
                        continue;
                    }
                    if (trimmed.length >= width)
                        lines[j] = trimmed;
                    else
                        lines[j] = " ".repeat(width - trimmed.length) + trimmed;
                }
                return lines.join("\n");
            };
            for (var i = 0; i < root.messages.length; i++) {
                var m = root.messages[i];
                if (m.role === "user") {
                    var userHeader = "👤 User (" + (m.time || "") + "):";
                    content += " ".repeat(Math.max(0, 80 - userHeader.length)) + userHeader + "\n";
                    content += rightAlignTxt(m.content, 80) + "\n\n";
                    content += "--------------------------------------------------\n\n";
                } else if (m.role === "assistant") {
                    var modelName = m.model || plasmoid.configuration.model || "Assistant";
                    content += "🤖 " + modelName + " (" + (m.time || "") + "):\n";
                    content += m.content + "\n\n";
                    content += "--------------------------------------------------\n\n";
                } else if (m.role === "error") {
                    content += "❌ System Error (" + (m.time || "") + "):\n";
                    content += "ERROR: " + m.content + "\n\n";
                    content += "--------------------------------------------------\n\n";
                }
            }
        }
        var safePath = Sec.validateFilePath(filePath);
        var helper = getHelperPath();
        if (!safePath || !helper) {
            pushErrorMessage("Export cancelled: invalid destination or helper unavailable.");
            return;
        }
        if (content.length > 500000) {
            pushErrorMessage("This chat is too large to export in one operation. Remove older messages or export a shorter conversation.");
            return;
        }
        var payload = {
            "filePath": safePath,
            "b64Content": Sec.base64Encode(content)
        };
        var encoded = Sec.base64Encode(JSON.stringify(payload));
        if (encoded.length > 900000) {
            pushErrorMessage("This chat is too large to export in one operation. Remove older messages or export a shorter conversation.");
            return;
        }
        var cmd = "python3 " + Sec.quoteForShell(helper) + " export_chat " + Sec.rawShellSnippetQuote(encoded)
            + " && (notify-send -i document-export " + Sec.quoteForShell("KDE AI Chat") + " "
            + Sec.quoteForShell("Chat session successfully exported to " + safePath) + " || true)";
        fileReaderDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #export-chat-save");
    }

    function initSystemPrompt() {
        compiledSystemPrompt = String(plasmoid.configuration.systemPrompt || "").trim().substring(0, 100000);
    }

    Plasmoid.title: plasmoid.configuration.appDisplayName || "KDE AI Chat"
    // Panels and the desktop show the compact icon; standalone hosts such as
    // plasmawindowed (used by scripts/dev-run.sh) open the chat directly.
    preferredRepresentation: Qt.application.name === "plasmawindowed" ? fullRepresentation : compactRepresentation
    onHistoryOnlyModeChanged: {
        if (!historyOnlyMode) {
            root.focusInput();
            Qt.callLater(function() { root.scrollToBottom(true); });
        }
    }
    onExpandedChanged: {
        if (expanded) {
            root.triggerInitialLoad();
            root.focusInput();
            Qt.callLater(root.scrollToBottom);
        }
    }
    Component.onCompleted: {
        // Build a usable prompt immediately; the deferred system-information
        // probe will refresh it once its results arrive.
        root.initSystemPrompt();
        root.stopLegacyWatchdog();
    }
    onMessagesChanged: {
        messageModel.sync(root.messages);
        // The streamed reply keeps its row even if messages before it are removed or added.
        if (root.currentStreamIndex >= 0)
            root.currentStreamIndex = messageModel.indexOfKey(root.currentStreamKey);
    }

    Timer {
        id: startupTimer

        interval: 1000
        running: true
        repeat: false
        onTriggered: {
            root.triggerInitialLoad();
        }
    }

    Timer {
        id: lazyWalletTimer

        interval: 150
        repeat: false
        onTriggered: {
            root.ensureWalletLoaded();
        }
    }

    Timer {
        id: walletReloadTimer
        interval: 250
        repeat: false
        onTriggered: {
            root.keysLoaded = false;
            root.ensureWalletLoaded();
        }
    }

    Connections {
        function onSystemPromptChanged() {
            initSystemPrompt();
        }

        function onCustomProvidersJsonChanged() { scheduleWalletReload(); }
        function onWalletKeysRevisionChanged() { scheduleWalletReload(); }

        target: plasmoid.configuration
    }

    P5Support.DataSource {
        id: soundDs

        engine: "executable"
        connectedSources: []
    }

    P5Support.DataSource {
        id: piDiscoveryDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var stdout = data["stdout"] || "";
            var providers = [];
            var modelMap = {};
            try {
                var payload = JSON.parse(stdout);
                var rows = payload.providers || [];
                for (var i = 0; i < rows.length; i++) {
                    var row = rows[i] || {};
                    var id = row.id || row.provider || "";
                    if (!id) continue;
                    var models = Array.isArray(row.models) ? row.models : [];
                    providers.push({"text": id, "value": id});
                    modelMap[id] = models;
                }
            } catch (e) {}
            root.piProviderCandidates = providers;
            root.piProviderModelMap = modelMap;
            root.piModelsFetching = false;
            disconnectSource(sourceName);
            var waiters = root.piModelFetchWaiters || [];
            root.piModelFetchWaiters = [];
            for (var w = 0; w < waiters.length; w++)
                if (waiters[w]) waiters[w](providers, modelMap);
        }
    }

    P5Support.DataSource {
        id: fileReaderDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var exitCode = Number(data["exit code"]);
            if (isNaN(exitCode)) exitCode = 1;
            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            if (sourceName.indexOf("--clipboard") !== -1) {
                if (exitCode === 0 && stderr.trim() === "") {
                    try {
                        var res = JSON.parse(stdout);
                        if (res.status === "success") {
                            var currentFiles = root.attachedFiles.slice();
                            if (res.mode === "files" && res.files) {
                                for (var f = 0; f < Math.min(res.files.length, 10 - currentFiles.length); f++) {
                                    var fInfo = res.files[f];
                                    var exists = false;
                                    for (var idx = 0; idx < currentFiles.length; idx++) {
                                        if (currentFiles[idx].path === fInfo.path) {
                                            exists = true;
                                            break;
                                        }
                                    }
                                    if (!exists)
                                        currentFiles.push({
                                            "name": fInfo.filename || fInfo.name,
                                            "path": fInfo.path,
                                            "type": fInfo.type,
                                            "content": fInfo.content,
                                            "mimeType": fInfo.mimeType,
                                            "size": fInfo.size,
                                            "loading": false,
                                            "error": ""
                                        });

                                }
                            } else if (res.mode === "image" && res.file && currentFiles.length < 10) {
                                var fInfo = res.file;
                                var exists = false;
                                for (var idx = 0; idx < currentFiles.length; idx++) {
                                    if (currentFiles[idx].path === fInfo.path) {
                                        exists = true;
                                        break;
                                    }
                                }
                                if (!exists)
                                    currentFiles.push({
                                        "name": fInfo.name,
                                        "path": fInfo.path,
                                        "type": fInfo.type,
                                        "content": fInfo.content,
                                        "mimeType": fInfo.mimeType,
                                        "size": fInfo.size,
                                        "loading": false,
                                        "error": ""
                                    });

                            }
                            root.attachedFiles = currentFiles;
                        }
                    } catch (e) {
                        console.log("Failed to parse clipboard data: " + e);
                    }
                }
                disconnectSource(sourceName);
                return ;
            }
            if (sourceName.indexOf("#fetch-opencode-agents") !== -1) {
                var fallbackAgents = [];
                var fallbackDefault = "";
                if (exitCode === 0 && stdout.trim() !== "") {
                    try {
                        var agentData = JSON.parse(stdout.trim());
                        fallbackAgents = normalizeOpenCodeAgents(agentData);
                        fallbackDefault = agentData.default || agentData.default_agent || "";
                    } catch (e) {
                        console.log("Failed to parse opencode agents: " + e);
                    }
                }
                _finishOpenCodeAgents(fallbackAgents, fallbackDefault);
                disconnectSource(sourceName);
                return ;
            }
            if (sourceName.indexOf("#plasmashell-watchdog-") !== -1) {
                disconnectSource(sourceName);
                return ;
            }
            if (sourceName.indexOf("#export-chat-save") !== -1) {
                if (exitCode !== 0)
                    pushErrorMessage("Export failed: " + (stderr.trim() || stdout.trim() || ("helper exited with code " + exitCode)));
                disconnectSource(sourceName);
                return ;
            }
            var matchedIndex = -1;
            var files = root.attachedFiles.slice();
            var attachmentPath = "";
            var requestKeys = Object.keys(root.pendingAttachmentRequests || {});
            for (var rk = 0; rk < requestKeys.length; rk++) {
                if (sourceName.indexOf(requestKeys[rk]) !== -1) {
                    var pendingEntry = root.pendingAttachmentRequests[requestKeys[rk]] || {};
                    attachmentPath = typeof pendingEntry === "string" ? pendingEntry : (pendingEntry.path || "");
                    var remainingRequests = Object.assign({}, root.pendingAttachmentRequests);
                    delete remainingRequests[requestKeys[rk]];
                    root.pendingAttachmentRequests = remainingRequests;
                    break;
                }
            }
            if (!attachmentPath) {
                disconnectSource(sourceName);
                return;
            }
            for (var i = 0; i < files.length; i++) {
                if (files[i].path === attachmentPath) {
                    matchedIndex = i;
                    break;
                }
            }
            if (matchedIndex === -1) {
                disconnectSource(sourceName);
                return;
            }
            var fileObj = Object.assign({
            }, files[matchedIndex]);
            fileObj.loading = false;
            if (exitCode !== 0 || stderr.trim() !== "") {
                fileObj.error = stderr.trim() || ("Command exited with code " + exitCode);
            } else {
                try {
                    var res = JSON.parse(stdout);
                    if (res.status === "success") {
                        fileObj.type = res.type;
                        fileObj.content = res.content;
                        fileObj.mimeType = res.mimeType;
                        fileObj.size = res.size;
                    } else {
                        fileObj.error = res.message || "Failed to extract file contents";
                    }
                } catch (e) {
                    fileObj.error = "Failed to parse extractor output: " + e;
                }
            }
            files[matchedIndex] = fileObj;
            root.attachedFiles = files;
            disconnectSource(sourceName);
        }
    }

    FileDialog {
        id: fileDialog

        title: "Attach Files"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["All supported files (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.pdf *.csv *.docx *.txt *.md *.json)", "Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)", "Documents (*.pdf *.docx *.csv *.txt *.md *.json)", "All files (*)"]
        onAccepted: {
            for (var i = 0; i < selectedFiles.length; i++) {
                root.attachFile(selectedFiles[i]);
            }
        }
    }

    FileDialog {
        id: exportFileDialog

        title: "Export Chat Session"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Markdown files (*.md)", "Plain text files (*.txt)"]
        onAccepted: {
            var path = selectedFile.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            root.performExportChat(path);
        }
    }

    FolderDialog {
        id: workspaceFolderDialog

        title: "Select OpenCode Working Directory"
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            root.openCodeWorkspaceCwd = path;
            plasmoid.configuration.openCodeWorkspaceCwd = path;
        }
    }

    // Text editor acting as helper to interact with OS text clipboard (copy / paste)
    // Placed offscreen so selection/clipboard actions function correctly in all Qt versions
    TextEdit {
        id: clipboardHelper

        x: -9999
        y: -9999
        width: 1
        height: 1
        visible: true
    }

    function getHelperPath() {
        let urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        let path = decodeURIComponent(urlStr);
        return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
    }

    function enqueueSchedulerTrigger(trigger) {
        if (!trigger || !trigger.chatId || !trigger.message)
            return false;
        var idx = root.sessionIndexById(String(trigger.chatId));
        if (idx < 0) {
            console.warn("Scheduler trigger: chatId not found in sessions:", trigger.chatId);
            return false;
        }
        if (!root.schedulerResumeSessionId && root.currentSessionId !== String(trigger.chatId))
            root.schedulerResumeSessionId = root.currentSessionId;
        var updated = root.sessions.slice();
        var session = Object.assign({}, updated[idx]);
        var messages = session.value === root.currentSessionId ? root.messages.slice() : (session.messages || []).slice();
        var ts = Date.now();
        messages.push({
            "role": "queued",
            "content": String(trigger.message),
            "time": root.nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": ++root.queueCounter,
            "attachments": [],
            "scheduled": true,
            "scheduleName": String(trigger.name || "Scheduled task")
        });
        session.messages = messages;
        session.updatedAt = ts;
        updated[idx] = session;
        root.sessions = updated;
        if (session.value === root.currentSessionId)
            root.messages = messages;
        root.persistSessions();
        return true;
    }

    P5Support.DataSource {
        id: schedulerDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let out = data["stdout"] ? data["stdout"] : "";
            if (sourceName.indexOf("poll_pending_triggers") >= 0) {
                root.schedulerPollInFlight = false;
                schedulerPollTimeout.stop();
            }

            schedulerDs.disconnectSource(sourceName);

            if (out.trim() === "")
                return;

            if (sourceName.indexOf("poll_pending_triggers") >= 0) {
                try {
                    let parsed = JSON.parse(out);
                    let pending = parsed.pending || [];
                    for (let i = 0; i < pending.length; i++) {
                        let p = pending[i];
                        if (root.enqueueSchedulerTrigger(p)) {
                            console.log("Scheduler trigger:", p.name, "-> chatId:", p.chatId);
                            if (p.notify) {
                                root.triggerNotificationSound();
                                let escMsg = String(p.name || "Scheduled task") + ": " + String(p.message);
                                let notifyCmd = "notify-send -i dialog-messages 'KDE AI Chat - Scheduler' " + Sec.quoteForShell(escMsg);
                                soundDs.connectSource(notifyCmd + " #sched-notify-" + Date.now());
                            }
                        }
                    }
                    if (!root.loading)
                        root.processNextQueuedMessage();
                } catch (e) {
                    console.warn("Failed to parse pending triggers JSON:", e);
                }
            }
        }
    }

    Timer {
        id: schedulerPollTimeout
        interval: 10000
        repeat: false
        onTriggered: root.schedulerPollInFlight = false
    }

    Timer {
        id: schedulerPollTimer
        interval: 3000
        repeat: true
        // Only the scheduler daemon writes pending triggers, so don't spawn a
        // shell every few seconds while the scheduler is switched off.
        running: plasmoid.configuration.schedulerEnabled === true
        onTriggered: {
            // Don't poll until sessions are loaded so sessionIndexById works
            if (!root._initialLoadDone || root.schedulerPollInFlight)
                return;

            let localShare = String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation));
            if (localShare.indexOf("file://") === 0) {
                localShare = localShare.substring(7);
            }
            localShare = decodeURIComponent(localShare);
            let pendingDir = localShare + "/kdeaichat/pending";
            let helper = root.getHelperPath();
            if (!helper) return;
            let cmd = "[ -d " + Sec.quoteForShell(pendingDir) + " ] && [ \"$(ls -A " + Sec.quoteForShell(pendingDir) + " 2>/dev/null)\" ] && python3 " + Sec.quoteForShell(helper) + " poll_pending_triggers";
            root.schedulerPollInFlight = true;
            schedulerPollTimeout.restart();
            schedulerDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #poll_pending_triggers-" + Date.now());
        }
    }

    // True when the custom widget icon is an image file (not a KDE icon name).
    function customIconIsImage() {
        var v = (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.customIcon || "") : "";
        if (v === "")
            return false;
        var s = v.trim().toLowerCase();
        if (s.indexOf("file://") === 0 || s.charAt(0) === "/")
            return true;
        return s.endsWith(".png") || s.endsWith(".jpg") || s.endsWith(".jpeg")
            || s.endsWith(".gif") || s.endsWith(".webp") || s.endsWith(".svg")
            || s.endsWith(".svgz") || s.endsWith(".bmp");
    }

    // Turns the stored icon value (a file path) into a QML-usable source URL.
    function customIconImageSource() {
        var v = (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.customIcon || "") : "";
        if (v === "")
            return "";
        if (v.indexOf("file://") === 0)
            return v;
        return "file://" + v;
    }

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        // Custom image icons (including animated GIFs) are rendered with an
        // Image element; KDE icon names fall back to Kirigami.Icon.
        Image {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            visible: root.customIconIsImage()
            source: root.customIconIsImage() ? root.customIconImageSource() : ""
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            visible: !root.customIconIsImage()
            source: (plasmoid && plasmoid.configuration && plasmoid.configuration.customIcon)
                ? plasmoid.configuration.customIcon : "dialog-messages"
        }
    }

    fullRepresentation: Item {
        implicitWidth: root.popupPreferredWidth
        implicitHeight: root.popupPreferredHeight
        Layout.minimumWidth: 500
        Layout.minimumHeight: 620
        Layout.preferredWidth: root.popupPreferredWidth
        Layout.preferredHeight: root.popupPreferredHeight
        Component.onCompleted: {
            root.focusInput();
        }
        onVisibleChanged: {
            if (visible) {
                root.focusInput();
                Qt.callLater(root.scrollToBottom);
            }
        }
        // No background or colours of its own: the Plasma popup draws the
        // background and the content follows the Plasma colour scheme.
        Loader {
            id: mainContentLoader

            anchors.fill: parent
            active: root.expanded || root._initialLoadDone
            source: "FullRepresentationContent.qml"

            onStatusChanged: {
                console.log("Loader status changed:", status, (status === Loader.Error ? "ERROR!" : ""));
                if (status === Loader.Error) {
                    console.log("Error string:", sourceComponent ? sourceComponent.errorString() : "No sourceComponent");
                }
            }
        }

    }

}
