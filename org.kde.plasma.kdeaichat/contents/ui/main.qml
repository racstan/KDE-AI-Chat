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

PlasmoidItem {
    // No custom text and no way to read options from here,
    // so prompt user to type something or click an option
    // The option buttons themselves handle single-click submit
    // for non-multiple mode

    id: root

    property bool debugMode: false
    function debugLog() {
        return MainDatabase.debugLog(root);
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
    property bool configOpenCodeAutoKill: !!plasmoid.configuration.openCodeAutoKill
    property int configOpenCodeAutoKillMinutes: plasmoid.configuration.openCodeAutoKillMinutes || 5
    property bool kwalletKeysLoaded: false
    property int kwalletOpenAttempts: 0
    property bool kwalletLoading: false
    property var kwalletLoadSuccessCallbacks: []
    property var kwalletLoadFailureCallbacks: []
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
        return MainDatabase.sessionHasSchedules(root, sessionId);
    }

    function triggerConfigure() {
        return MainDatabase.triggerConfigure(root);
    }

    function focusInput() {
        return MainDatabase.focusInput(root);
    }

    function searchNext() {
        return MainDatabase.searchNext(root);
    }

    function searchPrev() {
        return MainDatabase.searchPrev(root);
    }

    function pad2(v) {
        return MainDatabase.pad2(root, v);
    }

    function nowTime(ts) {
        return MainDatabase.nowTime(root, ts);
    }

    function formatDateTime(ts) {
        return MainDatabase.formatDateTime(root, ts);
    }

    function makeSessionId() {
        return MainDatabase.makeSessionId(root);
    }

    // Centralized helper for reporting a benign parse failure (e.g. an
    // OpenCode / clipboard / custom-history reply we could not decode).
    // Always logs to console for diagnostics and surfaces a non-blocking
    // notification to the user, so the failure is never silently dropped.
    function reportParseFailure(context, error) {
        return MainDatabase.reportParseFailure(root, context, error);
    }

    function makeForkSessionId() {
        return MainDatabase.makeForkSessionId(root);
    }

    function forkSession(messageIndex) {
        return MainDatabase.forkSession(root, messageIndex);
    }

    // ── /schedule command handler ──────────────────────────────────────────────
    function handleScheduleCommand(messageText) {
        return MainScheduler.handleScheduleCommand(root, messageText);
    }

    function toggleScheduleEnabled(schedId, newEnabled) {
        return MainScheduler.toggleScheduleEnabled(root, schedId, newEnabled);
    }

    function injectScheduledMessage(chatId, messageText, notify, schedId, schedName) {
        return MainScheduler.injectScheduledMessage(root, chatId, messageText, notify, schedId, schedName);
    }

    function parseSessions(customRaw) {
        return MainDatabase.parseSessions(root, customRaw);
    }

    function checkAndMarkCurrentSessionAsRead() {
        return MainDatabase.checkAndMarkCurrentSessionAsRead(root);
    }

    function base64Encode(str) {
        return MainNetwork.base64Encode(root, str);
    }

    function base64Decode(str) {
        return MainNetwork.base64Decode(root, str);
    }

    function getHistoryFilePath(customDir) {
        return MainDatabase.getHistoryFilePath(root, customDir);
    }

    function migrateHistory(oldPath, newPath) {
        return MainDatabase.migrateHistory(root, oldPath, newPath);
    }

    function persistSessions() {
        return MainDatabase.persistSessions(root);
    }

    function flushPersistSessions() {
        return MainDatabase.flushPersistSessions(root);
    }

    function sortSessionsByUpdated() {
        return MainDatabase.sortSessionsByUpdated(root);
    }

    function historySessionTint(sessionData) {
        return MainDatabase.historySessionTint(root, sessionData);
    }

    function sessionSubtitle(sessionData) {
        return MainDatabase.sessionSubtitle(root, sessionData);
    }

    function sessionIndexById(sessionId) {
        return MainDatabase.sessionIndexById(root, sessionId);
    }

    function createSession(switchToNew) {
        return MainDatabase.createSession(root, switchToNew);
    }

    function loadSessions() {
        return MainDatabase.loadSessions(root);
    }

    function saveCurrentSessionState(touchUpdatedAt) {
        return MainDatabase.saveCurrentSessionState(root, touchUpdatedAt);
    }

    function setCurrentSessionSource(source) {
        return MainDatabase.setCurrentSessionSource(root, source);
    }

    function setSessionArchived(sessionId, archived) {
        return MainDatabase.setSessionArchived(root, sessionId, archived);
    }

    function switchSession(sessionId) {
        return MainDatabase.switchSession(root, sessionId);
    }

    function renameCurrentSession(newTitle) {
        return MainDatabase.renameCurrentSession(root, newTitle);
    }

    function startSessionRename(sessionId) {
        return MainDatabase.startSessionRename(root, sessionId);
    }

    function cancelSessionRename() {
        return MainDatabase.cancelSessionRename(root);
    }

    function saveSessionRename(sessionId) {
        return MainDatabase.saveSessionRename(root, sessionId);
    }

    function deleteSession(sessionId) {
        return MainDatabase.deleteSession(root, sessionId);
    }

    function deleteMessage(index) {
        return MainDatabase.deleteMessage(root, index);
    }

    function saveEditedMessage() {
        return MainDatabase.saveEditedMessage(root);
    }

    function openCodeBaseUrl() {
        return MainOpenCode.openCodeBaseUrl(root);
    }

    function currentOpenCodeSessionId() {
        return MainOpenCode.currentOpenCodeSessionId(root);
    }

    function setCurrentOpenCodeSessionId(remoteSessionId) {
        return MainOpenCode.setCurrentOpenCodeSessionId(root, remoteSessionId);
    }

    function clearCurrentOpenCodeSessionIfNeeded() {
        return MainOpenCode.clearCurrentOpenCodeSessionIfNeeded(root);
    }

    function getSessionProperty(sessionId, key, defaultValue) {
        return MainDatabase.getSessionProperty(root, sessionId, key, defaultValue);
    }

    function setSessionProperty(sessionId, key, value) {
        return MainDatabase.setSessionProperty(root, sessionId, key, value);
    }

    function appendCompactPromptMessage(chatId) {
        return MainDatabase.appendCompactPromptMessage(root, chatId);
    }

    function respondToCompactRequest(msgIndex, approved) {
        return MainDatabase.respondToCompactRequest(root, msgIndex, approved);
    }

    function touchSessionsList(chatId) {
        return MainDatabase.touchSessionsList(root, chatId);
    }

    function checkAndAutoCompact(sessionId) {
        return MainDatabase.checkAndAutoCompact(root, sessionId);
    }

    function compactSessionContext(sessionId) {
        return MainDatabase.compactSessionContext(root, sessionId);
    }

    function sendBackgroundSummarizationRequest(sId, promptText, count) {
        return MainDatabase.sendBackgroundSummarizationRequest(root, sId, promptText, count);
    }

    function updateAutocomplete() {
        return MainDatabase.updateAutocomplete(root);
    }

    function extractReadableError(prefix, errObj, fallbackText) {
        return MainDatabase.extractReadableError(root, prefix, errObj, fallbackText);
    }

    function beginAssistantStreaming(modelLabel) {
        return MainDatabase.beginAssistantStreaming(root, modelLabel);
    }

    function updateAssistantStreamingContent(text, modelLabel) {
        return MainDatabase.updateAssistantStreamingContent(root, text, modelLabel);
    }

    function finishOpenCodeRequest() {
        return MainNetwork.finishOpenCodeRequest(root);
    }

    // Handle slash commands in OpenCode mode.
    // Commands are dispatched to the appropriate handler:
    //  - /help, /session, /stats → local inline info (no server needed)
    //  - /models                 → REST API GET /v1/models
    //  - /version                → opencode --version (real CLI flag)
    //  - /export                 → syncOpenCodeSessionHistory() (REST API)
    //  - TUI-only commands       → friendly explanation shown inline
    function runLocalOpenCodeCommand(cmdText) {
        return MainDatabase.runLocalOpenCodeCommand(root, cmdText);
    }

    function syncOpenCodeSessionHistory() {
        return MainDatabase.syncOpenCodeSessionHistory(root);
    }

    function ensureOpenCodeEventStream() {
        return MainOpenCode.ensureOpenCodeEventStream(root);
    }

    function handleOpenCodeEvent(eventObj) {
        return MainDatabase.handleOpenCodeEvent(root, eventObj);
    }

    function appendSystemMessageToSession(chatId, text) {
        return MainDatabase.appendSystemMessageToSession(root, chatId, text);
    }

    function removeMessageFromSessionByTimestamp(chatId, timestamp) {
        return MainDatabase.removeMessageFromSessionByTimestamp(root, chatId, timestamp);
    }

    function scheduleMessageRemoval(chatId, timestamp, delayMs) {
        return MainDatabase.scheduleMessageRemoval(root, chatId, timestamp, delayMs);
    }

    function setOpenCodeSessionIdForChatId(chatId, remoteSessionId) {
        return MainDatabase.setOpenCodeSessionIdForChatId(root, chatId, remoteSessionId);
    }

    function ensureOpenCodeSessionForChatId(chatId, successCallback, failureCallback) {
        return MainDatabase.ensureOpenCodeSessionForChatId(root, chatId, successCallback, failureCallback);
    }

    function ensureCurrentOpenCodeSession(successCallback, failureCallback) {
        return MainOpenCode.ensureCurrentOpenCodeSession(root, successCallback, failureCallback);
    }

    function ensureOpenCodeServerRunning(chatId, successCallback, failureCallback) {
        return MainOpenCode.ensureOpenCodeServerRunning(root, chatId, successCallback, failureCallback);
    }

    function doOpenCodeRequest() {
        return MainOpenCode.doOpenCodeRequest(root);
    }

    function scrollToBottom() {
        return MainDatabase.scrollToBottom(root);
    }

    function scrollToMessageByTimestamp(timestamp) {
        return MainDatabase.scrollToMessageByTimestamp(root, timestamp);
    }

    function messageTimestampAt(index) {
        return MainDatabase.messageTimestampAt(root, index);
    }

    function messageDayKeyAt(index) {
        return MainDatabase.messageDayKeyAt(root, index);
    }

    function dayBucketLabel(ts) {
        return MainDatabase.dayBucketLabel(root, ts);
    }

    function countMessagesForDayKey(dayKey) {
        return MainDatabase.countMessagesForDayKey(root, dayKey);
    }

    function dayDividerLabelForIndex(index) {
        return MainDatabase.dayDividerLabelForIndex(root, index);
    }

    function formatMessageTime(message, index) {
        return MainDatabase.formatMessageTime(root, message, index);
    }

    function jumpOneMessageAbove() {
        return MainDatabase.jumpOneMessageAbove(root);
    }

    function jumpOneMessageBelow() {
        return MainDatabase.jumpOneMessageBelow(root);
    }

    function formatTokensUsage(tokens, cost) {
        return MainDatabase.formatTokensUsage(root, tokens, cost);
    }

    function pushErrorMessage(text) {
        return MainNetwork.pushErrorMessage(root, text);
    }

    function pushInfoMessage(text) {
        return MainDatabase.pushInfoMessage(root, text);
    }

    function appendUserMessage(text, role, attachments, isScheduled) {
        return MainDatabase.appendUserMessage(root, text, role, attachments, isScheduled);
    }

    function appendSystemMessage(text) {
        return MainDatabase.appendSystemMessage(root, text);
    }

    function getSchedulesForSession(sessionId) {
        return MainDatabase.getSchedulesForSession(root, sessionId);
    }

    function validateCurrentSendTarget() {
        return MainNetwork.validateCurrentSendTarget(root);
    }

    function sendMessageByIndex(index) {
        return MainDatabase.sendMessageByIndex(root, index);
    }

    function processNextQueuedMessage() {
        return MainDatabase.processNextQueuedMessage(root);
    }

    function providerDisplayName(providerId) {
        return MainDatabase.providerDisplayName(root, providerId);
    }

    function validateOpenCodeConfig() {
        return MainDatabase.validateOpenCodeConfig(root);
    }

    function validateProviderConfig(providerId, cfg) {
        return MainDatabase.validateProviderConfig(root, providerId, cfg);
    }

    function sendMessage() {
        return MainDatabase.sendMessage(root);
    }

    function getProviderConfig(provider) {
        return MainDatabase.getProviderConfig(root, provider);
    }

    function translate(text) {
        return MainDatabase.translate(root, text);
    }

    function isSessionScheduled(sessionId, messagesList) {
        return MainDatabase.isSessionScheduled(root, sessionId, messagesList);
    }

    function buildEffectiveSystemPrompt(sessionId) {
        return MainDatabase.buildEffectiveSystemPrompt(root, sessionId);
    }

    // Returns a filtered, context-limited list of {role, content} pairs.
    // System-status bubbles (error, schedules_list, info …) are excluded.
    // Messages before the compacted boundary are excluded.
    // Only the last N user/assistant messages are kept (N = per-session override OR global limit).
    function buildContextWindow(messagesList, sessionId) {
        return MainDatabase.buildContextWindow(root, messagesList, sessionId);
    }

    function buildOpenAICompatPayload() {
        return MainDatabase.buildOpenAICompatPayload(root);
    }

    function buildAnthropicPayload() {
        return MainDatabase.buildAnthropicPayload(root);
    }

    function buildOpenAICompatPayloadForMessages(messagesList, chatId) {
        return MainDatabase.buildOpenAICompatPayloadForMessages(root, messagesList, chatId);
    }

    function buildAnthropicPayloadForMessages(messagesList, chatId) {
        return MainNetwork.buildAnthropicPayloadForMessages(root, messagesList, chatId);
    }

    function _buildMessageArray(messagesList, chatId, format) {
        return MainDatabase._buildMessageArray(root, messagesList, chatId, format);
    }

    function appendMessageToSession(chatId, msgObj) {
        return MainDatabase.appendMessageToSession(root, chatId, msgObj);
    }

    function handleBackgroundError(chatId, errorMsg, notify, schedId, schedName) {
        return MainNetwork.handleBackgroundError(root, chatId, errorMsg, notify, schedId, schedName);
    }

    function doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName) {
        return MainOpenCode.doBackgroundOpenCodeRequest(root, chatId, messageText, notify, schedId, schedName);
    }

    function doBackgroundOpenAICompatRequest(chatId, baseUrl, apiKey, model, extraHeaders, modelLabel, messageText, notify, schedId, schedName) {
        return MainNetwork.doBackgroundOpenAICompatRequest(root, chatId, baseUrl, apiKey, model, extraHeaders, modelLabel, messageText, notify, schedId, schedName);
    }

    function doBackgroundAnthropicRequest(chatId, apiKey, model, messageText, notify, schedId, schedName) {
        return MainNetwork.doBackgroundAnthropicRequest(root, chatId, apiKey, model, messageText, notify, schedId, schedName);
    }

    function executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName) {
        return MainScheduler.executeScheduledMessageInBackground(root, chatId, messageText, notify, schedId, schedName);
    }

    function doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel) {
        return MainNetwork.doOpenAICompatRequest(root, baseUrl, apiKey, model, extraHeaders, modelLabel);
    }

    function doAnthropicRequest(apiKey, model) {
        return MainNetwork.doAnthropicRequest(root, apiKey, model);
    }

    function triggerNotificationSound() {
        return MainDatabase.triggerNotificationSound(root);
    }

    function respondToPermission(permissionId, approved) {
        return MainDatabase.respondToPermission(root, permissionId, approved);
    }

    // Collect selected options from the question UI and submit the answer
    function submitQuestionAnswer(questionId, questions, customField) {
        return MainDatabase.submitQuestionAnswer(root, questionId, questions, customField);
    }

    function respondToQuestion(questionId, answerValue, isReject) {
        return MainDatabase.respondToQuestion(root, questionId, answerValue, isReject);
    }

    function stopStreaming() {
        return MainDatabase.stopStreaming(root);
    }

    function convertMarkdownToHtml(markdown) {
        return MainDatabase.convertMarkdownToHtml(root, markdown);
    }

    function fileIconName(filename) {
        return MainDatabase.fileIconName(root, filename);
    }

    function removeAttachedFile(index) {
        return MainDatabase.removeAttachedFile(root, index);
    }

    function getDocExtractorPath() {
        return MainDatabase.getDocExtractorPath(root);
    }

    function getHelperPath() {
        return MainDatabase.getHelperPath(root);
    }

    function getScriptsPath() {
        return MainDatabase.getScriptsPath(root);
    }

    function attachFile(fileUrl) {
        return MainDatabase.attachFile(root, fileUrl);
    }

    // Split raw markdown into typed blocks: {type:"text"|"code"|"table", content, lang}
    function parseMessageBlocks(markdown) {
        return MainDatabase.parseMessageBlocks(root, markdown);
    }

    // Convert markdown table to CSV string
    function tableMarkdownToCsv(tableMarkdown) {
        return MainDatabase.tableMarkdownToCsv(root, tableMarkdown);
    }

    function buildMessageContent(text, attachments, apiType) {
        return MainDatabase.buildMessageContent(root, text, attachments, apiType);
    }

    function checkClipboardForAttachments() {
        return MainDatabase.checkClipboardForAttachments(root);
    }

    function readClipboardText() {
        return MainDatabase.readClipboardText(root);
    }

    function applyKWalletKeyToMemory(targetId, secretValue) {
        return MainScheduler.applyKWalletKeyToMemory(root, targetId, secretValue);
    }

    function walletBulkReadCommand(walletName) {
        return MainDatabase.walletBulkReadCommand(root, walletName);
    }

    function triggerKWalletCallbacks(success, errorMsg) {
        return MainScheduler.triggerKWalletCallbacks(root, success, errorMsg);
    }

    function loadKWalletKeysIfNeeded(onSuccess, onFailure) {
        return MainScheduler.loadKWalletKeysIfNeeded(root, onSuccess, onFailure);
    }

    function performExportChat(filePath) {
        return MainDatabase.performExportChat(root, filePath);
    }

    function removeLastErrorMessages() {
        return MainDatabase.removeLastErrorMessages(root);
    }

    function retryLastFailedMessage() {
        return MainDatabase.retryLastFailedMessage(root);
    }

    function resetOpenCodeIdleKillTimer() {
        return MainDatabase.resetOpenCodeIdleKillTimer(root);
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

    function copyToClipboard(textValue) {
        return MainDatabase.copyToClipboard(root, textValue);
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
                    // 1. Sync schedulesList
                    if (parsed && Array.isArray(parsed.schedules))
                        root.schedulesList = parsed.schedules;

                    // 2. Handle pending triggers
                    let triggers = (parsed && parsed.pending) || [];
                    if (Array.isArray(triggers) && triggers.length > 0) {
                        for (let i = 0; i < triggers.length; i++) {
                            let t = triggers[i];
                            if (t && t.message) {
                                let cid = t.chatId || "";
                                if (cid === "" || cid === "new") {
                                    // Create a new session first
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
                ensureOpenCodeEventStream();

        }
    }

    // Debounce timer for `persistSessions()`. Every state mutation
    // (message add, edit, archive, label change) calls
    // `persistSessions()`, which used to run the full JSON.stringify
    // + config write + Python helper pipeline on every keystroke.
    // The wrapper now schedules a single 1-Hz flush per burst of
    // changes. `flushPersistSessions()` forces an immediate flush
    // for code paths that need synchronous persistence (close,
    // settings save, manual refresh).
    Timer {
        id: persistSessionsDebounce
        interval: 1000
        repeat: false
        onTriggered: root.flushPersistSessions()
    }

    // Audit 5.1: batch streaming token updates to avoid full model
    // resets on every chunk. Tokens are buffered in `_pendingStreamingText`
    // and flushed at ~30 Hz instead of per-token. `flushStreamingBuffer()`
    // forces an immediate flush (used on stream end, cancel, and
    // session switch).
    property string _pendingStreamingText: ""
    property string _pendingStreamingModelLabel: ""
    property bool _streamingDirty: false
    Timer {
        id: streamingBatchTimer
        interval: 150
        repeat: false
        onTriggered: root.flushStreamingBuffer()
    }
    function flushStreamingBuffer() {
        return MainDatabase.flushStreamingBuffer(root);
    }

    Timer {
        id: openCodeIdleKillTimer

        interval: 300000 // 5 minutes
        repeat: false
        onTriggered: {
            if (root.openCodeMode && plasmoid.configuration.autoStartOpenCodeServer && root.configOpenCodeAutoKill) {
                let stopCmd = (plasmoid.configuration.openCodeStopCommand || "pkill -f opencode >/dev/null 2>&1 && echo ok").trim();
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

        interval: 1000
        repeat: false
        onTriggered: {
            retriesLeft--;
            let checkUrl = openCodeBaseUrl() + "/config/providers";
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

        interval: 30000
        repeat: true
        running: root.expanded
        triggeredOnStart: true
        onTriggered: {
            if (root.schedPolling)
                return ;

            root.schedPolling = true;
            let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " poll_pending_triggers";
            schedulerDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-poll-" + Date.now());
        }
    }

    // Fires after a short delay on startup when autoStartOpenCodeServer is enabled,
    // so session loading completes before we spawn the server process.
    Timer {
        id: autoStartOpenCodeTimer

        interval: 1500
        repeat: false
        onTriggered: {
            let cmd = (plasmoid.configuration.openCodeStartCommand || "logf=\"${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log\"; nohup opencode serve --port 4096 --hostname 127.0.0.1 >\"$logf\" 2>&1 & echo ok").trim();
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
                            } else if (res.mode === "image" && res.file) {
                                let fInfo = res.file;
                                let exists = false;
                                for (let idx = 0; idx < currentFiles.length; idx++) {
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
                        reportParseFailure("Failed to parse clipboard data", e);
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
            let fileObj = Object.assign({
            }, files[matchedIndex]);
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
                        let jsonStr = base64Decode(stdout.trim());
                        let arr = JSON.parse(jsonStr);
                        if (Array.isArray(arr)) {
                            root.sessions = parseSessions(arr);
                            if (root.sessions.length === 0)
                                createSession(true);

                            let preferred = plasmoid.configuration.lastSessionId || "";
                            let idx = sessionIndexById(preferred);
                            if (idx < 0)
                                idx = 0;

                            root.currentSessionId = root.sessions[idx].value;
                            root.currentSessionTitle = root.sessions[idx].text;
                            root.messages = root.sessions[idx].messages || [];
                            if (root.sessions[idx])
                                root.openCodeMode = (root.sessions[idx].source === "opencode");

                            sortSessionsByUpdated();
                            checkAndMarkCurrentSessionAsRead();
                            disconnectSource(sourceName);
                            return ;
                        }
                    } catch (e) {
                        reportParseFailure("Failed to parse custom history", e);
                    }
                }
                // Fallback & Seamless Migration:
                let oldJson = plasmoid.configuration.chatSessionsJson || "";
                if (oldJson !== "" && oldJson !== "[]") {
                    loadSessions();
                    persistSessions();
                } else {
                    loadSessions();
                }
                checkAndMarkCurrentSessionAsRead();
            } else if (sourceName.indexOf("#migrate-history") !== -1) {
                if (exitCode === 0 && stdout.trim() !== "") {
                    try {
                        let jsonRaw = base64Decode(stdout.trim());
                        let res = JSON.parse(jsonRaw);
                        if (res.status === "ok") {
                            if (res.action === "load" && res.content) {
                                let arrVal = JSON.parse(base64Decode(res.content));
                                if (Array.isArray(arrVal)) {
                                    root.sessions = parseSessions(arrVal);
                                    if (root.sessions.length === 0)
                                        createSession(true);

                                    let pref = plasmoid.configuration.lastSessionId || "";
                                    let idxVal = sessionIndexById(pref);
                                    if (idxVal < 0)
                                        idxVal = 0;

                                    root.currentSessionId = root.sessions[idxVal].value;
                                    root.currentSessionTitle = root.sessions[idxVal].text;
                                    root.messages = root.sessions[idxVal].messages || [];
                                    if (root.sessions[idxVal])
                                        root.openCodeMode = (root.sessions[idxVal].source === "opencode");

                                    sortSessionsByUpdated();
                                    checkAndMarkCurrentSessionAsRead();
                                    persistSessions();
                                }
                            } else if (res.action === "write_current" || res.action === "copied" || res.action === "exported") {
                                persistSessions();
                            }
                        } else {
                            console.warn("Migration failed: " + res.message);
                        }
                    } catch (e) {
                        console.error("Failed to parse migration output: " + e);
                    }
                }
            }
            disconnectSource(sourceName);
        }
    }

    FileDialog {
        id: fileDialog

        title: "Attach Files"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["All supported files (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.pdf *.csv *.docx *.txt *.md *.json)", "Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)", "Documents (*.pdf *.docx *.csv *.txt *.md *.json)", "All files (*)"]
        onAccepted: {
            for (let i = 0; i < selectedFiles.length; i++) {
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
            let path = selectedFile.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            root.performExportChat(path);
        }
    }

    // Invisible text editor acting as helper to interact with OS text clipboard (copy / paste)
    TextEdit {
        id: clipboardHelper

        visible: false
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
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line.indexOf("__KAI_BULK__:OPEN_FAILED") === 0) {
                        openFailed = true;
                        openFailedMsg = "KWallet open failed.";
                    } else if (line.indexOf("__KAI_BULK__:NO_WALLET") === 0) {
                        openFailed = true;
                        openFailedMsg = "Configured KWallet not found.";
                    } else if (line.indexOf("__KAI_SECRET__:") === 0) {
                        let rest = line.slice("__KAI_SECRET__:".length);
                        let sep = rest.indexOf(":");
                        if (sep > 0) {
                            let targetId = rest.slice(0, sep);
                            let secretValue = rest.slice(sep + 1);
                            applyKWalletKeyToMemory(targetId, secretValue);
                        }
                    }
                }
                if (openFailed) {
                    root.kwalletKeysLoaded = false;
                    root.kwalletOpenAttempts++;
                    debugLog("[KAI-DEBUG] KWallet open failed (attempt " + root.kwalletOpenAttempts + " of 3)");
                    triggerKWalletCallbacks(false, openFailedMsg);
                } else {
                    root.kwalletOpenAttempts = 0;
                    root.kwalletKeysLoaded = true;
                    triggerKWalletCallbacks(true);
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
                // Detect opencode not installed
                if (exitCode !== undefined && (output.indexOf("not found") >= 0 || output.indexOf("No such file") >= 0 || output === "")) {
                    root.loading = false;
                    finishOpenCodeRequest();
                    pushErrorMessage("**OpenCode is not installed or not in PATH.**\nInstall it with:\n```\nnpm install -g opencode-ai\n```\nor visit https://opencode.ai for instructions.");
                    disconnectSource(sourceName);
                    return ;
                }
                if (output !== "")
                    updateAssistantStreamingContent(output, "OpenCode CLI");

                if (exitCode !== undefined) {
                    root.loading = false;
                    finishOpenCodeRequest();
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
            xhr.open("GET", openCodeBaseUrl() + "/", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                if (xhr.status >= 200 && xhr.status < 300) {
                    openCodePollTimer.stop();
                    pushInfoMessage("OpenCode server is online. Resuming thread...");
                    removeLastErrorMessages();
                    retryLastFailedMessage();
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
                pushErrorMessage("OpenCode server failed to start in time. Check logs in ${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log");
                return ;
            }
            checkServerStatus();
        }
    }

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
