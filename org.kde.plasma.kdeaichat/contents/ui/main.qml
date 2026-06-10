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
import "MainDatabase.js" as MainDatabase
import "MainNetwork.js" as MainNetwork
import "MainOpenCode.js" as MainOpenCode
import "MainScheduler.js" as MainScheduler

// LINKAGE RELATIONSHIPS:
// - main.qml: The root entrypoint PlasmoidItem.
// - Linked to MainDataSources.qml (instantiated as 'dataSources' and exposed via property aliases):
//   Holds all the external process command execution DataSources, Timers, and File Dialogs to keep main.qml under 1000 lines.
//   It takes a reference to 'root' (this) to read config and update state.
// - Linked to MainDatabase.js (imported as MainDatabase):
//   Contains helper functions for managing session states, parsing, and database transactions.

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
        return MainDatabase.debugLog();
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
            let content = messages[j].content || "";
            if (content.toLowerCase().indexOf(q) >= 0) {
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
    property var plasmoidRef: plasmoid
    property string configCustomHistoryPath: plasmoid.configuration.customHistoryPath || ""
    property bool configUseOpenCode: !!plasmoid.configuration.useOpenCode
    property int configKeyStorageMode: plasmoid.configuration.keyStorageMode || 0
    property bool configKwalletAutoPrompt: plasmoid.configuration.kwalletAutoPrompt !== undefined ? !!plasmoid.configuration.kwalletAutoPrompt : true
    property bool configOpenCodeAutoKill: !!plasmoid.configuration.openCodeAutoKill
    property int configOpenCodeAutoKillMinutes: plasmoid.configuration.openCodeAutoKillMinutes || 5
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
            if (typeof root.openKeyboardShortcutsHelp === "function") {
                root.openKeyboardShortcutsHelp();
            } else {
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
    }

    signal clearChatInput()

    function sessionHasSchedules(sessionId) {
        return MainDatabase.sessionHasSchedules(sessionId);
    }

    function triggerConfigure() {
        return MainDatabase.triggerConfigure();
    }

    function focusInput() {
        return MainDatabase.focusInput();
    }

    function searchNext() {
        return MainDatabase.searchNext();
    }

    function searchPrev() {
        return MainDatabase.searchPrev();
    }

    function pad2(v) {
        return MainDatabase.pad2(v);
    }

    function nowTime(ts) {
        return MainDatabase.nowTime(ts);
    }

    function formatDateTime(ts) {
        return MainDatabase.formatDateTime(ts);
    }

    function makeSessionId() {
        return MainDatabase.makeSessionId();
    }

    // Centralized helper for reporting a benign parse failure (e.g. an
    // OpenCode / clipboard / custom-history reply we could not decode).
    // Always logs to console for diagnostics and surfaces a non-blocking
    // notification to the user, so the failure is never silently dropped.
    function reportParseFailure(context, error) {
        return MainDatabase.reportParseFailure(context, error);
    }

    function makeForkSessionId() {
        return MainDatabase.makeForkSessionId();
    }

    function forkSession(messageIndex) {
        return MainDatabase.forkSession(messageIndex);
    }

    // ── /schedule command handler ──────────────────────────────────────────────
    function handleScheduleCommand(messageText) {
        return MainScheduler.handleScheduleCommand(messageText);
    }

    function toggleScheduleEnabled(schedId, newEnabled) {
        return MainScheduler.toggleScheduleEnabled(schedId, newEnabled);
    }

    function injectScheduledMessage(chatId, messageText, notify, schedId, schedName) {
        return MainScheduler.injectScheduledMessage(chatId, messageText, notify, schedId, schedName);
    }

    function parseSessions(customRaw) {
        return MainDatabase.parseSessions(customRaw);
    }

    function checkAndMarkCurrentSessionAsRead() {
        return MainDatabase.checkAndMarkCurrentSessionAsRead();
    }

    function base64Encode(str) {
        return MainNetwork.base64Encode(str);
    }

    function base64Decode(str) {
        return MainNetwork.base64Decode(str);
    }

    function getHistoryFilePath(customDir) {
        return MainDatabase.getHistoryFilePath(customDir);
    }

    function migrateHistory(oldPath, newPath) {
        return MainDatabase.migrateHistory(oldPath, newPath);
    }

    function persistSessions() {
        return MainDatabase.persistSessions();
    }

    function flushPersistSessions() {
        return MainDatabase.flushPersistSessions();
    }

    function sortSessionsByUpdated() {
        return MainDatabase.sortSessionsByUpdated();
    }

    function historySessionTint(sessionData) {
        return MainDatabase.historySessionTint(sessionData);
    }

    function sessionSubtitle(sessionData) {
        return MainDatabase.sessionSubtitle(sessionData);
    }

    function sessionIndexById(sessionId) {
        return MainDatabase.sessionIndexById(sessionId);
    }

    function createSession(switchToNew) {
        return MainDatabase.createSession(switchToNew);
    }

    function loadSessions() {
        return MainDatabase.loadSessions();
    }

    function saveCurrentSessionState(touchUpdatedAt) {
        return MainDatabase.saveCurrentSessionState(touchUpdatedAt);
    }

    function setCurrentSessionSource(source) {
        return MainDatabase.setCurrentSessionSource(source);
    }

    function setSessionArchived(sessionId, archived) {
        return MainDatabase.setSessionArchived(sessionId, archived);
    }

    function switchSession(sessionId) {
        return MainDatabase.switchSession(sessionId);
    }

    function renameCurrentSession(newTitle) {
        return MainDatabase.renameCurrentSession(newTitle);
    }

    function startSessionRename(sessionId) {
        return MainDatabase.startSessionRename(sessionId);
    }

    function cancelSessionRename() {
        return MainDatabase.cancelSessionRename();
    }

    function saveSessionRename(sessionId) {
        return MainDatabase.saveSessionRename(sessionId);
    }

    function deleteSession(sessionId) {
        return MainDatabase.deleteSession(sessionId);
    }

    function deleteMessage(index) {
        return MainDatabase.deleteMessage(index);
    }

    function isLatestUserMessage(index) {
        return MainDatabase.isLatestUserMessage(index);
    }

    function hasSubsequentAssistantMessage(index) {
        return MainDatabase.hasSubsequentAssistantMessage(index);
    }

    function regenerateReply(index, type) {
        return MainDatabase.regenerateReply(index, type);
    }

    function saveEditedMessage() {
        return MainDatabase.saveEditedMessage();
    }

    function openCodeBaseUrl() {
        return MainOpenCode.openCodeBaseUrl();
    }

    function currentOpenCodeSessionId() {
        return MainOpenCode.currentOpenCodeSessionId();
    }

    function setCurrentOpenCodeSessionId(remoteSessionId) {
        return MainOpenCode.setCurrentOpenCodeSessionId(remoteSessionId);
    }

    function clearCurrentOpenCodeSessionIfNeeded() {
        return MainOpenCode.clearCurrentOpenCodeSessionIfNeeded();
    }

    function getSessionProperty(sessionId, key, defaultValue) {
        return MainDatabase.getSessionProperty(sessionId, key, defaultValue);
    }

    function setSessionProperty(sessionId, key, value) {
        return MainDatabase.setSessionProperty(sessionId, key, value);
    }

    function appendCompactPromptMessage(chatId) {
        return MainDatabase.appendCompactPromptMessage(chatId);
    }

    function respondToCompactRequest(msgIndex, approved) {
        return MainDatabase.respondToCompactRequest(msgIndex, approved);
    }

    function touchSessionsList(chatId) {
        return MainDatabase.touchSessionsList(chatId);
    }

    function checkAndAutoCompact(sessionId) {
        return MainDatabase.checkAndAutoCompact(sessionId);
    }

    function compactSessionContext(sessionId) {
        return MainDatabase.compactSessionContext(sessionId);
    }

    function sendBackgroundSummarizationRequest(sId, promptText, count) {
        return MainDatabase.sendBackgroundSummarizationRequest(sId, promptText, count);
    }

    function updateAutocomplete() {
        return MainDatabase.updateAutocomplete();
    }

    function extractReadableError(prefix, errObj, fallbackText) {
        return MainDatabase.extractReadableError(prefix, errObj, fallbackText);
    }

    function beginAssistantStreaming(modelLabel) {
        return MainDatabase.beginAssistantStreaming(modelLabel);
    }

    function updateAssistantStreamingContent(text, modelLabel) {
        return MainDatabase.updateAssistantStreamingContent(text, modelLabel);
    }

    function finishOpenCodeRequest() {
        return MainNetwork.finishOpenCodeRequest();
    }

    // Handle slash commands in OpenCode mode.
    // Commands are dispatched to the appropriate handler:
    //  - /help, /session, /stats → local inline info (no server needed)
    //  - /models                 → REST API GET /v1/models
    //  - /version                → opencode --version (real CLI flag)
    //  - /export                 → syncOpenCodeSessionHistory() (REST API)
    //  - TUI-only commands       → friendly explanation shown inline
    function runLocalOpenCodeCommand(cmdText) {
        return MainDatabase.runLocalOpenCodeCommand(cmdText);
    }

    function syncOpenCodeSessionHistory() {
        return MainDatabase.syncOpenCodeSessionHistory();
    }

    function ensureOpenCodeEventStream() {
        return MainOpenCode.ensureOpenCodeEventStream();
    }

    function handleOpenCodeEvent(eventObj) {
        return MainDatabase.handleOpenCodeEvent(eventObj);
    }

    function appendSystemMessageToSession(chatId, text) {
        return MainDatabase.appendSystemMessageToSession(chatId, text);
    }

    function removeMessageFromSessionByTimestamp(chatId, timestamp) {
        return MainDatabase.removeMessageFromSessionByTimestamp(chatId, timestamp);
    }

    function scheduleMessageRemoval(chatId, timestamp, delayMs) {
        return MainDatabase.scheduleMessageRemoval(chatId, timestamp, delayMs);
    }

    function setOpenCodeSessionIdForChatId(chatId, remoteSessionId) {
        return MainDatabase.setOpenCodeSessionIdForChatId(chatId, remoteSessionId);
    }

    function ensureOpenCodeSessionForChatId(chatId, successCallback, failureCallback) {
        return MainDatabase.ensureOpenCodeSessionForChatId(chatId, successCallback, failureCallback);
    }

    function ensureCurrentOpenCodeSession(successCallback, failureCallback) {
        return MainOpenCode.ensureCurrentOpenCodeSession(successCallback, failureCallback);
    }

    function ensureOpenCodeServerRunning(chatId, successCallback, failureCallback) {
        return MainOpenCode.ensureOpenCodeServerRunning(chatId, successCallback, failureCallback);
    }

    function doOpenCodeRequest() {
        return MainOpenCode.doOpenCodeRequest();
    }

    function scrollToBottom() {
        return MainDatabase.scrollToBottom();
    }

    function scrollToMessageByTimestamp(timestamp) {
        return MainDatabase.scrollToMessageByTimestamp(timestamp);
    }

    function messageTimestampAt(index) {
        return MainDatabase.messageTimestampAt(index);
    }

    function messageDayKeyAt(index) {
        return MainDatabase.messageDayKeyAt(index);
    }

    function dayBucketLabel(ts) {
        return MainDatabase.dayBucketLabel(ts);
    }

    function countMessagesForDayKey(dayKey) {
        return MainDatabase.countMessagesForDayKey(dayKey);
    }

    function dayDividerLabelForIndex(index) {
        return MainDatabase.dayDividerLabelForIndex(index);
    }

    function formatMessageTime(message, index) {
        return MainDatabase.formatMessageTime(message, index);
    }

    function jumpOneMessageAbove() {
        return MainDatabase.jumpOneMessageAbove();
    }

    function jumpOneMessageBelow() {
        return MainDatabase.jumpOneMessageBelow();
    }

    function formatTokensUsage(tokens, cost) {
        return MainDatabase.formatTokensUsage(tokens, cost);
    }

    function pushErrorMessage(text) {
        return MainNetwork.pushErrorMessage(text);
    }

    function pushInfoMessage(text) {
        return MainDatabase.pushInfoMessage(text);
    }

    function appendUserMessage(text, role, attachments, isScheduled) {
        return MainDatabase.appendUserMessage(text, role, attachments, isScheduled);
    }

    function appendSystemMessage(text) {
        return MainDatabase.appendSystemMessage(text);
    }

    function getSchedulesForSession(sessionId) {
        return MainDatabase.getSchedulesForSession(sessionId);
    }

    function validateCurrentSendTarget() {
        return MainNetwork.validateCurrentSendTarget();
    }

    function sendMessageByIndex(index) {
        return MainDatabase.sendMessageByIndex(index);
    }

    function processNextQueuedMessage() {
        return MainDatabase.processNextQueuedMessage();
    }

    function providerDisplayName(providerId) {
        return MainDatabase.providerDisplayName(providerId);
    }

    function validateOpenCodeConfig() {
        return MainDatabase.validateOpenCodeConfig();
    }

    function validateProviderConfig(providerId, cfg) {
        return MainDatabase.validateProviderConfig(providerId, cfg);
    }

    function sendMessage() {
        return MainDatabase.sendMessage();
    }

    function getProviderConfig(provider) {
        return MainDatabase.getProviderConfig(provider);
    }

    function translate(text) {
        return MainDatabase.translate(text);
    }

    function isSessionScheduled(sessionId, messagesList) {
        return MainDatabase.isSessionScheduled(sessionId, messagesList);
    }

    function buildEffectiveSystemPrompt(sessionId) {
        return MainDatabase.buildEffectiveSystemPrompt(sessionId);
    }

    // Returns a filtered, context-limited list of {role, content} pairs.
    // System-status bubbles (error, schedules_list, info …) are excluded.
    // Messages before the compacted boundary are excluded.
    // Only the last N user/assistant messages are kept (N = per-session override OR global limit).
    function buildContextWindow(messagesList, sessionId) {
        return MainDatabase.buildContextWindow(messagesList, sessionId);
    }

    function buildOpenAICompatPayload() {
        return MainDatabase.buildOpenAICompatPayload();
    }

    function buildAnthropicPayload() {
        return MainDatabase.buildAnthropicPayload();
    }

    function buildOpenAICompatPayloadForMessages(messagesList, chatId) {
        return MainDatabase.buildOpenAICompatPayloadForMessages(messagesList, chatId);
    }

    function buildAnthropicPayloadForMessages(messagesList, chatId) {
        return MainNetwork.buildAnthropicPayloadForMessages(messagesList, chatId);
    }

    function _buildMessageArray(messagesList, chatId, format) {
        return MainDatabase._buildMessageArray(messagesList, chatId, format);
    }

    function appendMessageToSession(chatId, msgObj) {
        return MainDatabase.appendMessageToSession(chatId, msgObj);
    }

    function handleBackgroundError(chatId, errorMsg, notify, schedId, schedName) {
        return MainNetwork.handleBackgroundError(chatId, errorMsg, notify, schedId, schedName);
    }

    function doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName) {
        return MainOpenCode.doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName);
    }

    function doBackgroundOpenAICompatRequest(chatId, baseUrl, apiKey, model, extraHeaders, modelLabel, messageText, notify, schedId, schedName) {
        return MainNetwork.doBackgroundOpenAICompatRequest(chatId, baseUrl, apiKey, model, extraHeaders, modelLabel, messageText, notify, schedId, schedName);
    }

    function doBackgroundAnthropicRequest(chatId, apiKey, model, messageText, notify, schedId, schedName) {
        return MainNetwork.doBackgroundAnthropicRequest(chatId, apiKey, model, messageText, notify, schedId, schedName);
    }

    function executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName) {
        return MainScheduler.executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName);
    }

    function doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel) {
        return MainNetwork.doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel);
    }

    function doAnthropicRequest(apiKey, model) {
        return MainNetwork.doAnthropicRequest(apiKey, model);
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
        return MainDatabase.triggerNotificationSound();
    }

    function respondToPermission(permissionId, approved) {
        return MainDatabase.respondToPermission(permissionId, approved);
    }

    // Collect selected options from the question UI and submit the answer
    function submitQuestionAnswer(questionId, questions, customField) {
        return MainDatabase.submitQuestionAnswer(questionId, questions, customField);
    }

    function respondToQuestion(questionId, answerValue, isReject) {
        return MainDatabase.respondToQuestion(questionId, answerValue, isReject);
    }

    function stopStreaming() {
        return MainDatabase.stopStreaming();
    }

    function flushStreamingBuffer() {
        return MainDatabase.flushStreamingBuffer();
    }

    function copyToClipboard(textValue) {
        return MainDatabase.copyToClipboard(textValue);
    }

    function convertMarkdownToHtml(markdown) {
        return MainDatabase.convertMarkdownToHtml(markdown);
    }

    function fileIconName(filename) {
        return MainDatabase.fileIconName(filename);
    }

    function removeAttachedFile(index) {
        return MainDatabase.removeAttachedFile(index);
    }

    function getDocExtractorPath() {
        return MainDatabase.getDocExtractorPath();
    }

    function getHelperPath() {
        return MainDatabase.getHelperPath();
    }

    function getScriptsPath() {
        return MainDatabase.getScriptsPath();
    }

    function attachFile(fileUrl) {
        return MainDatabase.attachFile(fileUrl);
    }

    // Split raw markdown into typed blocks: {type:"text"|"code"|"table", content, lang}
    function parseMessageBlocks(markdown) {
        return MainDatabase.parseMessageBlocks(markdown);
    }

    // Convert markdown table to CSV string
    function tableMarkdownToCsv(tableMarkdown) {
        return MainDatabase.tableMarkdownToCsv(tableMarkdown);
    }

    function buildMessageContent(text, attachments, apiType) {
        return MainDatabase.buildMessageContent(text, attachments, apiType);
    }

    function checkClipboardForAttachments() {
        return MainDatabase.checkClipboardForAttachments();
    }

    function readClipboardText() {
        return MainDatabase.readClipboardText();
    }

    function applyKWalletKeyToMemory(targetId, secretValue) {
        return MainScheduler.applyKWalletKeyToMemory(targetId, secretValue);
    }

    function walletBulkReadCommand(walletName) {
        return MainDatabase.walletBulkReadCommand(walletName);
    }

    function triggerKWalletCallbacks(success, errorMsg) {
        return MainScheduler.triggerKWalletCallbacks(success, errorMsg);
    }

    function loadKWalletKeysIfNeeded(onSuccess, onFailure) {
        return MainScheduler.loadKWalletKeysIfNeeded(onSuccess, onFailure);
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
        return MainDatabase.performExportChat(filePath);
    }

    function removeLastErrorMessages() {
        return MainDatabase.removeLastErrorMessages();
    }

    function retryLastFailedMessage() {
        return MainDatabase.retryLastFailedMessage();
    }

    function resetOpenCodeIdleKillTimer() {
        return MainDatabase.resetOpenCodeIdleKillTimer();
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
    onCurrentSessionIdChanged: {
        // Switches are rare; flush any pending debounced write so the
        // next session starts from a fully persisted baseline.
        if (persistSessionsDebounce.running) {
            persistSessionsDebounce.stop();
            root.flushPersistSessions();
        }
        resetOpenCodeIdleKillTimer();
        root._markdownCache.clear();
        root._blocksCache.clear();
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
    onExpandedChanged: {
        if (expanded) {
            root.focusInput();
            checkAndMarkCurrentSessionAsRead();
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
    onMessagesChanged: {
        if (root.messages) {
            for (let i = 0; i < root.messages.length; i++) {
                let m = root.messages[i];
                if (m && m.content !== undefined && (m.blocks === undefined || m.lastParsedContent !== m.content)) {
                    m.blocks = root.parseMessageBlocks(m.content);
                    m.lastParsedContent = m.content;
                }
            }
        }
        if (!root.historyOnlyMode && !root.userScrolledUp)
            Qt.callLater(scrollToBottom);

        checkAndMarkCurrentSessionAsRead();
    }

    MainDataSources {
        id: dataSources
        root: root
    }

    property alias soundDs: dataSources.soundDs
    property alias clipboardDs: dataSources.clipboardDs
    property alias schedulerDs: dataSources.schedulerDs
    property alias openCodeReconnectTimer: dataSources.openCodeReconnectTimer
    property alias persistSessionsDebounce: dataSources.persistSessionsDebounce
    property alias streamingBatchTimer: dataSources.streamingBatchTimer
    property alias openCodeIdleKillTimer: dataSources.openCodeIdleKillTimer
    property alias openCodeStartPollTimer: dataSources.openCodeStartPollTimer
    property alias schedulerPollTimer: dataSources.schedulerPollTimer
    property alias autoStartOpenCodeTimer: dataSources.autoStartOpenCodeTimer
    property alias opencodeServerDs: dataSources.opencodeServerDs
    property alias fileReaderDs: dataSources.fileReaderDs
    property alias customStorageDs: dataSources.customStorageDs
    property alias fileDialog: dataSources.fileDialog
    property alias exportFileDialog: dataSources.exportFileDialog
    property alias clipboardHelper: dataSources.clipboardHelper
    property alias kwalletStartupDs: dataSources.kwalletStartupDs
    property alias opencodeTerminalDs: dataSources.opencodeTerminalDs
    property alias openCodePollTimer: dataSources.openCodePollTimer

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
