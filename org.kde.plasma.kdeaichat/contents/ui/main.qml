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

// MONOLITHIC ARCHITECTURE (v1.2.9 style):
// - main.qml: Single root PlasmoidItem containing all UI, DataSources, Timers, and Dialogs.
//   (Previously modular: FullRepresentation.qml, SessionSidebar.qml, MessageContent.qml,
//    MainDataSources.qml — all merged here for performance and simplicity.)
// - Linked to ChatEngine.js:
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

    // DataSources and timers are direct children of root (monolithic)

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            source: "dialog-messages"
        }
    }

    fullRepresentation: Item {
        id: fullRep
    
    function requestDeleteSession(sessionId) {
        if (plasmoid.configuration.askDeleteChatConfirmation) {
            deleteChatConfirmDialog.sessionIdToDelete = sessionId;
            dontAskDeleteChatCheck.checked = false;
            deleteChatConfirmDialog.open();
        } else {
            root.deleteSession(sessionId);
        }
    }

    // Plasma popup sizing follows implicit size more reliably than Layout hints here.
    implicitWidth: root.popupPreferredWidth
    implicitHeight: root.popupPreferredHeight
    width: implicitWidth
    height: implicitHeight
    Layout.minimumWidth: 500
    Layout.minimumHeight: 620
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Component.onCompleted: {
        root.focusInput();
    }
    onVisibleChanged: {
        if (visible)
            root.focusInput();

    }
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorGroup: root.popupIsDark ? Kirigami.Theme.Dark : Kirigami.Theme.Light
    Kirigami.Theme.backgroundColor: root.popupIsDark ? "#121212" : "#ffffff"
    Kirigami.Theme.alternateBackgroundColor: root.popupIsDark ? "#1a1a1a" : "#f5f7fa"
    Kirigami.Theme.textColor: root.popupIsDark ? "#f7fafc" : "#1a202c"
    Kirigami.Theme.highlightColor: "#3182ce"

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        radius: 8
    }

    DropArea {
        id: dropArea

        anchors.fill: parent
        onEntered: function(drag) {
            if (drag.hasUrls)
                drag.accept(Qt.CopyAction);

        }
        onDropped: function(drop) {
            if (drop.hasUrls) {
                for (let i = 0; i < drop.urls.length; i++) {
                    root.attachFile(drop.urls[i]);
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
            border.color: Kirigami.Theme.highlightColor
            border.width: 2
            radius: 8
            visible: parent.containsDrag
            z: 999

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "mail-attachment"
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 48
                    implicitHeight: 48
                    color: Kirigami.Theme.highlightColor
                }

                PC3.Label {
                    text: "Drop files here to attach"
                    font.bold: true
                    font.pointSize: 14
                    color: Kirigami.Theme.highlightColor
                    Layout.alignment: Qt.AlignHCenter
                }

            }

        }

    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true

            PC3.ToolButton {
                icon.name: root.historyOnlyMode ? "go-previous-symbolic" : "view-list-icons"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.historyOnlyMode ? "Back to chat" : "Expand history"
                onClicked: root.historyOnlyMode = !root.historyOnlyMode
            }

            Item {
                Layout.fillWidth: true
            }

            ColumnLayout {
                Layout.fillWidth: false
                Layout.maximumWidth: Math.max(50, parent.width - 220)
                spacing: 0

                PC3.Label {
                    text: {
                        if (root.historyOnlyMode)
                            return (plasmoid.configuration.appDisplayName || "KDE AI Chat") + " History";

                        let rawText = root.currentSessionTitle || "New Chat";
                        if (rawText.indexOf("[FK] ") === 0)
                            rawText = rawText.substring(5);

                        return root.translate(rawText);
                    }
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    clip: true
                }



            }

            Item {
                Layout.fillWidth: true
            }

             PC3.ToolButton {
                visible: !root.historyOnlyMode
                icon.name: "document-edit"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Rename current chat"
                Accessible.name: root.translate("Rename current chat")
                Accessible.role: Accessible.Button
                Accessible.description: root.translate("Toggle renaming of the current chat session")
                onClicked: {
                    root.renamingCurrentChat = !root.renamingCurrentChat;
                    root.currentChatRenameDraft = root.currentSessionTitle || "";
                }
            }

             PC3.ToolButton {
                visible: !root.historyOnlyMode
                icon.name: "configure"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.translate("Chat settings")
                Accessible.name: root.translate("Chat settings")
                Accessible.role: Accessible.Button
                Accessible.description: root.translate("Open settings dialog for the current chat session")
                onClicked: {
                    root.debugLog("[KDE AIChat] Gear button clicked! Opening chatSettingsDialog...");
                    chatSettingsDialog.open();
                    root.debugLog("[KDE AIChat] chatSettingsDialog state: visible=" + chatSettingsDialog.visible + ", x=" + chatSettingsDialog.x + ", y=" + chatSettingsDialog.y + ", width=" + chatSettingsDialog.width + ", height=" + chatSettingsDialog.height + ", parent=" + chatSettingsDialog.parent);
                }
            }

            PC3.ToolButton {
                visible: !root.historyOnlyMode
                icon.name: "go-top"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Jump to first message"
                Accessible.name: root.translate("Jump to first message")
                Accessible.role: Accessible.Button
                Accessible.description: root.translate("Scroll to the beginning of the conversation")
                onClicked: {
                    if (root.msgListViewRef && root.msgListViewRef.count > 0) {
                        root.userScrolledUp = true;
                        root.msgListViewRef.positionViewAtBeginning();
                    }
                }
            }

            PC3.ToolButton {
                visible: !root.historyOnlyMode
                icon.name: "go-up"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Jump to one message above"
                Accessible.name: root.translate("Jump to one message above")
                Accessible.role: Accessible.Button
                Accessible.description: root.translate("Scroll to the previous message")
                onClicked: root.jumpOneMessageAbove()
            }

            PC3.ToolButton {
                visible: !root.historyOnlyMode
                icon.name: "go-down"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Jump to one message below"
                Accessible.name: root.translate("Jump to one message below")
                Accessible.role: Accessible.Button
                Accessible.description: root.translate("Scroll to the next message")
                onClicked: root.jumpOneMessageBelow()
            }

            PC3.ToolButton {
                visible: !root.historyOnlyMode
                icon.name: "go-bottom"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Jump to latest message"
                Accessible.name: root.translate("Jump to latest message")
                Accessible.role: Accessible.Button
                Accessible.description: root.translate("Scroll to the end of the conversation")
                onClicked: {
                    root.userScrolledUp = false;
                    root.scrollToBottom();
                }
            }

            PC3.ToolButton {
                visible: !root.historyOnlyMode
                icon.name: "edit-clear-all"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.translate("Clear current chat history")
                Accessible.name: root.translate("Clear current chat history")
                Accessible.role: Accessible.Button
                Accessible.description: root.translate("Delete all messages in the current session")
                enabled: !root.loading && root.messages.length > 0
                onClicked: {
                    if (plasmoid.configuration.askClearChatConfirmation) {
                        dontAskClearChatCheck.checked = false;
                        clearChatConfirmDialog.open();
                    } else {
                        root.messages = [];
                        root.editingMessageIndex = -1;
                        root.editingDraft = "";
                        root.clearCurrentOpenCodeSessionIfNeeded();
                        root.saveCurrentSessionState(true);
                    }
                }
            }

            PC3.ToolButton {
                visible: !root.historyOnlyMode && root.messages.length > 0
                icon.name: "document-export"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.translate("Export chat session")
                Accessible.name: root.translate("Export chat session")
                Accessible.role: Accessible.Button
                Accessible.description: root.translate("Export the current conversation to a Markdown file")
                enabled: !root.loading
                onClicked: {
                    let cleanTitle = (root.currentSessionTitle || "New Chat").replace(/[\/\?<>\\:\*\|":\s]+/g, "_");
                    let now = new Date();
                    let year = now.getFullYear();
                    let month = String(now.getMonth() + 1).padStart(2, "0");
                    let day = String(now.getDate()).padStart(2, "0");
                    let hour = String(now.getHours()).padStart(2, "0");
                    let min = String(now.getMinutes()).padStart(2, "0");
                    let sec = String(now.getSeconds()).padStart(2, "0");
                    let timestamp = year + "-" + month + "-" + day + "_" + hour + "-" + min + "-" + sec;
                    exportFileDialog.currentFile = "file://" + StandardPaths.writableLocation(StandardPaths.DocumentsLocation) + "/" + cleanTitle + "_" + timestamp + ".md";
                    exportFileDialog.open();
                }
            }

            PC3.ToolButton {
                icon.name: "list-add"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.translate("New chat")
                Accessible.name: root.translate("New chat")
                Accessible.role: Accessible.Button
                Accessible.description: root.translate("Create a new chat conversation")
                enabled: !root.loading
                onClicked: root.createSession(true)
            }

        }

        RowLayout {
            visible: !root.historyOnlyMode && root.openCodeMode && root.messages.length > 0
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                Layout.fillWidth: true
                text: root.currentOpenCodeSessionId() !== "" ? root.translate("OpenCode Session: <b>%1...</b>").replace("%1", root.currentOpenCodeSessionId().substring(0, 10)) : root.translate("OpenCode Session: <b>Not started</b>")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.italic: true
                opacity: 0.85
                elide: Text.ElideRight
                textFormat: Text.RichText
            }

            PC3.ToolButton {
                icon.name: "utilities-terminal"
                implicitWidth: Kirigami.Units.gridUnit * 1.8
                implicitHeight: Kirigami.Units.gridUnit * 1.8
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.translate("Open OpenCode TUI in a terminal window")
                onClicked: {
                    let opencodeSessionFile = StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/kdeaichat/.opencode-session";
                    let safeSessionFile = Sec.validateFilePath(opencodeSessionFile);
                    root.ensureCurrentOpenCodeSession(function(sid) {
                        let opencodeCmd = "opencode" + (sid !== "" ? " --session " + sid : "");
                        clipboardHelper.text = opencodeCmd;
                        clipboardHelper.selectAll();
                        clipboardHelper.copy();
                        let safeSid = Sec.validateSessionId(sid);
                        let safeScriptsPath = Sec.validateFilePath(getScriptsPath());
                        let termCmd = "echo -n " + Sec.quoteForShell(safeSid) + " > " + Sec.quoteForShell(safeSessionFile) + " && konsole --workdir " + Sec.quoteForShell(safeScriptsPath) + " -e bash ./opencode-terminal.sh";
                        customStorageDs.connectSource(termCmd + " #opencode-terminal-launch");
                    }, function(err) {
                        root.pushErrorMessage(err);
                        clipboardHelper.text = "opencode";
                        clipboardHelper.selectAll();
                        clipboardHelper.copy();
                        let safeScriptsPath = Sec.validateFilePath(getScriptsPath());
                        let termCmd = "echo -n " + Sec.quoteForShell("") + " > " + Sec.quoteForShell(safeSessionFile) + " && konsole --workdir " + Sec.quoteForShell(safeScriptsPath) + " -e bash ./opencode-terminal.sh";
                        customStorageDs.connectSource(termCmd + " #opencode-terminal-launch");
                    });
                }
            }

            PC3.ToolButton {
                icon.name: "view-refresh"
                implicitWidth: Kirigami.Units.gridUnit * 1.8
                implicitHeight: Kirigami.Units.gridUnit * 1.8
                enabled: !root.loading && root.currentOpenCodeSessionId() !== ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.translate("Sync chat history from this OpenCode session")
                onClicked: root.syncOpenCodeSessionHistory()
            }

        }

        RowLayout {
            visible: !root.historyOnlyMode && root.renamingCurrentChat
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                Layout.fillWidth: true
                text: root.currentChatRenameDraft
                onTextChanged: root.currentChatRenameDraft = text
                onAccepted: {
                    root.renameCurrentSession(root.currentChatRenameDraft);
                    root.renamingCurrentChat = false;
                }
            }

            PC3.ToolButton {
                icon.name: "dialog-ok-apply"
                onClicked: {
                    root.renameCurrentSession(root.currentChatRenameDraft);
                    root.renamingCurrentChat = false;
                }
            }

            PC3.ToolButton {
                icon.name: "dialog-cancel"
                onClicked: root.renamingCurrentChat = false
            }

        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.historyOnlyMode ? 1 : 0

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        visible: {
                            let idx = root.sessionIndexById(root.currentSessionId);
                            return idx >= 0 && root.sessions[idx].parentSessionId !== undefined && root.sessions[idx].parentSessionId !== "";
                        }
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        Layout.rightMargin: Kirigami.Units.smallSpacing
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            Layout.fillWidth: true
                            height: Math.max(32, parentLinkText.implicitHeight + Kirigami.Units.smallSpacing * 3)
                            color: Qt.rgba(0.48, 0.2, 0.92, 0.08)
                            border.color: Qt.rgba(0.48, 0.2, 0.92, 0.25)
                            border.width: 1
                            radius: 6

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Kirigami.Units.mediumSpacing
                                anchors.rightMargin: Kirigami.Units.mediumSpacing
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: "fork"
                                    implicitWidth: Kirigami.Units.iconSizes.small
                                    implicitHeight: Kirigami.Units.iconSizes.small
                                }

                                PC3.Label {
                                    id: parentLinkText

                                    Layout.fillWidth: true
                                    text: {
                                        let idx = root.sessionIndexById(root.currentSessionId);
                                        if (idx < 0)
                                            return "";

                                        let parentTitle = root.sessions[idx].parentSessionTitle || "Original Chat";
                                        if (parentTitle.indexOf("[FK] ") === 0)
                                            parentTitle = parentTitle.substring(5);

                                        let parentId = root.sessions[idx].parentSessionId;
                                        let exists = parentId && root.sessionIndexById(parentId) >= 0;
                                        if (exists)
                                            return root.translate("Forked from:") + " <b>" + root.translate(parentTitle) + "</b>";
                                        else
                                            return root.translate("Forked from:") + " <b>" + root.translate(parentTitle) + "</b> <font color='gray'>(" + root.translate("deleted") + ")</font>";
                                    }
                                    textFormat: Text.RichText
                                    elide: Text.ElideRight
                                }

                                PC3.Button {
                                    text: "Go to Original Chat"
                                    icon.name: "go-jump"
                                    onClicked: {
                                        let idx = root.sessionIndexById(root.currentSessionId);
                                        if (idx >= 0) {
                                            let parentId = root.sessions[idx].parentSessionId;
                                            if (root.sessionIndexById(parentId) >= 0) {
                                                root.switchSession(parentId);
                                                root.historyOnlyMode = false;
                                            } else {
                                                root.appendSystemMessage("The original chat no longer exists.");
                                            }
                                        }
                                    }
                                }

                            }

                        }

                    }

                    RowLayout {
                        id: searchBar
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        Layout.rightMargin: Kirigami.Units.smallSpacing
                        visible: root.searchBarActive
                        spacing: Kirigami.Units.smallSpacing
                        onVisibleChanged: {
                            if (visible) {
                                Qt.callLater(function() {
                                    searchInput.forceActiveFocus();
                                });
                            }
                        }

                        QQC2.TextField {
                            id: searchInput
                            Layout.fillWidth: true
                            placeholderText: root.translate("Search messages...")
                            selectByMouse: true
                            onTextChanged: {
                                root.searchQuery = text;
                                if (root.searchMatches.length > 0) {
                                    root.currentSearchMatchIndex = 0;
                                    root.positionListViewAtIndex(root.searchMatches[0], ListView.Center);
                                } else {
                                    root.currentSearchMatchIndex = -1;
                                }
                            }
                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                                    event.accepted = true;
                                    if (event.modifiers & Qt.ShiftModifier) {
                                        root.searchPrev();
                                    } else {
                                        root.searchNext();
                                    }
                                } else if (event.key === Qt.Key_Escape) {
                                    event.accepted = true;
                                    root.searchBarActive = false;
                                    root.searchQuery = "";
                                    root.focusInput();
                                }
                            }
                        }

                        PC3.Label {
                            text: {
                                if (root.searchQuery.trim() === "") return "";
                                let count = root.searchMatches.length;
                                if (count === 0) return root.translate("No matches");
                                return (root.currentSearchMatchIndex + 1) + " " + root.translate("of") + " " + count;
                            }
                            opacity: 0.7
                            Layout.alignment: Qt.AlignVCenter
                        }

                        PC3.ToolButton {
                            icon.name: "go-up"
                            enabled: root.searchMatches.length > 0
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: root.translate("Previous match (Shift+Enter)")
                            onClicked: root.searchPrev()
                        }

                        PC3.ToolButton {
                            icon.name: "go-down"
                            enabled: root.searchMatches.length > 0
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: root.translate("Next match (Enter)")
                            onClicked: root.searchNext()
                        }

                        PC3.ToolButton {
                            icon.name: "window-close"
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: root.translate("Close search (Esc)")
                            onClicked: {
                                root.searchBarActive = false;
                                root.searchQuery = "";
                                root.focusInput();
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: Kirigami.Theme.alternateBackgroundColor
                        clip: true

                        ListView {
                            id: msgList

                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Kirigami.Units.smallSpacing
                            anchors.topMargin: Kirigami.Units.smallSpacing
                            anchors.bottomMargin: Kirigami.Units.smallSpacing
                            anchors.rightMargin: Kirigami.Units.gridUnit
                            verticalLayoutDirection: ListView.TopToBottom
                            model: root.messages
                            spacing: Kirigami.Units.largeSpacing
                            clip: true
                            cacheBuffer: 20000
                            reuseItems: true
                            // Tweaked scroll velocities for smoother dragging
                            maximumFlickVelocity: 2500
                            flickDeceleration: 1500
                            boundsBehavior: Flickable.StopAtBounds
                            Component.onCompleted: {
                                root.msgListViewRef = msgList;
                                Qt.callLater(function() {
                                    if (msgList.count > 0) msgList.positionViewAtEnd();
                                });
                            }
                            onMovementStarted: {
                                if (!msgList.atYEnd)
                                    root.userScrolledUp = true;
                            }
                            onAtYEndChanged: {
                                if (msgList.atYEnd)
                                    root.userScrolledUp = false;
                            }
                            onContentYChanged: {
                                if (!msgList.atYEnd && (msgList.moving || msgList.dragging || vbar.pressed || vbar.active)) {
                                    if (!root.userScrolledUp)
                                        root.userScrolledUp = true;
                                }
                            }

                            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                                id: vbar
                                policy: QQC2.ScrollBar.AsNeeded
                            }

                            footer: Item {
                                id: footerItem
                                width: msgList.width
                                height: root.streamingResponse && root.streamingContent !== "" ? footerBubble.implicitHeight + Kirigami.Units.largeSpacing : 0
                                visible: root.streamingResponse && root.streamingContent !== ""

                                Rectangle {
                                    id: footerBubble
                                    width: Math.min(msgList.width * 0.76, 560)
                                    implicitHeight: footerCol.implicitHeight + Kirigami.Units.largeSpacing
                                    radius: 10
                                    color: Kirigami.Theme.backgroundColor
                                    border.width: 1
                                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
                                    anchors.left: parent.left
                                    anchors.margins: Kirigami.Units.smallSpacing

                                    Column {
                                        id: footerCol
                                        width: parent.width - Kirigami.Units.largeSpacing
                                        x: Kirigami.Units.smallSpacing + Kirigami.Units.smallSpacing / 2
                                        y: Kirigami.Units.smallSpacing + Kirigami.Units.smallSpacing / 2
                                        spacing: Kirigami.Units.smallSpacing

                                        Row {
                                            width: parent.width
                                            spacing: Kirigami.Units.smallSpacing
                                            PC3.Label {
                                                text: "AI"
                                                font.bold: true
                                            }
                                            PC3.Label {
                                                text: root.streamingModel ? ("(" + root.streamingModel + ")") : ""
                                                opacity: 0.6
                                                visible: text !== ""
                                            }
                                        }

                                         // Render streaming text as plain for performance —
                                         // Markdown is applied only when the message is committed.
                                         Text {
                                             width: parent.width
                                             wrapMode: Text.Wrap
                                             textFormat: Text.PlainText
                                             text: root.streamingContent
                                             color: Kirigami.Theme.textColor
                                             font: Kirigami.Theme.defaultFont
                                         }

                                        // Context items (tool invocations) display in footer
                                        Column {
                                            visible: root.streamingContextItems.length > 0
                                            width: parent.width
                                            spacing: 2

                                            Row {
                                                spacing: Kirigami.Units.smallSpacing
                                                Kirigami.Icon {
                                                    source: "code-context"
                                                    width: 14
                                                    height: 14
                                                    opacity: 0.6
                                                }
                                                PC3.Label {
                                                    text: root.translate("Thinking process...")
                                                    font.italic: true
                                                    font.pointSize: 8
                                                    opacity: 0.6
                                                }
                                            }

                                            Repeater {
                                                model: root.streamingContextItems
                                                delegate: PC3.Label {
                                                    width: parent.width
                                                    text: "• " + modelData
                                                    font.pointSize: 8
                                                    opacity: 0.5
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            delegate: Item {
                                required property var modelData
                                required property int index
                                readonly property int originalIndex: index
                                readonly property bool showDayHeader: modelData.showDayHeader || false

                                property bool isSearchMatch: root.searchBarActive && root.searchQuery.trim() !== "" && modelData.searchText && modelData.searchText.indexOf(root.searchQuery.trim().toLowerCase()) >= 0
                                property bool isCurrentSearchMatch: isSearchMatch && root.searchMatches[root.currentSearchMatchIndex] === originalIndex

                                 // Cache expensive per-role lookups as readonly properties so they are
                                // only recomputed when the role changes, not on every frame repaint.
                                readonly property bool roleIsUser: modelData.role === "user"
                                readonly property bool roleIsQueued: modelData.role === "queued"
                                readonly property bool roleIsError: modelData.role === "error"
                                readonly property bool roleIsSpecial: modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list" || modelData.role === "compact_request"
                                readonly property bool roleIsAssistant: modelData.role === "assistant"
                                readonly property string roleLabel: {
                                    if (roleIsUser)    return "You";
                                    if (roleIsQueued)  return "You (Queued)";
                                    if (roleIsError)   return "Error";
                                    if (modelData.role === "question_request")  return "OpenCode Interactive Question";
                                    if (modelData.role === "permission_request") return "OpenCode Security Request";
                                    if (modelData.role === "schedules_list")    return "Schedules Manager";
                                    if (modelData.role === "compact_request")   return "Context Compaction Request";
                                    return "AI";
                                }

                                width: msgList.width
                                implicitHeight: delegateCol.implicitHeight
                                height: implicitHeight

                                Column {
                                    id: delegateCol

                                    width: parent.width
                                    spacing: Kirigami.Units.largeSpacing

                                    Item {
                                        visible: showDayHeader
                                        width: parent.width
                                        height: showDayHeader ? dayHeaderChip.implicitHeight : 0

                                        Rectangle {
                                            id: dayHeaderChip

                                            anchors.horizontalCenter: parent.horizontalCenter
                                            radius: 999
                                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                                            implicitWidth: dayHeaderText.implicitWidth + Kirigami.Units.largeSpacing
                                            implicitHeight: dayHeaderText.implicitHeight + Kirigami.Units.smallSpacing

                                            PC3.Label {
                                                id: dayHeaderText

                                                anchors.centerIn: parent
                                                horizontalAlignment: Text.AlignHCenter
                                                opacity: 0.78
                                                text: modelData.dayDividerLabel || root.dayDividerLabelForIndex(originalIndex)
                                            }

                                        }

                                    }

                                    Item {
                                        width: parent.width
                                        height: bubble.implicitHeight

                                        Rectangle {
                                            id: bubble

                                            width: Math.min(msgList.width * 0.76, 560)
                                            implicitHeight: bubbleCol.implicitHeight + Kirigami.Units.largeSpacing
                                            radius: 10
                                            // Use parent delegate's cached role booleans instead of
                                            // re-evaluating string comparisons every repaint.
                                            color: {
                                                if (isCurrentSearchMatch)
                                                    return Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.25);
                                                if (isSearchMatch)
                                                    return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15);
                                                if (roleIsUser)
                                                    return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2);
                                                if (roleIsQueued)
                                                    return Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.18);
                                                if (roleIsError)
                                                    return Kirigami.Theme.negativeBackgroundColor;
                                                if (roleIsSpecial)
                                                    return Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.12);
                                                return Kirigami.Theme.backgroundColor;
                                            }
                                            border.width: {
                                                if (isCurrentSearchMatch) return 3;
                                                if (isSearchMatch) return 2;
                                                return (roleIsError || roleIsSpecial) ? 2 : 1;
                                            }
                                            border.color: {
                                                if (isCurrentSearchMatch) return Kirigami.Theme.focusColor;
                                                if (isSearchMatch) return Kirigami.Theme.highlightColor;
                                                if (roleIsError) return Kirigami.Theme.negativeTextColor;
                                                if (roleIsSpecial) return Kirigami.Theme.focusColor;
                                                return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16);
                                            }
                                            // Use explicit x instead of left/right anchors so recycled
                                            // delegates do not keep stale anchor state from a previous role.
                                            x: (roleIsUser || roleIsQueued)
                                                ? (parent.width - width - (Kirigami.Units.largeSpacing + 4))
                                                : 0

                                            Column {
                                                // ── end message body ───────────────────────────────────────

                                                id: bubbleCol

                                                width: parent.width - Kirigami.Units.largeSpacing
                                                x: Kirigami.Units.smallSpacing + Kirigami.Units.smallSpacing / 2
                                                y: Kirigami.Units.smallSpacing + Kirigami.Units.smallSpacing / 2
                                                spacing: Kirigami.Units.smallSpacing

                                                Row {
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing

                                                    PC3.Label {
                                                        text: roleLabel
                                                        font.bold: true
                                                    }

                                                    Rectangle {
                                                        visible: !!modelData.sc
                                                        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
                                                        border.color: Kirigami.Theme.highlightColor
                                                        border.width: 1
                                                        radius: 3
                                                        width: scLabel.implicitWidth + 8
                                                        height: scLabel.implicitHeight + 2

                                                        PC3.Label {
                                                            id: scLabel

                                                            text: "sc"
                                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.75
                                                            font.bold: true
                                                            color: Kirigami.Theme.highlightColor
                                                            anchors.centerIn: parent
                                                        }

                                                    }

                                                    PC3.Label {
                                                        text: root.formatMessageTime(modelData, originalIndex)
                                                        opacity: 0.7
                                                        visible: text !== ""
                                                    }

                                                    PC3.Label {
                                                        text: modelData.role === "assistant" && modelData.model ? ("(" + modelData.model + ")") : ""
                                                        opacity: 0.6
                                                        visible: text !== ""
                                                    }

                                                }

                                                Loader {
                                                    active: root.editingMessageIndex === originalIndex && modelData.role !== "error" && modelData.role !== "assistant"
                                                    width: parent.width

                                                    sourceComponent: QQC2.TextArea {
                                                        width: parent ? parent.width : implicitWidth
                                                        text: root.editingDraft
                                                        wrapMode: Text.WordWrap
                                                        onTextChanged: root.editingDraft = text
                                                    }

                                                }

                                                // ── Selectable / interactive message body ─────────────────
                                                Column {
                                                    id: inlinedMsgContent


                                                    visible: modelData && (root.editingMessageIndex !== originalIndex || modelData.role === "error" || modelData.isImage === true)
                                                    width: parent ? parent.width : 0
                                                    spacing: 4

                                                    Text {
                                                        visible: modelData && modelData.role === "error"
                                                        width: parent.width
                                                        wrapMode: Text.Wrap
                                                        textFormat: Text.PlainText
                                                        text: modelData ? (modelData.content || "") : ""
                                                        color: Kirigami.Theme.negativeTextColor
                                                        font: Kirigami.Theme.defaultFont
                                                    }

                                                    // Image generation display
                                                    Column {
                                                        visible: modelData && modelData.isImage === true
                                                        width: parent.width
                                                        spacing: Kirigami.Units.smallSpacing

                                                        PC3.Label {
                                                            text: {
                                                                let prov = modelData ? (modelData.imageProvider || "") : "";
                                                                let names = {"pollinations": "Pollinations.ai", "huggingface-image": "HuggingFace", "together-image": "Together AI"};
                                                                return names[prov] || prov;
                                                            }
                                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
                                                            font.italic: true
                                                            color: Kirigami.Theme.disabledTextColor
                                                        }

                                                        Rectangle {
                                                            width: Math.min(parent.width, 512)
                                                            height: chatImage.status === Image.Ready ? chatImage.implicitHeight : (chatImage.status === Image.Loading ? 300 : 0)
                                                            radius: 6
                                                            color: root && root.popupIsDark ? "#2d3139" : "#f0f2f5"
                                                            border.width: 1
                                                            border.color: root && root.popupIsDark ? "#3e4452" : "#d0d4dc"
                                                            clip: true

                                                            Image {
                                                                id: chatImage
                                                                anchors.fill: parent
                                                                fillMode: Image.PreserveAspectFit
                                                                source: (modelData && modelData.isImage === true) ? (modelData.imageUrl || "") : ""
                                                                asynchronous: true
                                                                cache: true

                                                                QQC2.BusyIndicator {
                                                                    anchors.centerIn: parent
                                                                    running: chatImage.status === Image.Loading
                                                                    width: Kirigami.Units.gridUnit * 3
                                                                    height: Kirigami.Units.gridUnit * 3
                                                                }

                                                                QQC2.Label {
                                                                    anchors.centerIn: parent
                                                                    visible: chatImage.status === Image.Error
                                                                    text: root ? root.translate("Failed to load image") : "Failed to load image"
                                                                    color: Kirigami.Theme.negativeTextColor
                                                                }
                                                            }
                                                        }

                                                        PC3.ToolButton {
                                                            icon.name: "download"
                                                            display: PC3.AbstractButton.TextBesideIcon
                                                            flat: true
                                                            text: root ? root.translate("Save image") : "Save image"
                                                            visible: modelData && modelData.imageUrl !== ""
                                                            onClicked: {
                                                                if (root && root.msgListViewRef) {
                                                                    let url = modelData.imageUrl || "";
                                                                    if (url.indexOf("data:") === 0) {
                                                                        let cmd = "python3 -c \"import base64,sys; d=sys.stdin.buffer.read(); open('/tmp/kdeaichat_img.png','wb').write(base64.b64decode(d.split(',')[1]))\" <<< '" + url.split(",")[1] + "'";
                                                                        root.customStorageDs.connectSource(cmd + " #save-img-" + Date.now());
                                                                    } else {
                                                                        Qt.openUrlExternally(url);
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Quoted message bubble (if present)
                                                    Rectangle {
                                                        visible: !!(modelData && modelData.quote)
                                                        width: parent.width
                                                        implicitHeight: quoteCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                                                        radius: 6
                                                        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                                                        border.width: 1
                                                        border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2)

                                                        RowLayout {
                                                            id: quoteCol
                                                            anchors.fill: parent
                                                            anchors.margins: Kirigami.Units.smallSpacing
                                                            spacing: Kirigami.Units.smallSpacing

                                                            Kirigami.Icon {
                                                                source: "mail-reply-sender"
                                                                Layout.preferredWidth: 16
                                                                Layout.preferredHeight: 16
                                                                color: Kirigami.Theme.highlightColor
                                                            }

                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                spacing: 2

                                                                PC3.Label {
                                                                    text: {
                                                                        if (!modelData || !modelData.quote) return "";
                                                                        let q = modelData.quote;
                                                                        let sender = q.role === "assistant" ? (q.model || "Assistant") : "User";
                                                                        return "Replying to @" + sender;
                                                                    }
                                                                    font.bold: true
                                                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
                                                                    color: Kirigami.Theme.highlightColor
                                                                }

                                                                PC3.Label {
                                                                    Layout.fillWidth: true
                                                                    text: modelData && modelData.quote ? modelData.quote.content : ""
                                                                    elide: Text.ElideRight
                                                                    maximumLineCount: 1
                                                                    font.italic: true
                                                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
                                                                    opacity: 0.8
                                                                }
                                                            }
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (modelData && modelData.quote && modelData.quote.at) {
                                                                    let targetAt = modelData.quote.at;
                                                                    if (root) {
                                                                        root.scrollToMessageByTimestamp(targetAt);
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Main text content rendering as RichText
                                                    Text {
                                                        id: mainTextEdit

                                                        visible: modelData
                                                                 && modelData.role !== "error"
                                                                 && modelData.role !== "schedules_list"
                                                                 && modelData.isImage !== true
                                                        width: parent.width
                                                        wrapMode: Text.Wrap
                                                        textFormat: Text.RichText
                                                        text: {
                                                            if (!visible) return "";
                                                            let darkKey = root && root.popupIsDark ? "dark" : "light";
                                                            if (modelData.contentHtmlCache && modelData.contentHtmlCache[darkKey] !== undefined) {
                                                                return modelData.contentHtmlCache[darkKey];
                                                            }
                                                            if (root) {
                                                                let html = root.convertMarkdownToHtml(modelData.content || "");
                                                                if (!modelData.contentHtmlCache) {
                                                                    modelData.contentHtmlCache = {};
                                                                }
                                                                modelData.contentHtmlCache[darkKey] = html;
                                                                return html;
                                                            }
                                                            return modelData.content || "";
                                                        }
                                                        color: Kirigami.Theme.textColor
                                                        font: Kirigami.Theme.defaultFont
                                                        onLinkActivated: function(link) {
                                                            let safe = Sec.validateUrl(link);
                                                            if (safe !== "")
                                                                Qt.openUrlExternally(safe);
                                                        }
                                                    }
                                                }

                                                Row {
                                                    visible: modelData.role === "error"
                                                    spacing: Kirigami.Units.smallSpacing

                                                    PC3.Button {
                                                        text: root.translate("Open Settings")
                                                        icon.name: "configure"
                                                        onClicked: {
                                                            root.triggerConfigure();
                                                        }
                                                    }

                                                }

                                                Flow {
                                                    width: parent.width
                                                    visible: !!(modelData.attachments && modelData.attachments.length > 0)
                                                    spacing: Kirigami.Units.smallSpacing

                                                    Repeater {
                                                        model: modelData.attachments || []

                                                        delegate: Rectangle {
                                                            width: Math.min(150, msgFilenameLabel.implicitWidth + 36)
                                                            height: Kirigami.Units.gridUnit * 1.25
                                                            radius: 6
                                                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                                                            border.width: 1
                                                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)

                                                            RowLayout {
                                                                anchors.fill: parent
                                                                anchors.margins: Kirigami.Units.smallSpacing
                                                                spacing: Kirigami.Units.smallSpacing

                                                                Item {
                                                                    Layout.preferredWidth: 16
                                                                    Layout.preferredHeight: 16

                                                                    Image {
                                                                        anchors.fill: parent
                                                                        visible: modelData.type === "image"
                                                                        source: modelData.type === "image" ? ((modelData.content && modelData.content !== "") ? ("data:" + (modelData.mimeType || "image/png") + ";base64," + modelData.content) : ("file://" + modelData.path)) : ""
                                                                        fillMode: Image.PreserveAspectCrop
                                                                        clip: true
                                                                    }

                                                                    Kirigami.Icon {
                                                                        anchors.fill: parent
                                                                        visible: modelData.type !== "image"
                                                                        source: root.fileIconName(modelData.name)
                                                                    }

                                                                }

                                                                PC3.Label {
                                                                    id: msgFilenameLabel

                                                                    Layout.fillWidth: true
                                                                    text: modelData.name
                                                                    elide: Text.ElideRight
                                                                    font.pointSize: 8
                                                                    color: Kirigami.Theme.textColor
                                                                }

                                                            }

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                QQC2.ToolTip.visible: hovered
                                                                QQC2.ToolTip.text: "Open: " + modelData.path
                                                                onClicked: {
                                                                    let safePath = Sec.validateFilePath(modelData.path);
                                                                    if (safePath !== "")
                                                                        Qt.openUrlExternally("file://" + safePath);
                                                                }
                                                            }

                                                        }

                                                    }

                                                }

                                                Row {
                                                    visible: modelData.role === "permission_request"
                                                    width: parent.width
                                                    spacing: Kirigami.Units.largeSpacing
                                                    Layout.topMargin: Kirigami.Units.smallSpacing

                                                    PC3.Button {
                                                        visible: modelData.status === "pending"
                                                        text: "Allow"
                                                        icon.name: "dialog-ok-apply"
                                                        onClicked: root.respondToPermission(modelData.permissionId, true)
                                                    }

                                                    PC3.Button {
                                                        visible: modelData.status === "pending"
                                                        text: "Reject"
                                                        icon.name: "dialog-cancel"
                                                        onClicked: root.respondToPermission(modelData.permissionId, false)
                                                    }

                                                    PC3.Label {
                                                        visible: modelData.status !== "pending"
                                                        text: modelData.status === "allowed" ? "Approved ✅" : modelData.status === "denied" ? "Rejected ❌" : modelData.status === "allowing..." ? "Approving..." : "Rejecting..."
                                                        font.bold: true
                                                        color: modelData.status === "allowed" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                                                    }

                                                }

                                                Row {
                                                    visible: modelData.role === "compact_request"
                                                    width: parent.width
                                                    spacing: Kirigami.Units.largeSpacing
                                                    Layout.topMargin: Kirigami.Units.smallSpacing

                                                    PC3.Button {
                                                        visible: modelData.status === "pending"
                                                        text: "Compact"
                                                        icon.name: "run-build"
                                                        onClicked: root.respondToCompactRequest(originalIndex, true)
                                                    }

                                                    PC3.Button {
                                                        visible: modelData.status === "pending"
                                                        text: "Cancel"
                                                        icon.name: "dialog-cancel"
                                                        onClicked: root.respondToCompactRequest(originalIndex, false)
                                                    }

                                                    PC3.Label {
                                                        visible: modelData.status !== "pending"
                                                        text: modelData.status === "compacted" ? "Compacted ✅" : "Cancelled ❌"
                                                        font.bold: true
                                                        color: modelData.status === "compacted" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                                                    }
                                                }

                                                Column {
                                                    id: questionCol

                                                    property string qId: modelData.questionId || ""
                                                    property var qQuestions: modelData.questions || []
                                                    property bool qAllowCustom: modelData.allowCustom !== false
                                                    property string qStatus: modelData.status || ""

                                                    visible: modelData.role === "question_request"
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing

                                                    // Per-question sections when structured options are available
                                                    Repeater {
                                                        model: (questionCol.qStatus === "pending" && questionCol.qQuestions.length > 0) ? questionCol.qQuestions : []

                                                        delegate: Column {
                                                            id: questionItemCol

                                                            required property var modelData
                                                            required property int index
                                                            property bool qMultiple: modelData.multiple || false

                                                            width: parent.width
                                                            spacing: Kirigami.Units.smallSpacing

                                                            // Question header chip
                                                            Rectangle {
                                                                visible: (modelData.header || "") !== ""
                                                                width: qHeaderLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                                                                height: qHeaderLabel.implicitHeight + Kirigami.Units.smallSpacing
                                                                radius: 999
                                                                color: Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.18)

                                                                PC3.Label {
                                                                    id: qHeaderLabel

                                                                    anchors.centerIn: parent
                                                                    text: modelData.header || ""
                                                                    font.bold: true
                                                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                                                    color: Kirigami.Theme.focusColor
                                                                }

                                                            }

                                                            // Clickable option buttons
                                                            Flow {
                                                                width: parent.width
                                                                spacing: Kirigami.Units.smallSpacing
                                                                visible: modelData.options && modelData.options.length > 0

                                                                Repeater {
                                                                    model: modelData.options || []

                                                                    delegate: Rectangle {
                                                                        id: optionBtn

                                                                        required property var modelData
                                                                        required property int index
                                                                        property bool selected: false

                                                                        width: optBtnLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                                                                        height: optBtnLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                                                                        radius: 6
                                                                        color: selected ? Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.3) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                                                        border.width: selected ? 2 : 1
                                                                        border.color: selected ? Kirigami.Theme.focusColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                                                                        QQC2.ToolTip.visible: optionMa.containsMouse && (optionBtn.modelData.description || "") !== ""
                                                                        QQC2.ToolTip.text: optionBtn.modelData.description || ""

                                                                        PC3.Label {
                                                                            id: optBtnLabel

                                                                            anchors.centerIn: parent
                                                                            text: (optionBtn.selected ? "✓ " : "") + (optionBtn.modelData.label || "")
                                                                            font.bold: optionBtn.selected
                                                                            color: optionBtn.selected ? Kirigami.Theme.focusColor : Kirigami.Theme.textColor
                                                                        }

                                                                        MouseArea {
                                                                            id: optionMa

                                                                            anchors.fill: parent
                                                                            hoverEnabled: true
                                                                            cursorShape: Qt.PointingHandCursor
                                                                            onClicked: {
                                                                                optionBtn.selected = !optionBtn.selected;
                                                                                // For non-multiple questions, submit immediately on click
                                                                                if (!questionItemCol.qMultiple && optionBtn.selected)
                                                                                    root.respondToQuestion(questionCol.qId, optionBtn.modelData.label || "", false);

                                                                            }
                                                                        }

                                                                    }

                                                                }

                                                            }

                                                            // Separator between questions
                                                            Rectangle {
                                                                visible: index < (parent.model ? parent.model.length - 1 : 0)
                                                                width: parent.width
                                                                height: 1
                                                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                                                            }

                                                        }

                                                    }

                                                    // Custom answer text field (shown when custom is allowed or no options exist)
                                                    PC3.Label {
                                                        text: (questionCol.qQuestions.length > 0) ? "Or type a custom answer:" : "Your Answer:"
                                                        font.bold: true
                                                        visible: questionCol.qStatus === "pending" && questionCol.qAllowCustom
                                                    }

                                                    PC3.TextField {
                                                        id: questionReplyField

                                                        visible: questionCol.qStatus === "pending" && questionCol.qAllowCustom
                                                        width: parent.width
                                                        placeholderText: root.translate("Type your answer here...")
                                                        onAccepted: {
                                                            if (text.trim() !== "")
                                                                root.respondToQuestion(questionCol.qId, text, false);

                                                        }
                                                    }

                                                    Row {
                                                        width: parent.width
                                                        spacing: Kirigami.Units.largeSpacing

                                                        PC3.Button {
                                                            visible: questionCol.qStatus === "pending"
                                                            text: "Submit"
                                                            icon.name: "mail-send"
                                                            onClicked: root.submitQuestionAnswer(questionCol.qId, questionCol.qQuestions, questionReplyField)
                                                        }

                                                        PC3.Button {
                                                            visible: questionCol.qStatus === "pending"
                                                            text: "Dismiss"
                                                            icon.name: "dialog-cancel"
                                                            onClicked: root.respondToQuestion(questionCol.qId, "", true)
                                                        }

                                                        PC3.Label {
                                                            visible: questionCol.qStatus !== "pending"
                                                            text: questionCol.qStatus === "answered" ? "Answered: \"" + (modelData.submittedAnswer || "") + "\" ✅" : questionCol.qStatus === "dismissed" ? "Dismissed ❌" : questionCol.qStatus === "answering..." ? "Submitting..." : "Dismissing..."
                                                            font.bold: true
                                                            color: questionCol.qStatus === "answered" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                                                        }

                                                    }

                                                }

                                                ColumnLayout {
                                                    visible: modelData.role === "schedules_list"
                                                    width: parent.width
                                                    spacing: Kirigami.Units.largeSpacing

                                                    RowLayout {
                                                        Layout.fillWidth: true

                                                        PC3.Label {
                                                            text: "📅 Active Schedules in this Chat"
                                                            font.bold: true
                                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                                                            color: Kirigami.Theme.highlightColor
                                                            Layout.fillWidth: true
                                                        }

                                                        PC3.ToolButton {
                                                            icon.name: "view-refresh"
                                                            QQC2.ToolTip.text: "Refresh Schedules"
                                                            QQC2.ToolTip.visible: hovered
                                                            onClicked: {
                                                                schedulerPollTimer.triggered();
                                                            }
                                                        }

                                                    }

                                                    Column {
                                                        width: parent.width
                                                        spacing: Kirigami.Units.smallSpacing

                                                        // Repeater over schedules belonging to root.currentSessionId
                                                        Repeater {
                                                            model: root.getSchedulesForSession(root.currentSessionId)

                                                            delegate: Rectangle {
                                                                width: parent.width
                                                                implicitHeight: rowCol.implicitHeight + Kirigami.Units.largeSpacing
                                                                color: (modelData.enabled !== false) ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.02)
                                                                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                                                                radius: 6
                                                                opacity: (modelData.enabled !== false) ? 1 : 0.6

                                                                ColumnLayout {
                                                                    id: rowCol

                                                                    anchors.fill: parent
                                                                    anchors.margins: Kirigami.Units.largeSpacing
                                                                    spacing: Kirigami.Units.smallSpacing

                                                                    RowLayout {
                                                                        Layout.fillWidth: true
                                                                        spacing: Kirigami.Units.smallSpacing

                                                                        Kirigami.Icon {
                                                                            source: "appointment-new"
                                                                            implicitWidth: Kirigami.Units.iconSizes.small
                                                                            implicitHeight: Kirigami.Units.iconSizes.small
                                                                        }

                                                                        PC3.Label {
                                                                            text: (modelData.name ? modelData.name : "Untitled Schedule") + ((modelData.enabled !== false) ? "" : " (Paused)")
                                                                            font.bold: true
                                                                            Layout.fillWidth: true
                                                                            elide: Text.ElideRight
                                                                        }

                                                                        PC3.Button {
                                                                            icon.name: (modelData.enabled !== false) ? "media-playback-pause" : "media-playback-start"
                                                                            text: (modelData.enabled !== false) ? "Pause" : "Resume"
                                                                            QQC2.ToolTip.text: (modelData.enabled !== false) ? "Pause this schedule" : "Resume this schedule"
                                                                            QQC2.ToolTip.visible: hovered
                                                                            onClicked: {
                                                                                root.toggleScheduleEnabled(modelData.id, !(modelData.enabled !== false));
                                                                            }
                                                                        }

                                                                        PC3.Button {
                                                                            icon.name: "edit-delete"
                                                                            text: "Delete"
                                                                            QQC2.ToolTip.text: "Delete this schedule"
                                                                            QQC2.ToolTip.visible: hovered
                                                                            onClicked: {
                                                                                let schedId = modelData.id;
                                                                                let payload = {
                                                                                    "schedId": schedId
                                                                                };
                                                                                 let b64Payload = root.base64Encode(JSON.stringify(payload));
                                                                                 let cmd = "python3 " + Sec.quoteForShell(root.getHelperPath()) + " delete_schedule " + Sec.quoteForShell(b64Payload);
                                                                                 schedulerDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-delete-" + Date.now());
                                                                                // Remove immediately from UI to be responsive!
                                                                                let copy = root.schedulesList.slice();
                                                                                root.schedulesList = copy.filter(function(s) {
                                                                                    return s.id !== schedId;
                                                                                });
                                                                                root.appendSystemMessage("🗑️ Schedule deleted successfully.");
                                                                            }
                                                                        }

                                                                    }

                                                                    PC3.Label {
                                                                        text: "Message: " + modelData.message
                                                                        wrapMode: Text.Wrap
                                                                        Layout.fillWidth: true
                                                                        opacity: 0.85
                                                                        font.italic: true
                                                                    }

                                                                    PC3.Label {
                                                                        text: "⏰ " + (modelData.humanReadable ? modelData.humanReadable : "Scheduled task")
                                                                        color: Kirigami.Theme.highlightColor
                                                                        font.bold: true
                                                                    }

                                                                }

                                                            }

                                                        }

                                                        PC3.Label {
                                                            visible: root.getSchedulesForSession(root.currentSessionId).length === 0
                                                            text: "No active schedules for this chat."
                                                            font.italic: true
                                                            opacity: 0.7
                                                        }

                                                    }

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: Kirigami.Units.mediumSpacing

                                                        PC3.Button {
                                                            text: "Create Schedule"
                                                            icon.name: "appointment-new"
                                                            highlighted: true
                                                            onClicked: {
                                                                plasmoid.configuration.preselectedChatId = root.currentSessionId;
                                                                plasmoid.configuration.preselectedChatName = root.currentSessionTitle || "Current Chat";
                                                                root.triggerConfigure();
                                                            }
                                                        }

                                                        PC3.Button {
                                                            text: "Refresh"
                                                            icon.name: "view-refresh"
                                                            onClicked: {
                                                                schedulerPollTimer.triggered();
                                                            }
                                                        }

                                                    }

                                                }

                                                Rectangle {
                                                    visible: root.editingMessageIndex === originalIndex && modelData.role !== "error"
                                                    width: parent.width
                                                    height: editWarn.implicitHeight + Kirigami.Units.smallSpacing * 2
                                                    radius: 6
                                                    color: Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.1)

                                                    PC3.Label {
                                                        id: editWarn

                                                        anchors.fill: parent
                                                        anchors.margins: Kirigami.Units.smallSpacing
                                                        wrapMode: Text.Wrap
                                                        text: "Saving this edit will remove all messages below this one and make this the latest message."
                                                    }

                                                }

                                                PC3.Label {
                                                    visible: modelData.role === "assistant" && modelData.tokens !== undefined
                                                    width: parent.width
                                                    horizontalAlignment: Text.AlignRight
                                                    text: root.formatTokensUsage(modelData.tokens, modelData.cost)
                                                    font.pointSize: 8
                                                    opacity: 0.55
                                                    elide: Text.ElideRight
                                                }

                                                // Context items (tool invocations) display
                                                Column {
                                                    visible: modelData.role === "assistant" && modelData.contextItems !== undefined && modelData.contextItems.length > 0
                                                    width: parent.width
                                                    spacing: 2

                                                    Row {
                                                        spacing: Kirigami.Units.smallSpacing

                                                        PC3.Label {
                                                            text: "📂 Context (" + (modelData.contextItems ? modelData.contextItems.length : 0) + ")"
                                                            font.pointSize: 7
                                                            font.bold: true
                                                            opacity: 0.6
                                                        }

                                                        PC3.Label {
                                                            id: contextToggle

                                                            property bool expanded: false

                                                            text: expanded ? "▲ hide" : "▼ show"
                                                            font.pointSize: 7
                                                            opacity: 0.5

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: contextToggle.expanded = !contextToggle.expanded
                                                            }

                                                        }

                                                    }

                                                    Flow {
                                                        visible: contextToggle.expanded
                                                        width: parent.width
                                                        spacing: 3

                                                        Repeater {
                                                            model: modelData.contextItems || []

                                                            delegate: Rectangle {
                                                                required property string modelData

                                                                width: ctxLabel.implicitWidth + 10
                                                                height: ctxLabel.implicitHeight + 4
                                                                radius: 999
                                                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)

                                                                PC3.Label {
                                                                    id: ctxLabel

                                                                    anchors.centerIn: parent
                                                                    text: modelData
                                                                    font.pointSize: 7
                                                                    opacity: 0.6
                                                                    elide: Text.ElideMiddle
                                                                    maximumLineCount: 1
                                                                }

                                                            }

                                                        }

                                                    }

                                                }

                                                Row {
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing

                                                    PC3.ToolButton {
                                                        visible: root.editingMessageIndex !== originalIndex && modelData.role !== "error" && modelData.role !== "assistant"
                                                        icon.name: "document-edit"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: modelData.role === "queued" ? "Edit queued message" : "Edit message"
                                                        onClicked: {
                                                            root.editingMessageIndex = originalIndex;
                                                            root.editingDraft = modelData.content;
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        visible: root.editingMessageIndex === originalIndex && modelData.role !== "error" && modelData.role !== "assistant"
                                                        icon.name: "dialog-ok-apply"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: "Apply edit"
                                                        onClicked: root.saveEditedMessage()
                                                    }

                                                    PC3.ToolButton {
                                                        visible: root.editingMessageIndex === originalIndex && modelData.role !== "error" && modelData.role !== "assistant"
                                                        icon.name: "dialog-cancel"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: "Cancel edit"
                                                        onClicked: {
                                                            root.editingMessageIndex = -1;
                                                            root.editingDraft = "";
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        icon.name: "edit-copy"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: "Copy message"
                                                        onClicked: {
                                                            // Use an invisible text input to copy to clipboard in QML
                                                            clipboardHelper.text = modelData.content || "";
                                                            clipboardHelper.selectAll();
                                                            clipboardHelper.copy();
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        visible: plasmoid.configuration.voiceEnabled && plasmoid.configuration.voiceTtsEnabled && modelData.role !== "error" && modelData.role !== "queued" && modelData.role !== "schedules_list"
                                                        icon.name: "audio-volume-medium"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: "Read message aloud"
                                                        onClicked: {
                                                            root.triggerTts(modelData.content || "");
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        visible: modelData.role === "user" && root.isLatestUserMessage(originalIndex)
                                                        icon.name: "view-refresh"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: "Regenerate reply"
                                                        onClicked: regenerateMenu.open()

                                                        QQC2.Menu {
                                                            id: regenerateMenu
                                                            y: parent.height
                                                            QQC2.MenuItem {
                                                                text: "Generate shorter reply"
                                                                onTriggered: root.regenerateReply(originalIndex, "shorter")
                                                            }
                                                            QQC2.MenuItem {
                                                                text: "Generate bigger reply"
                                                                onTriggered: root.regenerateReply(originalIndex, "longer")
                                                            }
                                                        }
                                                    }

                                                     PC3.ToolButton {
                                                         visible: modelData.role !== "error" && modelData.role !== "queued" && modelData.role !== "schedules_list"
                                                         icon.name: "mail-reply-sender"
                                                         display: PC3.AbstractButton.IconOnly
                                                         QQC2.ToolTip.visible: hovered
                                                         QQC2.ToolTip.text: "Quote/Reply to message"
                                                         onClicked: {
                                                             root.quotedMessage = modelData;
                                                             if (root.msgInputRef) {
                                                                 root.msgInputRef.forceActiveFocus();
                                                             }
                                                         }
                                                     }

                                                     PC3.ToolButton {
                                                         visible: !root.openCodeMode && modelData.role !== "error" && modelData.role !== "queued"
                                                         icon.name: "git-branch"
                                                         display: PC3.AbstractButton.IconOnly
                                                         QQC2.ToolTip.visible: hovered
                                                         QQC2.ToolTip.text: "Fork chat from this message"
                                                         onClicked: root.forkSession(originalIndex)
                                                     }

                                                    PC3.ToolButton {
                                                        icon.name: "edit-delete"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: modelData.role === "queued" ? "Delete queued message" : "Delete message"
                                                        onClicked: root.deleteMessage(originalIndex)
                                                    }

                                                }

                                            }

                                        }

                                    }

                                    Rectangle {
                                        width: parent.width
                                        implicitHeight: 1
                                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.14)
                                    }

                                }

                            }

                        }

                    }

                    RowLayout {
                        visible: root.loading

                        PC3.BusyIndicator {
                            running: root.loading
                            width: 20
                            height: 20
                        }

                        PC3.Label {
                            text: root.streamingResponse ? "Streaming response..." : "Thinking..."
                            opacity: 0.8
                        }

                    }

                    // Attached Files Bar
                    QQC2.ScrollView {
                        Layout.fillWidth: true
                        visible: root.attachedFiles.length > 0
                        height: Kirigami.Units.gridUnit * 2
                        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                        QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff

                        Row {
                            spacing: Kirigami.Units.smallSpacing
                            padding: Kirigami.Units.smallSpacing

                            Repeater {
                                model: root.attachedFiles

                                delegate: Rectangle {
                                    width: Math.min(180, filenameLabel.implicitWidth + 60)
                                    height: Kirigami.Units.gridUnit * 1.5
                                    radius: 6
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                    border.width: 1
                                    border.color: modelData.error !== "" ? Kirigami.Theme.negativeTextColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                                    QQC2.ToolTip.visible: fileMouseArea.hovered && modelData.error !== ""
                                    QQC2.ToolTip.text: modelData.error

                                    MouseArea {
                                        id: fileMouseArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: Kirigami.Units.smallSpacing
                                        spacing: Kirigami.Units.smallSpacing

                                        Item {
                                            Layout.preferredWidth: 20
                                            Layout.preferredHeight: 20

                                            PC3.BusyIndicator {
                                                anchors.centerIn: parent
                                                visible: modelData.loading
                                                running: modelData.loading
                                                width: 16
                                                height: 16
                                            }

                                            Image {
                                                anchors.fill: parent
                                                visible: !modelData.loading && modelData.type === "image"
                                                source: (!modelData.loading && modelData.type === "image") ? ((modelData.content && modelData.content !== "") ? ("data:" + (modelData.mimeType || "image/png") + ";base64," + modelData.content) : ("file://" + modelData.path)) : ""
                                                fillMode: Image.PreserveAspectCrop
                                                clip: true
                                            }

                                            Kirigami.Icon {
                                                anchors.fill: parent
                                                visible: !modelData.loading && modelData.type !== "image"
                                                source: root.fileIconName(modelData.name)
                                            }

                                        }

                                        PC3.Label {
                                            id: filenameLabel

                                            Layout.fillWidth: true
                                            text: modelData.name
                                            elide: Text.ElideRight
                                            font.pointSize: 9
                                            color: modelData.error !== "" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                        }

                                        PC3.ToolButton {
                                            icon.name: "dialog-close"
                                            Layout.preferredWidth: 20
                                            Layout.preferredHeight: 20
                                            display: PC3.AbstractButton.IconOnly
                                            QQC2.ToolTip.visible: hovered
                                            QQC2.ToolTip.text: "Remove file"
                                            onClicked: root.removeAttachedFile(index)
                                        }

                                    }

                                }

                            }

                        }

                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.autocompleteActive ? Math.min(220, autocompleteListView.contentHeight + Kirigami.Units.smallSpacing * 2) : 0
                        visible: root.autocompleteActive
                        radius: 6
                        color: Kirigami.Theme.backgroundColor
                        border.color: Kirigami.Theme.focusColor
                        border.width: 1

                        ListView {
                            id: autocompleteListView

                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            model: root.filteredCommands
                            clip: true
                            currentIndex: root.autocompleteSelectedIndex
                            onCurrentIndexChanged: {
                                positionViewAtIndex(currentIndex, ListView.Contain);
                            }

                            delegate: Rectangle {
                                width: parent.width
                                height: Kirigami.Units.gridUnit * 1.8
                                radius: 4
                                color: index === root.autocompleteSelectedIndex ? Kirigami.Theme.focusColor : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.largeSpacing

                                    PC3.Label {
                                        text: modelData.name
                                        font.bold: true
                                        font.pointSize: 10
                                        color: index === root.autocompleteSelectedIndex ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    }

                                    PC3.Label {
                                        Layout.fillWidth: true
                                        text: modelData.desc
                                        font.pointSize: 9
                                        opacity: 0.75
                                        elide: Text.ElideRight
                                        color: index === root.autocompleteSelectedIndex ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    }

                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: root.autocompleteSelectedIndex = index
                                    onClicked: {
                                        if (root.msgInputRef) {
                                            root.msgInputRef.text = modelData.name;
                                            root.chatInputText = modelData.name;
                                            root.sendMessage();
                                        }
                                        root.autocompleteActive = false;
                                    }
                                }

                            }

                        }

                    }

                                            // Quoted Message Preview Bar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.quotedMessage ? (quotePreviewRow.implicitHeight + Kirigami.Units.smallSpacing * 2) : 0
                        visible: !!root.quotedMessage
                        radius: 6
                        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                        border.width: 1
                        border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2)

                        RowLayout {
                            id: quotePreviewRow
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: "mail-reply-sender"
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                color: Kirigami.Theme.highlightColor
                            }

                            PC3.Label {
                                text: {
                                    if (!root.quotedMessage) return "";
                                    let q = root.quotedMessage;
                                    let sender = q.role === "assistant" ? (q.model || "Assistant") : "User";
                                    return "Replying to @" + sender + ": " + q.content;
                                }
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.italic: true
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
                                opacity: 0.9
                            }

                            PC3.ToolButton {
                                icon.name: "dialog-close"
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                display: PC3.AbstractButton.IconOnly
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: "Cancel reply"
                                onClicked: {
                                    root.quotedMessage = null;
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PC3.ToolButton {
                            icon.name: "mail-attachment"
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            enabled: !root.loading
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: "Attach files (Images, PDF, CSV, Word documents)"
                            Accessible.name: root.translate("Attach files")
                            Accessible.role: Accessible.Button
                            Accessible.description: root.translate("Attach images, PDFs, CSVs, or Word documents to the chat")
                            onClicked: fileDialog.open()
                        }

                        PC3.ToolButton {
                            icon.name: "edit-paste"
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            enabled: !root.loading
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: "Paste file or text from clipboard"
                            Accessible.name: root.translate("Paste clipboard")
                            Accessible.role: Accessible.Button
                            Accessible.description: root.translate("Paste file or text from clipboard into chat")
                            onClicked: {
                                root.checkClipboardForAttachments();
                                let txt = root.readClipboardText();
                                if (txt && txt.trim() !== "") {
                                    let curPos = msgInput.cursorPosition;
                                    msgInput.insert(curPos, txt);
                                }
                            }
                        }

                        QQC2.ScrollView {
                            id: inputScrollView

                            Layout.fillWidth: true
                            Layout.minimumHeight: Kirigami.Units.gridUnit * 3
                            Layout.maximumHeight: Kirigami.Units.gridUnit * 7
                            Layout.preferredHeight: Math.min(Layout.maximumHeight, Math.max(Layout.minimumHeight, msgInput.contentHeight + msgInput.topPadding + msgInput.bottomPadding))
                            implicitWidth: Kirigami.Units.gridUnit * 10
                            clip: true
                            QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded
                            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                            QQC2.TextArea {
                                id: msgInput

                                property alias focusTimerRef: focusTimer

                                implicitWidth: parent.width
                                wrapMode: Text.Wrap
                                placeholderText: {
                                    if (root.voiceRecording) {
                                        if (root.voiceSttStatus === "starting_daemon") {
                                            return root.translate("Voice input: Starting voice daemon...");
                                        } else if (root.voiceSttStatus === "loading_model") {
                                            return root.translate("Voice input: Loading model...");
                                        } else if (root.voiceSttStatus === "recording") {
                                            return root.translate("Voice input: Listening...");
                                        } else if (root.voiceSttStatus === "transcribing" || root.voiceSttStatus === "stopping") {
                                            return root.translate("Voice input: Processing...");
                                        } else {
                                            return root.translate("Voice input: Listening...");
                                        }
                                    }
                                    return root.translate("Type message (Enter sends, Shift+Enter newline)");
                                }
                                focus: true
                                Accessible.name: root.translate("Message input")
                                Accessible.role: Accessible.EditableText
                                Accessible.description: root.translate("Type your message to the AI here")
                                onTextChanged: {
                                    root.chatInputText = text;
                                    root.updateAutocomplete();
                                }
                                Keys.onPressed: function(event) {
                                    if (root.autocompleteActive) {
                                        if (event.key === Qt.Key_Down) {
                                            event.accepted = true;
                                            root.autocompleteSelectedIndex = (root.autocompleteSelectedIndex + 1) % root.filteredCommands.length;
                                            return ;
                                        } else if (event.key === Qt.Key_Up) {
                                            event.accepted = true;
                                            root.autocompleteSelectedIndex = (root.autocompleteSelectedIndex - 1 + root.filteredCommands.length) % root.filteredCommands.length;
                                            return ;
                                        } else if (event.key === Qt.Key_Escape) {
                                            event.accepted = true;
                                            root.autocompleteActive = false;
                                            return ;
                                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                                            event.accepted = true;
                                            let selected = root.filteredCommands[root.autocompleteSelectedIndex];
                                            if (selected) {
                                                msgInput.text = selected.name;
                                                root.chatInputText = selected.name;
                                                root.sendMessage();
                                            }
                                            root.autocompleteActive = false;
                                            return ;
                                        }
                                    }
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                        event.accepted = true;
                                        root.sendMessage();
                                    } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                        root.checkClipboardForAttachments();
                                        event.accepted = false;
                                    }
                                }
                                Component.onCompleted: {
                                    root.msgInputRef = msgInput;
                                    if (root.expanded)
                                        focusTimer.start();

                                }

                                Timer {
                                    id: focusTimer

                                    interval: 120
                                    repeat: false
                                    onTriggered: {
                                        if (msgInput.enabled && msgInput.visible)
                                            msgInput.forceActiveFocus();

                                    }
                                }

                                Connections {
                                    target: root
                                    function onExpandedChanged() {
                                        if (root.expanded)
                                            focusTimer.start();
                                    }
                                    function onClearChatInput() {
                                        msgInput.text = "";
                                    }
                                }

                            }

                        }

                        PC3.Button {
                            icon.name: root.loading ? "list-add" : "document-send"
                            text: root.loading ? "Queue" : "Send"
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 5
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            enabled: root.chatInputText.trim() !== "" || root.attachedFiles.length > 0
                            Accessible.name: root.translate(root.loading ? "Queue message" : "Send message")
                            Accessible.role: Accessible.Button
                            Accessible.description: root.translate("Send the current message to the AI")
                            onClicked: root.sendMessage()
                        }

                        PC3.ToolButton {
                            visible: plasmoid.configuration.voiceEnabled && plasmoid.configuration.voiceTtsEnabled
                            icon.name: plasmoid.configuration.voiceTtsAuto ? "audio-volume-high" : "audio-volume-muted"
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: plasmoid.configuration.voiceTtsAuto ? root.translate("Auto Read Aloud: Enabled") : root.translate("Auto Read Aloud: Disabled")
                            Accessible.name: root.translate("Toggle auto read aloud")
                            Accessible.role: Accessible.Button
                            onClicked: {
                                plasmoid.configuration.voiceTtsAuto = !plasmoid.configuration.voiceTtsAuto;
                            }
                        }

                        PC3.ToolButton {
                            visible: plasmoid.configuration.voiceEnabled && !root.voiceRecording && !root.ttsPlaying
                            icon.name: "audio-input-microphone"
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            enabled: !root.loading
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: root.translate("Start voice input")
                            Accessible.name: root.translate("Voice input")
                            Accessible.role: Accessible.Button
                            onClicked: root.startVoiceRecording()
                        }

                        PC3.ToolButton {
                            visible: root.voiceRecording
                            icon.name: (root.voiceSttStatus === "transcribing" || root.voiceSttStatus === "stopping") ? "process-working" : "media-playback-stop"
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            enabled: root.voiceSttStatus !== "transcribing" && root.voiceSttStatus !== "stopping"
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: (root.voiceSttStatus === "transcribing" || root.voiceSttStatus === "stopping") ? root.translate("Processing...") : root.translate("Stop recording")
                            Accessible.name: root.translate("Stop recording")
                            Accessible.role: Accessible.Button
                            onClicked: root.stopVoiceRecording()
                            PC3.BusyIndicator {
                                anchors.centerIn: parent
                                width: parent.width * 0.6
                                height: parent.height * 0.6
                                running: root.voiceRecording
                                visible: root.voiceRecording
                            }
                        }

                        PC3.ToolButton {
                            visible: root.ttsPlaying
                            icon.name: "media-playback-stop"
                            text: {
                                if (root.voiceTtsStatus === "starting_daemon") {
                                    return root.translate("Starting voice daemon...");
                                }
                                return root.translate("Reading Aloud");
                            }
                            display: PC3.AbstractButton.TextBesideIcon
                            highlighted: !root.ttsPaused
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: root.translate("Stop reading aloud")
                            Accessible.name: root.translate("Stop TTS")
                            Accessible.role: Accessible.Button
                            onClicked: root.stopTts()
                        }

                        PC3.ToolButton {
                            visible: root.ttsPlaying
                            enabled: root.voiceTtsStatus !== "starting_daemon"
                            icon.name: root.ttsPaused ? "media-playback-start" : "media-playback-pause"
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: root.ttsPaused ? root.translate("Resume reading aloud") : root.translate("Pause reading aloud")
                            Accessible.name: root.ttsPaused ? root.translate("Resume TTS") : root.translate("Pause TTS")
                            Accessible.role: Accessible.Button
                            onClicked: {
                                if (root.ttsPaused) {
                                    root.resumeTts();
                                } else {
                                    root.pauseTts();
                                }
                            }
                        }

                        PC3.ToolButton {
                            visible: root.loading
                            icon.name: "process-stop"
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: "Stop current response"
                            Accessible.name: root.translate("Stop response")
                            Accessible.role: Accessible.Button
                            Accessible.description: root.translate("Stop generating the response")
                            onClicked: root.stopStreaming()
                        }

                    }

                }

            }
            Rectangle {
                id: inlinedSidebar
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                Component.onCompleted: { root.sessionsSidebarRef = inlinedSidebar; }

                property string sortBy: "date_desc"

                radius: 8
                color: Kirigami.Theme.alternateBackgroundColor

                function focusSearch() {
                    sidebarSearchInput.forceActiveFocus();
                }

                function getFilteredSessions(isArchived) {
                    if (!root || !root.sessions) return [];
                    let rawList = root.sessions;
                    let filtered = [];
                    let query = sidebarSearchInput.text.trim().toLowerCase();
                    for (let i = 0; i < rawList.length; i++) {
                        let s = rawList[i];
                        let isArch = s.archived || false;
                        if (isArch !== isArchived) continue;
                        if (query !== "") {
                            let title = (s.text || "New Chat").toLowerCase();
                            let subtitle = (root ? root.sessionSubtitle(s) : "").toLowerCase();
                            if (title.indexOf(query) === -1 && subtitle.indexOf(query) === -1) {
                                continue;
                            }
                        }
                        filtered.push(s);
                    }
                    // Sort
                    filtered.sort(function(a, b) {
                        if (sortBy === "date_desc") {
                            let tA = a.updatedAt || a.createdAt || 0;
                            let tB = b.updatedAt || b.createdAt || 0;
                            return tB - tA;
                        } else if (sortBy === "date_asc") {
                            let tA = a.updatedAt || a.createdAt || 0;
                            let tB = b.updatedAt || b.createdAt || 0;
                            return tA - tB;
                        } else if (sortBy === "name_asc") {
                            let nA = (a.text || "New Chat").toLowerCase();
                            let nB = (b.text || "New Chat").toLowerCase();
                            return nA.localeCompare(nB);
                        } else if (sortBy === "name_desc") {
                            let nA = (a.text || "New Chat").toLowerCase();
                            let nB = (b.text || "New Chat").toLowerCase();
                            return nB.localeCompare(nA);
                        }
                        return 0;
                    });
                    return filtered;
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    // Search & Sort bar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.TextField {
                            id: sidebarSearchInput
                            Layout.fillWidth: true
                            placeholderText: root ? root.translate("Search chats...") : "Search chats..."
                            rightPadding: clearSearchButton.visible ? clearSearchButton.width : Kirigami.Units.smallSpacing

                            PC3.ToolButton {
                                id: clearSearchButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: parent.text !== ""
                                icon.name: "edit-clear"
                                display: PC3.AbstractButton.IconOnly
                                onClicked: {
                                    parent.text = "";
                                }
                            }
                        }

                        PC3.ToolButton {
                            id: sortButton
                            icon.name: "view-sort"
                            display: PC3.AbstractButton.IconOnly
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: root ? root.translate("Sort order") : "Sort order"
                            onClicked: sortMenu.open()

                            QQC2.Menu {
                                id: sortMenu
                                y: parent.height

                                QQC2.MenuItem {
                                    text: root ? root.translate("Newest first") : "Newest first"
                                    checkable: true
                                    checked: sortBy === "date_desc"
                                    onTriggered: sortBy = "date_desc"
                                }
                                QQC2.MenuItem {
                                    text: root ? root.translate("Oldest first") : "Oldest first"
                                    checkable: true
                                    checked: sortBy === "date_asc"
                                    onTriggered: sortBy = "date_asc"
                                }
                                QQC2.MenuItem {
                                    text: root ? root.translate("Name (A-Z)") : "Name (A-Z)"
                                    checkable: true
                                    checked: sortBy === "name_asc"
                                    onTriggered: sortBy = "name_asc"
                                }
                                QQC2.MenuItem {
                                    text: root ? root.translate("Name (Z-A)") : "Name (Z-A)"
                                    checkable: true
                                    checked: sortBy === "name_desc"
                                    onTriggered: sortBy = "name_desc"
                                }
                            }
                        }
                    }

                    // Sessions list in ScrollView
                    QQC2.ScrollView {
                        id: historyScrollView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded

                        ColumnLayout {
                            x: Kirigami.Units.smallSpacing
                            width: historyScrollView.availableWidth - Kirigami.Units.smallSpacing * 2
                            spacing: Kirigami.Units.smallSpacing

                            // Active Chats Header
                            RowLayout {
                                Layout.fillWidth: true
                                visible: activeRepeater.count > 0

                                PC3.Label {
                                    text: root ? root.translate("Active Chats") : "Active Chats"
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                PC3.Label {
                                    text: activeRepeater.count
                                    opacity: 0.6
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                }
                            }

                            Repeater {
                                id: activeRepeater
                                model: inlinedSidebar.getFilteredSessions(false)
                                delegate: sessionDelegateComponent
                            }

                            // Separator between Active and Archived if both exist
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                                visible: activeRepeater.count > 0 && archivedRepeater.count > 0
                            }

                            // Archived Chats Header
                            RowLayout {
                                Layout.fillWidth: true
                                visible: archivedRepeater.count > 0

                                PC3.Label {
                                    text: root ? root.translate("Archived Chats") : "Archived Chats"
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                PC3.Label {
                                    text: archivedRepeater.count
                                    opacity: 0.6
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                }
                            }

                            Repeater {
                                id: archivedRepeater
                                model: inlinedSidebar.getFilteredSessions(true)
                                delegate: sessionDelegateComponent
                            }
                        }
                    }
                }

                Component {
                    id: sessionDelegateComponent

                    Rectangle {
                        id: delegateBg
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: delegateLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: 8
                        opacity: modelData.archived ? 0.72 : 1
                        color: root ? root.historySessionTint(modelData) : "transparent"

                        MouseArea {
                            id: delegateMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (root) {
                                    root.switchSession(modelData.value);
                                    root.historyOnlyMode = false;
                                }
                            }
                        }

                        RowLayout {
                            id: delegateLayout
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing

                            // Left side: Badges and Text (Title + Subtitle)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                // Badges layout (horizontal)
                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing / 2
                                    visible: modeBadge.visible || schedBadge.visible || forkBadge.visible
                                    Layout.alignment: Qt.AlignVCenter

                                    Rectangle {
                                        id: modeBadge
                                        visible: modelData.source === "opencode"
                                        width: modeBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 1.5
                                        height: modeBadgeText.implicitHeight + Kirigami.Units.smallSpacing * 0.5
                                        radius: 4
                                        color: Qt.rgba(0.2, 0.48, 0.92, 0.15)

                                        PC3.Label {
                                            id: modeBadgeText
                                            anchors.centerIn: parent
                                            text: "OC"
                                            font.bold: true
                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.8
                                            color: Qt.rgba(0.12, 0.35, 0.78, 1)
                                        }
                                    }

                                    Rectangle {
                                        id: schedBadge
                                        visible: root && root.sessionHasSchedules(modelData.value)
                                        width: schedBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 1.5
                                        height: schedBadgeText.implicitHeight + Kirigami.Units.smallSpacing * 0.5
                                        radius: 4
                                        color: Qt.rgba(0.92, 0.48, 0.2, 0.15)

                                        PC3.Label {
                                            id: schedBadgeText
                                            anchors.centerIn: parent
                                            text: "SC"
                                            font.bold: true
                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.8
                                            color: Qt.rgba(0.78, 0.35, 0.12, 1)
                                        }
                                    }

                                    Rectangle {
                                        id: forkBadge
                                        visible: modelData.value && modelData.value.indexOf("fork-") === 0
                                        width: forkBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 1.5
                                        height: forkBadgeText.implicitHeight + Kirigami.Units.smallSpacing * 0.5
                                        radius: 4
                                        color: Qt.rgba(0.48, 0.2, 0.92, 0.15)

                                        PC3.Label {
                                            id: forkBadgeText
                                            anchors.centerIn: parent
                                            text: "FK"
                                            font.bold: true
                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.8
                                            color: Qt.rgba(0.35, 0.12, 0.78, 1)
                                        }
                                    }
                                }

                                // Title and Subtitle stacked vertically
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    // Rename field (if editing)
                                    QQC2.TextField {
                                        id: renameField
                                        visible: root && root.editingSessionId === modelData.value
                                        Layout.fillWidth: true
                                        text: root ? root.editingSessionDraft : ""
                                        onTextChanged: if (root) root.editingSessionDraft = text
                                        onAccepted: if (root) root.saveSessionRename(modelData.value)
                                        Component.onCompleted: {
                                            if (visible) forceActiveFocus();
                                        }
                                    }

                                    // Chat Title
                                    PC3.Label {
                                        id: sessionTitleLabel
                                        visible: root && root.editingSessionId !== modelData.value
                                        Layout.fillWidth: true
                                        text: {
                                            let rawText = modelData.text || "New Chat";
                                            if (rawText.indexOf("[FK] ") === 0)
                                                rawText = rawText.substring(5);
                                            return root ? root.translate(rawText) : rawText;
                                        }
                                        font.bold: root && modelData.value === root.currentSessionId
                                        color: root && root.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                                        elide: Text.ElideRight
                                    }

                                    // Chat Subtitle (Updated Date / Time / etc)
                                    PC3.Label {
                                        Layout.fillWidth: true
                                        opacity: root && root.popupIsDark ? 0.8 : 0.6
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                                        color: root && root.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                                        text: root ? root.sessionSubtitle(modelData) : ""
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Right side: Message Count Badge (Actions are now an overlay)
                            RowLayout {
                                id: actionsRow
                                spacing: Kirigami.Units.smallSpacing / 2
                                Layout.alignment: Qt.AlignVCenter

                                // Message Count Badge
                                Rectangle {
                                    id: countBadge
                                    property int totalCount: (modelData.messages || []).length
                                    property int readCount: modelData.readCount !== undefined ? modelData.readCount : totalCount
                                    property int unreadCount: Math.max(0, totalCount - readCount)

                                    visible: unreadCount > 0 && !actionsContainer.visible
                                    width: countBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 1.5
                                    height: countBadgeText.implicitHeight + Kirigami.Units.smallSpacing * 0.5
                                    radius: 10
                                    color: Kirigami.Theme.highlightColor

                                    PC3.Label {
                                        id: countBadgeText
                                        anchors.centerIn: parent
                                        text: parent.unreadCount > 99 ? "99+" : parent.unreadCount
                                        font.bold: true
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.75
                                        color: Kirigami.Theme.highlightedTextColor
                                    }
                                }
                            }
                        }

                        // Actions Container Overlay
                        // Positioned as an overlay to prevent layout reflows (flickering)
                        // anchored with a larger margin to clear the scrollbar.
                        Rectangle {
                            id: actionsContainer
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: Kirigami.Units.gridUnit * 0.8
                            radius: 6
                            color: {
                                let bg = delegateBg.color;
                                if (bg === "transparent" || bg === "#00000000" || bg === "rgba(0,0,0,0)")
                                    return Kirigami.Theme.alternateBackgroundColor;
                                return bg;
                            }
                            border.width: 1
                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)

                            // Visibility logic: include button hover states to prevent flickering when
                            // the mouse enters the overlay (which might cause the main MouseArea to lose hover).
                            visible: delegateMouseArea.containsMouse || 
                                     saveRename.hovered || 
                                     archiveChat.hovered || 
                                     removeChat.hovered ||
                                     (root && (modelData.value === root.currentSessionId || 
                                                                root.editingSessionId === modelData.value))

                            width: actionsRowInner.implicitWidth + Kirigami.Units.smallSpacing
                            height: actionsRowInner.implicitHeight + Kirigami.Units.smallSpacing

                            RowLayout {
                                id: actionsRowInner
                                anchors.centerIn: parent
                                spacing: 2

                                PC3.ToolButton {
                                    id: saveRename
                                    icon.name: root && root.editingSessionId === modelData.value ? "dialog-ok-apply" : "document-edit"
                                    display: PC3.AbstractButton.IconOnly
                                    implicitWidth: Kirigami.Units.gridUnit * 1.5
                                    implicitHeight: Kirigami.Units.gridUnit * 1.5
                                    QQC2.ToolTip.visible: hovered
                                    QQC2.ToolTip.text: root && root.editingSessionId === modelData.value ? "Save title" : "Rename chat"
                                    onClicked: {
                                        if (root) {
                                            if (root.editingSessionId === modelData.value)
                                                root.saveSessionRename(modelData.value);
                                            else
                                                root.startSessionRename(modelData.value);
                                        }
                                    }
                                }

                                PC3.ToolButton {
                                    id: archiveChat
                                    icon.name: modelData.archived ? "archive-remove" : "archive-insert"
                                    display: PC3.AbstractButton.IconOnly
                                    implicitWidth: Kirigami.Units.gridUnit * 1.5
                                    implicitHeight: Kirigami.Units.gridUnit * 1.5
                                    QQC2.ToolTip.visible: hovered
                                    QQC2.ToolTip.text: modelData.archived ? "Unarchive chat" : "Archive chat"
                                    onClicked: if (root) root.setSessionArchived(modelData.value, !modelData.archived)
                                }

                                PC3.ToolButton {
                                    id: removeChat
                                    icon.name: root && root.editingSessionId === modelData.value ? "dialog-cancel" : "edit-delete"
                                    display: PC3.AbstractButton.IconOnly
                                    implicitWidth: Kirigami.Units.gridUnit * 1.5
                                    implicitHeight: Kirigami.Units.gridUnit * 1.5
                                    QQC2.ToolTip.visible: hovered
                                    QQC2.ToolTip.text: root && root.editingSessionId === modelData.value ? "Cancel rename" : "Delete chat"
                                    onClicked: {
                                        if (root) {
                                            if (root.editingSessionId === modelData.value)
                                                root.cancelSessionRename();
                                            else
                                                fullRep.requestDeleteSession(modelData.value);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

    }

    MouseArea {
        property real startX: 0
        property real startY: 0
        property real startW: 0
        property real startH: 0

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Kirigami.Units.gridUnit
        height: Kirigami.Units.gridUnit
        cursorShape: Qt.SizeFDiagCursor
        onPressed: function(mouse) {
            startX = mouse.x;
            startY = mouse.y;
            startW = parent.implicitWidth;
            startH = parent.implicitHeight;
        }
        onPositionChanged: function(mouse) {
            if (pressed) {
                let dx = mouse.x - startX;
                let dy = mouse.y - startY;
                let newW = Math.max(500, startW + dx);
                let newH = Math.max(620, startH + dy);
                parent.implicitWidth = newW;
                parent.implicitHeight = newH;
                plasmoid.configuration.customPopupWidth = newW;
                plasmoid.configuration.customPopupHeight = newH;
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"

            Canvas {
                anchors.fill: parent
                anchors.margins: 4
                onPaint: {
                    let ctx = getContext("2d");
                    ctx.strokeStyle = Kirigami.Theme.textColor;
                    ctx.lineWidth = 1;
                    ctx.globalAlpha = 0.5;
                    ctx.beginPath();
                    ctx.moveTo(width - 4, height);
                    ctx.lineTo(width, height - 4);
                    ctx.moveTo(width - 8, height);
                    ctx.lineTo(width, height - 8);
                    ctx.moveTo(width - 12, height);
                    ctx.lineTo(width, height - 12);
                    ctx.stroke();
                }
            }

        }

    }


// ── Per-session Chat Settings dialog ──────────────────────────────────────
QQC2.Dialog {
    id: chatSettingsDialog

    title: root.translate("Chat Settings")
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(420, parent.width * 0.9)
    height: Math.min(600, parent.height * 0.85)
    standardButtons: QQC2.Dialog.NoButton
    onAboutToShow: {
        let sId = root.currentSessionId;
        root.debugLog("[KDE AIChat] chatSettingsDialog about to show for session ID: " + sId);
        let overrideVal = getSessionProperty(sId, "contextOverride", false);
        let enabledVal = getSessionProperty(sId, "contextEnabled", true);
        let limitVal = getSessionProperty(sId, "contextLimit", (plasmoid.configuration.globalContextLimit !== undefined && plasmoid.configuration.globalContextLimit !== null ? plasmoid.configuration.globalContextLimit : 1));
        let autoCompactVal = getSessionProperty(sId, "contextAutoCompact", plasmoid.configuration.globalContextAutoCompact || false);
        let compactThresholdVal = getSessionProperty(sId, "contextCompactThreshold", plasmoid.configuration.globalContextCompactThreshold || 10);
        let chatSysPromptVal = getSessionProperty(sId, "chatSystemPrompt", "");
        let chatMemoryVal = getSessionProperty(sId, "chatMemory", "");
        let chatModelVal = getSessionProperty(sId, "chatModel", "");
        let responseLengthVal = getSessionProperty(sId, "responseLength", plasmoid.configuration.responseLength || 0);

        root.debugLog("[KDE AIChat] Loaded settings: override=" + overrideVal + ", enabled=" + enabledVal + ", limit=" + limitVal + ", autoCompact=" + autoCompactVal + ", compactThreshold=" + compactThresholdVal);

        // Sync controls imperatively to avoid QML binding breakage
        overrideToggle.checked = overrideVal;
        contextEnabledToggle.checked = enabledVal;
        contextLimitSpin.value = limitVal;
        autoCompactToggle.checked = autoCompactVal;
        compactThresholdSpin.value = compactThresholdVal;
        chatSystemPromptArea.text = chatSysPromptVal;
        chatMemoryArea.text = chatMemoryVal;
        quickModelSwitch.currentIndex = chatModelVal === "" ? 0 : Math.max(0, quickModelSwitch.model.indexOf(chatModelVal));
        responseLengthCombo.currentIndex = responseLengthVal;
    }
    onAccepted: {
        let sId = root.currentSessionId;
        let overrideVal = overrideToggle.checked;
        let enabledVal = contextEnabledToggle.checked;
        let limitVal = contextLimitSpin.value;
        let autoCompactVal = autoCompactToggle.checked;
        let compactThresholdVal = compactThresholdSpin.value;
        let chatSysPromptVal = chatSystemPromptArea.text;
        let chatMemoryVal = chatMemoryArea.text;
        let chatModelVal = quickModelSwitch.currentIndex > 0 ? quickModelSwitch.currentText : "";
        let responseLengthVal = responseLengthCombo.currentIndex;

        root.debugLog("[KDE AIChat] Saving settings for session ID: " + sId);
        root.debugLog("[KDE AIChat] Saving values: override=" + overrideVal + ", enabled=" + enabledVal + ", limit=" + limitVal + ", autoCompact=" + autoCompactVal + ", compactThreshold=" + compactThresholdVal);

        setSessionProperty(sId, "contextOverride", overrideVal);
        setSessionProperty(sId, "contextEnabled", enabledVal);
        setSessionProperty(sId, "contextLimit", limitVal);
        setSessionProperty(sId, "contextAutoCompact", autoCompactVal);
        setSessionProperty(sId, "contextCompactThreshold", compactThresholdVal);
        setSessionProperty(sId, "chatSystemPrompt", chatSysPromptVal);
        setSessionProperty(sId, "chatMemory", chatMemoryVal);
        setSessionProperty(sId, "chatModel", chatModelVal);
        setSessionProperty(sId, "responseLength", responseLengthVal);
    }

    QQC2.ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing

        // ── Chat System Prompt ─────────────────────────────────────
        QQC2.Label {
            text: root.translate("Chat System Prompt:")
            font.bold: true
            Layout.fillWidth: true
        }

        QQC2.Label {
            text: root.translate("Add chat-specific instructions that are appended to the global system prompt. Leave blank to use only the global system prompt.")
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4
            clip: true

            QQC2.TextArea {
                id: chatSystemPromptArea
                wrapMode: Text.Wrap
                placeholderText: root.translate("Leave blank to use only the global system prompt")
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // ── Chat Memory ────────────────────────────────────────────
        QQC2.Label {
            text: root.translate("Chat Memory:")
            font.bold: true
            Layout.fillWidth: true
        }

        QQC2.Label {
            text: root.translate("Facts the AI should remember for this chat only. Deleted when the chat is deleted.")
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.fillWidth: true
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4
            clip: true

            QQC2.TextArea {
                id: chatMemoryArea
                wrapMode: Text.Wrap
                placeholderText: root.translate("E.g., This chat is about my Python project. Prefer type hints.")
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // ── Model Switch ────────────────────────────────────────────
        QQC2.Label {
            text: root.translate("Model:")
            font.bold: true
            visible: !plasmoid.configuration.useOpenCode
            Layout.fillWidth: true
        }

        RowLayout {
            visible: !plasmoid.configuration.useOpenCode
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: quickModelSwitch
                Layout.fillWidth: true
                model: {
                    let models = [root.translate("(provider default)")];
                    let prov = plasmoid.configuration.provider || "openai";
                    let pm = root.getProviderConfig(prov).model || "";
                    let chatModel = root.getSessionProperty(root.currentSessionId, "chatModel", "");
                    if (chatModel && chatModel !== pm) models.push(chatModel);
                    if (pm && pm !== chatModel) models.push(pm);
                    return models;
                }
                currentIndex: 0
                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                QQC2.ToolTip.text: root.translate("Switch model for this chat")
            }
        }

        // ── Response Length ──────────────────────────────────────────
        QQC2.Label {
            text: root.translate("Response Length:")
            font.bold: true
            visible: !plasmoid.configuration.useOpenCode
            Layout.fillWidth: true
        }

        QQC2.ComboBox {
            id: responseLengthCombo
            visible: !plasmoid.configuration.useOpenCode
            Layout.fillWidth: true
            model: [root.translate("Default"), root.translate("Short"), root.translate("Medium"), root.translate("Long"), root.translate("Max")]
            currentIndex: 0
        }

        QQC2.Label {
            visible: !plasmoid.configuration.useOpenCode
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: {
                let lengths = [
                    root.translate("Default — no limit"),
                    root.translate("Short (~256 tokens)"),
                    root.translate("Medium (~1024 tokens)"),
                    root.translate("Long (~4096 tokens)"),
                    root.translate("Max (~8192 tokens)")
                ];
                return lengths[responseLengthCombo.currentIndex] || lengths[0];
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // ── Override toggle ─────────────────────────────────────────
        QQC2.CheckBox {
            id: overrideToggle

            text: root.translate("Override global context settings for this chat")
            Layout.fillWidth: true
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: overrideToggle.checked
        }

        // ── Context enable/disable ──────────────────────────────────
        QQC2.CheckBox {
            id: contextEnabledToggle

            visible: overrideToggle.checked
            text: checked ? root.translate("Context enabled — previous messages are sent to AI") : root.translate("Context disabled — AI sees only the current prompt")
            Layout.fillWidth: true
        }

        // ── Context limit ───────────────────────────────────────────
        RowLayout {
            visible: overrideToggle.checked && contextEnabledToggle.checked
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                text: root.translate("Context limit:")
            }

            QQC2.SpinBox {
                id: contextLimitSpin

                from: 1
                to: 200
                editable: true
            }

            PC3.Label {
                text: root.translate("messages")
            }

        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: overrideToggle.checked && contextEnabledToggle.checked
        }

        // ── Auto-compact ────────────────────────────────────────────
        QQC2.CheckBox {
            id: autoCompactToggle

            visible: overrideToggle.checked && contextEnabledToggle.checked
            text: checked ? root.translate("Auto-compact older messages when limit is reached") : root.translate("Do not auto-compact")
            Layout.fillWidth: true
        }

        RowLayout {
            visible: overrideToggle.checked && contextEnabledToggle.checked && autoCompactToggle.checked
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                text: root.translate("Compact threshold:")
            }

            QQC2.SpinBox {
                id: compactThresholdSpin
                from: 5
                to: 200
                editable: true
            }

            PC3.Label {
                text: root.translate("messages")
            }

        }

        // ── Info about inherited settings ───────────────────────────
        PC3.Label {
            visible: !overrideToggle.checked
            text: root.translate("This chat uses the global defaults from Settings → General → Global Context.\n\nEnable the override above to customise context for this chat only.")
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.72
            Layout.fillWidth: true
        }

        // ── Manual compact button ───────────────────────────────────
        QQC2.Button {
            visible: overrideToggle.checked && contextEnabledToggle.checked
            text: root.translate("Compact context now")
            icon.name: "edit-clear-history"
            Layout.fillWidth: true
            onClicked: {
                chatSettingsDialog.accept();
                Qt.callLater(function() {
                    compactSessionContext(root.currentSessionId);
                });
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // ── Custom Actions (Save/Cancel) ────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.mediumSpacing

            QQC2.Button {
                text: root.translate("Cancel")
                Layout.fillWidth: true
                onClicked: {
                    chatSettingsDialog.reject();
                }
            }

            QQC2.Button {
                text: root.translate("Save")
                highlighted: true
                Layout.fillWidth: true
                onClicked: {
                    chatSettingsDialog.accept();
                }
            }
        }

        }

    }

}

// ── Inline /schedule command dialog ───────────────────────────────────────
QQC2.Dialog {
    id: scheduleCommandDialog

    property string prefillMessage: ""
    property string chatId: ""
    property string chatName: ""
    property string schedType: "days"
    property int schedEvery: 1
    property string schedTime: "09:00"
    property var schedDays: [1]
    property int schedDayOfMonth: 1
    property bool schedNotify: true

    function buildCron() {
        let t = schedType, n = schedEvery;
        let tp = schedTime.split(":"), hr = parseInt(tp[0]) || 9, mn = parseInt(tp[1]) || 0;
        if (t === "minutes")
            return "*/" + n + " * * * *";

        if (t === "hours")
            return "0 */" + n + " * * *";

        if (t === "days")
            return (n === 1 ? mn + " " + hr + " * * *" : mn + " " + hr + " */" + n + " * *");

        if (t === "weeks") {
            let ds = schedDays.length > 0 ? schedDays.slice().sort().join(",") : "1";
            return mn + " " + hr + " * * " + ds;
        }
        return (n === 1 ? mn + " " + hr + " " + schedDayOfMonth + " * *" : mn + " " + hr + " " + schedDayOfMonth + " */" + n + " *");
    }

    function humanText() {
        let t = schedType, n = schedEvery;
        let tp = schedTime.split(":"), hr = parseInt(tp[0]) || 9, mn = parseInt(tp[1]) || 0;
        let ap = hr >= 12 ? "PM" : "AM", h12 = hr % 12 || 12, ms = mn < 10 ? "0" + mn : "" + mn;
        let ts = h12 + ":" + ms + " " + ap;
        if (t === "minutes")
            return "Every " + (n === 1 ? "minute" : n + " minutes");

        if (t === "hours")
            return "Every " + (n === 1 ? "hour" : n + " hours");

        if (t === "days")
            return "Every " + (n === 1 ? "day" : n + " days") + " at " + ts;

        if (t === "weeks") {
            let dn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
            return "Every " + (n === 1 ? "week" : n + " weeks") + " on " + schedDays.map(function(x) {
                return dn[x];
            }).join(", ") + " at " + ts;
        }
        let sfx = schedDayOfMonth === 1 ? "st" : schedDayOfMonth === 2 ? "nd" : schedDayOfMonth === 3 ? "rd" : "th";
        return "Every " + (n === 1 ? "month" : n + " months") + " on the " + schedDayOfMonth + sfx + " at " + ts;
    }

    title: translate("Create Schedule")
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width * 0.92, 540)
    standardButtons: QQC2.Dialog.Close
    onOpened: {
        cmdMessage.text = scheduleCommandDialog.prefillMessage;
    }

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            visible: !!scheduleCommandDialog.chatName
            text: "In chat: " + scheduleCommandDialog.chatName
            font.italic: true
            font.pixelSize: 11
            opacity: 0.65
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            QQC2.Label {
                text: "Message to send:"
                font.bold: true
            }

            QQC2.TextArea {
                id: cmdMessage

                Layout.fillWidth: true
                Layout.preferredHeight: 68
                wrapMode: TextEdit.Wrap
                placeholderText: "e.g. What should I focus on today?"
            }

        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            QQC2.Label {
                text: "When to send:"
                font.bold: true
            }

            Flow {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: [{
                        "k": "minutes",
                        "l": "Minutes"
                    }, {
                        "k": "hours",
                        "l": "Hours"
                    }, {
                        "k": "days",
                        "l": "Days"
                    }, {
                        "k": "weeks",
                        "l": "Weeks"
                    }, {
                        "k": "months",
                        "l": "Months"
                    }]

                    QQC2.Button {
                        text: modelData.l
                        font.pixelSize: 11
                        highlighted: scheduleCommandDialog.schedType === modelData.k
                        flat: scheduleCommandDialog.schedType !== modelData.k
                        onClicked: scheduleCommandDialog.schedType = modelData.k
                    }

                }

            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    text: "Every"
                }

                QQC2.SpinBox {
                    from: 1
                    to: 999
                    value: scheduleCommandDialog.schedEvery
                    onValueChanged: scheduleCommandDialog.schedEvery = value
                }

                QQC2.Label {
                    text: {
                        let t = scheduleCommandDialog.schedType, n = scheduleCommandDialog.schedEvery;
                        let m = {
                            "minutes": "minute",
                            "hours": "hour",
                            "days": "day",
                            "weeks": "week",
                            "months": "month"
                        };
                        return n === 1 ? (m[t] || t) : (m[t] || t) + "s";
                    }
                }

            }

            RowLayout {
                visible: ["days", "weeks", "months"].indexOf(scheduleCommandDialog.schedType) >= 0
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    text: "At:"
                }

                QQC2.SpinBox {
                    from: 1
                    to: 12
                    value: {
                        let h2 = parseInt(scheduleCommandDialog.schedTime.split(":")[0]) || 9;
                        return (h2 % 12) || 12;
                    }
                    textFromValue: function(v) {
                        return (v < 10 ? "0" : "") + v;
                    }
                    onValueChanged: {
                        let parts = scheduleCommandDialog.schedTime.split(":");
                        let curH = parseInt(parts[0]) || 0;
                        let m2 = parseInt(parts[1]) || 0;
                        let isPm = curH >= 12;
                        let targetH = value;
                        if (isPm) {
                            if (value < 12)
                                targetH = value + 12;

                        } else {
                            if (value === 12)
                                targetH = 0;

                        }
                        scheduleCommandDialog.schedTime = (targetH < 10 ? "0" : "") + targetH + ":" + (m2 < 10 ? "0" : "") + m2;
                    }
                }

                QQC2.Label {
                    text: ":"
                }

                QQC2.SpinBox {
                    from: 0
                    to: 59
                    stepSize: 5
                    value: parseInt(scheduleCommandDialog.schedTime.split(":")[1]) || 0
                    textFromValue: function(v) {
                        return (v < 10 ? "0" : "") + v;
                    }
                    onValueChanged: {
                        let parts = scheduleCommandDialog.schedTime.split(":");
                        let h2 = parseInt(parts[0]) || 9;
                        scheduleCommandDialog.schedTime = (h2 < 10 ? "0" : "") + h2 + ":" + (value < 10 ? "0" : "") + value;
                    }
                }

                QQC2.Button {
                    text: (parseInt(scheduleCommandDialog.schedTime.split(":")[0]) >= 12 ? "PM" : "AM")
                    font.bold: true
                    onClicked: {
                        let parts = scheduleCommandDialog.schedTime.split(":");
                        let curH = parseInt(parts[0]) || 0;
                        let m2 = parseInt(parts[1]) || 0;
                        let targetH = curH;
                        if (curH >= 12)
                            targetH = curH - 12;
                        else
                            targetH = curH + 12;
                        scheduleCommandDialog.schedTime = (targetH < 10 ? "0" : "") + targetH + ":" + (m2 < 10 ? "0" : "") + m2;
                    }
                }

            }

            Flow {
                visible: scheduleCommandDialog.schedType === "weeks"
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

                    Rectangle {
                        property bool sel: scheduleCommandDialog.schedDays.indexOf(index) >= 0

                        width: 32
                        height: 26
                        radius: 4
                        color: sel ? Kirigami.Theme.highlightColor : "transparent"
                        border.color: sel ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                        border.width: 1

                        QQC2.Label {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 10
                            font.bold: sel
                            color: sel ? "white" : Kirigami.Theme.textColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                let ds2 = scheduleCommandDialog.schedDays.slice(), pos = ds2.indexOf(index);
                                if (pos >= 0) {
                                    if (ds2.length > 1)
                                        ds2.splice(pos, 1);

                                } else {
                                    ds2.push(index);
                                    ds2.sort();
                                }
                                scheduleCommandDialog.schedDays = ds2;
                            }
                        }

                    }

                }

            }

            RowLayout {
                visible: scheduleCommandDialog.schedType === "months"

                QQC2.Label {
                    text: "On day:"
                }

                QQC2.SpinBox {
                    from: 1
                    to: 28
                    value: scheduleCommandDialog.schedDayOfMonth
                    onValueChanged: scheduleCommandDialog.schedDayOfMonth = value
                }

                QQC2.Label {
                    text: "of the month"
                    opacity: 0.7
                }

            }

            Rectangle {
                Layout.fillWidth: true
                height: cmdSummaryLbl.implicitHeight + Kirigami.Units.gridUnit
                radius: 5
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1)
                border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.3)
                border.width: 1

                QQC2.Label {
                    id: cmdSummaryLbl

                    text: "📅 " + scheduleCommandDialog.humanText()
                    font.bold: true
                    wrapMode: Text.Wrap
                    color: Kirigami.Theme.highlightColor

                    anchors {
                        fill: parent
                        margins: Kirigami.Units.smallSpacing * 1.5
                    }

                }

            }

        }

        RowLayout {
            QQC2.Switch {
                id: cmdNotify

                checked: true
                onCheckedChanged: scheduleCommandDialog.schedNotify = checked
            }

            QQC2.Label {
                text: cmdNotify.checked ? "Notify me when done" : "Silent"
            }

        }

        RowLayout {
            Layout.fillWidth: true

            Item {
                Layout.fillWidth: true
            }

            QQC2.Button {
                text: "Cancel"
                onClicked: scheduleCommandDialog.close()
            }

            QQC2.Button {
                text: "Schedule It"
                highlighted: true
                enabled: cmdMessage.text.trim() !== ""
                onClicked: {
                    let hr2 = scheduleCommandDialog.humanText();
                    let msg = cmdMessage.text.trim();
                    let entry = {
                        "id": root.makeScheduleEntryId(),
                        "name": hr2,
                        "enabled": true,
                        "chatId": scheduleCommandDialog.chatId,
                        "chatName": scheduleCommandDialog.chatName,
                        "message": msg,
                        "schedType": scheduleCommandDialog.schedType,
                        "schedEvery": scheduleCommandDialog.schedEvery,
                        "schedTime": scheduleCommandDialog.schedTime,
                        "schedDays": scheduleCommandDialog.schedDays,
                        "schedDayOfMonth": scheduleCommandDialog.schedDayOfMonth,
                        "cron": scheduleCommandDialog.buildCron(),
                        "humanReadable": hr2,
                        "notify": scheduleCommandDialog.schedNotify,
                        "createdAt": new Date().toISOString()
                    };
                    let payload = {
                        "entry": entry
                    };
                    let b64Payload = root.base64Encode(JSON.stringify(payload));
                    let cmd = "python3 " + Sec.quoteForShell(root.getHelperPath()) + " add_schedule " + Sec.quoteForShell(b64Payload);
                    schedulerDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-save-" + Date.now());
                    scheduleCommandDialog.close();
                    root.appendSystemMessage("✅ Scheduled! I'll send \"" + msg.substring(0, 50) + (msg.length > 50 ? "…" : "") + "\" " + hr2 + ".");
                }
            }

        }

    }

}

// ── Interactive Chat Schedule Manager Dialog ───────────────────────────
QQC2.Dialog {
    id: chatScheduleManagerDialog

    property string chatId: ""
    property string chatName: ""
    // Filter schedules belonging to this chat
    property var activeSchedules: {
        let res = [];
        for (let i = 0; i < root.schedulesList.length; i++) {
            let s = root.schedulesList[i];
            if (s && s.chatId === chatScheduleManagerDialog.chatId)
                res.push(s);

        }
        return res;
    }

    function deleteSchedule(schedId) {
        let payload = {
            "schedId": schedId
        };
        let b64Payload = root.base64Encode(JSON.stringify(payload));
        let cmd = "python3 " + Sec.quoteForShell(root.getHelperPath()) + " delete_schedule " + Sec.quoteForShell(b64Payload);
        schedulerDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-delete-" + Date.now());
        root.appendSystemMessage("🗑️ Schedule deleted successfully.");
    }

    title: "Chat Schedule Manager"
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width * 0.92, 500)
    standardButtons: QQC2.Dialog.Close

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            level: 4
            text: chatScheduleManagerDialog.chatName + (chatScheduleManagerDialog.chatId ? " (ID: " + chatScheduleManagerDialog.chatId + ")" : "")
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        QQC2.Label {
            text: "Below are the active automated messages scheduled for this specific chat."
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            opacity: 0.7
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // List of schedules
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.mediumSpacing

            // If no active schedules
            QQC2.Label {
                visible: chatScheduleManagerDialog.activeSchedules.length === 0
                text: "No active schedules for this chat."
                font.italic: true
                opacity: 0.6
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            Repeater {
                model: chatScheduleManagerDialog.activeSchedules

                delegate: Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: col.implicitHeight + Kirigami.Units.mediumSpacing * 2
                    radius: 6
                    color: (modelData.enabled !== false) ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    border.width: 1
                    opacity: (modelData.enabled !== false) ? 1 : 0.6

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.mediumSpacing
                        spacing: Kirigami.Units.mediumSpacing

                        ColumnLayout {
                            id: col

                            Layout.fillWidth: true
                            spacing: 2

                            QQC2.Label {
                                text: (modelData.name || translate("Unnamed Schedule")) + ((modelData.enabled !== false) ? "" : " (" + translate("Paused") + ")")
                                font.bold: true
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }

                            QQC2.Label {
                                text: "💬 \"" + modelData.message + "\""
                                font.italic: true
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                                opacity: 0.8
                            }

                            QQC2.Label {
                                text: "⏰ " + (modelData.humanReadable || "Scheduled task")
                                font.pixelSize: 11
                                color: Kirigami.Theme.highlightColor
                                Layout.fillWidth: true
                            }

                        }

                        QQC2.Button {
                            icon.name: (modelData.enabled !== false) ? "media-playback-pause" : "media-playback-start"
                            display: QQC2.AbstractButton.IconOnly
                            Kirigami.Theme.colorSet: Kirigami.Theme.Button
                            Kirigami.Theme.inherit: false
                            onClicked: {
                                root.toggleScheduleEnabled(modelData.id, !(modelData.enabled !== false));
                            }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: (modelData.enabled !== false) ? "Pause Schedule" : "Resume Schedule"
                        }

                        QQC2.Button {
                            icon.name: "edit-delete"
                            display: QQC2.AbstractButton.IconOnly
                            Kirigami.Theme.colorSet: Kirigami.Theme.Button
                            Kirigami.Theme.inherit: false
                            onClicked: {
                                chatScheduleManagerDialog.deleteSchedule(modelData.id);
                            }
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: "Delete Schedule"
                        }

                    }

                }

            }

        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        QQC2.Button {
            text: "Create Schedule for this Chat"
            icon.name: "list-add"
            highlighted: true
            Layout.fillWidth: true
            onClicked: {
                chatScheduleManagerDialog.close();
                plasmoid.configuration.preselectedChatId = chatScheduleManagerDialog.chatId;
                plasmoid.configuration.preselectedChatName = chatScheduleManagerDialog.chatName || "Current Chat";
                root.triggerConfigure();
            }
        }

    }

}

QQC2.Dialog {
    id: clearChatConfirmDialog
    title: root.translate("Clear Chat History")
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(380, parent.width * 0.9)
    standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.largeSpacing

        PC3.Label {
            Layout.fillWidth: true
            text: root.translate("Are you sure you want to clear all messages in the current session? This action cannot be undone.")
            wrapMode: Text.Wrap
        }

        QQC2.CheckBox {
            id: dontAskClearChatCheck
            Layout.fillWidth: true
            text: root.translate("Don't ask again")
            checked: false
        }
    }

    onAccepted: {
        if (dontAskClearChatCheck.checked) {
            plasmoid.configuration.askClearChatConfirmation = false;
        }
        root.messages = [];
        root.editingMessageIndex = -1;
        root.editingDraft = "";
        root.clearCurrentOpenCodeSessionIfNeeded();
        root.saveCurrentSessionState(true);
    }
}

QQC2.Dialog {
    id: deleteChatConfirmDialog
    title: root.translate("Delete Chat Session")
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(380, parent.width * 0.9)
    standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No

    property string sessionIdToDelete: ""

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.largeSpacing

        PC3.Label {
            Layout.fillWidth: true
            text: root.translate("Are you sure you want to delete this chat session? All messages in this session will be permanently deleted.")
            wrapMode: Text.Wrap
        }

        QQC2.CheckBox {
            id: dontAskDeleteChatCheck
            Layout.fillWidth: true
            text: root.translate("Don't ask again")
            checked: false
        }
    }

    onAccepted: {
        if (dontAskDeleteChatCheck.checked) {
            plasmoid.configuration.askDeleteChatConfirmation = false;
        }
        if (sessionIdToDelete !== "") {
            root.deleteSession(sessionIdToDelete);
        }
    }
}

    }
}
