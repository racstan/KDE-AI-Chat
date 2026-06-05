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

PlasmoidItem {
    // No custom text and no way to read options from here,
    // so prompt user to type something or click an option
    // The option buttons themselves handle single-click submit
    // for non-multiple mode

    id: root

    property bool debugMode: false
    function debugLog() {
        if (debugMode) {
            let args = Array.prototype.slice.call(arguments);
            console.log.apply(console, args);
        }
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
    // Root-level proxies so root-scope functions can reach UI elements in fullRepresentation
    property string chatInputText: ""
    property var msgListViewRef: null
    property var msgInputRef: null
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
            if (root.sessionsSidebar && root.sessionsSidebar.visible) {
                if (root.searchBarActive) {
                    root.searchBarActive = false;
                    root.searchQuery = "";
                } else {
                    root.searchBarActive = true;
                }
                root.focusInput();
            } else {
                root.searchBarActive = true;
                root.focusInput();
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
        if (!sessionId)
            return false;

        for (let i = 0; i < root.schedulesList.length; i++) {
            let s = root.schedulesList[i];
            if (s && s.enabled && s.chatId === sessionId)
                return true;

        }
        return false;
    }

    function triggerConfigure() {
        if (typeof plasmoid.containment !== "undefined" && typeof plasmoid.containment.configureRequested === "function") {
            plasmoid.containment.configureRequested(plasmoid);
        } else if (typeof root.plasmoidRef !== "undefined" && typeof root.plasmoidRef.configureRequested === "function") {
            root.plasmoidRef.configureRequested();
        } else if (typeof plasmoid.configureRequested === "function") {
            plasmoid.configureRequested();
        } else if (typeof root.plasmoidRef !== "undefined" && typeof root.plasmoidRef.action === "function") {
            let act = root.plasmoidRef.action("configure");
            if (act && typeof act.trigger === "function")
                act.trigger();

        } else if (typeof plasmoid.action === "function") {
            let act2 = plasmoid.action("configure");
            if (act2 && typeof act2.trigger === "function")
                act2.trigger();

        }
    }

    function focusInput() {
        Qt.callLater(function() {
            if (typeof msgInput !== "undefined" && msgInput) {
                msgInput.forceActiveFocus();
                if (typeof msgInput.focusTimerRef !== "undefined" && msgInput.focusTimerRef)
                    msgInput.focusTimerRef.start();

            }
        });
    }

    function searchNext() {
        if (root.searchMatches.length === 0) return;
        root.currentSearchMatchIndex = (root.currentSearchMatchIndex + 1) % root.searchMatches.length;
        if (root.msgListViewRef) {
            root.msgListViewRef.positionViewAtIndex(root.searchMatches[root.currentSearchMatchIndex], ListView.Center);
        }
    }

    function searchPrev() {
        if (root.searchMatches.length === 0) return;
        root.currentSearchMatchIndex = (root.currentSearchMatchIndex - 1 + root.searchMatches.length) % root.searchMatches.length;
        if (root.msgListViewRef) {
            root.msgListViewRef.positionViewAtIndex(root.searchMatches[root.currentSearchMatchIndex], ListView.Center);
        }
    }

    function pad2(v) {
        return v < 10 ? ("0" + v) : String(v);
    }

    function nowTime(ts) {
        let d = ts ? new Date(ts) : new Date();
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
        return SessionManager.makeSessionId();
    }

    // Centralized helper for reporting a benign parse failure (e.g. an
    // OpenCode / clipboard / custom-history reply we could not decode).
    // Always logs to console for diagnostics and surfaces a non-blocking
    // notification to the user, so the failure is never silently dropped.
    function reportParseFailure(context, error) {
        let msg = (context || "Parse failure") + ": " + (error && error.toString ? error.toString() : String(error || ""));
        console.warn(msg);
        pushErrorMessage(msg);
    }

    function makeForkSessionId() {
        return SessionManager.makeForkSessionId();
    }

    function forkSession(messageIndex) {
        if (root.currentSessionId === "")
            return ;

        let idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        let originalSession = root.sessions[idx];
        let forkedMessages = [];
        if (originalSession.messages && messageIndex >= 0 && messageIndex < originalSession.messages.length) {
            for (let i = 0; i <= messageIndex; i++) {
                forkedMessages.push(JSON.parse(JSON.stringify(originalSession.messages[i])));
            }
        }
        let forkId = makeForkSessionId();
        let originalTitle = originalSession.text || "New Chat";
        let cleanTitle = originalTitle.indexOf("[FK] ") === 0 ? originalTitle.substring(5) : originalTitle;
        let forkTitle = "[FK] " + cleanTitle;
        let s = {
            "value": forkId,
            "text": forkTitle,
            "createdAt": Date.now(),
            "updatedAt": Date.now(),
            "archived": false,
            "source": originalSession.source || "provider",
            "openCodeSessionId": originalSession.openCodeSessionId || "",
            "parentSessionId": originalSession.value,
            "parentSessionTitle": originalSession.text || "Original Chat",
            "readCount": forkedMessages.length,
            "messages": forkedMessages
        };
        root.sessions = [s].concat(root.sessions);
        root.openCodeMode = (s.source === "opencode");
        root.currentSessionId = s.value;
        root.currentSessionTitle = s.text;
        root.messages = forkedMessages;
        root.editingMessageIndex = -1;
        root.editingDraft = "";
        root.editingSessionId = "";
        root.editingSessionDraft = "";
        root.renamingCurrentChat = false;
        root.currentChatRenameDraft = "";
        root.historyOnlyMode = false;
        persistSessions();
        scrollToBottom();
        root.focusInput();
    }

    // ── /schedule command handler ──────────────────────────────────────────────
    function handleScheduleCommand(messageText) {
        scheduleCommandDialog.prefillMessage = messageText;
        scheduleCommandDialog.chatId = root.currentSessionId;
        scheduleCommandDialog.chatName = root.currentSessionTitle || "Current chat";
        scheduleCommandDialog.open();
    }

    function toggleScheduleEnabled(schedId, newEnabled) {
        let payload = {
            "schedId": schedId,
            "enabled": newEnabled
        };
        let b64Payload = base64Encode(JSON.stringify(payload));
        let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " toggle_schedule " + Sec.quoteForShell(b64Payload);
        schedulerDs.connectSource("sh -lc " + Sec.quoteForShell(cmd) + " #sched-toggle-" + Date.now());
        // Update local schedulesList immediately
        let copy = root.schedulesList.slice();
        for (let i = 0; i < copy.length; i++) {
            if (copy[i].id === schedId) {
                let s = Object.assign({
                }, copy[i]);
                s.enabled = newEnabled;
                if (newEnabled)
                    s.nextRunAt = "";

                copy[i] = s;
            }
        }
        root.schedulesList = copy;
        root.appendSystemMessage(newEnabled ? "Schedule resumed successfully." : "Schedule paused successfully.");
    }

    function injectScheduledMessage(chatId, messageText, notify, schedId, schedName) {
        if (!chatId || !messageText)
            return ;

        // Switch to the correct session
        let idx = sessionIndexById(chatId);
        if (idx < 0) {
            console.warn("injectScheduledMessage: Target session " + chatId + " not found, ignoring schedule execution.");
            return ;
        }
        if (chatId !== root.currentSessionId) {
            executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName);
            return ;
        }
        // Play the custom scheduled execution sound
        let soundCmd = "pw-play /usr/share/sounds/ocean/stereo/service-login.oga || " + "paplay /usr/share/sounds/ocean/stereo/service-login.oga || " + "pw-play /usr/share/sounds/ocean/stereo/window-attention.oga || " + "paplay /usr/share/sounds/ocean/stereo/window-attention.oga || " + "aplay /usr/share/sounds/freedesktop/stereo/bell.oga || " + "canberra-gtk-play -i service-login";
        soundDs.connectSource(soundCmd + " #sched-sound-" + Date.now());
        // Validate provider/model configuration before executing
        let validationError = validateCurrentSendTarget();
            if (validationError !== "") {
                // Push validation error into chat window
                pushErrorMessage(validationError);
                // Display critical desktop notification popup of the configuration failure
                if (notify) {
                    let safeErr = Sec.sanitizeForShell(validationError);
                    let errTitle = "Schedule Failed: " + (schedName || root.currentSessionTitle || "Chat");
                    let safeErrTitle = Sec.sanitizeForShell(errTitle);
                    soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning " + Sec.quoteForShell(safeErrTitle) + " " + Sec.quoteForShell(safeErr) + " #sched-notify-err");
                }
            // Sync the detailed failure back to the scheduler's run history log
            if (schedId) {
                let historyPayload = {
                    "schedId": schedId,
                    "status": validationError
                };
                let b64HistoryPayload = base64Encode(JSON.stringify(historyPayload));
                let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " update_schedule_history_status " + Sec.quoteForShell(b64HistoryPayload);
                soundDs.connectSource("sh -lc " + Sec.quoteForShell(cmd) + " #sched-history-err");
            }
            return ;
        }
        // Append user message
        appendUserMessage(messageText, "user", [], true);
        // Trigger LLM generation
        sendMessageByIndex(root.messages.length - 1);
        // Show a desktop notification
        if (notify) {
            let safeText = Sec.sanitizeForShell(messageText.substring(0, 150)) + (messageText.length > 150 ? "…" : "");
            let title = "Scheduled: " + (root.currentSessionTitle || "Chat");
            let safeTitle = Sec.sanitizeForShell(title);
            soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information " + Sec.quoteForShell(safeTitle) + " " + Sec.quoteForShell(safeText) + " #sched-notify");
        }
    }

    function parseSessions(customRaw) {
        let raw = customRaw !== undefined ? customRaw : (plasmoid.configuration.chatSessionsJson || "[]");
        try {
            let arr = typeof raw === "string" ? JSON.parse(raw) : raw;
            if (Array.isArray(arr)) {
                for (let i = 0; i < arr.length; i++) {
                    if (!arr[i].messages)
                        arr[i].messages = [];

                    if (arr[i].archived === undefined)
                        arr[i].archived = false;

                    if (!arr[i].source)
                        arr[i].source = arr[i].openCodeSessionId ? "opencode" : "provider";

                    if (arr[i].readCount === undefined)
                        arr[i].readCount = arr[i].messages.length;

                    for (let j = 0; j < arr[i].messages.length; j++) {
                        if (!arr[i].messages[j].at)
                            arr[i].messages[j].at = arr[i].updatedAt || arr[i].createdAt || Date.now();

                        if (!arr[i].messages[j].time)
                            arr[i].messages[j].time = nowTime(arr[i].messages[j].at);

                    }
                    if (!arr[i].updatedAt)
                        arr[i].updatedAt = arr[i].createdAt || Date.now();

                }
                return arr;
            }
            return [];
        } catch (e) {
            return [];
        }
    }

    function checkAndMarkCurrentSessionAsRead() {
        if (root.expanded && !root.historyOnlyMode && root.currentSessionId !== "") {
            let idx = sessionIndexById(root.currentSessionId);
            if (idx >= 0) {
                let s = root.sessions[idx];
                let currentMsgsCount = root.messages.length;
                if (s.readCount !== currentMsgsCount) {
                    let updated = root.sessions.slice();
                    let item = Object.assign({
                    }, updated[idx]);
                    item.readCount = currentMsgsCount;
                    item.messages = root.messages;
                    updated[idx] = item;
                    root.sessions = updated;
                    persistSessions();
                }
            }
        }
    }

    function base64Encode(str) {
        try {
            return Qt.btoa(unescape(encodeURIComponent(str)));
        } catch (e) {
            console.error("base64Encode error:", e);
            return "";
        }
    }

    function base64Decode(str) {
        try {
            return decodeURIComponent(escape(Qt.atob(str)));
        } catch (e) {
            console.error("base64Decode error:", e);
            try {
                return Qt.atob(str);
            } catch (err) {
                return "";
            }
        }
    }

    function getHistoryFilePath(customDir) {
        let dir = (customDir || "").trim();
        if (dir === "")
            return "";

        if (dir.indexOf("file://") === 0)
            dir = decodeURIComponent(dir.slice(7));

        let fullPath = dir;
        if (!fullPath.endsWith(".json")) {
            if (fullPath.endsWith("/"))
                fullPath += "kdeaichat_history.json";
            else
                fullPath += "/kdeaichat_history.json";
        }
        return fullPath;
    }

    function migrateHistory(oldPath, newPath) {
        let oldFullPath = getHistoryFilePath(oldPath);
        let newFullPath = getHistoryFilePath(newPath);
        // When switching TO a custom path, always export current in-memory sessions
        // to the new location, then fall back to copying the old file if it exists.
        let currentJson = JSON.stringify(root.sessions);
        let b64Current = base64Encode(currentJson);
        let payload = {
            "oldFullPath": oldFullPath,
            "newFullPath": newFullPath,
            "currentB64": b64Current
        };
        let b64Payload = base64Encode(JSON.stringify(payload));
        let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " migrate_history " + Sec.quoteForShell(b64Payload);
        customStorageDs.connectSource(cmd + " #migrate-history-" + Date.now());
    }

    function persistSessions() {
        // Debounce: schedule a flush within the next 1 second. Bursts
        // of state changes (streaming tokens, typing, label edits) all
        // collapse into a single write instead of one per call.
        persistSessionsDebounce.restart();
    }

    function flushPersistSessions() {
        let jsonStr = JSON.stringify(root.sessions);
        plasmoid.configuration.chatSessionsJson = jsonStr;
        plasmoid.configuration.lastSessionId = root.currentSessionId;
        let customDir = (plasmoid.configuration.customHistoryPath || "").trim();
        if (customDir !== "") {
            let fullPath = getHistoryFilePath(customDir);
            let b64Str = base64Encode(jsonStr);
            let payload = {
                "fullPath": fullPath,
                "b64Str": b64Str
            };
            let b64Payload = base64Encode(JSON.stringify(payload));
            let writeCmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " write_history " + Sec.quoteForShell(b64Payload);
            customStorageDs.connectSource(writeCmd + " #custom-history-write-" + Date.now());
        }
    }

    function sortSessionsByUpdated() {
        // Audit 5.3: skip the O(n log n) sort + array reassignment cascade
        // when the list is already in canonical order. The reassignment
        // was the dominant cost during streaming because it invalidated
        // all sidebar binding caches on every save.
        if (SessionManager.isSessionOrderCorrect(root.sessions))
            return ;

        let copy = SessionManager.sortSessionsByUpdated(root.sessions);
        root.sessions = copy;
    }

    function historySessionTint(sessionData) {
        if (!sessionData)
            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05);

        if (sessionData.value === root.currentSessionId && sessionData.source === "opencode")
            return Qt.rgba(0.2, 0.48, 0.92, 0.22);

        if (sessionData.source === "opencode")
            return Qt.rgba(0.2, 0.48, 0.92, 0.1);

        if (sessionData.value === root.currentSessionId)
            return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18);

        return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05);
    }

    function sessionSubtitle(sessionData) {
        let parts = [];

        if (sessionData.source === "opencode")
            parts.push("OpenCode");

        if (sessionData.archived)
            parts.push("Archived");

        parts.push("Updated " + root.formatDateTime(sessionData.updatedAt || sessionData.createdAt || Date.now()));
        return parts.join(" · ");
    }

    function sessionIndexById(sessionId) {
        for (let i = 0; i < root.sessions.length; i++) {
            if (root.sessions[i].value === sessionId)
                return i;

        }
        return -1;
    }

    function createSession(switchToNew) {
        let mode = plasmoid.configuration.useOpenCode;
        let s = {
            "value": makeSessionId(),
            "text": "New Chat",
            "createdAt": Date.now(),
            "updatedAt": Date.now(),
            "archived": false,
            "source": mode ? "opencode" : "provider",
            "openCodeSessionId": "",
            "readCount": 0,
            "messages": []
        };
        root.sessions = [s].concat(root.sessions);
        if (switchToNew) {
            root.openCodeMode = mode;
            root.currentSessionId = s.value;
            root.currentSessionTitle = s.text;
            root.messages = [];
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

    function loadSessions() {
        root.sessions = parseSessions();
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
    }

    function saveCurrentSessionState(touchUpdatedAt) {
        let idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        let updated = root.sessions.slice();
        let s = Object.assign({
        }, updated[idx]);
        s.text = root.currentSessionTitle || "New Chat";
        s.messages = root.messages;
        if (root.expanded && !root.historyOnlyMode)
            s.readCount = root.messages.length;
        else
            s.readCount = s.readCount !== undefined ? s.readCount : root.messages.length;
        if (touchUpdatedAt !== false)
            s.updatedAt = Date.now();

        updated[idx] = s;
        root.sessions = updated;
        if (touchUpdatedAt !== false)
            sortSessionsByUpdated();

        persistSessions();
    }

    function setCurrentSessionSource(source) {
        let idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        let updated = root.sessions.slice();
        let item = Object.assign({
        }, updated[idx]);
        item.source = source || "provider";
        item.archived = false;
        updated[idx] = item;
        root.sessions = updated;
        persistSessions();
    }

    function setSessionArchived(sessionId, archived) {
        let idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        let updated = root.sessions.slice();
        let item = Object.assign({
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

        saveCurrentSessionState(false);
        let idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        root.currentSessionId = root.sessions[idx].value;
        root.currentSessionTitle = root.sessions[idx].text;
        root.messages = root.sessions[idx].messages || [];
        if (root.sessions[idx])
            root.openCodeMode = (root.sessions[idx].source === "opencode");

        root.editingMessageIndex = -1;
        root.editingDraft = "";
        root.editingSessionId = "";
        root.editingSessionDraft = "";
        root.renamingCurrentChat = false;
        root.currentChatRenameDraft = "";
        checkAndMarkCurrentSessionAsRead();
        persistSessions();
        scrollToBottom();
        root.focusInput();
    }

    function renameCurrentSession(newTitle) {
        let title = (newTitle || "").trim();
        if (title === "")
            title = "New Chat";

        root.currentSessionTitle = title;
        saveCurrentSessionState(true);
    }

    function startSessionRename(sessionId) {
        let idx = sessionIndexById(sessionId);
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
        let idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        let title = (root.editingSessionDraft || "").trim();
        if (title === "")
            title = "New Chat";

        let updated = root.sessions.slice();
        let s = Object.assign({
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

        let idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        let updated = root.sessions.slice();
        updated.splice(idx, 1);
        root.sessions = updated;
        if (root.currentSessionId === sessionId) {
            let next = root.sessions[0];
            root.currentSessionId = next.value;
            root.currentSessionTitle = next.text;
            root.messages = next.messages || [];
        }
        cancelSessionRename();
        persistSessions();
        // Clean up schedules associated with this session
        let payload = {
            "sessionId": sessionId
        };
        let b64Payload = base64Encode(JSON.stringify(payload));
        let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " delete_session_schedules " + Sec.quoteForShell(b64Payload);
        schedulerDs.connectSource("sh -lc " + Sec.quoteForShell(cmd) + " #sched-session-delete-" + Date.now());
        // Also update root.schedulesList locally
        let copy = root.schedulesList.filter(function(s) {
            return s.chatId !== sessionId;
        });
        root.schedulesList = copy;
    }

    function deleteMessage(index) {
        let copy = root.messages.slice();
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
        let i = root.editingMessageIndex;
        if (i < 0 || i >= root.messages.length)
            return ;

        if ((root.messages[i].role || "") === "error") {
            root.editingMessageIndex = -1;
            root.editingDraft = "";
            return ;
        }
        // Cancel any active streaming/loading requests first
        stopStreaming();
        let role = root.messages[i].role || "";
        let isQueued = role === "queued";
        let copy = isQueued ? root.messages.slice() : root.messages.slice(0, i + 1);
        let item = Object.assign({
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
        return root.openCodeBaseUrlVal;
    }

    function currentOpenCodeSessionId() {
        let sId = root.currentSessionId;
        let override = getSessionProperty(sId, "contextOverride", false);
        let contextEnabled = override ? getSessionProperty(sId, "contextEnabled", true) : plasmoid.configuration.globalContextEnabled;
        if (!contextEnabled)
            return "";

        let idx = sessionIndexById(sId);
        if (idx < 0)
            return "";

        return root.sessions[idx].openCodeSessionId || "";
    }

    function setCurrentOpenCodeSessionId(remoteSessionId) {
        let idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        let updated = root.sessions.slice();
        let item = Object.assign({
        }, updated[idx]);
        item.openCodeSessionId = remoteSessionId || "";
        updated[idx] = item;
        root.sessions = updated;
        persistSessions();
    }

    function clearCurrentOpenCodeSessionIfNeeded() {
        if (!root.openCodeMode)
            return ;

        setCurrentOpenCodeSessionId("");
    }

    function getSessionProperty(sessionId, key, defaultValue) {
        let idx = sessionIndexById(sessionId);
        if (idx < 0)
            return defaultValue;

        let val = root.sessions[idx][key];
        return val !== undefined ? val : defaultValue;
    }

    function setSessionProperty(sessionId, key, value) {
        let idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        let updated = root.sessions.slice();
        let item = Object.assign({
        }, updated[idx]);
        item[key] = value;
        updated[idx] = item;
        root.sessions = updated;
        persistSessions();
    }

    function appendCompactPromptMessage(chatId) {
        let ts = Date.now();
        let msgObj = {
            "role": "compact_request",
            "status": "pending",
            "content": "The conversation history has exceeded the configured threshold. Would you like to compact the older history into a concise summary to stay within context limit?",
            "time": nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": 0,
            "attachments": [],
            "isSystem": true
        };
        appendMessageToSession(chatId, msgObj);
        if (chatId === root.currentSessionId) {
            if (!root.userScrolledUp)
                Qt.callLater(scrollToBottom);
        }
    }

    function respondToCompactRequest(msgIndex, approved) {
        let copy = root.messages.slice();
        if (msgIndex < 0 || msgIndex >= copy.length)
            return;

        let msgObj = Object.assign({}, copy[msgIndex]);
        if (msgObj.role !== "compact_request")
            return;

        if (approved) {
            msgObj.status = "compacted";
            copy[msgIndex] = msgObj;
            root.messages = copy;
            saveCurrentSessionState(touchSessionsList(root.currentSessionId));
            compactSessionContext(root.currentSessionId);
        } else {
            msgObj.status = "cancelled";
            copy[msgIndex] = msgObj;
            root.messages = copy;
            saveCurrentSessionState(touchSessionsList(root.currentSessionId));
        }
    }

    function touchSessionsList(chatId) {
        // Helper to force-notify sessions update on QML side
        let idx = sessionIndexById(chatId);
        if (idx >= 0) {
            let updated = root.sessions.slice();
            updated[idx].updatedAt = Date.now();
            root.sessions = updated;
        }
        return true;
    }

    function checkAndAutoCompact(sessionId) {
        let sId = sessionId || root.currentSessionId;
        let idx = sessionIndexById(sId);
        if (idx < 0)
            return ;

        let msgs = root.sessions[idx].messages || [];
        let lastUserMsg = null;
        for (let j = msgs.length - 1; j >= 0; j--) {
            if (msgs[j].role === "user" && !msgs[j].isSystem) {
                lastUserMsg = msgs[j];
                break;
            }
        }
        if (lastUserMsg && lastUserMsg.sc)
            return ;

        let override = getSessionProperty(sId, "contextOverride", false);
        let autoCompact = override ? getSessionProperty(sId, "contextAutoCompact", false) : plasmoid.configuration.globalContextAutoCompact;
        if (!autoCompact)
            return ;

        let threshold = override ? getSessionProperty(sId, "contextCompactThreshold", 10) : plasmoid.configuration.globalContextCompactThreshold;
        let compactedCount = getSessionProperty(sId, "compactedMessageCount", 0);

        for (let k = compactedCount; k < msgs.length; k++) {
            if (msgs[k].role === "compact_request")
                return ;
        }

        let uncompactedCleanCount = 0;
        for (let i = compactedCount; i < msgs.length; i++) {
            let role = msgs[i].role;
            if ((role === "user" || role === "assistant") && !msgs[i].isSystem)
                uncompactedCleanCount++;

        }
        if (uncompactedCleanCount > threshold) {
            appendCompactPromptMessage(sId);
        }
    }

    function compactSessionContext(sessionId) {
        let sId = sessionId || root.currentSessionId;
        let idx = sessionIndexById(sId);
        if (idx < 0)
            return ;

        let msgs = root.sessions[idx].messages || [];
        let compactedCount = getSessionProperty(sId, "compactedMessageCount", 0);
        let cleanMsgs = [];
        for (let i = compactedCount; i < msgs.length; i++) {
            let role = msgs[i].role;
            if ((role === "user" || role === "assistant") && !msgs[i].isSystem)
                cleanMsgs.push({
                    "index": i,
                    "role": role,
                    "content": msgs[i].content
                });

        }
        if (cleanMsgs.length < 3) {
            appendSystemMessageToSession(sId, "Not enough messages to compact yet (need at least 3).");
            return ;
        }
        let limitCleanIndex = cleanMsgs.length - 2;
        let limitRealIndex = cleanMsgs[limitCleanIndex].index;
        let textToSummarize = "";
        let oldSummary = getSessionProperty(sId, "compactedSummary", "");
        if (oldSummary !== "")
            textToSummarize += "[Previous Summary]:\n" + oldSummary + "\n\n";

        for (let j = 0; j < limitCleanIndex; j++) {
            let prefix = cleanMsgs[j].role === "user" ? "User: " : "AI: ";
            textToSummarize += prefix + cleanMsgs[j].content + "\n\n";
        }
        appendSystemMessageToSession(sId, "Compacting context, please wait...");
        let promptText = "Please write a highly concise summary (max 3-4 sentences) of the following conversation history. Keep it extremely brief and factual, focus on user preferences, details of what was discussed/resolved, and any state that needs to be preserved. This summary will be injected into the system prompt of the next turns to maintain context:\n\n" + textToSummarize;
        sendBackgroundSummarizationRequest(sId, promptText, limitRealIndex + 1);
    }

    function sendBackgroundSummarizationRequest(sId, promptText, count) {
        let provider = "";
        let model = "";
        let apiKey = "";
        let url = "";
        let headers = null;
        let isAnthropic = false;
        if (root.openCodeMode) {
            url = openCodeBaseUrl() + "/v1/chat/completions";
            model = (plasmoid.configuration.openCodeModel || "").trim();
            provider = "opencode";
        } else {
            provider = plasmoid.configuration.provider || "openai";
            let providerCfg = getProviderConfig(provider);
            isAnthropic = (providerCfg.type === "anthropic");
            if (isAnthropic) {
                apiKey = providerCfg.apiKey;
                model = providerCfg.model;
            } else {
                url = providerCfg.baseUrl;
                apiKey = providerCfg.apiKey;
                model = providerCfg.model;
                headers = providerCfg.headers;
            }
        }
        let xhr = new XMLHttpRequest();
        if (isAnthropic) {
            xhr.open("POST", "https://api.anthropic.com/v1/messages", true);
            xhr.setRequestHeader("x-api-key", apiKey);
            xhr.setRequestHeader("anthropic-version", "2023-06-01");
            xhr.setRequestHeader("content-type", "application/json");
        } else {
            let fullUrl = url;
            if (!fullUrl.endsWith("/chat/completions") && !fullUrl.endsWith("/completions"))
                fullUrl = fullUrl.replace(/\/+$/, "") + "/chat/completions";

            xhr.open("POST", fullUrl, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            if (apiKey !== "")
                xhr.setRequestHeader("Authorization", "Bearer " + apiKey);

            if (headers) {
                for (let key in headers) {
                    xhr.setRequestHeader(key, headers[key]);
                }
            }
        }
        xhr.timeout = 30000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    let summaryText = "";
                    let res = JSON.parse(xhr.responseText);
                    if (isAnthropic) {
                        if (res.content && res.content.length > 0)
                            summaryText = res.content[0].text;

                    } else {
                        if (res.choices && res.choices.length > 0 && res.choices[0].message)
                            summaryText = res.choices[0].message.content;

                    }
                    summaryText = (summaryText || "").trim();
                    if (summaryText !== "") {
                        setSessionProperty(sId, "compactedSummary", summaryText);
                        setSessionProperty(sId, "compactedMessageCount", count);
                        if (root.openCodeMode)
                            setSessionProperty(sId, "openCodeSessionId", "");

                        appendSystemMessageToSession(sId, "Context compacted successfully. Summary: " + summaryText);
                    } else {
                        appendSystemMessageToSession(sId, "Warning: Context compaction returned an empty response.");
                    }
                } catch (e) {
                    appendSystemMessageToSession(sId, "Warning: Failed to parse compaction response: " + e.toString());
                }
            } else {
                let errMsg = "HTTP " + xhr.status;
                try {
                    let errObj = JSON.parse(xhr.responseText);
                    if (errObj.error && errObj.error.message)
                        errMsg += ": " + errObj.error.message;

                } catch (e) {
                }
                appendSystemMessageToSession(sId, "Warning: Context compaction failed: " + errMsg);
            }
        };
        xhr.onerror = function() {
            appendSystemMessageToSession(sId, "Warning: Network error while compacting context.");
        };
        let payload = {
        };
        if (isAnthropic)
            payload = {
                "model": model,
                "max_tokens": 512,
                "messages": [{
                    "role": "user",
                    "content": promptText
                }]
            };
        else
            payload = {
                "model": model,
                "max_tokens": 512,
                "messages": [{
                    "role": "user",
                    "content": promptText
                }]
            };
        try {
            xhr.send(JSON.stringify(payload));
        } catch (e) {
            appendSystemMessageToSession(sId, "Warning: Failed to send compaction request: " + e.toString());
        }
    }

    function updateAutocomplete() {
        let txt = (root.msgInputRef ? root.msgInputRef.text : "") || "";
        if (txt.startsWith("/")) {
            let search = txt.substring(1).toLowerCase();
            let filtered = [];
            let all = [];
            if (root.openCodeMode) {
                all.push({
                    "name": "/help",
                    "desc": "Show available commands"
                });
                all.push({
                    "name": "/version",
                    "desc": "Show OpenCode version"
                });
                all.push({
                    "name": "/session",
                    "desc": "Show current session info"
                });
                all.push({
                    "name": "/schedule",
                    "desc": "Create/manage schedules (System Scheduler)"
                });
            } else {
                all.push({
                    "name": "/schedule",
                    "desc": "Create/manage schedules"
                });
            }
            for (let i = 0; i < all.length; i++) {
                if (all[i].name.toLowerCase().indexOf("/" + search) === 0 || all[i].name.toLowerCase().substring(1).indexOf(search) >= 0)
                    filtered.push(all[i]);

            }
            root.filteredCommands = filtered;
            if (filtered.length > 0) {
                root.autocompleteActive = true;
                if (root.autocompleteSelectedIndex >= filtered.length)
                    root.autocompleteSelectedIndex = 0;

            } else {
                root.autocompleteActive = false;
            }
        } else {
            root.autocompleteActive = false;
        }
    }

    function extractReadableError(prefix, errObj, fallbackText) {
        if (errObj) {
            if (errObj.data && errObj.data.message)
                return prefix + errObj.data.message;

            if (errObj.message)
                return prefix + errObj.message;

            if (errObj.name)
                return prefix + errObj.name;

        }
        return prefix + (fallbackText || "Unknown error");
    }

    function beginAssistantStreaming(modelLabel) {
        if (modelLabel)
            root.openCodeAssistantModelLabel = modelLabel;

    }

    function updateAssistantStreamingContent(text, modelLabel) {
        let incoming = text || "";
        if (incoming === "")
            return ;

        if (modelLabel)
            root.openCodeAssistantModelLabel = modelLabel;

        // Audit 5.1: buffer streaming chunks and flush at ~30 Hz
        // instead of rebuilding the `messages` array on every token.
        // This is the dominant cost during streaming — each rebuild
        // was triggering a full ListView model reset, destroying and
        // recreating all delegates.
        if (root.openCodeAssistantMessageIndex < 0) {
            // First chunk for this stream — flush immediately so the
            // bubble appears without waiting for the batch window.
            let ts = Date.now();
            root.messages = root.messages.concat([{
                "role": "assistant",
                "content": incoming,
                "time": nowTime(ts),
                "at": ts,
                "model": root.openCodeAssistantModelLabel || "OpenCode"
            }]);
            root.openCodeAssistantMessageIndex = root.messages.length - 1;
            root.streamingResponse = true;
            if (!root.userScrolledUp)
                Qt.callLater(scrollToBottom);
            return;
        }
        // Subsequent chunks — buffer and restart the batch timer.
        let existing = root._pendingStreamingText;
        // OpenCode streams can be cumulative or token-delta; handle both.
        if (incoming.indexOf(existing) === 0)
            root._pendingStreamingText = incoming;
        else if (existing.indexOf(incoming) === 0)
            {} // already have it
        else
            root._pendingStreamingText = existing + incoming;
        if (modelLabel)
            root._pendingStreamingModelLabel = modelLabel;
        root._streamingDirty = true;
        streamingBatchTimer.restart();
    }

    function finishOpenCodeRequest() {
        root.loading = false;
        root.activeXhr = null;
        root.openCodeActiveSessionId = "";
        root.openCodeAssistantMessageIndex = -1;
        root.openCodeAssistantServerMessageId = "";
        root.openCodeErrorShownForRequest = false;
        root.streamingResponse = false;
        flushStreamingBuffer();
        saveCurrentSessionState(true);
        triggerNotificationSound();
        resetOpenCodeIdleKillTimer();
        processNextQueuedMessage();
    }

    // Handle slash commands in OpenCode mode.
    // Commands are dispatched to the appropriate handler:
    //  - /help, /session, /stats → local inline info (no server needed)
    //  - /models                 → REST API GET /v1/models
    //  - /version                → opencode --version (real CLI flag)
    //  - /export                 → syncOpenCodeSessionHistory() (REST API)
    //  - TUI-only commands       → friendly explanation shown inline
    function runLocalOpenCodeCommand(cmdText) {
        let cmd = cmdText.trim().toLowerCase();
        // Strip leading slash or "opencode " prefix
        let bare = cmd.startsWith("/") ? cmd.substring(1) : cmd;
        // Normalise e.g. "/models extra" → bare = "models"
        let verb = bare.split(" ")[0];
        root.autocompleteActive = false;
        // ── /help ─────────────────────────────────────────────────────────
        if (verb === "help") {
            pushInfoMessage("**OpenCode commands:**\n" + "- `/help` — this message\n" + "- `/version` — show installed OpenCode version\n" + "- `/session` — show current session info\n" + "\nTo use the full OpenCode TUI, click the terminal icon in the session bar.");
            return ;
        }
        // ── /version ──────────────────────────────────────────────────────
        if (verb === "version") {
            root.loading = true;
            root.openCodeAssistantMessageIndex = -1;
            root.openCodeAssistantServerMessageId = "";
            root.openCodeErrorShownForRequest = false;
            beginAssistantStreaming("OpenCode");
            updateAssistantStreamingContent("Checking OpenCode version...\n", "OpenCode");
            let token = "opencode-cli-" + Date.now();
            opencodeTerminalDs.connectSource("opencode --version #" + token);
            return ;
        }
        // ── /session ──────────────────────────────────────────────────────
        if (verb === "session") {
            let sid = currentOpenCodeSessionId();
            // Session objects are keyed by `value`, not `id` — see
            // SessionManager.createSessionObj. The previous code looked
            // for `s.id` and always returned -1, which made the
            // session-name lookup fall through to "(unnamed)".
            let idx = root.sessions.findIndex ? root.sessions.findIndex(function(s) {
                return s.value === root.currentSessionId;
            }) : -1;
            let sessionName = (idx >= 0 && root.sessions[idx]) ? (root.sessions[idx].text || root.sessions[idx].title || "(unnamed)") : "(unnamed)";
            if (sid)
                pushInfoMessage("**Current OpenCode Session**\n" + "- **Local session:** " + sessionName + "\n" + "- **Remote session ID:** `" + sid + "`\n" + "- **Server:** " + openCodeBaseUrl() + "\n" + "- **Messages in view:** " + root.messages.length);
            else
                pushInfoMessage("**Current OpenCode Session**\n" + "- **Local session:** " + sessionName + "\n" + "- **Remote session:** Not yet started (send a message to create one)\n" + "- **Server:** " + openCodeBaseUrl());
            return ;
        }
        // ── Unknown ───────────────────────────────────────────────────────
        pushErrorMessage("Unknown command: `" + cmdText.trim() + "`\nType `/help` to see available commands.");
    }

    function syncOpenCodeSessionHistory() {
        let remoteSessionId = currentOpenCodeSessionId();
        if (!remoteSessionId)
            return ;

        root.loading = true;
        let xhr = new XMLHttpRequest();
        xhr.open("GET", openCodeBaseUrl() + "/session/" + remoteSessionId + "/message", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            root.loading = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    let arr = JSON.parse(xhr.responseText);
                    if (Array.isArray(arr)) {
                        let newMsgs = [];
                        for (let i = 0; i < arr.length; i++) {
                            let item = arr[i] || {
                            };
                            let info = item.info || {
                            };
                            let parts = item.parts || [];
                            let role = info.role || "user";
                            let modelLabel = (info.providerID && info.modelID) ? (info.providerID + "/" + info.modelID) : (info.modelID || "OpenCode");
                            let combinedText = "";
                            let ctx = [];
                            for (let p = 0; p < parts.length; p++) {
                                let part = parts[p] || {
                                };
                                if (part.type === "text") {
                                    combinedText += part.text || part.content || "";
                                } else if (part.type === "tool-invocation") {
                                    let toolName = part.toolName || part.tool || "";
                                    let toolArgs = part.args || part.input || {
                                    };
                                    if (toolName !== "") {
                                        let desc = toolName;
                                        if (toolArgs.filePath || toolArgs.path || toolArgs.file)
                                            desc += ": " + (toolArgs.filePath || toolArgs.path || toolArgs.file);
                                        else if (toolArgs.command)
                                            desc += ": " + String(toolArgs.command).substring(0, 60);
                                        ctx.push(desc);
                                    }
                                }
                            }
                            // Normalize tokens
                            let normalizedTokens = {
                            };
                            if (item.tokens) {
                                let rawTokens = item.tokens || {
                                };
                                normalizedTokens.input = rawTokens.input !== undefined ? rawTokens.input : (rawTokens.prompt_tokens !== undefined ? rawTokens.prompt_tokens : (rawTokens.input_tokens !== undefined ? rawTokens.input_tokens : undefined));
                                normalizedTokens.output = rawTokens.output !== undefined ? rawTokens.output : (rawTokens.completion_tokens !== undefined ? rawTokens.completion_tokens : (rawTokens.output_tokens !== undefined ? rawTokens.output_tokens : undefined));
                                if (rawTokens.reasoning !== undefined)
                                    normalizedTokens.reasoning = rawTokens.reasoning;

                                if (rawTokens.cache !== undefined)
                                    normalizedTokens.cache = rawTokens.cache;

                            }
                            let ts = info.createdAt ? new Date(info.createdAt).getTime() : Date.now();
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
                            // Use the local `sessionIndexById` helper —
                            // `currentSessionIndex` does not exist on
                            // `root` and would throw a TypeError at
                            // runtime.
                            let idx = sessionIndexById(root.currentSessionId);
                            if (idx >= 0) {
                                root.messages = newMsgs;
                                root.sessions[idx].messages = newMsgs;
                                saveCurrentSessionState(true);
                                Qt.callLater(scrollToBottom);
                            }
                        }
                    }
                } catch (err) {
                    reportParseFailure("Failed to parse synced messages", err);
                }
            } else {
                pushErrorMessage("Sync failed: OpenCode returned HTTP " + xhr.status);
            }
        };
        xhr.send();
    }

    function ensureOpenCodeEventStream() {
        if (root.openCodeEventXhr)
            return ;

        let xhr = new XMLHttpRequest();
        let buffer = "";
        let offset = 0;
        let url = openCodeBaseUrl() + "/event";
        root.openCodeEventXhr = xhr;
        xhr.open("GET", url, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            let delta = xhr.responseText.slice(offset);
            offset = xhr.responseText.length;
            buffer += delta;
            while (true) {
                let split = buffer.indexOf("\n\n");
                if (split < 0)
                    break;

                let block = buffer.slice(0, split);
                buffer = buffer.slice(split + 2);
                let lines = block.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("data:") !== 0)
                        continue;

                    try {
                        let eventObj = JSON.parse(lines[i].slice(5).trim());
                        handleOpenCodeEvent(eventObj);
                    } catch (eventError) {
                    }
                }
            }
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.openCodeEventXhr = null;
                if (root.openCodeMode)
                    openCodeReconnectTimer.start();

            }
        };
        xhr.onerror = function() {
            root.openCodeEventXhr = null;
            if (root.openCodeMode)
                openCodeReconnectTimer.start();

        };
        try {
            xhr.send();
        } catch (streamError) {
            root.openCodeEventXhr = null;
            if (root.openCodeMode)
                openCodeReconnectTimer.start();

        }
    }

    function handleOpenCodeEvent(eventObj) {
        let props = eventObj && eventObj.properties ? eventObj.properties : {
        };
        let sessionId = props.sessionID || "";
        if (!sessionId || sessionId !== root.openCodeActiveSessionId)
            return ;

        if (eventObj.type === "message.updated") {
            let info = props.info || {
            };
            if (info.role === "assistant") {
                root.openCodeAssistantServerMessageId = info.id || root.openCodeAssistantServerMessageId;
                beginAssistantStreaming((info.providerID && info.modelID) ? (info.providerID + "/" + info.modelID) : (info.modelID || "OpenCode"));
                if (info.error && !root.openCodeErrorShownForRequest) {
                    root.openCodeErrorShownForRequest = true;
                    pushErrorMessage(extractReadableError("OpenCode: ", info.error, "Request failed."));
                }
            }
        } else if (eventObj.type === "message.part.updated") {
            let part = props.part || {
            };
            if (part.type === "text" && root.openCodeAssistantServerMessageId !== "" && part.messageID === root.openCodeAssistantServerMessageId)
                updateAssistantStreamingContent(part.text || "", "OpenCode");

            // Track tool invocations as context items on the assistant message
            if (part.type === "tool-invocation" && root.openCodeAssistantMessageIndex >= 0) {
                let toolName = part.toolName || part.tool || "";
                let toolArgs = part.args || part.input || {
                };
                let toolState = part.state || "";
                if (toolName !== "") {
                    let toolMsgs = root.messages.slice();
                    let item = Object.assign({
                    }, toolMsgs[root.openCodeAssistantMessageIndex]);
                    let ctx = item.contextItems || [];
                    // Build a concise description of the tool call
                    let desc = toolName;
                    if (toolArgs.filePath || toolArgs.path || toolArgs.file)
                        desc += ": " + (toolArgs.filePath || toolArgs.path || toolArgs.file);
                    else if (toolArgs.command)
                        desc += ": " + String(toolArgs.command).substring(0, 60);
                    else if (toolArgs.query || toolArgs.pattern)
                        desc += ": " + (toolArgs.query || toolArgs.pattern);
                    // Avoid duplicates
                    let exists = false;
                    for (let ci = 0; ci < ctx.length; ci++) {
                        if (ctx[ci] === desc) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists) {
                        ctx = ctx.concat([desc]);
                        item.contextItems = ctx;
                        toolMsgs[root.openCodeAssistantMessageIndex] = item;
                        root.messages = toolMsgs;
                    }
                }
            }
        } else if (eventObj.type === "session.error") {
            if (!root.openCodeErrorShownForRequest) {
                root.openCodeErrorShownForRequest = true;
                pushErrorMessage(extractReadableError("OpenCode: ", props.error, "Session error."));
            }
        } else if (eventObj.type === "session.status") {
            let status = props.status || {
            };
            if (status.type === "idle")
                finishOpenCodeRequest();

        } else if (eventObj.type === "session.idle") {
            finishOpenCodeRequest();
        } else if (eventObj.type === "permission.asked") {
            let p = props.permission || {
            };
            let permId = p.id || "";
            if (permId !== "") {
                let tool = p.tool || "";
                let args = p.arguments || {
                };
                let argStr = "";
                try {
                    argStr = typeof args === "string" ? args : JSON.stringify(args, null, 2);
                } catch (e) {
                    argStr = String(args);
                }
                let msg = {
                    "role": "permission_request",
                    "content": "OpenCode is asking for permission to run **" + tool + "**:\n\n```json\n" + argStr + "\n```",
                    "model": "OpenCode Security",
                    "id": "perm-" + permId,
                    "permissionId": permId,
                    "tool": tool,
                    "arguments": args,
                    "status": "pending",
                    "at": Date.now()
                };
                root.messages = root.messages.concat([msg]);
                saveCurrentSessionState(true);
                if (!root.userScrolledUp)
                    Qt.callLater(scrollToBottom);

            }
        } else if (eventObj.type === "permission.replied") {
            let pr = props.permission || {
            };
            let pId = pr.id || "";
            let response = pr.response || "";
            let permissionMsgs = root.messages.slice();
            let updated = false;
            for (let i = permissionMsgs.length - 1; i >= 0; i--) {
                if (permissionMsgs[i].role === "permission_request" && permissionMsgs[i].permissionId === pId) {
                    permissionMsgs[i].status = (response === "allow" ? "allowed" : "denied");
                    updated = true;
                    break;
                }
            }
            if (updated) {
                root.messages = permissionMsgs;
                saveCurrentSessionState(true);
            }
        } else if (eventObj.type === "session.next.step.ended") {
            let tokensMsgs = root.messages.slice();
            let updated = false;
            for (let idx = tokensMsgs.length - 1; idx >= 0; idx--) {
                if (tokensMsgs[idx].role === "assistant") {
                    let item = Object.assign({
                    }, tokensMsgs[idx]);
                    let normalizedTokens = {
                    };
                    let rawTokens = props.tokens || {
                    };
                    normalizedTokens.input = rawTokens.input !== undefined ? rawTokens.input : (rawTokens.prompt_tokens !== undefined ? rawTokens.prompt_tokens : (rawTokens.input_tokens !== undefined ? rawTokens.input_tokens : undefined));
                    normalizedTokens.output = rawTokens.output !== undefined ? rawTokens.output : (rawTokens.completion_tokens !== undefined ? rawTokens.completion_tokens : (rawTokens.output_tokens !== undefined ? rawTokens.output_tokens : undefined));
                    if (rawTokens.reasoning !== undefined)
                        normalizedTokens.reasoning = rawTokens.reasoning;

                    if (rawTokens.cache !== undefined)
                        normalizedTokens.cache = rawTokens.cache;

                    item.tokens = normalizedTokens;
                    item.cost = props.cost;
                    tokensMsgs[idx] = item;
                    updated = true;
                    break;
                }
            }
            if (updated) {
                root.messages = tokensMsgs;
                saveCurrentSessionState(true);
            }
        } else if (eventObj.type === "question.asked") {
            let requestID = props.requestID || props.id || eventObj.id || "";
            if (requestID !== "") {
                // Parse full structured questions array from OpenCode
                let questions = props.questions || [];
                let qText = "";
                let parsedQuestions = [];
                let allowCustom = true;
                if (questions.length > 0) {
                    // Structured question(s) with options
                    let parts = [];
                    for (let qi = 0; qi < questions.length; qi++) {
                        let qItem = questions[qi];
                        let header = qItem.header || "";
                        let questionText = qItem.question || "";
                        let opts = qItem.options || [];
                        let multiple = qItem.multiple || false;
                        let custom = qItem.custom !== undefined ? qItem.custom : true;
                        if (!custom)
                            allowCustom = false;

                        let partText = "";
                        if (header)
                            partText += "**" + header + "**: ";

                        partText += questionText;
                        if (opts.length > 0) {
                            let optLabels = [];
                            for (let oi = 0; oi < opts.length; oi++) optLabels.push(opts[oi].label || "")
                            partText += "\n\nOptions: " + optLabels.join(", ");
                        }
                        if (multiple)
                            partText += " *(select multiple)*";

                        parts.push(partText);
                        parsedQuestions.push({
                            "header": header,
                            "question": questionText,
                            "options": opts,
                            "multiple": multiple,
                            "custom": custom
                        });
                    }
                    qText = parts.join("\n\n---\n\n");
                } else {
                    // Fallback: legacy format
                    let q = props.question || {
                    };
                    if (typeof props.question === "string")
                        qText = props.question;
                    else if (q.text)
                        qText = q.text;
                    else if (q.content)
                        qText = q.content;
                    else
                        qText = props.text || props.content || "OpenCode requires clarification.";
                }
                let alreadyExists = false;
                for (let i = 0; i < root.messages.length; i++) {
                    if (root.messages[i].role === "question_request" && root.messages[i].questionId === requestID) {
                        alreadyExists = true;
                        break;
                    }
                }
                if (!alreadyExists) {
                    let msg = {
                        "role": "question_request",
                        "content": "OpenCode is asking a question:\n\n**" + qText + "**",
                        "model": "OpenCode Question",
                        "id": "question-" + requestID,
                        "questionId": requestID,
                        "questions": parsedQuestions,
                        "allowCustom": allowCustom,
                        "status": "pending",
                        "at": Date.now()
                    };
                    root.messages = root.messages.concat([msg]);
                    saveCurrentSessionState(true);
                    if (!root.userScrolledUp)
                        Qt.callLater(scrollToBottom);

                }
            }
        } else if (eventObj.type === "question.replied") {
            let qId = props.requestID || props.id || eventObj.id || "";
            let repliedMsgs = root.messages.slice();
            let updated = false;
            for (let i = repliedMsgs.length - 1; i >= 0; i--) {
                if (repliedMsgs[i].role === "question_request" && repliedMsgs[i].questionId === qId) {
                    if (repliedMsgs[i].status === "pending" || repliedMsgs[i].status === "answering...") {
                        repliedMsgs[i].status = "answered";
                        updated = true;
                    }
                    break;
                }
            }
            if (updated) {
                root.messages = repliedMsgs;
                saveCurrentSessionState(true);
            }
        } else if (eventObj.type === "question.rejected" || eventObj.type === "question.cancelled") {
            let qId2 = props.requestID || props.id || eventObj.id || "";
            let dismissedMsgs = root.messages.slice();
            let updated = false;
            for (let i = dismissedMsgs.length - 1; i >= 0; i--) {
                if (dismissedMsgs[i].role === "question_request" && dismissedMsgs[i].questionId === qId2) {
                    if (dismissedMsgs[i].status === "pending" || dismissedMsgs[i].status === "dismissing...") {
                        dismissedMsgs[i].status = "dismissed";
                        updated = true;
                    }
                    break;
                }
            }
            if (updated) {
                root.messages = dismissedMsgs;
                saveCurrentSessionState(true);
            }
        }
    }

    function appendSystemMessageToSession(chatId, text) {
        let ts = Date.now();
        let msgObj = {
            "role": "assistant",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": 0,
            "attachments": [],
            "isSystem": true
        };
        appendMessageToSession(chatId, msgObj);
        if (chatId === root.currentSessionId) {
            if (!root.userScrolledUp)
                Qt.callLater(scrollToBottom);
        }
        return ts;
    }

    function removeMessageFromSessionByTimestamp(chatId, timestamp) {
        let idx = sessionIndexById(chatId);
        if (idx < 0)
            return ;

        let updated = root.sessions.slice();
        let s = Object.assign({}, updated[idx]);
        let msgs = (s.messages || []).slice();
        let originalLength = msgs.length;
        msgs = msgs.filter(function(m) {
            return m.at !== timestamp;
        });
        if (msgs.length === originalLength)
            return ;

        s.messages = msgs;
        s.updatedAt = Date.now();
        if (chatId === root.currentSessionId) {
            root.messages = msgs;
            if (root.expanded && !root.historyOnlyMode)
                s.readCount = msgs.length;
        }
        updated[idx] = s;
        root.sessions = updated;
        persistSessions();
    }

    function scheduleMessageRemoval(chatId, timestamp, delayMs) {
        // Coerce delayMs to a number, clamp to a sane range, then inject
        // the numeric form into the QML source. Reject NaN, negative
        // values, and values larger than one hour to avoid QML-injection
        // via the interpolated string and to keep the timer bounded.
        let interval = Number(delayMs);
        if (!isFinite(interval) || interval < 0)
            interval = 0;
        if (interval > 3600000)
            interval = 3600000;
        let timerObj = Qt.createQmlObject("import QtQuick; Timer { interval: " + interval + "; repeat: false; running: true; }", root, "dynamicRemoveTimer");
        timerObj.triggered.connect(function() {
            removeMessageFromSessionByTimestamp(chatId, timestamp);
            timerObj.destroy();
        });
    }

    function setOpenCodeSessionIdForChatId(chatId, remoteSessionId) {
        let idx = sessionIndexById(chatId);
        if (idx < 0)
            return ;

        let updated = root.sessions.slice();
        let item = Object.assign({
        }, updated[idx]);
        item.openCodeSessionId = remoteSessionId || "";
        updated[idx] = item;
        root.sessions = updated;
        persistSessions();
    }

    function ensureOpenCodeSessionForChatId(chatId, successCallback, failureCallback) {
        let targetIdx = sessionIndexById(chatId);
        if (targetIdx < 0) {
            failureCallback("Session not found");
            return ;
        }
        let existing = root.sessions[targetIdx].openCodeSessionId || "";
        if (existing !== "") {
            successCallback(existing);
            return ;
        }
        let fail = function fail(msg) {
            if (typeof failureCallback === "function")
                failureCallback(msg);
            else
                pushErrorMessage(msg);
        };
        let xhr = new XMLHttpRequest();
        xhr.open("POST", openCodeBaseUrl() + "/session", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = 10000;
        xhr.ontimeout = function() {
            fail("OpenCode: session creation timed out. Check that the server is running at " + openCodeBaseUrl());
        };
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status >= 200 && xhr.status < 300) {
                triggerNotificationSound();
                try {
                    let obj = JSON.parse(xhr.responseText);
                    let remoteId = obj.id || "";
                    if (remoteId === "") {
                        fail("OpenCode: server created a session without an id.");
                        return ;
                    }
                    setOpenCodeSessionIdForChatId(chatId, remoteId);
                    successCallback(remoteId);
                } catch (parseError) {
                    fail("OpenCode: could not parse session creation response.");
                }
            } else {
                fail("OpenCode: failed to create a server session (HTTP " + xhr.status + ").");
            }
        };
        xhr.onerror = function() {
            fail("OpenCode: could not reach " + openCodeBaseUrl() + "/session. Check that the server is still running.");
        };
        try {
            let sTitle = root.sessions[targetIdx].title || "KDE AI Chat";
            xhr.send(JSON.stringify({
                "title": sTitle
            }));
        } catch (sendError) {
            fail("OpenCode: failed to create session: " + sendError);
        }
    }

    function ensureCurrentOpenCodeSession(successCallback, failureCallback) {
        let existing = currentOpenCodeSessionId();
        if (existing !== "") {
            successCallback(existing);
            return ;
        }
        let fail = function fail(msg) {
            if (typeof failureCallback === "function")
                failureCallback(msg);
            else
                pushErrorMessage(msg);
        };
        let xhr = new XMLHttpRequest();
        xhr.open("POST", openCodeBaseUrl() + "/session", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = 10000;
        xhr.ontimeout = function() {
            fail("OpenCode: session creation timed out. Check that the server is running at " + openCodeBaseUrl());
        };
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status >= 200 && xhr.status < 300) {
                triggerNotificationSound();
                try {
                    let obj = JSON.parse(xhr.responseText);
                    let remoteId = obj.id || "";
                    if (remoteId === "") {
                        fail("OpenCode: server created a session without an id.");
                        return ;
                    }
                    setCurrentOpenCodeSessionId(remoteId);
                    successCallback(remoteId);
                } catch (parseError) {
                    fail("OpenCode: could not parse session creation response.");
                }
            } else {
                fail("OpenCode: failed to create a server session (HTTP " + xhr.status + ").");
            }
        };
        xhr.onerror = function() {
            fail("OpenCode: could not reach " + openCodeBaseUrl() + "/session. Check that the server is still running.");
        };
        try {
            xhr.send(JSON.stringify({
                "title": root.currentSessionTitle || "KDE AI Chat"
            }));
        } catch (sendError) {
            fail("OpenCode: failed to create session: " + sendError);
        }
    }

    function ensureOpenCodeServerRunning(chatId, successCallback, failureCallback) {
        if (root.openCodeStarting) {
            if (successCallback) {
                let sCbs = root.openCodeStartSuccessCallbacks.slice();
                sCbs.push(successCallback);
                root.openCodeStartSuccessCallbacks = sCbs;
            }
            if (failureCallback) {
                let fCbs = root.openCodeStartFailureCallbacks.slice();
                fCbs.push(failureCallback);
                root.openCodeStartFailureCallbacks = fCbs;
            }
            return;
        }

        root.openCodeStarting = true;
        root.openCodeStartSuccessCallbacks = successCallback ? [successCallback] : [];
        root.openCodeStartFailureCallbacks = failureCallback ? [failureCallback] : [];

        let checkFinished = false;
        let completed = false;
        let resolveSuccess = function() {
            if (completed) return;
            completed = true;
            root.openCodeStarting = false;
            let successCbs = root.openCodeStartSuccessCallbacks;
            root.openCodeStartSuccessCallbacks = [];
            root.openCodeStartFailureCallbacks = [];
            for (let i = 0; i < successCbs.length; i++) {
                successCbs[i]();
            }
        };

        let resolveFailure = function(msg) {
            if (completed) return;
            completed = true;
            root.openCodeStarting = false;
            let failureCbs = root.openCodeStartFailureCallbacks;
            root.openCodeStartSuccessCallbacks = [];
            root.openCodeStartFailureCallbacks = [];
            
            if (failureCbs.length > 0) {
                for (let i = 0; i < failureCbs.length; i++) {
                    failureCbs[i](msg);
                }
            } else {
                if (chatId)
                    appendSystemMessageToSession(chatId, "Warning: " + msg);
                else
                    pushErrorMessage(msg);
            }
        };

        function handleSuccess() {
            if (checkFinished) return;
            checkFinished = true;
            resolveSuccess();
        }

        function handleNotRunning(err) {
            if (checkFinished) return;
            checkFinished = true;
            if (plasmoid.configuration.autoStartOpenCodeServer) {
                let startCmd = (plasmoid.configuration.openCodeStartCommand || "logf=\"${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log\"; nohup opencode serve --port 4096 --hostname 127.0.0.1 >\"$logf\" 2>&1 & echo ok").trim();
                // The user-editable start command is intentionally a shell
                // snippet (it can include `>`, `&`, `pkill`, etc.), so we
                // do *not* strip shell metacharacters. We only escape
                // single quotes for the outer `sh -lc '…'` wrapper.
                opencodeServerDs.connectSource("sh -lc '" + startCmd.replace(/'/g, "'\\''") + "' #ensure-opencode-startup-" + Date.now());
                if (chatId) {
                    let ts1 = appendSystemMessageToSession(chatId, translate("Starting OpenCode server, please wait..."));
                    scheduleMessageRemoval(chatId, ts1, 60000);
                }

                openCodeStartPollTimer.successCb = function() {
                    if (chatId) {
                        let ts2 = appendSystemMessageToSession(chatId, translate("Session restarted."));
                        scheduleMessageRemoval(chatId, ts2, 60000);
                    }
                    resolveSuccess();
                };
                openCodeStartPollTimer.failureCb = function(msg) {
                    resolveFailure(msg);
                };
                openCodeStartPollTimer.retriesLeft = 8;
                openCodeStartPollTimer.start();
            } else {
                resolveFailure("OpenCode server is not running. Please start it or enable \"Auto-start OpenCode server\" in General settings.");
            }
        }

        let checkUrl = openCodeBaseUrl() + "/config/providers";
        let xhr = new XMLHttpRequest();
        xhr.open("GET", checkUrl, true);
        xhr.timeout = 2000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status >= 200 && xhr.status < 300)
                handleSuccess();
            else
                handleNotRunning("HTTP " + xhr.status);
        };
        xhr.onerror = function() {
            handleNotRunning("Transport error");
        };
        xhr.ontimeout = function() {
            handleNotRunning("Timeout");
        };
        try {
            xhr.send();
        } catch (e) {
            handleNotRunning(e.toString());
        }
    }

    function doOpenCodeRequest() {
        function failOpenCodeRequest(message) {
            if (requestFinalized)
                return ;

            requestFinalized = true;
            if (!root.openCodeErrorShownForRequest) {
                root.openCodeErrorShownForRequest = true;
                pushErrorMessage(message);
            }
            finishOpenCodeRequest();
        }

        let requestFinalized = false;
        ensureOpenCodeServerRunning(root.currentSessionId, function() {
            ensureOpenCodeEventStream();
            root.loading = true;
            root.streamingResponse = false;
            root.openCodeAssistantMessageIndex = -1;
            root.openCodeAssistantServerMessageId = "";
            root.openCodeErrorShownForRequest = false;
            ensureCurrentOpenCodeSession(function(remoteSessionId) {
                let xhr = new XMLHttpRequest();
                let modelId = (plasmoid.configuration.openCodeModel || "").trim();
                let providerId = (plasmoid.configuration.openCodeProvider || "").trim();
                root.activeXhr = xhr;
                root.openCodeActiveSessionId = remoteSessionId;
                xhr.open("POST", openCodeBaseUrl() + "/session/" + remoteSessionId + "/message", true);
                xhr.setRequestHeader("Content-Type", "application/json");
                xhr.timeout = 15000;
                xhr.ontimeout = function() {
                    failOpenCodeRequest("OpenCode: message request timed out at " + openCodeBaseUrl());
                };
                xhr.onreadystatechange = function() {
                    if (xhr.readyState !== XMLHttpRequest.DONE)
                        return ;

                    if (requestFinalized)
                        return ;

                    if (xhr.status < 200 || xhr.status >= 300) {
                        if (xhr.status === 404)
                            setCurrentOpenCodeSessionId("");

                        let suffix = xhr.status > 0 ? ("HTTP " + xhr.status) : "transport error";
                        failOpenCodeRequest("OpenCode request failed (" + suffix + ") at " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message.");
                        return ;
                    }
                    try {
                        let obj = JSON.parse(xhr.responseText);
                        if (obj.info && obj.info.id)
                            root.openCodeAssistantServerMessageId = obj.info.id;

                        if (obj.info && obj.info.error && !root.openCodeErrorShownForRequest) {
                            root.openCodeErrorShownForRequest = true;
                            pushErrorMessage(extractReadableError("OpenCode: ", obj.info.error, "Request failed."));
                        }
                        if (obj.parts && obj.parts.length > 0) {
                            let combined = "";
                            for (let i = 0; i < obj.parts.length; i++) {
                                if (obj.parts[i].type === "text")
                                    combined += obj.parts[i].text || obj.parts[i].content || "";

                            }
                            if (combined !== "")
                                updateAssistantStreamingContent(combined, providerId + "/" + modelId);
                            else if (!root.openCodeErrorShownForRequest && root.openCodeAssistantMessageIndex < 0)
                                updateAssistantStreamingContent("(empty response)", providerId + "/" + modelId);
                        }
                    } catch (parseResponseError) {
                    }
                    requestFinalized = true;
                    finishOpenCodeRequest();
                };
                xhr.onerror = function() {
                    failOpenCodeRequest("OpenCode: request could not reach " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message. The server is reachable, but this request path failed.");
                };
                try {
                    let lastMsg = null;
                    for (let mIdx = root.messages.length - 1; mIdx >= 0; mIdx--) {
                        if (root.messages[mIdx].role === "user") {
                            lastMsg = root.messages[mIdx];
                            break;
                        }
                    }
                    if (!lastMsg) {
                        failOpenCodeRequest("No user message found to send.");
                        return ;
                    }
                    let userContent = lastMsg.content || "";
                    if (lastMsg.quote) {
                        let sender = lastMsg.quote.role === "assistant" ? (lastMsg.quote.model || "Assistant") : "User";
                        userContent = "[Replying to @" + sender + ": \"" + lastMsg.quote.content + "\"]\n\n" + userContent;
                    }
                    let parts = [];
                    if (lastMsg.attachments && lastMsg.attachments.length > 0) {
                        let payload = buildMessageContent(userContent, lastMsg.attachments, "openai");
                        if (typeof payload === "string") {
                            parts.push({
                                "type": "text",
                                "text": payload
                            });
                        } else {
                            for (let p = 0; p < payload.length; p++) {
                                let item = payload[p];
                                if (item.type === "text") {
                                    parts.push({
                                        "type": "text",
                                        "text": item.text
                                    });
                                } else if (item.type === "image_url") {
                                    let mType = item.image_url.url.split(";")[0].split(":")[1];
                                    parts.push({
                                        "type": "file",
                                        "mime": mType,
                                        "url": item.image_url.url
                                    });
                                }
                            }
                        }
                    } else {
                        parts.push({
                            "type": "text",
                            "text": userContent
                        });
                    }
                    xhr.send(JSON.stringify({
                        "model": {
                            "providerID": providerId,
                            "modelID": modelId
                        },
                        "system": buildEffectiveSystemPrompt(),
                        "parts": parts
                    }));
                } catch (sendError) {
                    failOpenCodeRequest("OpenCode: failed to send request: " + sendError);
                }
            }, function(errorMessage) {
                if (!root.openCodeErrorShownForRequest) {
                    root.openCodeErrorShownForRequest = true;
                    pushErrorMessage(errorMessage);
                }
                finishOpenCodeRequest();
            });
        }, function(err) {
            failOpenCodeRequest(err);
        });
    }

    function scrollToBottom() {
        if (root.msgListViewRef)
            root.msgListViewRef.positionViewAtEnd();

    }

    function scrollToMessageByTimestamp(timestamp) {
        if (!root.messages) return;
        for (let i = 0; i < root.messages.length; i++) {
            if (root.messages[i].at === timestamp) {
                if (root.msgListViewRef) {
                    root.msgListViewRef.currentIndex = i;
                    root.msgListViewRef.positionViewAtIndex(i, ListView.Center);
                }
                break;
            }
        }
    }

    function messageTimestampAt(index) {
        if (index < 0 || index >= root.messages.length)
            return Date.now();

        let m = root.messages[index] || {
        };
        return m.at || Date.now();
    }

    function messageDayKeyAt(index) {
        let d = new Date(messageTimestampAt(index));
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }

    function dayBucketLabel(ts) {
        let target = new Date(ts);
        let now = new Date();
        let today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        let targetDay = new Date(target.getFullYear(), target.getMonth(), target.getDate());
        let daysDiff = Math.floor((today.getTime() - targetDay.getTime()) / 8.64e+07);
        if (daysDiff === 0)
            return "Today";

        if (daysDiff === 1)
            return "Yesterday";

        if (daysDiff === 2)
            return "Day before yesterday";

        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return months[target.getMonth()] + " " + pad2(target.getDate()) + ", " + target.getFullYear();
    }

    function countMessagesForDayKey(dayKey) {
        let count = 0;
        for (let i = 0; i < root.messages.length; i++) {
            if (messageDayKeyAt(i) === dayKey)
                count++;

        }
        return count;
    }

    function dayDividerLabelForIndex(index) {
        let key = messageDayKeyAt(index);
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

        let currentTop = -1;
        for (let offset = 15; offset <= 100; offset += 20) {
            currentTop = root.msgListViewRef.indexAt(30, root.msgListViewRef.contentY + offset);
            if (currentTop >= 0)
                break;

        }
        if (currentTop < 0)
            currentTop = root.messages.length;

        let target = -1;
        for (let i = currentTop - 1; i >= 0; i--) {
            let msg = root.messages[i];
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

        let currentTop = -1;
        for (let offset = 15; offset <= 100; offset += 20) {
            currentTop = root.msgListViewRef.indexAt(30, root.msgListViewRef.contentY + offset);
            if (currentTop >= 0)
                break;

        }
        if (currentTop < 0)
            currentTop = -1;

        let target = -1;
        for (let i = currentTop + 1; i < root.messages.length; i++) {
            let msg = root.messages[i];
            if (msg && msg.role === "user") {
                target = i;
                break;
            }
        }
        if (target >= 0) {
            let isLastUser = true;
            for (let j = target + 1; j < root.messages.length; j++) {
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

        let parts = [];
        if (tokens.input !== undefined)
            parts.push("Input: " + tokens.input);

        if (tokens.output !== undefined)
            parts.push("Output: " + tokens.output);

        if (tokens.reasoning !== undefined && tokens.reasoning > 0)
            parts.push("Reasoning: " + tokens.reasoning);

        if (tokens.cache && (tokens.cache.read > 0 || tokens.cache.write > 0))
            parts.push("Cache R/W: " + tokens.cache.read + "/" + tokens.cache.write);

        let res = parts.join(" | ");
        if (cost !== undefined && cost > 0)
            res += " | Cost: $" + cost.toFixed(5);

        return res;
    }

    function pushErrorMessage(text) {
        let ts = Date.now();
        root.messages = root.messages.concat([{
            "role": "error",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": ""
        }]);
        scrollToBottom();
        saveCurrentSessionState(true);
        // If the last user message was a schedule, show a desktop notification of the execution failure!
        let isSched = false;
        for (let i = root.messages.length - 1; i >= 0; i--) {
            if (root.messages[i].role === "user") {
                if (root.messages[i].sc)
                    isSched = true;

                break;
            }
        }
        if (isSched) {
            let safeErr = Sec.sanitizeForShell(text);
            let errTitle = "Schedule Execution Failed";
            let safeErrTitle = Sec.sanitizeForShell(errTitle);
            soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning " + Sec.quoteForShell(safeErrTitle) + " " + Sec.quoteForShell(safeErr) + " #sched-execution-notify-err");
        }
    }

    function pushInfoMessage(text) {
        let ts = Date.now();
        root.messages = root.messages.concat([{
            "role": "assistant",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": "OpenCode",
            "isSystem": true
        }]);
        scrollToBottom();
        saveCurrentSessionState(true);
    }

    function appendUserMessage(text, role, attachments, isScheduled) {
        let ts = Date.now();
        let msgObj = {
            "role": role || "user",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": role === "queued" ? (++root.queueCounter) : 0,
            "attachments": attachments || [],
            "sc": !!isScheduled
        };
        if (root.quotedMessage && (role === "user" || role === "queued")) {
            msgObj.quote = {
                "role": root.quotedMessage.role,
                "content": root.quotedMessage.content,
                "model": root.quotedMessage.model || "",
                "at": root.quotedMessage.at
            };
            root.quotedMessage = null;
        }
        root.messages = root.messages.concat([msgObj]);
        saveCurrentSessionState(true);
    }

    function appendSystemMessage(text) {
        let ts = Date.now();
        root.messages = root.messages.concat([{
            "role": "assistant",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": 0,
            "attachments": [],
            "isSystem": true
        }]);
        saveCurrentSessionState(true);
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom);

    }

    function getSchedulesForSession(sessionId) {
        let res = [];
        for (let i = 0; i < root.schedulesList.length; i++) {
            let s = root.schedulesList[i];
            if (s && s.chatId === sessionId && !s.archived) {
                let isExecuted = false;
                if (s.taskType === "single") {
                    if ((s.lastRunAt && s.lastRunAt !== "") || (s.runCount && s.runCount > 0) || s.enabled === false)
                        isExecuted = true;

                } else {
                    if (s.enabled === false)
                        isExecuted = true;

                    if (s.limitEnabled && s.runCount >= s.limitCount)
                        isExecuted = true;

                }
                if (!isExecuted)
                    res.push(s);

            }
        }
        return res;
    }

    function validateCurrentSendTarget() {
        if (root.openCodeMode)
            return validateOpenCodeConfig();

        let provider = plasmoid.configuration.provider || "openai";
        let providerCfg = getProviderConfig(provider);
        return validateProviderConfig(provider, providerCfg);
    }

    function sendMessageByIndex(index) {
        resetOpenCodeIdleKillTimer();
        let source = root.messages[index] || {
        };
        let text = (source.content || "").trim();
        let hasAttachments = source.attachments && source.attachments.length > 0;
        if (!text && !hasAttachments)
            return ;

        let validationError = validateCurrentSendTarget();
        if (validationError !== "") {
            pushErrorMessage(validationError);
            return ;
        }
        if ((source.role || "") === "queued") {
            let copy = root.messages.slice();
            let queued = Object.assign({
            }, copy[index]);
            queued.role = "user";
            queued.at = Date.now();
            queued.time = nowTime(queued.at);
            copy[index] = queued;
            root.messages = copy;
            saveCurrentSessionState(true);
        }
        setCurrentSessionSource(root.openCodeMode ? "opencode" : "provider");
        if (root.openCodeMode) {
            if (text.startsWith("/")) {
                runLocalOpenCodeCommand(text);
                return ;
            }
            doOpenCodeRequest();
            return ;
        }
        let provider = plasmoid.configuration.provider || "openai";
        let providerCfg = getProviderConfig(provider);
        if (providerCfg.type === "anthropic")
            doAnthropicRequest(providerCfg.apiKey, providerCfg.model);
        else
            doOpenAICompatRequest(providerCfg.baseUrl, providerCfg.apiKey, providerCfg.model, providerCfg.headers, providerCfg.model);
    }

    function processNextQueuedMessage() {
        if (root.loading)
            return ;

        for (let i = 0; i < root.messages.length; i++) {
            if ((root.messages[i].role || "") === "queued") {
                sendMessageByIndex(i);
                return ;
            }
        }
    }

    function providerDisplayName(providerId) {
        return ProviderService.getProviderDisplayName(providerId);
    }

    function validateOpenCodeConfig() {
        let missing = [];
        if (!(plasmoid.configuration.openCodeUrl || "").trim())
            missing.push("OpenCode URL");

        if (!(plasmoid.configuration.openCodeProvider || "").trim())
            missing.push("OpenCode provider");

        if (!(plasmoid.configuration.openCodeModel || "").trim())
            missing.push("OpenCode model");

        if (missing.length > 0)
            return "Cannot send yet. Configure: " + missing.join(", ") + ".";

        return "";
    }

    function validateProviderConfig(providerId, cfg) {
        if (!cfg)
            return "Provider configuration missing.";

        let missing = [];
        let name = providerDisplayName(providerId);
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
            return "Cannot send with " + name + ". Missing: " + missing.join(", ") + ".";

        if (cfg.baseUrl && cfg.type !== "anthropic") {
            let urlTrimmed = cfg.baseUrl.trim();
            if (!urlTrimmed.startsWith("http://") && !urlTrimmed.startsWith("https://")) {
                return "Invalid URL in " + name + ": URL must start with http:// or https://";
            }
        }

        if (cfg.apiKey) {
            let trimmedKey = cfg.apiKey.trim();
            if (providerId === "openai" && !trimmedKey.startsWith("sk-")) {
                return "Invalid OpenAI API key format: keys should start with 'sk-'";
            }
            if (providerId === "anthropic" && !trimmedKey.startsWith("sk-ant-")) {
                return "Invalid Anthropic API key format: keys should start with 'sk-ant-'";
            }
        }

        return "";
    }

    function sendMessage() {
        // ──────────────────────────────────────────────────────────────

        try {
            let text = (root.chatInputText || "").trim();
            let attachments = root.attachedFiles || [];
            if (text === "" && attachments.length === 0)
                return ;

            let maxLen = 100000;
            if (text.length > maxLen) {
                pushErrorMessage("Message is too long (maximum " + maxLen + " characters).");
                return ;
            }

            // ── /schedule command ──────────────────────────────────────────
            let lowerText = text.toLowerCase().replace(/^\//, "").trim();
            if (lowerText === "schedule" || lowerText === "schedules" || lowerText === "scheduler" || text.toLowerCase().startsWith("/schedule")) {
                let schedText = "";
                if (text.toLowerCase().startsWith("/schedule"))
                    schedText = text.slice("/schedule".length).trim();
                else if (text.toLowerCase().startsWith("schedule"))
                    schedText = text.slice("schedule".length).trim();
                else if (text.toLowerCase().startsWith("schedules"))
                    schedText = text.slice("schedules".length).trim();
                else if (text.toLowerCase().startsWith("scheduler"))
                    schedText = text.slice("scheduler".length).trim();
                root.attachedFiles = [];
                root.chatInputText = "";
                root.clearChatInput();
                // 1. Append the user message
                appendUserMessage(text, "user", []);
                if (schedText !== "") {
                    // Open dialog prefilled with message
                    root.handleScheduleCommand(schedText);
                } else {
                    // Trigger a poll now so that the list is fresh when the bubble is rendered!
                    schedulerPollTimer.triggered();
                    // Append interactive list inline!
                    let ts = Date.now();
                    root.messages = root.messages.concat([{
                        "role": "schedules_list",
                        "content": "Interactive Schedules Manager",
                        "time": nowTime(ts),
                        "at": ts,
                        "model": "",
                        "queueId": 0,
                        "attachments": []
                    }]);
                    saveCurrentSessionState(true);
                    if (!root.userScrolledUp)
                        Qt.callLater(scrollToBottom);

                }
                return ;
            }
            root.attachedFiles = [];
            root.chatInputText = "";
            root.clearChatInput();
            root.userScrolledUp = false;
            if (root.loading) {
                let queueCount = 0;
                for (let idx = 0; idx < root.messages.length; idx++) {
                    if ((root.messages[idx].role || "") === "queued") {
                        queueCount++;
                    }
                }
                if (queueCount >= 5) {
                    pushErrorMessage("Too many messages in queue (maximum 5). Please wait for the current request to finish.");
                    return ;
                }
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

    function getProviderConfig(provider) {
        return ProviderService.getProviderConfig(provider, plasmoid.configuration);
    }

    function translate(text) {
        return Translations.translate(text, plasmoid.configuration.language);
    }

    function isSessionScheduled(sessionId, messagesList) {
        let msgs = messagesList;
        if (!msgs) {
            let idx = sessionIndexById(sessionId || root.currentSessionId);
            if (idx >= 0)
                msgs = root.sessions[idx].messages || [];
        }
        if (!msgs || msgs.length === 0)
            return false;
        // Search from the end for the last user message
        for (let i = msgs.length - 1; i >= 0; i--) {
            let m = msgs[i];
            if (m.role === "user" && !m.isSystem) {
                return !!m.sc;
            }
        }
        return false;
    }

    function buildEffectiveSystemPrompt(sessionId) {
        let sId = sessionId || root.currentSessionId;
        let base = plasmoid.configuration.systemPrompt || "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.";
        let memoryOn = plasmoid.configuration.memoryEnabled || false;
        let memoryTxt = (plasmoid.configuration.userMemory || "").trim();
        if (memoryOn && memoryTxt !== "")
            base = base + "\n\n--- User Memory ---\n" + memoryTxt + "\n--- End of User Memory ---";

        if (!isSessionScheduled(sId)) {
            let summary = getSessionProperty(sId, "compactedSummary", "");
            if (summary !== "")
                base = base + "\n\n--- Summary of Previous Conversation ---\n" + summary + "\n--- End of Summary ---";
        }

        return base;
    }

    // Returns a filtered, context-limited list of {role, content} pairs.
    // System-status bubbles (error, schedules_list, info …) are excluded.
    // Messages before the compacted boundary are excluded.
    // Only the last N user/assistant messages are kept (N = per-session override OR global limit).
    function buildContextWindow(messagesList, sessionId) {
        let sId = sessionId || root.currentSessionId;
        let override = getSessionProperty(sId, "contextOverride", false);
        let contextEnabled = override ? getSessionProperty(sId, "contextEnabled", true) : (plasmoid.configuration.globalContextEnabled !== false);
        let limit = override ? getSessionProperty(sId, "contextLimit", 1) : (plasmoid.configuration.globalContextLimit !== undefined && plasmoid.configuration.globalContextLimit !== null ? plasmoid.configuration.globalContextLimit : 1);
        let isSched = isSessionScheduled(sId, messagesList);
        let compactedCount = isSched ? 0 : getSessionProperty(sId, "compactedMessageCount", 0);
        let clean = [];
        for (let i = 0; i < messagesList.length; i++) {
            let m = messagesList[i];
            // Skip messages before the compacted boundary
            if (i < compactedCount)
                continue;

            // Only real conversation turns
            if (m.role !== "user" && m.role !== "assistant")
                continue;

            // Exclude system-status assistant bubbles (info/error injected by the widget)
            if (m.isSystem)
                continue;

            clean.push({
                "idx": i,
                "msg": m
            });
        }
        if (!contextEnabled) {
            // No context: only keep the very last user message
            for (let k = clean.length - 1; k >= 0; k--) {
                if (clean[k].msg.role === "user")
                    return [clean[k].msg];

            }
            return [];
        }
        // Apply limit (take the last `limit` items)
        if (clean.length > limit)
            clean = clean.slice(clean.length - limit);

        return clean.map(function(e) {
            return e.msg;
        });
    }

    function buildOpenAICompatPayload() {
        let sys = buildEffectiveSystemPrompt();
        let arr = [{
            "role": "system",
            "content": sys
        }];
        return arr.concat(_buildMessageArray(root.messages, "", "openai"));
    }

    function buildAnthropicPayload() {
        return _buildMessageArray(root.messages, "", "anthropic");
    }

    function buildOpenAICompatPayloadForMessages(messagesList, chatId) {
        let sys = buildEffectiveSystemPrompt(chatId);
        let arr = [{
            "role": "system",
            "content": sys
        }];
        return arr.concat(_buildMessageArray(messagesList, chatId, "openai"));
    }

    function buildAnthropicPayloadForMessages(messagesList, chatId) {
        return _buildMessageArray(messagesList, chatId, "anthropic");
    }

    function _buildMessageArray(messagesList, chatId, format) {
        let arr = [];
        let window = buildContextWindow(messagesList, chatId);
        for (let i = 0; i < window.length; i++) {
            let m = window[i];
            let contentVal = m.content;
            if (m.quote) {
                let sender = m.quote.role === "assistant" ? (m.quote.model || "Assistant") : "User";
                contentVal = "[Replying to @" + sender + ": \"" + m.quote.content + "\"]\n\n" + contentVal;
            }
            if (m.role === "user" && m.attachments && m.attachments.length > 0)
                arr.push({
                    "role": m.role,
                    "content": buildMessageContent(contentVal, m.attachments, format)
                });
            else
                arr.push({
                    "role": m.role,
                    "content": contentVal
                });
        }
        return arr;
    }

    function appendMessageToSession(chatId, msgObj) {
        let idx = sessionIndexById(chatId);
        if (idx < 0)
            return ;

        let updated = root.sessions.slice();
        let s = Object.assign({
        }, updated[idx]);
        let msgs = (s.messages || []).slice();
        msgs.push(msgObj);
        s.messages = msgs;
        s.updatedAt = Date.now();
        if (chatId === root.currentSessionId) {
            root.messages = msgs;
            if (root.expanded && !root.historyOnlyMode)
                s.readCount = msgs.length;

        }
        updated[idx] = s;
        root.sessions = updated;
        sortSessionsByUpdated();
        persistSessions();
    }

    function handleBackgroundError(chatId, errorMsg, notify, schedId, schedName) {
        let errTs = Date.now();
        let errMsgObj = {
            "role": "assistant",
            "content": "Warning: Schedule failed: " + errorMsg,
            "time": nowTime(errTs),
            "at": errTs,
            "model": ""
        };
        appendMessageToSession(chatId, errMsgObj);
        if (notify) {
            let safeErr = Sec.sanitizeForShell(errorMsg);
            let errTitle = "Schedule Failed: " + (schedName || "Chat");
            let safeErrTitle = Sec.sanitizeForShell(errTitle);
            soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning " + Sec.quoteForShell(safeErrTitle) + " " + Sec.quoteForShell(safeErr) + " #sched-notify-err");
        }
        if (schedId) {
            let payload = {
                "schedId": schedId,
                "status": errorMsg
            };
            let b64Payload = base64Encode(JSON.stringify(payload));
            let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " update_schedule_history_status " + Sec.quoteForShell(b64Payload);
            soundDs.connectSource("sh -lc " + Sec.quoteForShell(cmd) + " #sched-history-err");
        }
    }

    function doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName) {
        function failBackgroundOpenCodeRequest(message) {
            if (requestFinalized)
                return ;

            requestFinalized = true;
            handleBackgroundError(chatId, message, notify, schedId, schedName);
        }

        let requestFinalized = false;
        ensureOpenCodeServerRunning(chatId, function() {
            ensureOpenCodeSessionForChatId(chatId, function(remoteSessionId) {
                let xhr = new XMLHttpRequest();
                let modelId = (plasmoid.configuration.openCodeModel || "").trim();
                let providerId = (plasmoid.configuration.openCodeProvider || "").trim();
                xhr.open("POST", openCodeBaseUrl() + "/session/" + remoteSessionId + "/message", true);
                xhr.setRequestHeader("Content-Type", "application/json");
                xhr.timeout = 60000;
                xhr.ontimeout = function() {
                    failBackgroundOpenCodeRequest("OpenCode: message request timed out at " + openCodeBaseUrl());
                };
                xhr.onreadystatechange = function() {
                    if (xhr.readyState !== XMLHttpRequest.DONE)
                        return ;

                    if (requestFinalized)
                        return ;

                    if (xhr.status < 200 || xhr.status >= 300) {
                        if (xhr.status === 404)
                            setOpenCodeSessionIdForChatId(chatId, "");

                        let suffix = xhr.status > 0 ? ("HTTP " + xhr.status) : "transport error";
                        failBackgroundOpenCodeRequest("OpenCode request failed (" + suffix + ") at " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message.");
                        return ;
                    }
                    try {
                        let obj = JSON.parse(xhr.responseText);
                        let combined = "";
                        if (obj.parts && obj.parts.length > 0) {
                            for (let i = 0; i < obj.parts.length; i++) {
                                if (obj.parts[i].type === "text")
                                    combined += obj.parts[i].text || obj.parts[i].content || "";

                            }
                        }
                        if (obj.info && obj.info.error) {
                            failBackgroundOpenCodeRequest(extractReadableError("OpenCode: ", obj.info.error, "Request failed."));
                            return ;
                        }
                        if (combined !== "") {
                            let doneTs = Date.now();
                            let msgObj = {
                                "role": "assistant",
                                "content": combined,
                                "time": nowTime(doneTs),
                                "at": doneTs,
                                "model": providerId + "/" + modelId,
                                "queueId": 0,
                                "attachments": []
                            };
                            appendMessageToSession(chatId, msgObj);
                            triggerNotificationSound();
                            if (notify) {
                                let safeText = Sec.sanitizeForShell(combined.substring(0, 150)) + (combined.length > 150 ? "…" : "");
                                let title = (schedName || "Scheduled message response ready");
                                let safeTitle = Sec.sanitizeForShell(title);
                                soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information " + Sec.quoteForShell(safeTitle) + " " + Sec.quoteForShell(safeText) + " #sched-notify-resp");
                            }
                        } else {
                            failBackgroundOpenCodeRequest("The model returned an empty response.");
                        }
                    } catch (parseResponseError) {
                        failBackgroundOpenCodeRequest("Failed to parse response: " + parseResponseError);
                    }
                    requestFinalized = true;
                };
                xhr.onerror = function() {
                    failBackgroundOpenCodeRequest("OpenCode: request could not reach " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message. The server is reachable, but this request path failed.");
                };
                try {
                    xhr.send(JSON.stringify({
                        "role": "user",
                        "content": messageText,
                        "stream": false
                    }));
                } catch (sendError) {
                    failBackgroundOpenCodeRequest("Failed to send message: " + sendError);
                }
            }, function(sessionErr) {
                failBackgroundOpenCodeRequest(sessionErr);
            });
        }, function(serverErr) {
            failBackgroundOpenCodeRequest(serverErr);
        });
    }

    function doBackgroundOpenAICompatRequest(chatId, baseUrl, apiKey, model, extraHeaders, modelLabel, messageText, notify, schedId, schedName) {
        let url = (baseUrl || "").replace(/\/$/, "") + "/chat/completions";
        let xhr = new XMLHttpRequest();
        let errorHandled = false;
        let targetIdx = sessionIndexById(chatId);
        if (targetIdx < 0)
            return ;

        let targetSession = root.sessions[targetIdx];
        let messagesList = targetSession.messages || [];
        try {
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            if (apiKey !== "")
                xhr.setRequestHeader("Authorization", "Bearer " + apiKey);

            if (extraHeaders) {
                for (let headerName in extraHeaders) {
                    if (Object.prototype.hasOwnProperty.call(extraHeaders, headerName) && extraHeaders[headerName])
                        xhr.setRequestHeader(headerName, extraHeaders[headerName]);

                }
            }
            xhr.timeout = 60000;
            xhr.ontimeout = function() {
                if (errorHandled)
                    return ;

                errorHandled = true;
                handleBackgroundError(chatId, "Request timed out after 60 seconds.", notify, schedId, schedName);
            };
        } catch (setupError) {
            handleBackgroundError(chatId, "Failed to start request: " + setupError, notify, schedId, schedName);
            return ;
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status < 200 || xhr.status >= 300) {
                if (errorHandled)
                    return ;

                errorHandled = true;
                let err = "Request to " + url + " failed";
                if (xhr.status)
                    err += " (HTTP " + xhr.status + ")";

                try {
                    let eobj = JSON.parse(xhr.responseText);
                    if (eobj.error) {
                        if (typeof eobj.error === "string") {
                            err += " | " + eobj.error;
                        } else {
                            if (eobj.error.message)
                                err = "API Error (" + xhr.status + "): " + eobj.error.message;

                        }
                    } else if (eobj.detail)
                        err += " | " + eobj.detail;
                    else if (eobj.message)
                        err += " | " + eobj.message;
                } catch (e2) {
                }
                handleBackgroundError(chatId, err, notify, schedId, schedName);
                return ;
            }
            try {
                let parsed = JSON.parse(xhr.responseText);
                let finalText = (parsed.choices && parsed.choices[0] && parsed.choices[0].message && parsed.choices[0].message.content) || "";
                if (finalText !== "") {
                    let doneTs = Date.now();
                    let msgObj = {
                        "role": "assistant",
                        "content": finalText,
                        "time": nowTime(doneTs),
                        "at": doneTs,
                        "model": modelLabel || model || ""
                    };
                    if (parsed.usage)
                        msgObj.tokens = {
                            "input": parsed.usage.prompt_tokens || 0,
                            "output": parsed.usage.completion_tokens || 0
                        };

                    appendMessageToSession(chatId, msgObj);
                    if (chatId === root.currentSessionId) {
                        if (!root.userScrolledUp)
                            Qt.callLater(scrollToBottom);

                    }
                    triggerNotificationSound();
                    if (notify) {
                        let safeText = Sec.sanitizeForShell(finalText.substring(0, 150)) + (finalText.length > 150 ? "…" : "");
                        let title = (schedName || "Scheduled message response ready");
                        let safeTitle = Sec.sanitizeForShell(title);
                        soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information " + Sec.quoteForShell(safeTitle) + " " + Sec.quoteForShell(safeText) + " #sched-notify-resp");
                    }
                } else {
                    handleBackgroundError(chatId, "The model returned an empty response.", notify, schedId, schedName);
                }
            } catch (parseError) {
                handleBackgroundError(chatId, "Failed to parse response: " + parseError, notify, schedId, schedName);
            }
        };
        xhr.onerror = function() {
            if (errorHandled)
                return ;

            errorHandled = true;
            handleBackgroundError(chatId, "Could not reach " + url + ". Check network connectivity.", notify, schedId, schedName);
        };
        try {
            xhr.send(JSON.stringify({
                "model": model,
                "messages": buildOpenAICompatPayloadForMessages(messagesList, chatId),
                "stream": false
            }));
        } catch (sendError) {
            handleBackgroundError(chatId, "Failed to send request: " + sendError, notify, schedId, schedName);
        }
    }

    function doBackgroundAnthropicRequest(chatId, apiKey, model, messageText, notify, schedId, schedName) {
        let xhr = new XMLHttpRequest();
        let errorHandled = false;
        let targetIdx = sessionIndexById(chatId);
        if (targetIdx < 0)
            return ;

        let targetSession = root.sessions[targetIdx];
        let messagesList = targetSession.messages || [];
        try {
            xhr.open("POST", "https://api.anthropic.com/v1/messages", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("x-api-key", apiKey);
            xhr.setRequestHeader("anthropic-version", "2023-06-01");
            xhr.timeout = 60000;
            xhr.ontimeout = function() {
                if (errorHandled)
                    return ;

                errorHandled = true;
                handleBackgroundError(chatId, "Request timed out after 60 seconds.", notify, schedId, schedName);
            };
        } catch (setupError) {
            handleBackgroundError(chatId, "Failed to start request: " + setupError, notify, schedId, schedName);
            return ;
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    let obj = JSON.parse(xhr.responseText);
                    let text = "";
                    if (obj.content && obj.content.length) {
                        for (let i = 0; i < obj.content.length; i++) {
                            if (obj.content[i].type === "text")
                                text += obj.content[i].text;

                        }
                    }
                    let ts = Date.now();
                    let msgObj = {
                        "role": "assistant",
                        "content": text || "(empty response)",
                        "time": nowTime(ts),
                        "at": ts,
                        "model": model || ""
                    };
                    if (obj.usage)
                        msgObj.tokens = {
                            "input": obj.usage.input_tokens || 0,
                            "output": obj.usage.output_tokens || 0
                        };

                    appendMessageToSession(chatId, msgObj);
                    if (chatId === root.currentSessionId) {
                        if (!root.userScrolledUp)
                            Qt.callLater(scrollToBottom);

                    }
                    triggerNotificationSound();
                    if (notify) {
                        let safeText = Sec.sanitizeForShell((text || "").substring(0, 150)) + ((text || "").length > 150 ? "…" : "");
                        let title = (schedName || "Scheduled message response ready");
                        let safeTitle = Sec.sanitizeForShell(title);
                        soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information " + Sec.quoteForShell(safeTitle) + " " + Sec.quoteForShell(safeText) + " #sched-notify-resp");
                    }
                } catch (e) {
                    handleBackgroundError(chatId, "Failed to parse Anthropic response", notify, schedId, schedName);
                }
            } else {
                if (errorHandled)
                    return ;

                errorHandled = true;
                let err = "Anthropic HTTP " + xhr.status;
                try {
                    let eobj = JSON.parse(xhr.responseText);
                    if (eobj.error) {
                        if (typeof eobj.error === "string") {
                            err += " | " + eobj.error;
                        } else {
                            if (eobj.error.message)
                                err = "Anthropic Error (" + xhr.status + "): " + eobj.error.message;

                            if (eobj.error.type)
                                err = "[" + eobj.error.type + "] " + err;

                        }
                    }
                } catch (e2) {
                }
                handleBackgroundError(chatId, err, notify, schedId, schedName);
            }
        };
        xhr.onerror = function() {
            if (errorHandled)
                return ;

            errorHandled = true;
            handleBackgroundError(chatId, "Could not reach Anthropic API. Check network status.", notify, schedId, schedName);
        };
        try {
            xhr.send(JSON.stringify({
                "model": model,
                "max_tokens": 1024,
                "system": buildEffectiveSystemPrompt(chatId),
                "messages": buildAnthropicPayloadForMessages(messagesList, chatId)
            }));
        } catch (sendError) {
            handleBackgroundError(chatId, "Failed to send request: " + sendError, notify, schedId, schedName);
        }
    }

    function executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName) {
        let soundCmd = "pw-play /usr/share/sounds/ocean/stereo/service-login.oga || " + "paplay /usr/share/sounds/ocean/stereo/service-login.oga || " + "pw-play /usr/share/sounds/ocean/stereo/window-attention.oga || " + "paplay /usr/share/sounds/ocean/stereo/window-attention.oga || " + "aplay /usr/share/sounds/freedesktop/stereo/bell.oga || " + "canberra-gtk-play -i service-login";
        soundDs.connectSource(soundCmd + " #sched-sound-" + Date.now());
        let validationError = validateCurrentSendTarget();
        if (validationError !== "") {
            handleBackgroundError(chatId, validationError, notify, schedId, schedName);
            return ;
        }
        let userTs = Date.now();
        let userMsgObj = {
            "role": "user",
            "content": messageText,
            "time": nowTime(userTs),
            "at": userTs,
            "model": "",
            "attachments": [],
            "sc": true
        };
        appendMessageToSession(chatId, userMsgObj);
        if (notify) {
            let safeText = Sec.sanitizeForShell(messageText.substring(0, 150)) + (messageText.length > 150 ? "…" : "");
            let sIdx = sessionIndexById(chatId);
            let sTitle = (sIdx >= 0 && root.sessions[sIdx].title) ? root.sessions[sIdx].title : "Chat";
            let title = "Scheduled: " + sTitle;
            let safeTitle = Sec.sanitizeForShell(title);
            soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information " + Sec.quoteForShell(safeTitle) + " " + Sec.quoteForShell(safeText) + " #sched-notify");
        }
        if (root.openCodeMode) {
            doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName);
            return ;
        }
        let provider = plasmoid.configuration.provider || "openai";
        let providerCfg = getProviderConfig(provider);
        if (providerCfg.type === "anthropic")
            doBackgroundAnthropicRequest(chatId, providerCfg.apiKey, providerCfg.model, messageText, notify, schedId, schedName);
        else
            doBackgroundOpenAICompatRequest(chatId, providerCfg.baseUrl, providerCfg.apiKey, providerCfg.model, providerCfg.headers, providerCfg.model, messageText, notify, schedId, schedName);
    }

    function doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel) {
        let url = (baseUrl || "").replace(/\/$/, "") + "/chat/completions";
        let xhr = new XMLHttpRequest();
        let errorHandled = false;
        let lastUserText = "";
        for (let mIdx = root.messages.length - 1; mIdx >= 0; mIdx--) {
            if ((root.messages[mIdx].role || "") === "user") {
                lastUserText = root.messages[mIdx].content || "";
                break;
            }
        }
        let dedupKey = RequestDeduplicator.key(plasmoid.configuration.provider || "openai", model, lastUserText, root.currentSessionId);
        if (!RequestDeduplicator.tryClaim(dedupKey)) {
            pushErrorMessage("Duplicate request ignored: a response to this message is already in flight.");
            return ;
        }
        try {
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            if (apiKey !== "")
                xhr.setRequestHeader("Authorization", "Bearer " + apiKey);

            if (extraHeaders) {
                for (let headerName in extraHeaders) {
                    if (Object.prototype.hasOwnProperty.call(extraHeaders, headerName) && extraHeaders[headerName])
                        xhr.setRequestHeader(headerName, extraHeaders[headerName]);

                }
            }
            xhr.timeout = 60000;
            xhr.ontimeout = function() {
                if (errorHandled)
                    return ;

                errorHandled = true;
                root.loading = false;
                root.activeXhr = null;
                pushErrorMessage("Request timed out after 60 seconds.");
                processNextQueuedMessage();
            };
        } catch (setupError) {
            root.loading = false;
            root.activeXhr = null;
            RequestDeduplicator.release(dedupKey);
            pushErrorMessage("Failed to start request: " + setupError);
            return ;
        }
        root.loading = true;
        root.activeXhr = xhr;
        // Non-streaming: wait for the complete response, then display it at once.
        // This is intentional — streaming caused the QML engine to re-render on every
        // individual token, saturating the main thread and freezing the KDE desktop.
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            root.loading = false;
            root.activeXhr = null;
            RequestDeduplicator.release(dedupKey);
            if (xhr.status < 200 || xhr.status >= 300) {
                if (errorHandled)
                    return ;

                errorHandled = true;
                let err = "Request to " + Sec.scrubSecrets(url) + " failed";
                if (xhr.status)
                    err += " (HTTP " + xhr.status + ")";

                try {
                    let eobj = JSON.parse(xhr.responseText);
                    if (eobj.error) {
                        if (typeof eobj.error === "string") {
                            err += " | " + Sec.scrubSecrets(eobj.error);
                        } else {
                            if (eobj.error.message)
                                err = "API Error (" + xhr.status + "): " + Sec.scrubSecrets(eobj.error.message);

                            if (eobj.error.metadata) {
                                try {
                                    err += " | " + Sec.scrubSecrets(JSON.stringify(eobj.error.metadata));
                                } catch (ex) {
                                    err += " | " + Sec.scrubSecrets(String(eobj.error.metadata));
                                }
                            }
                        }
                    } else if (eobj.detail)
                        err += " | " + Sec.scrubSecrets(eobj.detail);
                    else if (eobj.message)
                        err += " | " + Sec.scrubSecrets(eobj.message);
                } catch (e2) {
                }
                pushErrorMessage(err);
                processNextQueuedMessage();
                return ;
            }
            try {
                let parsed = JSON.parse(xhr.responseText);
                let finalText = (parsed.choices && parsed.choices[0] && parsed.choices[0].message && parsed.choices[0].message.content) || "";
                if (finalText !== "") {
                    let doneTs = Date.now();
                    let msgObj = {
                        "role": "assistant",
                        "content": finalText,
                        "time": nowTime(doneTs),
                        "at": doneTs,
                        "model": modelLabel || model || ""
                    };
                    if (parsed.usage)
                        msgObj.tokens = {
                        "input": parsed.usage.prompt_tokens || 0,
                        "output": parsed.usage.completion_tokens || 0
                    };

                    root.messages = root.messages.concat([msgObj]);
                    if (!root.userScrolledUp)
                        Qt.callLater(scrollToBottom);

                } else {
                    pushErrorMessage("The model returned an empty response.");
                }
            } catch (parseError) {
                pushErrorMessage("Failed to parse response: " + parseError);
            }
            triggerNotificationSound();
            saveCurrentSessionState(true);
            Qt.callLater(function() {
                checkAndAutoCompact();
            });
            processNextQueuedMessage();
        };
        xhr.onerror = function() {
            if (errorHandled)
                return ;

            errorHandled = true;
            root.loading = false;
            root.activeXhr = null;
            RequestDeduplicator.release(dedupKey);
            pushErrorMessage("Could not reach " + Sec.scrubSecrets(url) + ". Check the server URL and whether that endpoint accepts API requests.");
            processNextQueuedMessage();
        };
        try {
            xhr.send(JSON.stringify({
                "model": model,
                "messages": buildOpenAICompatPayload(),
                "stream": false
            }));
        } catch (sendError) {
            root.loading = false;
            root.activeXhr = null;
            RequestDeduplicator.release(dedupKey);
            pushErrorMessage("Failed to send request: " + sendError);
        }
    }

    function doAnthropicRequest(apiKey, model) {
        if (!apiKey) {
            pushErrorMessage("Anthropic API key missing in settings.");
            processNextQueuedMessage();
            return ;
        }
        let xhr = new XMLHttpRequest();
        let errorHandled = false;
        let lastUserText = "";
        for (let mIdx = root.messages.length - 1; mIdx >= 0; mIdx--) {
            if ((root.messages[mIdx].role || "") === "user") {
                lastUserText = root.messages[mIdx].content || "";
                break;
            }
        }
        let dedupKey = RequestDeduplicator.key("anthropic", model, lastUserText, root.currentSessionId);
        if (!RequestDeduplicator.tryClaim(dedupKey)) {
            pushErrorMessage("Duplicate request ignored: a response to this message is already in flight.");
            return ;
        }
        root.loading = true;
        root.activeXhr = xhr;
        xhr.open("POST", "https://api.anthropic.com/v1/messages", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.setRequestHeader("x-api-key", apiKey);
        xhr.setRequestHeader("anthropic-version", "2023-06-01");
        xhr.timeout = 60000;
        xhr.ontimeout = function() {
            if (errorHandled)
                return ;

            errorHandled = true;
            root.loading = false;
            root.activeXhr = null;
            RequestDeduplicator.release(dedupKey);
            pushErrorMessage("Request timed out after 60 seconds.");
            processNextQueuedMessage();
        };
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            root.loading = false;
            root.activeXhr = null;
            RequestDeduplicator.release(dedupKey);
            if (xhr.status >= 200 && xhr.status < 300) {
                triggerNotificationSound();
                try {
                    let obj = JSON.parse(xhr.responseText);
                    let text = "";
                    if (obj.content && obj.content.length) {
                        for (let i = 0; i < obj.content.length; i++) {
                            if (obj.content[i].type === "text")
                                text += obj.content[i].text;

                        }
                    }
                    let ts = Date.now();
                    let msgObj = {
                        "role": "assistant",
                        "content": text || "(empty response)",
                        "time": nowTime(ts),
                        "at": ts,
                        "model": model || ""
                    };
                    if (obj.usage)
                        msgObj.tokens = {
                        "input": obj.usage.input_tokens || 0,
                        "output": obj.usage.output_tokens || 0
                    };

                    root.messages = root.messages.concat([msgObj]);
                } catch (e) {
                    pushErrorMessage("Failed to parse Anthropic response");
                }
            } else {
                let err = "Anthropic HTTP " + xhr.status;
                try {
                    let eobj = JSON.parse(xhr.responseText);
                    if (eobj.error) {
                        if (typeof eobj.error === "string") {
                            err += " | " + Sec.scrubSecrets(eobj.error);
                        } else {
                            if (eobj.error.message)
                                err = "Anthropic Error (" + xhr.status + "): " + Sec.scrubSecrets(eobj.error.message);

                            if (eobj.error.type)
                                err = "[" + eobj.error.type + "] " + err;

                        }
                    }
                } catch (e2) {
                }
                pushErrorMessage(err);
            }
            scrollToBottom();
            saveCurrentSessionState(true);
            Qt.callLater(function() {
                checkAndAutoCompact();
            });
            processNextQueuedMessage();
        };
        xhr.onerror = function() {
            if (errorHandled)
                return ;

            errorHandled = true;
            root.loading = false;
            root.activeXhr = null;
            RequestDeduplicator.release(dedupKey);
            pushErrorMessage("Could not reach https://api.anthropic.com/v1/messages. Check network access and API configuration.");
            processNextQueuedMessage();
        };
        xhr.send(JSON.stringify({
            "model": model,
            "max_tokens": 1024,
            "system": buildEffectiveSystemPrompt(),
            "messages": buildAnthropicPayload()
        }));
    }

    function triggerNotificationSound() {
        if (!plasmoid.configuration.playNotificationSound)
            return ;

        soundDs.connectSource("pw-play /usr/share/sounds/ocean/stereo/message-new-instant.oga || paplay /usr/share/sounds/ocean/stereo/message-new-instant.oga || aplay /usr/share/sounds/freedesktop/stereo/bell.oga || canberra-gtk-play -i message-new-instant");
    }

    function respondToPermission(permissionId, approved) {
        function sendToUrl(url, isRetry) {
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                if (xhr.status >= 200 && xhr.status < 300) {
                    let updatedMsgs = root.messages.slice();
                    for (let i = 0; i < updatedMsgs.length; i++) {
                        if (updatedMsgs[i].role === "permission_request" && updatedMsgs[i].permissionId === permissionId) {
                            updatedMsgs[i].status = approved ? "allowed" : "denied";
                            break;
                        }
                    }
                    root.messages = updatedMsgs;
                    saveCurrentSessionState(true);
                } else if (xhr.status === 404 && !isRetry) {
                    sendToUrl(fallbackUrl, true);
                } else {
                    let errorMsgs = root.messages.slice();
                    for (let i = 0; i < errorMsgs.length; i++) {
                        if (errorMsgs[i].role === "permission_request" && errorMsgs[i].permissionId === permissionId) {
                            errorMsgs[i].status = "pending";
                            break;
                        }
                    }
                    root.messages = errorMsgs;
                    pushErrorMessage("OpenCode: failed to reply to permission (HTTP " + xhr.status + ").");
                }
            };
            xhr.onerror = function() {
                if (!isRetry) {
                    sendToUrl(fallbackUrl, true);
                } else {
                    let networkMsgs = root.messages.slice();
                    for (let i = 0; i < networkMsgs.length; i++) {
                        if (networkMsgs[i].role === "permission_request" && networkMsgs[i].permissionId === permissionId) {
                            networkMsgs[i].status = "pending";
                            break;
                        }
                    }
                    root.messages = networkMsgs;
                    pushErrorMessage("OpenCode: could not reach permission reply server endpoint.");
                }
            };
            xhr.send(JSON.stringify({
                "response": responseValue
            }));
        }

        let sessionId = root.openCodeActiveSessionId;
        if (!sessionId) {
            let idx = sessionIndexById(root.currentSessionId);
            if (idx >= 0)
                sessionId = root.sessions[idx].openCodeSessionId || "";

        }
        if (!sessionId || !permissionId)
            return ;

        let copy = root.messages.slice();
        for (let i = 0; i < copy.length; i++) {
            if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                copy[i].status = approved ? "allowing..." : "denying...";
                break;
            }
        }
        root.messages = copy;
        let xhr = new XMLHttpRequest();
        let primaryUrl = openCodeBaseUrl() + "/session/" + sessionId + "/permission/" + permissionId;
        let fallbackUrl = openCodeBaseUrl() + "/session/" + sessionId + "/permissions/" + permissionId;
        let responseValue = approved ? "allow" : "deny";
        sendToUrl(primaryUrl, false);
    }

    // Collect selected options from the question UI and submit the answer
    function submitQuestionAnswer(questionId, questions, customField) {
        // Find the question_request message to access its question data
        let msgIdx = -1;
        for (let i = 0; i < root.messages.length; i++) {
            if (root.messages[i].role === "question_request" && root.messages[i].questionId === questionId) {
                msgIdx = i;
                break;
            }
        }
        if (msgIdx < 0)
            return ;

        let customText = customField ? (customField.text || "").trim() : "";
        // If no structured questions, fallback to custom text only
        if (!questions || questions.length === 0) {
            if (customText !== "")
                respondToQuestion(questionId, customText, false);

            return ;
        }
        // For structured questions, the answer format is array of arrays.
        // However since we can't easily traverse QML Repeater children
        // to read selected state, we use a simpler approach:
        // If user typed custom text, use that as the answer.
        // Otherwise this function is called from the Submit button
        // and we handle it via the text field.
        if (customText !== "") {
            respondToQuestion(questionId, customText, false);
        } else {
        }
    }

    function respondToQuestion(questionId, answerValue, isReject) {
        function tryNextUrl() {
            if (currentUrlIdx >= urls.length) {
                let exhaustedMsgs = root.messages.slice();
                for (let i = 0; i < exhaustedMsgs.length; i++) {
                    if (exhaustedMsgs[i].role === "question_request" && exhaustedMsgs[i].questionId === questionId) {
                        exhaustedMsgs[i].status = "pending";
                        break;
                    }
                }
                root.messages = exhaustedMsgs;
                pushErrorMessage("OpenCode: failed to reply to question endpoint.");
                return ;
            }
            let url = urls[currentUrlIdx];
            currentUrlIdx++;
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                if (xhr.status >= 200 && xhr.status < 300) {
                    let updatedMsgs = root.messages.slice();
                    for (let i = 0; i < updatedMsgs.length; i++) {
                        if (updatedMsgs[i].role === "question_request" && updatedMsgs[i].questionId === questionId) {
                            updatedMsgs[i].status = isReject ? "dismissed" : "answered";
                            updatedMsgs[i].submittedAnswer = answerValue;
                            break;
                        }
                    }
                    root.messages = updatedMsgs;
                    saveCurrentSessionState(true);
                } else if (xhr.status === 404) {
                    tryNextUrl();
                } else {
                    let errorMsgs = root.messages.slice();
                    for (let i = 0; i < errorMsgs.length; i++) {
                        if (errorMsgs[i].role === "question_request" && errorMsgs[i].questionId === questionId) {
                            errorMsgs[i].status = "pending";
                            break;
                        }
                    }
                    root.messages = errorMsgs;
                    pushErrorMessage("OpenCode: failed to reply to question (HTTP " + xhr.status + ").");
                }
            };
            xhr.onerror = function() {
                tryNextUrl();
            };
            try {
                if (isReject) {
                    xhr.send(JSON.stringify({
                    }));
                } else {
                    // Send in OpenCode's expected format: { answers: [["label"]] }
                    let answers = [];
                    if (typeof answerValue === "object" && Array.isArray(answerValue))
                        answers = answerValue;
                    else
                        answers = [[String(answerValue || "")]];
                    xhr.send(JSON.stringify({
                        "answers": answers
                    }));
                }
            } catch (err) {
                tryNextUrl();
            }
        }

        let sessionId = root.openCodeActiveSessionId;
        if (!sessionId) {
            let idx = sessionIndexById(root.currentSessionId);
            if (idx >= 0)
                sessionId = root.sessions[idx].openCodeSessionId || "";

        }
        if (!questionId)
            return ;

        let copy = root.messages.slice();
        for (let i = 0; i < copy.length; i++) {
            if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                copy[i].status = isReject ? "dismissing..." : "answering...";
                break;
            }
        }
        root.messages = copy;
        let xhr = new XMLHttpRequest();
        let action = isReject ? "reject" : "reply";
        let urls = [openCodeBaseUrl() + "/question/" + questionId + "/" + action, openCodeBaseUrl() + "/session/" + sessionId + "/question/" + questionId + "/" + action, openCodeBaseUrl() + "/session/" + sessionId + "/questions/" + questionId + "/" + action];
        let currentUrlIdx = 0;
        tryNextUrl();
    }

    function stopStreaming() {
        if (root.activeXhr) {
            try {
                root.activeXhr.abort();
            } catch (e) {
            }
            root.activeXhr = null;
        }
        root.loading = false;
        flushStreamingBuffer();
        saveCurrentSessionState(true);
        processNextQueuedMessage();
    }

    function convertMarkdownToHtml(markdown) {
        if (!markdown)
            return "";

        let cacheKey = markdown + "_" + (root.popupIsDark ? "dark" : "light");
        let cached = root._markdownCache.get(cacheKey);
        if (cached !== undefined) {
            return cached;
        }

        try {
            let html = MarkdownRenderer.convertMarkdownToHtml(markdown, root.popupIsDark);
            root._markdownCache.put(cacheKey, html);
            return html;
        } catch (e) {
            console.error("convertMarkdownToHtml failed: " + e);
            return String(markdown).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br/>");
        }
    }

    function fileIconName(filename) {
        let ext = filename.split('.').pop().toLowerCase();
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

    function removeAttachedFile(index) {
        let files = root.attachedFiles.slice();
        if (index >= 0 && index < files.length) {
            files.splice(index, 1);
            root.attachedFiles = files;
        }
    }

    function getDocExtractorPath() {
        // Resolve the doc-extractor path and refuse anything outside the
        // package's `contents/ui/` directory. See `getHelperPath()` for
        // the rationale.
        let urlStr = String(Qt.resolvedUrl("doc_extractor.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);

        let path = decodeURIComponent(urlStr);
        if (path.indexOf("/contents/ui/") === -1)
            return "";
        return path;
    }

    function getHelperPath() {
        // Resolve the helper path relative to this QML file's package.
        // We reject any path that does not point inside the package's
        // `contents/ui/` directory — this prevents a compromised
        // Qt.resolvedUrl override (e.g. via a symlinked install or
        // custom `KDEDIRS` path) from steering the widget at an
        // attacker-controlled script.
        let urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);

        let path = decodeURIComponent(urlStr);
        // The helper must live inside the package's `contents/ui`
        // directory. Anything outside (e.g. /tmp, $HOME) is rejected
        // and the caller falls back to an empty string so the IPC
        // command becomes a no-op instead of executing an arbitrary
        // script.
        if (path.indexOf("/contents/ui/") === -1)
            return "";
        return path;
    }

    function getScriptsPath() {
        let helper = getHelperPath();
        let parts = helper.split("/");
        if (parts.length >= 2) {
            parts.splice(parts.length - 2, 2);
            return parts.join("/") + "/scripts";
        }
        return "";
    }

    function attachFile(fileUrl) {
        let localPath = String(fileUrl);
        if (localPath.indexOf("file://") === 0)
            localPath = localPath.substring(7);

        localPath = decodeURIComponent(localPath);
        let files = root.attachedFiles.slice();
        for (let i = 0; i < files.length; i++) {
            if (files[i].path === localPath)
                return ;

        }
        let filename = localPath.substring(localPath.lastIndexOf("/") + 1);
        let newFile = {
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
        let docExtractorPath = getDocExtractorPath();
        let safePath = Sec.validateFilePath(localPath);
        if (safePath === "") {
            // Refuse to call the helper with an unsafe or non-existent path
            console.warn("attachFile: rejected unsafe path");
            return;
        }
        let cmd = "python3 " + Sec.quoteForShell(docExtractorPath) + " " + Sec.quoteForShell(safePath);
        fileReaderDs.connectSource(cmd);
    }

    // Split raw markdown into typed blocks: {type:"text"|"code"|"table", content, lang}
    function parseMessageBlocks(markdown) {
        if (!markdown)
            return [{
            "type": "text",
            "content": "",
            "lang": ""
        }];

        let cachedBlocks = root._blocksCache.get(markdown);
        if (cachedBlocks !== undefined) {
            return cachedBlocks;
        }

        try {
            let blocks = MarkdownRenderer.parseMessageBlocks(markdown);
            root._blocksCache.put(markdown, blocks);
            return blocks;
        } catch (e) {
            console.error("parseMessageBlocks failed: " + e);
            return [{
                "type": "text",
                "content": markdown,
                "lang": ""
            }];
        }
    }

    // Convert markdown table to CSV string
    function tableMarkdownToCsv(tableMarkdown) {
        return MarkdownRenderer.tableMarkdownToCsv(tableMarkdown);
    }

    function buildMessageContent(text, attachments, apiType) {
        let docs = [];
        let imgs = [];
        for (let i = 0; i < attachments.length; i++) {
            let att = attachments[i];
            if (att.type === "image")
                imgs.push(att);
            else if (att.type === "text")
                docs.push(att);
        }
        let compiledPrompt = "";
        for (let d = 0; d < docs.length; d++) {
            compiledPrompt += "[Attached File: " + docs[d].name + " (" + Math.round((docs[d].size || 0) / 1024) + " KB)]\n";
            compiledPrompt += "--- START OF FILE CONTENT ---\n";
            compiledPrompt += (docs[d].content || "") + "\n";
            compiledPrompt += "--- END OF FILE CONTENT ---\n\n";
        }
        compiledPrompt += text;
        if (imgs.length === 0)
            return compiledPrompt;

        let contentList = [];
        if (compiledPrompt.trim() !== "")
            contentList.push({
            "type": "text",
            "text": compiledPrompt
        });

        for (let imgIdx = 0; imgIdx < imgs.length; imgIdx++) {
            let image = imgs[imgIdx];
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
        let docExtractorPath = getDocExtractorPath();
        let cmd = "python3 '" + docExtractorPath + "' --clipboard";
        fileReaderDs.connectSource(cmd);
    }

    function readClipboardText() {
        clipboardHelper.text = "";
        clipboardHelper.paste();
        return clipboardHelper.text;
    }

    function applyKWalletKeyToMemory(targetId, secretValue) {
        let configKey = ProviderService.getApiKeyConfigKey(targetId);
        if (configKey) {
            plasmoid.configuration[configKey] = secretValue;
        }
    }

    function walletBulkReadCommand(walletName) {
        return WalletService.buildBulkReadCommand(walletName, ProviderService.getApiKeyProviderIds());
    }

    function loadKWalletKeysIfNeeded() {
        if (root.kwalletKeysLoaded)
            return ;

        if (root.kwalletOpenAttempts >= 3) {
            debugLog("[KAI-DEBUG] loadKWalletKeysIfNeeded open attempts limit of 3 exceeded. Skipping KWallet load.");
            return ;
        }
        if (plasmoid.configuration.keyStorageMode === 2) {
            root.kwalletKeysLoaded = true;
            let walletName = (plasmoid.configuration.kwalletName || "").trim() || "kdewallet";
            kwalletStartupDs.connectSource(walletBulkReadCommand(walletName) + " #kwallet-startup-load");
        }
    }

    function performExportChat(filePath) {
        let isMarkdown = filePath.toLowerCase().endsWith(".md") || filePath.toLowerCase().endsWith(".markdown");
        let content = "";
        let sessionTitle = root.currentSessionTitle || "Untitled Session";
        if (isMarkdown) {
            content += "# KDE AI Chat: " + sessionTitle + "\n";
            content += "*Exported on " + root.formatDateTime(Date.now()) + "*\n\n";
            content += "---\n\n";
            for (let i = 0; i < root.messages.length; i++) {
                let m = root.messages[i];
                let dateStrMsg = m.at ? root.formatDateTime(m.at) : (m.time || "");
                if (m.role === "user") {
                    content += "### **User**\n";
                    content += "*Sent on: " + dateStrMsg + "*\n\n";
                    content += m.content + "\n\n";
                    content += "---\n\n";
                } else if (m.role === "assistant") {
                    let modelName = m.model || plasmoid.configuration.model || "Assistant";
                    content += "### **" + modelName + "**\n";
                    content += "*Sent on: " + dateStrMsg + "*\n\n";
                    content += m.content + "\n\n";
                    content += "---\n\n";
                } else if (m.role === "error") {
                    content += "### **System Error**\n";
                    content += "*Occurred on: " + dateStrMsg + "*\n\n";
                    content += "> " + m.content + "\n\n";
                    content += "---\n\n";
                }
            }
        } else {
            content += "==================================================\n";
            content += "KDE AI Chat: " + sessionTitle + "\n";
            content += "Exported on: " + root.formatDateTime(Date.now()) + "\n";
            content += "==================================================\n\n";
            let rightAlignTxt = function rightAlignTxt(text, width) {
                if (!width)
                    width = 80;

                let lines = text.split("\n");
                for (let j = 0; j < lines.length; j++) {
                    let trimmed = lines[j].trim();
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
            for (let i = 0; i < root.messages.length; i++) {
                let m = root.messages[i];
                let dateStrMsg = m.at ? root.formatDateTime(m.at) : (m.time || "");
                if (m.role === "user") {
                    let userHeader = "User (" + dateStrMsg + "):";
                    content += " ".repeat(Math.max(0, 80 - userHeader.length)) + userHeader + "\n";
                    content += rightAlignTxt(m.content, 80) + "\n\n";
                    content += "--------------------------------------------------\n\n";
                } else if (m.role === "assistant") {
                    let modelName = m.model || plasmoid.configuration.model || "Assistant";
                    content += modelName + " (" + dateStrMsg + "):\n";
                    content += m.content + "\n\n";
                    content += "--------------------------------------------------\n\n";
                } else if (m.role === "error") {
                    content += "System Error (" + dateStrMsg + "):\n";
                    content += "ERROR: " + m.content + "\n\n";
                    content += "--------------------------------------------------\n\n";
                }
            }
        }
        let b64Str = base64Encode(content);
        let payload = {
            "filePath": filePath,
            "b64Content": b64Str
        };
        let b64Payload = base64Encode(JSON.stringify(payload));
        let safeFilePath = Sec.sanitizeForShell(filePath);
        let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " export_chat " + Sec.quoteForShell(b64Payload) + " && notify-send -i document-export " + Sec.quoteForShell("KDE AI Chat") + " " + Sec.quoteForShell("Chat session successfully exported to " + safeFilePath);
        fileReaderDs.connectSource(cmd + " #export-chat-save");
    }

    function removeLastErrorMessages() {
        let copy = root.messages.slice();
        while (copy.length > 0) {
            let lastRole = copy[copy.length - 1].role;
            let lastContent = copy[copy.length - 1].content || "";
            if (lastRole === "error" || (lastRole === "assistant" && lastContent.indexOf("Attempting to start") !== -1))
                copy.pop();
            else
                break;
        }
        root.messages = copy;
        saveCurrentSessionState(true);
    }

    function retryLastFailedMessage() {
        let lastUserIdx = -1;
        for (let i = root.messages.length - 1; i >= 0; i--) {
            if (root.messages[i].role === "user" || root.messages[i].role === "queued") {
                lastUserIdx = i;
                break;
            }
        }
        if (lastUserIdx >= 0) {
            root.loading = true;
            sendMessageByIndex(lastUserIdx);
        }
    }

    function resetOpenCodeIdleKillTimer() {
        if (root.openCodeMode && plasmoid.configuration.autoStartOpenCodeServer && root.configOpenCodeAutoKill) {
            let mins = root.configOpenCodeAutoKillMinutes || 5;
            openCodeIdleKillTimer.interval = mins * 60000;
            openCodeIdleKillTimer.restart();
        } else {
            openCodeIdleKillTimer.stop();
        }
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
            loadKWalletKeysIfNeeded();
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
            loadKWalletKeysIfNeeded();
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
        if (!root.openCodeMode)
            loadKWalletKeysIfNeeded();

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
            schedulerDs.connectSource("sh -lc '" + startCmd.replace(/'/g, "'\\''") + "' #sched-startup");
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
        let text = textValue || "";
        // Sanitize first so the entire single-quote payload is harmless
        // even if the surrounding wrapper is re-evaluated. The wrapper
        // now uses a single-quoted string around the inner command so
        // the outer `sh -lc` cannot perform command substitution on
        // the value.
        let safe = Sec.sanitizeForShell(text);
        let cmd = "sh -lc 'if command -v wl-copy >/dev/null 2>&1; then printf %s " + Sec.quoteForShell(safe) + " | wl-copy; " + "elif command -v xclip >/dev/null 2>&1; then printf %s " + Sec.quoteForShell(safe) + " | xclip -selection clipboard; " + "else echo \"Clipboard tool missing: install wl-clipboard or xclip\" 1>&2; exit 1; fi'";
        clipboardDs.connectSource(cmd + " #clipboard-copy");
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
        interval: 33
        repeat: false
        onTriggered: root.flushStreamingBuffer()
    }
    function flushStreamingBuffer() {
        if (!_streamingDirty)
            return;
        _streamingDirty = false;
        let text = _pendingStreamingText;
        let label = _pendingStreamingModelLabel;
        _pendingStreamingText = "";
        _pendingStreamingModelLabel = "";
        // Apply the coalesced update directly (bypasses re-buffering).
        if (root.openCodeAssistantMessageIndex < 0) {
            let ts = Date.now();
            root.messages = root.messages.concat([{
                "role": "assistant",
                "content": text,
                "time": nowTime(ts),
                "at": ts,
                "model": label || "OpenCode"
            }]);
            root.openCodeAssistantMessageIndex = root.messages.length - 1;
            root.streamingResponse = true;
            if (!root.userScrolledUp)
                Qt.callLater(scrollToBottom);
            return;
        }
        let copy = root.messages.slice();
        let item = Object.assign({}, copy[root.openCodeAssistantMessageIndex]);
        let existing = item.content || "";
        if (text.indexOf(existing) === 0)
            item.content = text;
        else if (existing.indexOf(text) === 0)
            item.content = existing;
        else
            item.content = existing + text;
        item.at = Date.now();
        item.time = nowTime(item.at);
        item.model = label || item.model || "OpenCode";
        root.streamingResponse = (item.content || "") !== "";
        copy[root.openCodeAssistantMessageIndex] = item;
        root.messages = copy;
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom);
    }

    Timer {
        id: openCodeIdleKillTimer

        interval: 300000 // 5 minutes
        repeat: false
        onTriggered: {
            if (root.openCodeMode && plasmoid.configuration.autoStartOpenCodeServer && root.configOpenCodeAutoKill) {
                let stopCmd = (plasmoid.configuration.openCodeStopCommand || "pkill -f opencode >/dev/null 2>&1 && echo ok").trim();
                // User-editable stop command — see note above.
                opencodeServerDs.connectSource("sh -lc '" + stopCmd.replace(/'/g, "'\\''") + "' #autokill-opencode");
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
            schedulerDs.connectSource("sh -lc " + Sec.quoteForShell(cmd) + " #sched-poll-" + Date.now());
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
            // User-editable start command — see note above.
            opencodeServerDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #autostart-opencode");
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
                let lines = stdout.split(/?\n/);
                let openFailed = false;
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line.indexOf("__KAI_BULK__:OPEN_FAILED") === 0) {
                        openFailed = true;
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
                    debugLog("[KAI-DEBUG] KWallet open failed on startup (attempt " + root.kwalletOpenAttempts + " of 3)");
                } else {
                    root.kwalletOpenAttempts = 0;
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

    fullRepresentation: Item {
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
                        debugLog("[KDE AIChat] Gear button clicked! Opening chatSettingsDialog...");
                        chatSettingsDialog.open();
                        debugLog("[KDE AIChat] chatSettingsDialog state: visible=" + chatSettingsDialog.visible + ", x=" + chatSettingsDialog.x + ", y=" + chatSettingsDialog.y + ", width=" + chatSettingsDialog.width + ", height=" + chatSettingsDialog.height + ", parent=" + chatSettingsDialog.parent);
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
                        root.messages = [];
                        root.editingMessageIndex = -1;
                        root.editingDraft = "";
                        root.clearCurrentOpenCodeSessionIfNeeded();
                        root.saveCurrentSessionState(true);
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
                                let idx = sessionIndexById(root.currentSessionId);
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
                                            let idx = sessionIndexById(root.currentSessionId);
                                            if (idx < 0)
                                                return "";

                                            let parentTitle = root.sessions[idx].parentSessionTitle || "Original Chat";
                                            if (parentTitle.indexOf("[FK] ") === 0)
                                                parentTitle = parentTitle.substring(5);

                                            let parentId = root.sessions[idx].parentSessionId;
                                            let exists = parentId && sessionIndexById(parentId) >= 0;
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
                                            let idx = sessionIndexById(root.currentSessionId);
                                            if (idx >= 0) {
                                                let parentId = root.sessions[idx].parentSessionId;
                                                if (sessionIndexById(parentId) >= 0) {
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
                                        msgList.positionViewAtIndex(root.searchMatches[0], ListView.Center);
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

                            Connections {
                                function onClearChatInput() {
                                    msgInput.text = "";
                                }

                                target: root
                            }

                            ListView {
                                id: msgList

                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                model: root.messages
                                spacing: Kirigami.Units.largeSpacing
                                clip: true
                                cacheBuffer: 4000
                                Component.onCompleted: root.msgListViewRef = msgList
                                // Track whether user manually scrolled away from bottom
                                onMovementStarted: {
                                    if (!msgList.atYEnd)
                                        root.userScrolledUp = true;

                                }
                                onAtYEndChanged: {
                                    if (msgList.atYEnd)
                                        root.userScrolledUp = false;

                                }
                                onContentYChanged: {
                                    if (!msgList.atYEnd) {
                                        if (msgList.moving || msgList.dragging || verticalScrollBar.pressed || verticalScrollBar.active)
                                            root.userScrolledUp = true;

                                    }
                                }

                                QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                                    id: verticalScrollBar
                                }

                                delegate: Item {
                                    property bool showDayHeader: index === 0 || root.messageDayKeyAt(index) !== root.messageDayKeyAt(index - 1)
                                    property bool isSearchMatch: root.searchBarActive && root.searchQuery.trim() !== "" && modelData.content && modelData.content.toLowerCase().indexOf(root.searchQuery.toLowerCase()) >= 0
                                    property bool isCurrentSearchMatch: isSearchMatch && root.searchMatches[root.currentSearchMatchIndex] === index

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
                                                    text: root.dayDividerLabelForIndex(index)
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
                                                color: {
                                                    if (isCurrentSearchMatch) {
                                                        return Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.25);
                                                    }
                                                    if (isSearchMatch) {
                                                        return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15);
                                                    }
                                                    return modelData.role === "user" ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2) : modelData.role === "queued" ? Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.18) : modelData.role === "error" ? Kirigami.Theme.negativeBackgroundColor : (modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list" || modelData.role === "compact_request") ? Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.12) : Kirigami.Theme.backgroundColor;
                                                }
                                                border.width: {
                                                    if (isCurrentSearchMatch) return 3;
                                                    if (isSearchMatch) return 2;
                                                    return modelData.role === "error" || modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list" || modelData.role === "compact_request" ? 2 : 1;
                                                }
                                                border.color: {
                                                    if (isCurrentSearchMatch) return Kirigami.Theme.focusColor;
                                                    if (isSearchMatch) return Kirigami.Theme.highlightColor;
                                                    return modelData.role === "error" ? Kirigami.Theme.negativeTextColor : (modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list" || modelData.role === "compact_request") ? Kirigami.Theme.focusColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16);
                                                }
                                                anchors.right: modelData.role === "user" || modelData.role === "queued" ? parent.right : undefined
                                                anchors.left: modelData.role === "assistant" || modelData.role === "error" || modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list" || modelData.role === "compact_request" ? parent.left : undefined

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
                                                            text: modelData.role === "user" ? "You" : modelData.role === "queued" ? "You (Queued)" : modelData.role === "error" ? "Error" : modelData.role === "question_request" ? "OpenCode Interactive Question" : modelData.role === "permission_request" ? "OpenCode Security Request" : modelData.role === "schedules_list" ? "Schedules Manager" : modelData.role === "compact_request" ? "Context Compaction Request" : "AI"
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
                                                            text: root.formatMessageTime(modelData, index)
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
                                                        active: root.editingMessageIndex === index && modelData.role !== "error" && modelData.role !== "assistant"
                                                        width: parent.width

                                                        sourceComponent: QQC2.TextArea {
                                                            width: parent ? parent.width : implicitWidth
                                                            text: root.editingDraft
                                                            wrapMode: Text.WordWrap
                                                            onTextChanged: root.editingDraft = text
                                                        }

                                                    }

                                                    // ── Selectable / interactive message body ─────────────────
                                                    MessageContent {
                                                        messageData: modelData
                                                        messageIndex: index
                                                        chatRoot: root
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
                                                                            source: (modelData.content && modelData.content !== "") ? ("data:" + (modelData.mimeType || "image/png") + ";base64," + modelData.content) : ("file://" + modelData.path)
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
                                                            onClicked: root.respondToCompactRequest(index, true)
                                                        }

                                                        PC3.Button {
                                                            visible: modelData.status === "pending"
                                                            text: "Cancel"
                                                            icon.name: "dialog-cancel"
                                                            onClicked: root.respondToCompactRequest(index, false)
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
                                                                                     let b64Payload = base64Encode(JSON.stringify(payload));
                                                                                     let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " delete_schedule " + Sec.quoteForShell(b64Payload);
                                                                                     schedulerDs.connectSource("sh -lc " + Sec.quoteForShell(cmd) + " #sched-delete-" + Date.now());
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
                                                        visible: root.editingMessageIndex === index && modelData.role !== "error"
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
                                                            visible: root.editingMessageIndex !== index && modelData.role !== "error" && modelData.role !== "assistant"
                                                            icon.name: "document-edit"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: modelData.role === "queued" ? "Edit queued message" : "Edit message"
                                                            onClicked: {
                                                                root.editingMessageIndex = index;
                                                                root.editingDraft = modelData.content;
                                                            }
                                                        }

                                                        PC3.ToolButton {
                                                            visible: root.editingMessageIndex === index && modelData.role !== "error" && modelData.role !== "assistant"
                                                            icon.name: "dialog-ok-apply"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: "Apply edit"
                                                            onClicked: root.saveEditedMessage()
                                                        }

                                                        PC3.ToolButton {
                                                            visible: root.editingMessageIndex === index && modelData.role !== "error" && modelData.role !== "assistant"
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
                                                             onClicked: root.forkSession(index)
                                                         }

                                                        PC3.ToolButton {
                                                            icon.name: "edit-delete"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: modelData.role === "queued" ? "Delete queued message" : "Delete message"
                                                            onClicked: root.deleteMessage(index)
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
                                                    source: (modelData.content && modelData.content !== "") ? ("data:" + (modelData.mimeType || "image/png") + ";base64," + modelData.content) : ("file://" + modelData.path)
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

                                    // Dual-stage focus mechanism for Plasma 6
                                    property alias focusTimerRef: focusTimer

                                    width: inputScrollView.width - 16
                                    wrapMode: Text.Wrap
                                    enabled: !root.loading
                                    placeholderText: root.translate("Type message (Enter sends, Shift+Enter newline)")
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
                                        function onExpandedChanged() {
                                            if (root.expanded)
                                                focusTimer.start();

                                        }

                                        target: root
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
                                visible: root.loading
                                icon.name: "process-stop"
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: "Stop current response"
                                Accessible.name: root.translate("Stop response")
                                Accessible.role: Accessible.Button
                                Accessible.description: root.translate("Stop generating the response")
                                onClicked: root.stopStreaming()
                            }

                            PC3.Label {
                                text: {
                                    let chars = root.chatInputText.length;
                                    let tokens = Math.ceil(chars / 4);
                                    return chars + " " + root.translate("characters") + " | ~" + tokens + " " + root.translate("tokens");
                                }
                                font.pointSize: 8
                                opacity: 0.5
                                visible: root.chatInputText.length > 0
                                Layout.alignment: Qt.AlignRight
                                Layout.rightMargin: Kirigami.Units.gridUnit
                            }

                        }

                    }

                }

                Rectangle {
                    radius: 8
                    color: Kirigami.Theme.alternateBackgroundColor

                    SessionSidebar {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        chatRoot: root
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
        standardButtons: QQC2.Dialog.NoButton
        onAboutToShow: {
            let sId = root.currentSessionId;
            debugLog("[KDE AIChat] chatSettingsDialog about to show for session ID: " + sId);
            let overrideVal = getSessionProperty(sId, "contextOverride", false);
            let enabledVal = getSessionProperty(sId, "contextEnabled", true);
            let limitVal = getSessionProperty(sId, "contextLimit", (plasmoid.configuration.globalContextLimit !== undefined && plasmoid.configuration.globalContextLimit !== null ? plasmoid.configuration.globalContextLimit : 1));
            let autoCompactVal = getSessionProperty(sId, "contextAutoCompact", plasmoid.configuration.globalContextAutoCompact || false);
            let compactThresholdVal = getSessionProperty(sId, "contextCompactThreshold", plasmoid.configuration.globalContextCompactThreshold || 10);

            debugLog("[KDE AIChat] Loaded settings: override=" + overrideVal + ", enabled=" + enabledVal + ", limit=" + limitVal + ", autoCompact=" + autoCompactVal + ", compactThreshold=" + compactThresholdVal);

            // Sync controls imperatively to avoid QML binding breakage
            overrideToggle.checked = overrideVal;
            contextEnabledToggle.checked = enabledVal;
            contextLimitSpin.value = limitVal;
            autoCompactToggle.checked = autoCompactVal;
            compactThresholdSpin.value = compactThresholdVal;
        }
        onAccepted: {
            let sId = root.currentSessionId;
            let overrideVal = overrideToggle.checked;
            let enabledVal = contextEnabledToggle.checked;
            let limitVal = contextLimitSpin.value;
            let autoCompactVal = autoCompactToggle.checked;
            let compactThresholdVal = compactThresholdSpin.value;

            debugLog("[KDE AIChat] Saving settings for session ID: " + sId);
            debugLog("[KDE AIChat] Saving values: override=" + overrideVal + ", enabled=" + enabledVal + ", limit=" + limitVal + ", autoCompact=" + autoCompactVal + ", compactThreshold=" + compactThresholdVal);

            setSessionProperty(sId, "contextOverride", overrideVal);
            setSessionProperty(sId, "contextEnabled", enabledVal);
            setSessionProperty(sId, "contextLimit", limitVal);
            setSessionProperty(sId, "contextAutoCompact", autoCompactVal);
            setSessionProperty(sId, "contextCompactThreshold", compactThresholdVal);
        }

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing

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
                            "id": SessionManager.makeScheduleEntryId(),
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
                        let b64Payload = base64Encode(JSON.stringify(payload));
                        let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " add_schedule " + Sec.quoteForShell(b64Payload);
                        schedulerDs.connectSource("sh -lc " + Sec.quoteForShell(cmd) + " #sched-save-" + Date.now());
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
            let b64Payload = base64Encode(JSON.stringify(payload));
            let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " delete_schedule " + Sec.quoteForShell(b64Payload);
            schedulerDs.connectSource("sh -lc " + Sec.quoteForShell(cmd) + " #sched-delete-" + Date.now());
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


}

}
