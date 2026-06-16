import QtQuick
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid
import "translations.js" as Translations
import "ProviderService.js" as ProviderService
import "SessionManager.js" as SessionManager
import "MarkdownRenderer.js" as MarkdownRenderer
import "WalletService.js" as WalletService
import "RequestDeduplicator.js" as RequestDeduplicator
import "LRUCache.js" as LRUCache
import "Security.js" as Sec
import "ChatEngine.js" as ChatEngine

// LINKAGE RELATIONSHIPS:
// - main.qml: The root entrypoint PlasmoidItem.
// - Linked to MainDataSources.qml (instantiated as 'dataSources' and exposed via property aliases):
//   Holds all the external process command execution DataSources, Timers, and File Dialogs to keep main.qml under 1000 lines.
//   It takes a reference to 'root' (this) to read config and update state.
// - Linked to ChatEngine.js (imported as MainDatabase):
//   Contains ALL application logic — session, network, streaming, schedule, and voice functions.

PlasmoidItem {
    // No custom text and no way to read options from here,
    // so prompt user to type something or click an option
    // The option buttons themselves handle single-click submit
    // for non-multiple mode

    id: root

    property color themeTextColor: Kirigami.Theme.textColor
    property color themeHighlightColor: Kirigami.Theme.highlightColor
    property bool debugMode: false
    function debugLog() {
        return ChatEngine.debugLog();
    }

    property var sessions: []
    // Bounded LRU caches for markdown/HTML conversion and block parsing.
    // Replaces the previous unbounded `({})` maps that grew with every
    // streaming token. 500 entries is enough to cover the visible
    // message history plus a few pages of scrollback.
    property var _markdownCache: LRUCache.create(500)
    property var _blocksCache: LRUCache.create(500)
    readonly property string openCodeBaseUrlVal: {
        let raw = (plasmoid.configuration.openCodeUrl || "http://127.0.0.1:4096/v1").trim();
        return raw.replace(/\/v1\/?$/, "").replace(/\/$/, "");
    }
    property string currentSessionId: ""
    property string activeHistoryPath: ""
    property string currentSessionTitle: ""
    property var messages: []
    property var quotedMessage: null
    property bool searchBarActive: false
    property string searchQuery: ""
    property int currentSearchMatchIndex: -1
    // Memoization for `searchMatches` (audit 5.2).
    // The original binding re-ran on every `messages` array replacement
    // (which happens per streaming token) and re-scanned every message
    // with `toLowerCase()` + `indexOf()`. The binding is still recomputed
    // on every relevant change, but the work is skipped when a cheap
    // fingerprint of (query, length, sampled content) is unchanged.
    // Catches: appended messages (length), edited middle messages (sampled
    // hash), and streaming tokens (last-message length).
    property string _searchFingerprint: {
        if (!searchBarActive || searchQuery.trim() === "") return "";
        let parts = [searchQuery, "|" + messages.length];
        let step = Math.max(1, Math.floor(messages.length / 16));
        for (let i = 0; i < messages.length; i += step) {
            let c = messages[i].content || "";
            parts.push("|" + c.length);
        }
        if (messages.length > 0) {
            let last = messages[messages.length - 1].content || "";
            parts.push("!L=" + last.length + ":" + last.slice(-32));
        }
        return parts.join("");
    }
    property string _searchFingerprintCached: ""
    property var _searchMatchesCached: []
    property var searchMatches: {
        if (!searchBarActive || searchQuery.trim() === "") return [];
        let fp = root._searchFingerprint;
        if (fp === root._searchFingerprintCached) return root._searchMatchesCached;
        let q = searchQuery.toLowerCase();
        let list = [];
        for (let j = 0; j < messages.length; j++) {
            let msg = messages[j] || {};
            let content = msg.searchText || ((msg.content || "").toLowerCase());
            if (content.indexOf(q) >= 0) {
                list.push(j);
            }
        }
        root._searchFingerprintCached = fp;
        root._searchMatchesCached = list;
        return list;
    }
    property var attachedFiles: []
    property bool historyOnlyMode: false
    property bool loading: false
    property var activeXhr: null
    property var openCodeEventXhr: null
    property string openCodeActiveSessionId: ""
    property int openCodeAssistantMessageIndex: -1
    property string openCodeAssistantServerMessageId: ""
    property string openCodeAssistantModelLabel: "OpenCode"
    property bool openCodeErrorShownForRequest: false
    property bool streamingResponse: false
    property string streamingContent: ""
    property string streamingModel: ""
    property var streamingContextItems: []
    property var streamingTokens: null
    property real streamingCost: 0
    property bool autocompleteActive: false
    property int autocompleteSelectedIndex: 0
    property var filteredCommands: []
    property int editingMessageIndex: -1
    property string editingDraft: ""
    property string editingSessionId: ""
    property string editingSessionDraft: ""
    property bool renamingCurrentChat: false
    property string currentChatRenameDraft: ""
    property bool openCodeMode: false
    property var schedulesList: []
    property bool openCodeStarting: false
    property var openCodeStartSuccessCallbacks: []
    property var openCodeStartFailureCallbacks: []
    property bool schedPolling: false
    // Voice (STT/TTS) state
    property bool voiceRecording: false
    property string voiceSttStatus: ""
    property bool ttsPlaying: false
    property bool ttsPaused: false
    property string voiceTtsStatus: ""
    property bool voiceEnvChecked: false
    property var voiceEnvResult: null
    property string voicePendingText: ""
    property bool voiceSttTesting: false
    property string voiceSttTestResult: ""
    property var plasmoidRef: plasmoid
    property string configCustomHistoryPath: plasmoid.configuration.customHistoryPath || ""
    property bool configUseOpenCode: !!plasmoid.configuration.useOpenCode
    property int configKeyStorageMode: plasmoid.configuration.keyStorageMode || 0
    property bool configKwalletAutoPrompt: plasmoid.configuration.kwalletAutoPrompt !== undefined ? !!plasmoid.configuration.kwalletAutoPrompt : true
    property bool configOpenCodeAutoKill: !!plasmoid.configuration.openCodeAutoKill
    property int configOpenCodeAutoKillMinutes: plasmoid.configuration.openCodeAutoKillMinutes || 5
    property int configResponseLength: plasmoid.configuration.responseLength || 0

    property bool kwalletKeysLoaded: false
    property int kwalletOpenAttempts: 0
    property bool kwalletLoading: false
    property var kwalletLoadSuccessCallbacks: []
    property var kwalletLoadFailureCallbacks: []
    // When kwalletOpenAttempts reaches 3 this is set true and no further
    // automatic prompts are made. Reset explicitly by the "Refresh from KWallet"
    // button in settings, which resets kwalletOpenAttempts to 0 as well.
    property bool kwalletPermanentlyFailed: false
    property string kwalletFailReason: ""
    // Root-level proxies so root-scope functions can reach UI elements in fullRepresentation
    property string chatInputText: ""
    property var msgListViewRef: null
    property var msgInputRef: null
    property var sessionsSidebarRef: null
    property bool userScrolledUp: false
    property bool scrollToBottomQueued: false


    property int queueCounter: 0
    property int popupPreferredWidth: plasmoid.configuration.customPopupWidth > 0 ? plasmoid.configuration.customPopupWidth : 760
    property int popupPreferredHeight: plasmoid.configuration.customPopupHeight > 0 ? plasmoid.configuration.customPopupHeight : 760
    readonly property bool popupIsDark: {
        let mode = plasmoid.configuration.appearanceMode || 0;
        if (mode === 1)
            return false;

        if (mode === 2)
            return true;

        return Qt.styleHints.colorScheme === Qt.Dark;
    }

    Shortcut {
        sequence: (plasmoid.configuration.keyToggleSearch !== undefined) ? plasmoid.configuration.keyToggleSearch : "Ctrl+F"
        context: Qt.WindowShortcut
        onActivated: {
            root.searchBarActive = !root.searchBarActive;
            if (!root.searchBarActive) {
                root.searchQuery = "";
                root.focusInput();
            }
        }
    }
    Shortcut {
        sequence: (plasmoid.configuration.keyNewChat !== undefined) ? plasmoid.configuration.keyNewChat : "Ctrl+N"
        context: Qt.WindowShortcut
        onActivated: root.createSession(true)
    }
    Shortcut {
        sequence: (plasmoid.configuration.keyToggleHistory !== undefined) ? plasmoid.configuration.keyToggleHistory : "Ctrl+H"
        context: Qt.WindowShortcut
        onActivated: root.historyOnlyMode = !root.historyOnlyMode
    }
    Shortcut {
        sequence: (plasmoid.configuration.keySettings !== undefined) ? plasmoid.configuration.keySettings : "Ctrl+,"
        context: Qt.WindowShortcut
        onActivated: root.triggerConfigure()
    }
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: {
            if (root.searchBarActive) {
                root.searchBarActive = false;
                root.searchQuery = "";
                root.focusInput();
            } else if (root.loading) {
                root.stopStreaming();
            }
        }
    }
    Shortcut {
        sequence: (plasmoid.configuration.keyFocusInput !== undefined) ? plasmoid.configuration.keyFocusInput : "Ctrl+I"
        context: Qt.WindowShortcut
        onActivated: root.focusInput()
    }
    Shortcut {
        sequence: (plasmoid.configuration.keyClearInput !== undefined) ? plasmoid.configuration.keyClearInput : "Ctrl+L"
        context: Qt.WindowShortcut
        onActivated: {
            root.chatInputText = "";
            root.clearChatInput();
            root.focusInput();
        }
    }
    Shortcut {
        sequence: (plasmoid.configuration.keyToggleSearchSidebar !== undefined) ? plasmoid.configuration.keyToggleSearchSidebar : "Ctrl+Shift+K"
        context: Qt.WindowShortcut
        onActivated: {
            if (root.sessionsSidebarRef) {
                root.sessionsSidebarRef.focusSearch();
            }
        }
    }
    Shortcut {
        sequence: (plasmoid.configuration.keyNextSession !== undefined) ? plasmoid.configuration.keyNextSession : "Ctrl+Shift+."
        context: Qt.WindowShortcut
        onActivated: {
            let idx = SessionManager.sessionIndexById(root.sessions, root.currentSessionId);
            if (idx < 0)
                return ;
            for (let i = idx + 1; i < root.sessions.length; i++) {
                if (!(root.sessions[i].archived || false)) {
                    root.switchSession(root.sessions[i].value);
                    return ;
                }
            }
        }
    }
    Shortcut {
        sequence: (plasmoid.configuration.keyPrevSession !== undefined) ? plasmoid.configuration.keyPrevSession : "Ctrl+Shift+,"
        context: Qt.WindowShortcut
        onActivated: {
            let idx = SessionManager.sessionIndexById(root.sessions, root.currentSessionId);
            for (let i = (idx < 0 ? root.sessions.length - 1 : idx - 1); i >= 0; i--) {
                if (!(root.sessions[i].archived || false)) {
                    root.switchSession(root.sessions[i].value);
                    return ;
                }
            }
        }
    }
    Shortcut {
        sequence: (plasmoid.configuration.keyRefresh !== undefined) ? plasmoid.configuration.keyRefresh : "Ctrl+R"
        context: Qt.WindowShortcut
        onActivated: {
            if (root.loading) {
                root.stopStreaming();
            }
            root.loadSessions();
        }
    }
    Shortcut {
        sequence: (plasmoid.configuration.keyCopyLastReply !== undefined) ? plasmoid.configuration.keyCopyLastReply : "Ctrl+Shift+C"
        context: Qt.WindowShortcut
        onActivated: {
            for (let i = root.messages.length - 1; i >= 0; i--) {
                if (root.messages[i].role === "assistant" && !(root.messages[i].isSystem || false)) {
                    root.copyToClipboard(root.messages[i].content || "");
                    return ;
                }
            }
            root.pushErrorMessage(root.translate("No assistant reply to copy."));
        }
    }
    Shortcut {
        sequence: "F1"
        context: Qt.WindowShortcut
        onActivated: {
            let msg = root.translate("Keyboard shortcuts:") + " " +
                (plasmoid.configuration.keyNewChat || root.translate("Disabled")) + " " + root.translate("new chat") + ", " +
                (plasmoid.configuration.keyToggleSearch || root.translate("Disabled")) + " " + root.translate("search") + ", " +
                (plasmoid.configuration.keyFocusInput || root.translate("Disabled")) + " " + root.translate("focus input") + ", " +
                (plasmoid.configuration.keyClearInput || root.translate("Disabled")) + " " + root.translate("clear input") + ", " +
                (plasmoid.configuration.keyToggleHistory || root.translate("Disabled")) + " " + root.translate("history") + ", " +
                (plasmoid.configuration.keySettings || root.translate("Disabled")) + " " + root.translate("settings") + ", " +
                (plasmoid.configuration.keyRefresh || root.translate("Disabled")) + " " + root.translate("refresh") + ", " +
                (plasmoid.configuration.keyCopyLastReply || root.translate("Disabled")) + " " + root.translate("copy last reply") + ", " +
                (plasmoid.configuration.keyPrevSession || root.translate("Disabled")) + "/" + (plasmoid.configuration.keyNextSession || root.translate("Disabled")) + " " + root.translate("switch session") + ", " +
                "Esc " + root.translate("stop/cancel") + ".";
            root.pushErrorMessage(msg);
        }
    }

    signal clearChatInput()

    function sessionHasSchedules(sessionId) {
        return ChatEngine.sessionHasSchedules(sessionId);
    }

    function triggerConfigure() {
        return ChatEngine.triggerConfigure();
    }

    function focusInput() {
        return ChatEngine.focusInput();
    }

    function searchNext() {
        return ChatEngine.searchNext();
    }

    function searchPrev() {
        return ChatEngine.searchPrev();
    }

    function pad2(v) {
        return ChatEngine.pad2(v);
    }

    function nowTime(ts) {
        return ChatEngine.nowTime(ts);
    }

    function formatDateTime(ts) {
        return ChatEngine.formatDateTime(ts);
    }

    function makeSessionId() {
        return ChatEngine.makeSessionId();
    }

    // Centralized helper for reporting a benign parse failure (e.g. an
    // OpenCode / clipboard / custom-history reply we could not decode).
    // Always logs to console for diagnostics and surfaces a non-blocking
    // notification to the user, so the failure is never silently dropped.
    function reportParseFailure(context, error) {
        return ChatEngine.reportParseFailure(context, error);
    }

    function makeForkSessionId() {
        return ChatEngine.makeForkSessionId();
    }

    function forkSession(messageIndex) {
        return ChatEngine.forkSession(messageIndex);
    }

    // ── /schedule command handler ──────────────────────────────────────────────
    function handleScheduleCommand(messageText) {
        return ChatEngine.handleScheduleCommand(messageText);
    }

    function toggleScheduleEnabled(schedId, newEnabled) {
        return ChatEngine.toggleScheduleEnabled(schedId, newEnabled);
    }

    function injectScheduledMessage(chatId, messageText, notify, schedId, schedName) {
        return ChatEngine.injectScheduledMessage(chatId, messageText, notify, schedId, schedName);
    }

    function parseSessions(customRaw) {
        return ChatEngine.parseSessions(customRaw);
    }

    function checkAndMarkCurrentSessionAsRead() {
        return ChatEngine.checkAndMarkCurrentSessionAsRead();
    }

    function base64Encode(str) {
        return ChatEngine.base64Encode(str);
    }

    function base64Decode(str) {
        return ChatEngine.base64Decode(str);
    }

    function getHistoryFilePath(customDir) {
        return ChatEngine.getHistoryFilePath(customDir);
    }

    function migrateHistory(oldPath, newPath) {
        return ChatEngine.migrateHistory(oldPath, newPath);
    }

    function persistSessions() {
        return ChatEngine.persistSessions();
    }

    function flushPersistSessions() {
        return ChatEngine.flushPersistSessions();
    }

    function sortSessionsByUpdated() {
        return ChatEngine.sortSessionsByUpdated();
    }

    function historySessionTint(sessionData) {
        return ChatEngine.historySessionTint(sessionData);
    }

    function sessionSubtitle(sessionData) {
        return ChatEngine.sessionSubtitle(sessionData);
    }

    function sessionIndexById(sessionId) {
        return ChatEngine.sessionIndexById(sessionId);
    }

    function createSession(switchToNew) {
        return ChatEngine.createSession(switchToNew);
    }

    function loadSessions() {
        return ChatEngine.loadSessions();
    }

    function saveCurrentSessionState(touchUpdatedAt) {
        return ChatEngine.saveCurrentSessionState(touchUpdatedAt);
    }

    function setCurrentSessionSource(source) {
        return ChatEngine.setCurrentSessionSource(source);
    }

    function setSessionArchived(sessionId, archived) {
        return ChatEngine.setSessionArchived(sessionId, archived);
    }

    function switchSession(sessionId) {
        return ChatEngine.switchSession(sessionId);
    }

    function listViewIndexAt(x, y) {
        if (!msgListViewRef || !messages) return -1;
        return msgListViewRef.indexAt(x, y);
    }

    function toOriginalMessageIndex(localIdx) {
        return localIdx;
    }

    function toLocalMessageIndex(originalIdx) {
        return originalIdx;
    }

    function positionListViewAtIndex(originalIdx, mode) {
        if (!msgListViewRef || !messages) return;
        if (originalIdx < 0 || originalIdx >= messages.length) return;
        let localIdx = toLocalMessageIndex(originalIdx);
        msgListViewRef.currentIndex = localIdx;
        msgListViewRef.positionViewAtIndex(localIdx, mode);
    }

    function renameCurrentSession(newTitle) {
        return ChatEngine.renameCurrentSession(newTitle);
    }

    function startSessionRename(sessionId) {
        return ChatEngine.startSessionRename(sessionId);
    }

    function cancelSessionRename() {
        return ChatEngine.cancelSessionRename();
    }

    function saveSessionRename(sessionId) {
        return ChatEngine.saveSessionRename(sessionId);
    }

    function deleteSession(sessionId) {
        return ChatEngine.deleteSession(sessionId);
    }

    function deleteMessage(index) {
        return ChatEngine.deleteMessage(index);
    }

    function isLatestUserMessage(index) {
        return ChatEngine.isLatestUserMessage(index);
    }

    function hasSubsequentAssistantMessage(index) {
        return ChatEngine.hasSubsequentAssistantMessage(index);
    }

    function regenerateReply(index, type) {
        return ChatEngine.regenerateReply(index, type);
    }

    function saveEditedMessage() {
        return ChatEngine.saveEditedMessage();
    }

    function openCodeBaseUrl() {
        return ChatEngine.openCodeBaseUrl();
    }

    function currentOpenCodeSessionId() {
        return ChatEngine.currentOpenCodeSessionId();
    }

    function setCurrentOpenCodeSessionId(remoteSessionId) {
        return ChatEngine.setCurrentOpenCodeSessionId(remoteSessionId);
    }

    function clearCurrentOpenCodeSessionIfNeeded() {
        return ChatEngine.clearCurrentOpenCodeSessionIfNeeded();
    }

    function getSessionProperty(sessionId, key, defaultValue) {
        return ChatEngine.getSessionProperty(sessionId, key, defaultValue);
    }

    function setSessionProperty(sessionId, key, value) {
        return ChatEngine.setSessionProperty(sessionId, key, value);
    }

    function appendCompactPromptMessage(chatId) {
        return ChatEngine.appendCompactPromptMessage(chatId);
    }

    function respondToCompactRequest(msgIndex, approved) {
        return ChatEngine.respondToCompactRequest(msgIndex, approved);
    }

    function touchSessionsList(chatId) {
        return ChatEngine.touchSessionsList(chatId);
    }

    function checkAndAutoCompact(sessionId) {
        return ChatEngine.checkAndAutoCompact(sessionId);
    }

    function compactSessionContext(sessionId) {
        return ChatEngine.compactSessionContext(sessionId);
    }

    function sendBackgroundSummarizationRequest(sId, promptText, count) {
        return ChatEngine.sendBackgroundSummarizationRequest(sId, promptText, count);
    }

    function updateAutocomplete() {
        return ChatEngine.updateAutocomplete();
    }

    function updateMessageMetadata() {
        return ChatEngine.updateMessageMetadata();
    }

    function extractReadableError(prefix, errObj, fallbackText) {
        return ChatEngine.extractReadableError(prefix, errObj, fallbackText);
    }

    function beginAssistantStreaming(modelLabel) {
        return ChatEngine.beginAssistantStreaming(modelLabel);
    }

    function updateAssistantStreamingContent(text, modelLabel) {
        return ChatEngine.updateAssistantStreamingContent(text, modelLabel);
    }

    function finishOpenCodeRequest() {
        return ChatEngine.finishOpenCodeRequest();
    }

    // Handle slash commands in OpenCode mode.
    // Commands are dispatched to the appropriate handler:
    //  - /help, /session, /stats → local inline info (no server needed)
    //  - /models                 → REST API GET /v1/models
    //  - /version                → opencode --version (real CLI flag)
    //  - /export                 → syncOpenCodeSessionHistory() (REST API)
    //  - TUI-only commands       → friendly explanation shown inline
    function runLocalOpenCodeCommand(cmdText) {
        return ChatEngine.runLocalOpenCodeCommand(cmdText);
    }

    function syncOpenCodeSessionHistory() {
        return ChatEngine.syncOpenCodeSessionHistory();
    }

    function ensureOpenCodeEventStream() {
        return ChatEngine.ensureOpenCodeEventStream();
    }

    function handleOpenCodeEvent(eventObj) {
        return ChatEngine.handleOpenCodeEvent(eventObj);
    }

    function appendSystemMessageToSession(chatId, text) {
        return ChatEngine.appendSystemMessageToSession(chatId, text);
    }

    function removeMessageFromSessionByTimestamp(chatId, timestamp) {
        return ChatEngine.removeMessageFromSessionByTimestamp(chatId, timestamp);
    }

    function scheduleMessageRemoval(chatId, timestamp, delayMs) {
        return ChatEngine.scheduleMessageRemoval(chatId, timestamp, delayMs);
    }

    function setOpenCodeSessionIdForChatId(chatId, remoteSessionId) {
        return ChatEngine.setOpenCodeSessionIdForChatId(chatId, remoteSessionId);
    }

    function ensureOpenCodeSessionForChatId(chatId, successCallback, failureCallback) {
        return ChatEngine.ensureOpenCodeSessionForChatId(chatId, successCallback, failureCallback);
    }

    function ensureCurrentOpenCodeSession(successCallback, failureCallback) {
        return ChatEngine.ensureCurrentOpenCodeSession(successCallback, failureCallback);
    }

    function ensureOpenCodeServerRunning(chatId, successCallback, failureCallback) {
        return ChatEngine.ensureOpenCodeServerRunning(chatId, successCallback, failureCallback);
    }

    function doOpenCodeRequest() {
        return ChatEngine.doOpenCodeRequest();
    }

    function scrollToBottom() {
        return ChatEngine.scrollToBottom();
    }

    function queueScrollToBottom() {
        return ChatEngine.queueScrollToBottom();
    }

    function scrollToMessageByTimestamp(timestamp) {
        return ChatEngine.scrollToMessageByTimestamp(timestamp);
    }

    function messageTimestampAt(index) {
        return ChatEngine.messageTimestampAt(index);
    }

    function messageDayKeyAt(index) {
        return ChatEngine.messageDayKeyAt(index);
    }

    function dayBucketLabel(ts) {
        return ChatEngine.dayBucketLabel(ts);
    }

    function countMessagesForDayKey(dayKey) {
        return ChatEngine.countMessagesForDayKey(dayKey);
    }

    function dayDividerLabelForIndex(index) {
        return ChatEngine.dayDividerLabelForIndex(index);
    }

    function formatMessageTime(message, index) {
        return ChatEngine.formatMessageTime(message, index);
    }

    function jumpOneMessageAbove() {
        return ChatEngine.jumpOneMessageAbove();
    }

    function jumpOneMessageBelow() {
        return ChatEngine.jumpOneMessageBelow();
    }

    function formatTokensUsage(tokens, cost) {
        return ChatEngine.formatTokensUsage(tokens, cost);
    }

    function pushErrorMessage(text) {
        return ChatEngine.pushErrorMessage(text);
    }

    function pushInfoMessage(text) {
        return ChatEngine.pushInfoMessage(text);
    }

    function appendUserMessage(text, role, attachments, isScheduled) {
        return ChatEngine.appendUserMessage(text, role, attachments, isScheduled);
    }

    function appendSystemMessage(text) {
        return ChatEngine.appendSystemMessage(text);
    }

    function getSchedulesForSession(sessionId) {
        return ChatEngine.getSchedulesForSession(sessionId);
    }

    function validateCurrentSendTarget() {
        return ChatEngine.validateCurrentSendTarget();
    }

    function sendMessageByIndex(index) {
        return ChatEngine.sendMessageByIndex(index);
    }

    function processNextQueuedMessage() {
        return ChatEngine.processNextQueuedMessage();
    }

    function providerDisplayName(providerId) {
        return ChatEngine.providerDisplayName(providerId);
    }

    function validateOpenCodeConfig() {
        return ChatEngine.validateOpenCodeConfig();
    }

    function validateProviderConfig(providerId, cfg) {
        return ChatEngine.validateProviderConfig(providerId, cfg);
    }

    function sendMessage() {
        return ChatEngine.sendMessage();
    }

    function getProviderConfig(provider) {
        return ChatEngine.getProviderConfig(provider);
    }

    function translate(text) {
        return ChatEngine.translate(text);
    }

    function isSessionScheduled(sessionId, messagesList) {
        return ChatEngine.isSessionScheduled(sessionId, messagesList);
    }

    function buildEffectiveSystemPrompt(sessionId) {
        return ChatEngine.buildEffectiveSystemPrompt(sessionId);
    }

    function injectMemoriesToUserMessage(contentVal, sessionId) {
        return ChatEngine.injectMemoriesToUserMessage(contentVal, sessionId);
    }

    // Returns a filtered, context-limited list of {role, content} pairs.
    // System-status bubbles (error, schedules_list, info …) are excluded.
    // Messages before the compacted boundary are excluded.
    // Only the last N user/assistant messages are kept (N = per-session override OR global limit).
    function buildContextWindow(messagesList, sessionId) {
        return ChatEngine.buildContextWindow(messagesList, sessionId);
    }

    function buildOpenAICompatPayload() {
        return ChatEngine.buildOpenAICompatPayload();
    }

    function buildAnthropicPayload() {
        return ChatEngine.buildAnthropicPayload();
    }

    function buildOpenAICompatPayloadForMessages(messagesList, chatId) {
        return ChatEngine.buildOpenAICompatPayloadForMessages(messagesList, chatId);
    }

    function buildAnthropicPayloadForMessages(messagesList, chatId) {
        return ChatEngine.buildAnthropicPayloadForMessages(messagesList, chatId);
    }

    function _buildMessageArray(messagesList, chatId, format) {
        return ChatEngine._buildMessageArray(messagesList, chatId, format);
    }

    function appendMessageToSession(chatId, msgObj) {
        return ChatEngine.appendMessageToSession(chatId, msgObj);
    }

    function handleBackgroundError(chatId, errorMsg, notify, schedId, schedName) {
        return ChatEngine.handleBackgroundError(chatId, errorMsg, notify, schedId, schedName);
    }

    function doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName) {
        return ChatEngine.doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName);
    }

    function doBackgroundOpenAICompatRequest(chatId, baseUrl, apiKey, model, extraHeaders, modelLabel, messageText, notify, schedId, schedName) {
        return ChatEngine.doBackgroundOpenAICompatRequest(chatId, baseUrl, apiKey, model, extraHeaders, modelLabel, messageText, notify, schedId, schedName);
    }

    function doBackgroundAnthropicRequest(chatId, apiKey, model, messageText, notify, schedId, schedName) {
        return ChatEngine.doBackgroundAnthropicRequest(chatId, apiKey, model, messageText, notify, schedId, schedName);
    }

    function executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName) {
        return ChatEngine.executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName);
    }

    function doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel) {
        return ChatEngine.doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel);
    }

    function doAnthropicRequest(apiKey, model) {
        return ChatEngine.doAnthropicRequest(apiKey, model);
    }

    // RequestDeduplicator wrappers
    function reqDedupKey(provider, model, text, sessionId) {
        return RequestDeduplicator.key(provider, model, text, sessionId);
    }

    function reqDedupTryClaim(key) {
        return RequestDeduplicator.tryClaim(key);
    }

    function reqDedupRelease(key) {
        RequestDeduplicator.release(key);
    }

    function triggerNotificationSound() {
        return ChatEngine.triggerNotificationSound();
    }

    function respondToPermission(permissionId, approved) {
        return ChatEngine.respondToPermission(permissionId, approved);
    }

    // Collect selected options from the question UI and submit the answer
    function submitQuestionAnswer(questionId, questions, customField) {
        return ChatEngine.submitQuestionAnswer(questionId, questions, customField);
    }

    function respondToQuestion(questionId, answerValue, isReject) {
        return ChatEngine.respondToQuestion(questionId, answerValue, isReject);
    }

    function stopStreaming() {
        return ChatEngine.stopStreaming();
    }

    function flushStreamingBuffer() {
        return ChatEngine.flushStreamingBuffer();
    }

    function flushIntermediateStreaming() {
        return ChatEngine.flushIntermediateStreaming();
    }

    function copyToClipboard(textValue) {
        return ChatEngine.copyToClipboard(textValue);
    }

    function convertMarkdownToHtml(markdown) {
        return ChatEngine.convertMarkdownToHtml(markdown);
    }

    function fileIconName(filename) {
        return ChatEngine.fileIconName(filename);
    }

    function removeAttachedFile(index) {
        return ChatEngine.removeAttachedFile(index);
    }

    function getDocExtractorPath() {
        return ChatEngine.getDocExtractorPath();
    }

    function getHelperPath() {
        return ChatEngine.getHelperPath();
    }

    function getScriptsPath() {
        return ChatEngine.getScriptsPath();
    }

    function attachFile(fileUrl) {
        return ChatEngine.attachFile(fileUrl);
    }

    // Split raw markdown into typed blocks: {type:"text"|"code"|"table", content, lang}
    function parseMessageBlocks(markdown) {
        return ChatEngine.parseMessageBlocks(markdown);
    }

    // Convert markdown table to CSV string
    function tableMarkdownToCsv(tableMarkdown) {
        return ChatEngine.tableMarkdownToCsv(tableMarkdown);
    }

    function buildMessageContent(text, attachments, apiType) {
        return ChatEngine.buildMessageContent(text, attachments, apiType);
    }

    function checkClipboardForAttachments() {
        return ChatEngine.checkClipboardForAttachments();
    }

    function readClipboardText() {
        return ChatEngine.readClipboardText();
    }

    function applyKWalletKeyToMemory(targetId, secretValue) {
        return ChatEngine.applyKWalletKeyToMemory(targetId, secretValue);
    }

    function walletBulkReadCommand(walletName) {
        return ChatEngine.walletBulkReadCommand(walletName);
    }

    function triggerKWalletCallbacks(success, errorMsg) {
        return ChatEngine.triggerKWalletCallbacks(success, errorMsg);
    }

    function loadKWalletKeysIfNeeded(onSuccess, onFailure) {
        return ChatEngine.loadKWalletKeysIfNeeded(onSuccess, onFailure);
    }

    // Resets all KWallet failure state so that the next call to
    // loadKWalletKeysIfNeeded() can try again. Called from the
    // "Refresh from KWallet" button in settings after a permanent fail.
    function resetKwalletFailState() {
        root.kwalletPermanentlyFailed = false;
        root.kwalletFailReason = "";
        root.kwalletOpenAttempts = 0;
        root.kwalletLoading = false;
        root.kwalletKeysLoaded = false;
    }

    function performExportChat(filePath) {
        return ChatEngine.performExportChat(filePath);
    }

    function removeLastErrorMessages() {
        return ChatEngine.removeLastErrorMessages();
    }

    function retryLastFailedMessage() {
        return ChatEngine.retryLastFailedMessage();
    }

    function resetOpenCodeIdleKillTimer() {
        return ChatEngine.resetOpenCodeIdleKillTimer();
    }

    // Voice (TTS/STT) proxy functions — called by FullRepresentation.qml
    function triggerTts(text) {
        return ChatEngine.triggerTts(text);
    }
    function startVoiceRecording() {
        return ChatEngine.startVoiceRecording();
    }
    function stopVoiceRecording() {
        return ChatEngine.stopVoiceRecording();
    }
    function stopTts() {
        return ChatEngine.stopTts();
    }
    function pauseTts() {
        return ChatEngine.pauseTts();
    }
    function resumeTts() {
        return ChatEngine.resumeTts();
    }
    function makeScheduleEntryId() {
        return SessionManager.makeScheduleEntryId();
    }

    onConfigOpenCodeAutoKillChanged: {
        resetOpenCodeIdleKillTimer();
    }
    onConfigOpenCodeAutoKillMinutesChanged: {
        resetOpenCodeIdleKillTimer();
    }

    onConfigCustomHistoryPathChanged: {
        let newPath = configCustomHistoryPath.trim();
        if (newPath !== root.activeHistoryPath) {
            migrateHistory(root.activeHistoryPath, newPath);
            root.activeHistoryPath = newPath;
        }
    }
    onConfigUseOpenCodeChanged: {
        if (root.messages.length === 0) {
            root.openCodeMode = configUseOpenCode;
            setCurrentSessionSource(root.openCodeMode ? "opencode" : "provider");
        }
    }
    onConfigKeyStorageModeChanged: {
        if (configKeyStorageMode === 2) {
            root.kwalletKeysLoaded = false;
            root.kwalletOpenAttempts = 0;
            root.kwalletPermanentlyFailed = false;
            root.kwalletFailReason = "";
            // Loaded on demand when sending a message or opening settings.
        }
    }
    onConfigResponseLengthChanged: {
        // Response length preference changed; applies on next send
    }
    onCurrentSessionIdChanged: {
        if (persistSessionsDebounce.running) {
            persistSessionsDebounce.stop();
            root.flushPersistSessions();
        }
        resetOpenCodeIdleKillTimer();
        root._lastMetaIdx = -1;
        root._lastParsedMsgIdx = -1;
    }
    Plasmoid.title: plasmoid.configuration.appDisplayName || "KDE AI Chat"
    preferredRepresentation: compactRepresentation
    onOpenCodeModeChanged: {
        resetOpenCodeIdleKillTimer();
        if (!openCodeMode) {
            // Loaded on demand when sending a message.
        } else {
            if (plasmoid.configuration.autoStartOpenCodeServer)
                autoStartOpenCodeTimer.start();

        }
    }
    onExpandedChanged: function() {
        if (expanded) {
            root.focusInput();
            root.userScrolledUp = false;
            checkAndMarkCurrentSessionAsRead();
            Qt.callLater(function() {
                if (root.msgListViewRef && root.msgListViewRef.count > 0)
                    root.msgListViewRef.positionViewAtEnd();
            });
        }
    }
    onHistoryOnlyModeChanged: {
        if (!historyOnlyMode) {
            root.focusInput();
            checkAndMarkCurrentSessionAsRead();
        }
    }
    Component.onCompleted: {
        root.openCodeMode = plasmoid.configuration.useOpenCode;
        // Do not load KWallet keys on startup to prevent password popup spam.
        // They will be loaded on demand.

        let customDir = (plasmoid.configuration.customHistoryPath || "").trim();
        root.activeHistoryPath = customDir;
        if (customDir !== "") {
            let fullPath = getHistoryFilePath(customDir);
            let safePath = Sec.validateFilePath(fullPath);
            if (safePath !== "") {
                let readCmd = "python3 -c \"import base64, os; path=os.path.expanduser(" + Sec.quoteForShell(safePath) + "); print(base64.b64encode(open(path, 'rb').read()).decode('utf-8') if os.path.exists(path) else '')\"";
                customStorageDs.connectSource(readCmd + " #custom-history-read-" + Date.now());
            } else {
                loadSessions();
            }
        } else {
            loadSessions();
        }
        // Auto-start OpenCode server if the feature is enabled
        if (root.openCodeMode && plasmoid.configuration.autoStartOpenCodeServer) {
            autoStartOpenCodeTimer.start();
            resetOpenCodeIdleKillTimer();
        }
        // Auto-start scheduler if the autoStart is enabled in settings
        if (plasmoid.configuration.schedulerAutoStart) {
            plasmoid.configuration.schedulerEnabled = true;
            let schedulerScriptPath = StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/kdeaichat/kde-ai-scheduler.py";
            // The auto-start snippet is built from a hard-coded template;
            // only the writable XDG path is interpolated, so we route it
            // through the file-path validator and the shell-quote helper.
            let safeSchedulerPath = Sec.validateFilePath(schedulerScriptPath);
            let startCmd = "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || " + "(pkill -f kde-ai-scheduler.py; sleep 0.5; " + "python3 " + Sec.quoteForShell(safeSchedulerPath) + " &) ; " + "echo SCHED_AUTOSTART_OK";
            schedulerDs.connectSource("sh -c '" + startCmd.replace(/'/g, "'\\''") + "' #sched-startup");
        }
        checkAndMarkCurrentSessionAsRead();
    }
    // Track the highest index we have fully parsed so non-streaming updates
    // only scan new messages rather than the full list every time.
    property int _lastParsedMsgIdx: -1
    property int _lastMetaIdx: -1
    property int _msgVersion: 0

    onMessagesChanged: {
        root.updateMessageMetadata();
        if (root.streamingResponse) {
            return;
        }
        if (root.messages) {
            let startIdx = (root._lastParsedMsgIdx >= 0 && root._lastParsedMsgIdx < root.messages.length)
                ? root._lastParsedMsgIdx : 0;
            if (startIdx === 0 && root.messages.length > 0 && root.messages[0].blocks) {
                root._lastParsedMsgIdx = root.messages.length;
            } else {
                for (let i = startIdx; i < root.messages.length; i++) {
                    let m = root.messages[i];
                    if (m) ChatEngine.precomputeBlocksAndHtmlForMessage(m);
                }
                root._lastParsedMsgIdx = root.messages.length;
            }
        } else { root._lastParsedMsgIdx = -1; }
        Qt.callLater(checkAndMarkCurrentSessionAsRead);
        if (!root.historyOnlyMode && !root.userScrolledUp) root.queueScrollToBottom();
    }

    P5Support.DataSource {
        id: soundDs
        engine: "executable"
        connectedSources: []
    }

    P5Support.DataSource {
        id: clipboardDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: schedulerDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = (data["stdout"] || "").trim();
            disconnectSource(sourceName);
            if (sourceName.indexOf("#sched-poll") >= 0)
                root.schedPolling = false;

            if (sourceName.indexOf("#sched-delete") >= 0 || sourceName.indexOf("#sched-save") >= 0 || sourceName.indexOf("#sched-toggle") >= 0)
                schedulerPollTimer.triggered();

            if (stdout !== "") {
                try {
                    let parsed = JSON.parse(stdout);
                    if (parsed && Array.isArray(parsed.schedules))
                        root.schedulesList = parsed.schedules;

                    let triggers = (parsed && parsed.pending) || [];
                    if (Array.isArray(triggers) && triggers.length > 0) {
                        for (let i = 0; i < triggers.length; i++) {
                            let t = triggers[i];
                            if (t && t.message) {
                                let cid = t.chatId || "";
                                if (cid === "" || cid === "new") {
                                    root.createSession(true);
                                    cid = root.currentSessionId;
                                }
                                root.injectScheduledMessage(cid, t.message, t.notify, t.id, t.name);
                            }
                        }
                    }
                } catch (e) {
                    debugLog("[KAI-DEBUG] Failed to parse poll data:", e);
                }
            }
        }
    }

    Timer {
        id: openCodeReconnectTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.openCodeMode)
                root.ensureOpenCodeEventStream();
        }
    }

    Timer {
        id: persistSessionsDebounce
        interval: 3000
        repeat: false
        onTriggered: root.flushPersistSessions()
    }

    Timer {
        id: deferSaveStateTimer
        interval: 300
        repeat: false
        onTriggered: {
            root.clearCurrentOpenCodeSessionIfNeeded();
            root.saveCurrentSessionState(true);
        }
    }

    Timer {
        id: streamingBatchTimer
        interval: 120
        repeat: false
        onTriggered: root.flushIntermediateStreaming()
    }

    Timer {
        id: sendMessageDelayTimer
        interval: 50
        repeat: false
        property int messageIndex: -1
        onTriggered: {
            if (messageIndex >= 0) {
                ChatEngine.sendMessageByIndex(messageIndex);
            }
        }
    }

    Timer {
        id: openCodeIdleKillTimer
        interval: 300000 // 5 minutes
        repeat: false
        onTriggered: {
            if (root.openCodeMode && plasmoid.configuration.autoStartOpenCodeServer && root.configOpenCodeAutoKill) {
                let pidfile = '"${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).pid"';
                let userStop = (plasmoid.configuration.openCodeStopCommand || "").trim();
                let stopCmd;
                if (userStop !== "") {
                    stopCmd = userStop + ' ; rm -f ' + pidfile;
                } else {
                    stopCmd = 'if [ -f ' + pidfile + ' ]; then '
                        + 'pid=$(cat ' + pidfile + '); '
                        + 'if kill -0 "$pid" 2>/dev/null; then kill "$pid" && echo ok; '
                        + 'else echo "process already stopped"; fi; '
                        + 'rm -f ' + pidfile + '; '
                        + 'else echo "no pid file"; fi';
                }
                let envPrefix = "export PATH=\"$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/local/bin:$HOME/.opencode/bin\"; ";
                opencodeServerDs.connectSource("sh -c '" + envPrefix + stopCmd.replace(/'/g, "'\\''") + "' #autokill-opencode");
                debugLog("[KAI-DEBUG] OpenCode server auto-killed due to idleness/chat switch.");
            }
        }
    }

    Timer {
        id: openCodeStartPollTimer
        property var successCb
        property var failureCb
        property int retriesLeft: 0
        interval: 600
        repeat: false
        onTriggered: {
            retriesLeft--;
            let checkUrl = root.openCodeBaseUrl() + "/config/providers";
            let xhr = new XMLHttpRequest();
            xhr.open("GET", checkUrl, true);
            xhr.timeout = 1000;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;
                if (xhr.status >= 200 && xhr.status < 300) {
                    if (successCb)
                        successCb();
                } else {
                    if (retriesLeft > 0) {
                        openCodeStartPollTimer.start();
                    } else {
                        if (failureCb)
                            failureCb("OpenCode server failed to start (HTTP " + xhr.status + ")");
                    }
                }
            };
            xhr.onerror = function() {
                if (retriesLeft > 0) {
                    openCodeStartPollTimer.start();
                } else {
                    if (failureCb)
                        failureCb("OpenCode server failed to start (Connection refused)");
                }
            };
            xhr.ontimeout = function() {
                if (retriesLeft > 0) {
                    openCodeStartPollTimer.start();
                } else {
                    if (failureCb)
                        failureCb("OpenCode server failed to start (Timeout)");
                }
            };
            try {
                xhr.send();
            } catch (e) {
                if (retriesLeft > 0) {
                    openCodeStartPollTimer.start();
                } else {
                    if (failureCb)
                        failureCb(e.toString());
                }
            }
        }
    }

    Timer {
        id: schedulerPollTimer
        interval: root.expanded ? 5000 : 15000
        repeat: true
        running: plasmoid.configuration.schedulerEnabled
        triggeredOnStart: true
        onTriggered: {
            if (root.schedPolling)
                return ;
            root.schedPolling = true;
            let cmd = "python3 " + Sec.quoteForShell(root.getHelperPath()) + " poll_pending_triggers";
            schedulerDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-poll-" + Date.now());
        }
    }

    Timer {
        id: autoStartOpenCodeTimer
        interval: 1500
        repeat: false
        onTriggered: {
            let cmd = ChatEngine.sanitizeOpenCodeStartCommand(plasmoid.configuration.openCodeStartCommand);
            let envPrefix = "export PATH=\"$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/local/bin:$HOME/.opencode/bin\"; ";
            opencodeServerDs.connectSource("sh -c '" + envPrefix + cmd.replace(/'/g, "'\\''") + "' #autostart-opencode");
        }
    }

    P5Support.DataSource {
        id: opencodeServerDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: fileReaderDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let exitCode = data["exit code"];
            let stdout = data["stdout"] || "";
            let stderr = data["stderr"] || "";
            if (sourceName.indexOf("--clipboard") !== -1) {
                if (exitCode === 0 && stderr.trim() === "") {
                    try {
                        let res = JSON.parse(stdout);
                        if (res.status === "success") {
                            let currentFiles = root.attachedFiles.slice();
                            if (res.mode === "files" && res.files) {
                                for (let f = 0; f < res.files.length; f++) {
                                    let fInfo = res.files[f];
                                    let exists = false;
                                    for (let idx = 0; idx < currentFiles.length; idx++) {
                                        if (currentFiles[idx].path === fInfo.path) {
                                            exists = true;
                                            break;
                                        }
                                    }
                                    if (!exists) {
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
                                }
                            } else if (res.mode === "image" && res.file) {
                                let fInfo = res.file;
                                let exists = false;
                                for (let idx = 0; idx < currentFiles.length; idx++) {
                                    if (currentFiles[idx].path === fInfo.path) {
                                        exists = true;
                                        break;
                                    }
                                }
                                if (!exists) {
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
                            }
                            root.attachedFiles = currentFiles;
                        }
                    } catch (e) {
                        root.reportParseFailure("Failed to parse clipboard data", e);
                    }
                }
                disconnectSource(sourceName);
                return ;
            }
            let matchedIndex = -1;
            let files = root.attachedFiles.slice();
            for (let i = 0; i < files.length; i++) {
                let filePath = files[i].path;
                if (sourceName.indexOf(filePath) !== -1) {
                    matchedIndex = i;
                    break;
                }
            }
            if (matchedIndex === -1) {
                disconnectSource(sourceName);
                return ;
            }
            let fileObj = Object.assign({}, files[matchedIndex]);
            fileObj.loading = false;
            if (exitCode !== 0 || stderr.trim() !== "") {
                fileObj.error = stderr.trim() || ("Command exited with code " + exitCode);
            } else {
                try {
                    let res = JSON.parse(stdout);
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

    P5Support.DataSource {
        id: customStorageDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let exitCode = data["exit code"];
            let stdout = data["stdout"] || "";
            if (sourceName.indexOf("#custom-history-read-") !== -1) {
                if (exitCode === 0 && stdout.trim() !== "") {
                    try {
                        let jsonStr = root.base64Decode(stdout.trim());
                        let arr = JSON.parse(jsonStr);
                        if (Array.isArray(arr)) {
                            root.sessions = root.parseSessions(arr);
                            if (root.sessions.length === 0)
                                root.createSession(true);

                            let preferred = plasmoid.configuration.lastSessionId || "";
                            let idx = root.sessionIndexById(preferred);
                            if (idx < 0)
                                idx = 0;

                            root.currentSessionId = root.sessions[idx].value;
                            root.currentSessionTitle = root.sessions[idx].text;
                            root.messages = root.sessions[idx].messages || [];
                            if (root.sessions[idx])
                                root.openCodeMode = (root.sessions[idx].source === "opencode");

                            root.sortSessionsByUpdated();
                            root.checkAndMarkCurrentSessionAsRead();
                            disconnectSource(sourceName);
                            return ;
                        }
                    } catch (e) {
                        root.reportParseFailure("Failed to parse custom history", e);
                    }
                }
                let oldJson = plasmoid.configuration.chatSessionsJson || "";
                if (oldJson !== "" && oldJson !== "[]") {
                    root.loadSessions();
                    root.persistSessions();
                } else {
                    root.loadSessions();
                }
                root.checkAndMarkCurrentSessionAsRead();
            } else if (sourceName.indexOf("#custom-history-write-") !== -1) {
                disconnectSource(sourceName);
                return;
            } else if (sourceName.indexOf("#migrate-history") !== -1) {
                if (exitCode === 0 && stdout.trim() !== "") {
                    try {
                        let decoded = root.base64Decode(stdout.trim());
                        if (!decoded || decoded === "") { disconnectSource(sourceName); return; }
                        let jsonRaw = decoded;
                        let res = JSON.parse(jsonRaw);
                        if (res.status === "ok") {
                            if (res.action === "load" && res.content) {
                                let arrVal = JSON.parse(root.base64Decode(res.content));
                                if (Array.isArray(arrVal)) {
                                    root.sessions = root.parseSessions(arrVal);
                                    if (root.sessions.length === 0)
                                        root.createSession(true);

                                    let pref = plasmoid.configuration.lastSessionId || "";
                                    let idxVal = root.sessionIndexById(pref);
                                    if (idxVal < 0)
                                        idxVal = 0;

                                    root.currentSessionId = root.sessions[idxVal].value;
                                    root.currentSessionTitle = root.sessions[idxVal].text;
                                    root.messages = root.sessions[idxVal].messages || [];
                                    if (root.sessions[idxVal])
                                        root.openCodeMode = (root.sessions[idxVal].source === "opencode");

                                    root.sortSessionsByUpdated();
                                    root.checkAndMarkCurrentSessionAsRead();
                                    root.persistSessions();
                                }
                            } else if (res.action === "write_current" || res.action === "copied" || res.action === "exported") {
                                root.persistSessions();
                            }
                        } else {
                            console.warn("Migration failed: " + res.message);
                        }
                    } catch (e) {
                        console.error("Failed to parse migration output: " + e);
                    }
                }
            } else if (sourceName.indexOf("#sessions-read-") !== -1) {
                if (exitCode === 0 && stdout.trim() !== "") {
                    try {
                        let jsonStr = root.base64Decode(stdout.trim());
                        let arr = JSON.parse(jsonStr);
                        if (Array.isArray(arr) && arr.length > 0) {
                            root.sessions = root.parseSessions(arr);
                            if (root.sessions.length === 0) {
                                root.createSession(true);
                            }
                            let preferred = plasmoid.configuration.lastSessionId || "";
                            let idx = root.sessionIndexById(preferred);
                            if (idx < 0) idx = 0;
                            root.currentSessionId = root.sessions[idx].value;
                            root.currentSessionTitle = root.sessions[idx].text;
                            root.messages = root.sessions[idx].messages || [];
                            root.precomputeBlocksForMessages(root.messages);
                            if (root.sessions[idx])
                                root.openCodeMode = (root.sessions[idx].source === "opencode");
                            root.sortSessionsByUpdated();
                            root.checkAndMarkCurrentSessionAsRead();
                        }
                    } catch (e) {
                        console.warn("[KAI] Failed to parse sessions file: " + e);
                    }
                }
            }
            disconnectSource(sourceName);
        }
    }

    FileDialog {
        id: kaiAttachFileDialog
        title: "Attach Files"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["All files (*)", "Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.svg)", "Documents (*.pdf *.docx *.odt *.rtf *.csv *.txt *.md *.json *.xml *.yaml *.yml)", "Code (*.py *.js *.ts *.rs *.go *.cpp *.c *.h *.java *.kt *.swift *.sh *.bash *.zsh *.fish *.rb *.php *.html *.css *.scss *.sql *.toml *.ini *.conf)"]
        onAccepted: function() {
            for (var i = 0; i < selectedFiles.length; i++) {
                root.attachFile(selectedFiles[i]);
            }
        }
    }

    FileDialog {
        id: kaiExportChatFileDialog
        title: "Export Chat Session"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Markdown files (*.md)", "Plain text files (*.txt)"]
        onAccepted: function() {
            var rawPath = selectedFile.toString();
            if (rawPath.indexOf("file://") === 0)
                rawPath = decodeURIComponent(rawPath.slice(7));
            root.performExportChat(rawPath);
        }
    }

    TextEdit {
        id: clipboardHelper
        width: 0
        height: 0
        opacity: 0
        activeFocusOnTab: false
    }

    P5Support.DataSource {
        id: kwalletStartupDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = data["stdout"] || "";
            if (sourceName.indexOf("kwallet-startup-load") >= 0) {
                let lines = stdout.split(/\r?\n/);
                let openFailed = false;
                let openFailedMsg = "KWallet open failed.";
                let notUnlocked = false;
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line.indexOf("__KAI_BULK__:OPEN_FAILED") === 0) {
                        openFailed = true;
                        openFailedMsg = "KWallet open failed.";
                    } else if (line.indexOf("__KAI_BULK__:NO_WALLET") === 0) {
                        openFailed = true;
                        openFailedMsg = "Configured KWallet not found.";
                    } else if (line.indexOf("__KAI_BULK__:NOT_UNLOCKED") === 0) {
                        notUnlocked = true;
                    } else if (line.indexOf("__KAI_SECRET__:") === 0) {
                        let rest = line.slice("__KAI_SECRET__:".length);
                        let sep = rest.indexOf(":");
                        if (sep > 0) {
                            let targetId = rest.slice(0, sep);
                            let secretValue = rest.slice(sep + 1);
                            root.applyKWalletKeyToMemory(targetId, secretValue);
                        }
                    }
                }
                if (notUnlocked) {
                    root.kwalletKeysLoaded = false;
                    root.kwalletLoading = false;
                    root.triggerKWalletCallbacks(false, "KWallet is locked/closed. Click 'Refresh from KWallet' in settings to unlock.");
                } else if (openFailed) {
                    root.kwalletKeysLoaded = false;
                    root.kwalletOpenAttempts++;
                    debugLog("[KAI-DEBUG] KWallet open failed (attempt " + root.kwalletOpenAttempts + " of 3)");
                    if (root.kwalletOpenAttempts >= 3) {
                        let reason = "KWallet sync failed after 3 attempts — possibly wrong password or wallet locked. Click \"Refresh from KWallet\" in settings to retry.";
                        root.kwalletPermanentlyFailed = true;
                        root.kwalletFailReason = reason;
                        root.kwalletLoading = false;
                        root.triggerKWalletCallbacks(false, reason);
                    } else {
                        root.triggerKWalletCallbacks(false, openFailedMsg);
                    }
                } else {
                    root.kwalletOpenAttempts = 0;
                    root.kwalletPermanentlyFailed = false;
                    root.kwalletFailReason = "";
                    root.kwalletKeysLoaded = true;
                    root.triggerKWalletCallbacks(true);
                }
            }
            disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: opencodeTerminalDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = data["stdout"] || "";
            let stderr = data["stderr"] || "";
            let exitCode = data["exit code"];
            if (sourceName.indexOf("opencode-cli-") >= 0) {
                let output = stdout || stderr;
                if (exitCode !== undefined && (output.indexOf("not found") >= 0 || output.indexOf("No such file") >= 0 || output === "")) {
                    root.loading = false;
                    root.finishOpenCodeRequest();
                    root.pushErrorMessage("**OpenCode is not installed or not in PATH.**\nInstall it with:\n```\nnpm install -g opencode-ai\n```\nor visit https://opencode.ai for instructions.");
                    disconnectSource(sourceName);
                    return ;
                }
                if (output !== "")
                    root.updateAssistantStreamingContent(output, "OpenCode CLI");

                if (exitCode !== undefined) {
                    root.loading = false;
                    root.finishOpenCodeRequest();
                    disconnectSource(sourceName);
                }
            } else {
                disconnectSource(sourceName);
            }
        }
    }

    Timer {
        id: openCodePollTimer
        property int retriesLeft: 0
        function startPolling() {
            retriesLeft = 15;
            start();
        }
        function checkServerStatus() {
            let xhr = new XMLHttpRequest();
            xhr.open("GET", root.openCodeBaseUrl() + "/", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;
                if (xhr.status >= 200 && xhr.status < 300) {
                    openCodePollTimer.stop();
                    root.pushInfoMessage("OpenCode server is online. Resuming thread...");
                    root.removeLastErrorMessages();
                    root.retryLastFailedMessage();
                }
            };
            xhr.onerror = function() {
            };
            try {
                xhr.send();
            } catch (e) {
            }
        }
        interval: 1000
        repeat: true
        onTriggered: {
            retriesLeft--;
            if (retriesLeft <= 0) {
                stop();
                root.pushErrorMessage("OpenCode server failed to start in time. Check logs in ${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log");
                return ;
            }
            checkServerStatus();
        }
    }

    P5Support.DataSource {
        id: voiceDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = (data["stdout"] || "").trim();
            let stderr = (data["stderr"] || "").trim();
            let exitCode = data["exit code"];
            if (stdout !== "") {
                let lines = stdout.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (!line) continue;
                    try {
                        let resp = JSON.parse(line);
                        try {
                            ChatEngine.handleVoiceResponse(resp, sourceName);
                        } catch (respErr) {
                            console.error("voiceDs: handleVoiceResponse threw for line, skipping:", respErr, line);
                        }
                    } catch (e) {
                    }
                }
            }
            if (exitCode !== undefined) {
                if (exitCode !== 0) {
                    let errMsg = stderr || ("Process exited with code " + exitCode);
                    root.pushErrorMessage("Voice helper execution failed: " + errMsg);
                }
                disconnectSource(sourceName);
            }
        }
    }

    Timer {
        id: voiceStatusPollTimer
        interval: (root.voiceSttStatus === "starting_daemon"
            || root.voiceSttStatus === "loading_model"
            || root.voiceSttStatus === "transcribing"
            || root.voiceTtsStatus === "starting_daemon") ? 500 : 1500
        repeat: true
        property int _consecutivePollFailures: 0
        readonly property int _pollFailureThreshold: 4
        running: root.voiceRecording || root.ttsPlaying

        function notePollFailure(message) {
            voiceStatusPollTimer._consecutivePollFailures++;
            if (voiceStatusPollTimer._consecutivePollFailures
                    < voiceStatusPollTimer._pollFailureThreshold) {
                return;
            }
            voiceStatusPollTimer._consecutivePollFailures = 0;
            if (root.ttsPlaying) {
                root.ttsPlaying = false;
                root.ttsPaused = false;
                root.voiceTtsStatus = message;
            } else if (root.voiceRecording) {
                root.voiceRecording = false;
                root.voiceSttStatus = "";
                root.voiceSttTestResult = "Error: " + message;
            }
        }

        onTriggered: {
            let port = root.voiceRecording ? 9015 : 9016;
            let xhr = new XMLHttpRequest();
            xhr.open("GET", "http://127.0.0.1:" + port + "/status", true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status === 200) {
                    voiceStatusPollTimer._consecutivePollFailures = 0;
                    try {
                        let resp = JSON.parse(xhr.responseText);
                        if (root.voiceRecording) {
                            ChatEngine.handleVoiceResponse({
                                "type": "stt_status",
                                "status": resp.status,
                                "countdown": resp.countdown
                            }, "");
                        } else if (root.ttsPlaying) {
                            ChatEngine.handleVoiceResponse({
                                "type": "tts_status",
                                "status": resp.status
                            }, "");
                        }
                    } catch (e) {
                    }
                    return;
                }
                voiceStatusPollTimer.notePollFailure("daemon stopped responding");
            };
            xhr.onerror = function() {
                voiceStatusPollTimer.notePollFailure("daemon unreachable");
            };
            xhr.ontimeout = xhr.onerror;
            try {
                xhr.send();
            } catch (e) {
                voiceStatusPollTimer.notePollFailure("daemon command failed");
            }
        }
    }

    Timer {
        id: voiceForceStopTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.voiceRecording) {
                root.voiceRecording = false;
                root.voiceSttStatus = "";
            }
            if (root.loading && root.streamingResponse && root.streamingContent === "") {
                root.loading = false;
                root.streamingResponse = false;
                root.activeXhr = null;
            }
        }
    }

    Timer {
        id: voiceDaemonStartTimer
        interval: 250
        repeat: true
        property int port: 9015
        property int elapsed: 0
        property var callback: null
        onTriggered: {
            elapsed += 250;
            let xhr = new XMLHttpRequest();
            xhr.open("GET", "http://127.0.0.1:" + port + "/status", true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        voiceDaemonStartTimer.stop();
                        if (callback) callback(true);
                    }
                }
            };
            try {
                xhr.send();
            } catch (e) {}

            if (elapsed >= 4000) {
                voiceDaemonStartTimer.stop();
                if (callback) callback(false);
            }
        }
    }

    Timer {
        id: voiceIdleTimer
        interval: 300000 // 5 minutes
        repeat: false
        running: true
        onTriggered: {
            root.voiceDs.connectSource("systemctl --user stop kde-ai-stt.service #stop-stt-idle-" + Date.now());
            root.voiceDs.connectSource("systemctl --user stop kde-ai-tts.service #stop-tts-idle-" + Date.now());
            console.log("KDE AI Chat: Stopped voice daemons due to 5 minutes of inactivity to save system resources.");
        }
    }

    property alias soundDs: soundDs
    property alias clipboardDs: clipboardDs
    property alias schedulerDs: schedulerDs
    property alias openCodeReconnectTimer: openCodeReconnectTimer
    property alias persistSessionsDebounce: persistSessionsDebounce
    property alias deferSaveStateTimer: deferSaveStateTimer
    property alias streamingBatchTimer: streamingBatchTimer
    property alias openCodeIdleKillTimer: openCodeIdleKillTimer
    property alias openCodeStartPollTimer: openCodeStartPollTimer
    property alias schedulerPollTimer: schedulerPollTimer
    property alias autoStartOpenCodeTimer: autoStartOpenCodeTimer
    property alias opencodeServerDs: opencodeServerDs
    property alias fileReaderDs: fileReaderDs
    property alias customStorageDs: customStorageDs
    property alias fileDialog: kaiAttachFileDialog
    property alias exportFileDialog: kaiExportChatFileDialog
    property alias clipboardHelper: clipboardHelper
    property alias kwalletStartupDs: kwalletStartupDs
    property alias opencodeTerminalDs: opencodeTerminalDs
    property alias openCodePollTimer: openCodePollTimer
    property alias voiceDs: voiceDs
    property alias sendMessageDelayTimer: sendMessageDelayTimer

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            source: "dialog-messages"
        }
    }

    fullRepresentation: FullRepresentation {
        id: fullRepresentation
    }
}
