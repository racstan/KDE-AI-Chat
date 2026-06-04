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

PlasmoidItem {
    // No custom text and no way to read options from here,
    // so prompt user to type something or click an option
    // The option buttons themselves handle single-click submit
    // for non-multiple mode

    id: root

    property var sessions: []
    property string currentSessionId: ""
    property string activeHistoryPath: ""
    property string currentSessionTitle: ""
    property var messages: []
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
        var mode = plasmoid.configuration.appearanceMode || 0;
        if (mode === 1)
            return false;

        if (mode === 2)
            return true;

        return Qt.styleHints.colorScheme === Qt.Dark;
    }

    signal clearChatInput()

    function sessionHasSchedules(sessionId) {
        if (!sessionId)
            return false;

        for (var i = 0; i < root.schedulesList.length; i++) {
            var s = root.schedulesList[i];
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
            var act = root.plasmoidRef.action("configure");
            if (act && typeof act.trigger === "function")
                act.trigger();

        } else if (typeof plasmoid.action === "function") {
            var act2 = plasmoid.action("configure");
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
        var chars = "abcdefghijklmnopqrstuvwxyz0123456789";
        var str = "";
        for (var i = 0; i < 6; i++) {
            str += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return "s-" + str;
    }

    function makeForkSessionId() {
        var chars = "0123456789";
        var str = "";
        for (var i = 0; i < 6; i++) {
            str += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return "fork-" + str;
    }

    function forkSession(messageIndex) {
        if (root.currentSessionId === "")
            return ;

        var idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        var originalSession = root.sessions[idx];
        var forkedMessages = [];
        if (originalSession.messages && messageIndex >= 0 && messageIndex < originalSession.messages.length) {
            for (var i = 0; i <= messageIndex; i++) {
                forkedMessages.push(JSON.parse(JSON.stringify(originalSession.messages[i])));
            }
        }
        var forkId = makeForkSessionId();
        var originalTitle = originalSession.text || "New Chat";
        var cleanTitle = originalTitle.indexOf("[FK] ") === 0 ? originalTitle.substring(5) : originalTitle;
        var forkTitle = "[FK] " + cleanTitle;
        var s = {
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
        var payload = {
            "schedId": schedId,
            "enabled": newEnabled
        };
        var b64Payload = base64Encode(JSON.stringify(payload));
        var cmd = "python3 '" + getHelperPath() + "' toggle_schedule '" + b64Payload + "'";
        schedulerDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #sched-toggle-" + Date.now());
        // Update local schedulesList immediately
        var copy = root.schedulesList.slice();
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].id === schedId) {
                var s = Object.assign({
                }, copy[i]);
                s.enabled = newEnabled;
                if (newEnabled)
                    s.nextRunAt = "";

                copy[i] = s;
            }
        }
        root.schedulesList = copy;
        root.appendSystemMessage(newEnabled ? "▶️ Schedule resumed successfully." : "⏸️ Schedule paused successfully.");
    }

    function injectScheduledMessage(chatId, messageText, notify, schedId, schedName) {
        if (!chatId || !messageText)
            return ;

        // Switch to the correct session
        var idx = sessionIndexById(chatId);
        if (idx < 0) {
            console.warn("injectScheduledMessage: Target session " + chatId + " not found, ignoring schedule execution.");
            return ;
        }
        if (chatId !== root.currentSessionId) {
            executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName);
            return ;
        }
        // Play the custom scheduled execution sound
        var soundCmd = "pw-play /usr/share/sounds/ocean/stereo/service-login.oga || " + "paplay /usr/share/sounds/ocean/stereo/service-login.oga || " + "pw-play /usr/share/sounds/ocean/stereo/window-attention.oga || " + "paplay /usr/share/sounds/ocean/stereo/window-attention.oga || " + "aplay /usr/share/sounds/freedesktop/stereo/bell.oga || " + "canberra-gtk-play -i service-login";
        soundDs.connectSource(soundCmd + " #sched-sound-" + Date.now());
        // Validate provider/model configuration before executing
        var validationError = validateCurrentSendTarget();
        if (validationError !== "") {
            // Push validation error into chat window
            pushErrorMessage(validationError);
            // Display critical desktop notification popup of the configuration failure
            if (notify) {
                var escapedErr = validationError.replace(/'/g, "'\\''");
                var errTitle = "Schedule Failed: " + (schedName || root.currentSessionTitle || "Chat");
                var escapedErrTitle = errTitle.replace(/'/g, "'\\''");
                soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning '" + escapedErrTitle + "' '" + escapedErr + "' #sched-notify-err");
            }
            // Sync the detailed failure back to the scheduler's run history log
            if (schedId) {
                var historyPayload = {
                    "schedId": schedId,
                    "status": validationError
                };
                var b64HistoryPayload = base64Encode(JSON.stringify(historyPayload));
                var cmd = "python3 '" + getHelperPath() + "' update_schedule_history_status '" + b64HistoryPayload + "'";
                soundDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #sched-history-err");
            }
            return ;
        }
        // Append user message
        appendUserMessage(messageText, "user", [], true);
        // Trigger LLM generation
        sendMessageByIndex(root.messages.length - 1);
        // Show a desktop notification
        if (notify) {
            var escapedText = messageText.substring(0, 150).replace(/'/g, "'\\''") + (messageText.length > 150 ? "…" : "");
            var title = "Scheduled: " + (root.currentSessionTitle || "Chat");
            var escapedTitle = title.replace(/'/g, "'\\''");
            soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information '" + escapedTitle + "' '" + escapedText + "' #sched-notify");
        }
    }

    function parseSessions(customRaw) {
        var raw = customRaw !== undefined ? customRaw : (plasmoid.configuration.chatSessionsJson || "[]");
        try {
            var arr = typeof raw === "string" ? JSON.parse(raw) : raw;
            if (Array.isArray(arr)) {
                for (var i = 0; i < arr.length; i++) {
                    if (!arr[i].messages)
                        arr[i].messages = [];

                    if (arr[i].archived === undefined)
                        arr[i].archived = false;

                    if (!arr[i].source)
                        arr[i].source = arr[i].openCodeSessionId ? "opencode" : "provider";

                    if (arr[i].readCount === undefined)
                        arr[i].readCount = arr[i].messages.length;

                    for (var j = 0; j < arr[i].messages.length; j++) {
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
            var idx = sessionIndexById(root.currentSessionId);
            if (idx >= 0) {
                var s = root.sessions[idx];
                var currentMsgsCount = root.messages.length;
                if (s.readCount !== currentMsgsCount) {
                    var updated = root.sessions.slice();
                    var item = Object.assign({
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
            console.log("base64Encode error:", e);
            return "";
        }
    }

    function base64Decode(str) {
        try {
            return decodeURIComponent(escape(Qt.atob(str)));
        } catch (e) {
            console.log("base64Decode error:", e);
            try {
                return Qt.atob(str);
            } catch (err) {
                return "";
            }
        }
    }

    function getHistoryFilePath(customDir) {
        var dir = (customDir || "").trim();
        if (dir === "")
            return "";

        if (dir.indexOf("file://") === 0)
            dir = decodeURIComponent(dir.slice(7));

        var fullPath = dir;
        if (!fullPath.endsWith(".json")) {
            if (fullPath.endsWith("/"))
                fullPath += "kdeaichat_history.json";
            else
                fullPath += "/kdeaichat_history.json";
        }
        return fullPath;
    }

    function migrateHistory(oldPath, newPath) {
        var oldFullPath = getHistoryFilePath(oldPath);
        var newFullPath = getHistoryFilePath(newPath);
        // When switching TO a custom path, always export current in-memory sessions
        // to the new location, then fall back to copying the old file if it exists.
        var currentJson = JSON.stringify(root.sessions);
        var b64Current = base64Encode(currentJson);
        var payload = {
            "oldFullPath": oldFullPath,
            "newFullPath": newFullPath,
            "currentB64": b64Current
        };
        var b64Payload = base64Encode(JSON.stringify(payload));
        var cmd = "python3 '" + getHelperPath() + "' migrate_history '" + b64Payload + "'";
        customStorageDs.connectSource(cmd + " #migrate-history-" + Date.now());
    }

    function persistSessions() {
        var jsonStr = JSON.stringify(root.sessions);
        plasmoid.configuration.chatSessionsJson = jsonStr;
        plasmoid.configuration.lastSessionId = root.currentSessionId;
        var customDir = (plasmoid.configuration.customHistoryPath || "").trim();
        if (customDir !== "") {
            var fullPath = getHistoryFilePath(customDir);
            var b64Str = base64Encode(jsonStr);
            var payload = {
                "fullPath": fullPath,
                "b64Str": b64Str
            };
            var b64Payload = base64Encode(JSON.stringify(payload));
            var writeCmd = "python3 '" + getHelperPath() + "' write_history '" + b64Payload + "'";
            customStorageDs.connectSource(writeCmd + " #custom-history-write-" + Date.now());
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
        var parts = [];
        if (sessionData.value)
            parts.push("ID: " + sessionData.value);

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

    function createSession(switchToNew) {
        var mode = plasmoid.configuration.useOpenCode;
        var s = {
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

        var preferred = plasmoid.configuration.lastSessionId || "";
        var idx = sessionIndexById(preferred);
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
        var idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var s = Object.assign({
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

        saveCurrentSessionState(false);
        var idx = sessionIndexById(sessionId);
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

        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        updated.splice(idx, 1);
        root.sessions = updated;
        if (root.currentSessionId === sessionId) {
            var next = root.sessions[0];
            root.currentSessionId = next.value;
            root.currentSessionTitle = next.text;
            root.messages = next.messages || [];
        }
        cancelSessionRename();
        persistSessions();
        // Clean up schedules associated with this session
        var payload = {
            "sessionId": sessionId
        };
        var b64Payload = base64Encode(JSON.stringify(payload));
        var cmd = "python3 '" + getHelperPath() + "' delete_session_schedules '" + b64Payload + "'";
        schedulerDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #sched-session-delete-" + Date.now());
        // Also update root.schedulesList locally
        var copy = root.schedulesList.filter(function(s) {
            return s.chatId !== sessionId;
        });
        root.schedulesList = copy;
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
        var raw = (plasmoid.configuration.openCodeUrl || "http://127.0.0.1:4096/v1").trim();
        return raw.replace(/\/v1\/?$/, "").replace(/\/$/, "");
    }

    function currentOpenCodeSessionId() {
        var sId = root.currentSessionId;
        var override = getSessionProperty(sId, "contextOverride", false);
        var contextEnabled = override ? getSessionProperty(sId, "contextEnabled", true) : plasmoid.configuration.globalContextEnabled;
        if (!contextEnabled)
            return "";

        var idx = sessionIndexById(sId);
        if (idx < 0)
            return "";

        return root.sessions[idx].openCodeSessionId || "";
    }

    function setCurrentOpenCodeSessionId(remoteSessionId) {
        var idx = sessionIndexById(root.currentSessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var item = Object.assign({
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
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return defaultValue;

        var val = root.sessions[idx][key];
        return val !== undefined ? val : defaultValue;
    }

    function setSessionProperty(sessionId, key, value) {
        var idx = sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var item = Object.assign({
        }, updated[idx]);
        item[key] = value;
        updated[idx] = item;
        root.sessions = updated;
        persistSessions();
    }

    function appendCompactPromptMessage(chatId) {
        var ts = Date.now();
        var msgObj = {
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
        var copy = root.messages.slice();
        if (msgIndex < 0 || msgIndex >= copy.length)
            return;

        var msgObj = Object.assign({}, copy[msgIndex]);
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
        var idx = sessionIndexById(chatId);
        if (idx >= 0) {
            var updated = root.sessions.slice();
            updated[idx].updatedAt = Date.now();
            root.sessions = updated;
        }
        return true;
    }

    function checkAndAutoCompact(sessionId) {
        var sId = sessionId || root.currentSessionId;
        var idx = sessionIndexById(sId);
        if (idx < 0)
            return ;

        var msgs = root.sessions[idx].messages || [];
        var lastUserMsg = null;
        for (var j = msgs.length - 1; j >= 0; j--) {
            if (msgs[j].role === "user" && !msgs[j].isSystem) {
                lastUserMsg = msgs[j];
                break;
            }
        }
        if (lastUserMsg && lastUserMsg.sc)
            return ;

        var override = getSessionProperty(sId, "contextOverride", false);
        var autoCompact = override ? getSessionProperty(sId, "contextAutoCompact", false) : plasmoid.configuration.globalContextAutoCompact;
        if (!autoCompact)
            return ;

        var threshold = override ? getSessionProperty(sId, "contextCompactThreshold", 10) : plasmoid.configuration.globalContextCompactThreshold;
        var compactedCount = getSessionProperty(sId, "compactedMessageCount", 0);

        for (var k = compactedCount; k < msgs.length; k++) {
            if (msgs[k].role === "compact_request")
                return ;
        }

        var uncompactedCleanCount = 0;
        for (var i = compactedCount; i < msgs.length; i++) {
            var role = msgs[i].role;
            if ((role === "user" || role === "assistant") && !msgs[i].isSystem)
                uncompactedCleanCount++;

        }
        if (uncompactedCleanCount > threshold) {
            appendCompactPromptMessage(sId);
        }
    }

    function compactSessionContext(sessionId) {
        var sId = sessionId || root.currentSessionId;
        var idx = sessionIndexById(sId);
        if (idx < 0)
            return ;

        var msgs = root.sessions[idx].messages || [];
        var compactedCount = getSessionProperty(sId, "compactedMessageCount", 0);
        var cleanMsgs = [];
        for (var i = compactedCount; i < msgs.length; i++) {
            var role = msgs[i].role;
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
        var limitCleanIndex = cleanMsgs.length - 2;
        var limitRealIndex = cleanMsgs[limitCleanIndex].index;
        var textToSummarize = "";
        var oldSummary = getSessionProperty(sId, "compactedSummary", "");
        if (oldSummary !== "")
            textToSummarize += "[Previous Summary]:\n" + oldSummary + "\n\n";

        for (var j = 0; j < limitCleanIndex; j++) {
            var prefix = cleanMsgs[j].role === "user" ? "User: " : "AI: ";
            textToSummarize += prefix + cleanMsgs[j].content + "\n\n";
        }
        appendSystemMessageToSession(sId, "Compacting context, please wait...");
        var promptText = "Please write a highly concise summary (max 3-4 sentences) of the following conversation history. Keep it extremely brief and factual, focus on user preferences, details of what was discussed/resolved, and any state that needs to be preserved. This summary will be injected into the system prompt of the next turns to maintain context:\n\n" + textToSummarize;
        sendBackgroundSummarizationRequest(sId, promptText, limitRealIndex + 1);
    }

    function sendBackgroundSummarizationRequest(sId, promptText, count) {
        var provider = "";
        var model = "";
        var apiKey = "";
        var url = "";
        var headers = null;
        var isAnthropic = false;
        if (root.openCodeMode) {
            url = openCodeBaseUrl() + "/v1/chat/completions";
            model = (plasmoid.configuration.openCodeModel || "").trim();
            provider = "opencode";
        } else {
            provider = plasmoid.configuration.provider || "openai";
            var providerCfg = getProviderConfig(provider);
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
        var xhr = new XMLHttpRequest();
        if (isAnthropic) {
            xhr.open("POST", "https://api.anthropic.com/v1/messages", true);
            xhr.setRequestHeader("x-api-key", apiKey);
            xhr.setRequestHeader("anthropic-version", "2023-06-01");
            xhr.setRequestHeader("content-type", "application/json");
        } else {
            var fullUrl = url;
            if (!fullUrl.endsWith("/chat/completions") && !fullUrl.endsWith("/completions"))
                fullUrl = fullUrl.replace(/\/+$/, "") + "/chat/completions";

            xhr.open("POST", fullUrl, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            if (apiKey !== "")
                xhr.setRequestHeader("Authorization", "Bearer " + apiKey);

            if (headers) {
                for (var key in headers) {
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
                    var summaryText = "";
                    var res = JSON.parse(xhr.responseText);
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
                        appendSystemMessageToSession(sId, "⚠️ Context compaction returned an empty response.");
                    }
                } catch (e) {
                    appendSystemMessageToSession(sId, "⚠️ Failed to parse compaction response: " + e.toString());
                }
            } else {
                var errMsg = "HTTP " + xhr.status;
                try {
                    var errObj = JSON.parse(xhr.responseText);
                    if (errObj.error && errObj.error.message)
                        errMsg += ": " + errObj.error.message;

                } catch (e) {
                }
                appendSystemMessageToSession(sId, "⚠️ Context compaction failed: " + errMsg);
            }
        };
        xhr.onerror = function() {
            appendSystemMessageToSession(sId, "⚠️ Network error while compacting context.");
        };
        var payload = {
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
            appendSystemMessageToSession(sId, "⚠️ Failed to send compaction request: " + e.toString());
        }
    }

    function updateAutocomplete() {
        var txt = (root.msgInputRef ? root.msgInputRef.text : "") || "";
        if (txt.startsWith("/")) {
            var search = txt.substring(1).toLowerCase();
            var filtered = [];
            var all = [];
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
            for (var i = 0; i < all.length; i++) {
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
        var incoming = text || "";
        if (incoming === "")
            return ;

        if (modelLabel)
            root.openCodeAssistantModelLabel = modelLabel;

        if (root.openCodeAssistantMessageIndex < 0) {
            var ts = Date.now();
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

            return ;
        }
        var copy = root.messages.slice();
        var item = Object.assign({
        }, copy[root.openCodeAssistantMessageIndex]);
        var existing = item.content || "";
        // OpenCode streams can be cumulative or token-delta; handle both.
        if (incoming.indexOf(existing) === 0)
            item.content = incoming;
        else if (existing.indexOf(incoming) === 0)
            item.content = existing;
        else
            item.content = existing + incoming;
        item.at = Date.now();
        item.time = nowTime(item.at);
        item.model = root.openCodeAssistantModelLabel || item.model || "OpenCode";
        root.streamingResponse = (item.content || "") !== "";
        copy[root.openCodeAssistantMessageIndex] = item;
        root.messages = copy;
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom);

    }

    function finishOpenCodeRequest() {
        root.loading = false;
        root.activeXhr = null;
        root.openCodeActiveSessionId = "";
        root.openCodeAssistantMessageIndex = -1;
        root.openCodeAssistantServerMessageId = "";
        root.openCodeErrorShownForRequest = false;
        root.streamingResponse = false;
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
        var cmd = cmdText.trim().toLowerCase();
        // Strip leading slash or "opencode " prefix
        var bare = cmd.startsWith("/") ? cmd.substring(1) : cmd;
        // Normalise e.g. "/models extra" → bare = "models"
        var verb = bare.split(" ")[0];
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
            var token = "opencode-cli-" + Date.now();
            opencodeTerminalDs.connectSource("opencode --version #" + token);
            return ;
        }
        // ── /session ──────────────────────────────────────────────────────
        if (verb === "session") {
            var sid = currentOpenCodeSessionId();
            var idx = root.sessions.findIndex ? root.sessions.findIndex(function(s) {
                return s.id === root.currentSessionId;
            }) : -1;
            var sessionName = (idx >= 0 && root.sessions[idx]) ? (root.sessions[idx].name || "(unnamed)") : "(unnamed)";
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
        var remoteSessionId = currentOpenCodeSessionId();
        if (!remoteSessionId)
            return ;

        root.loading = true;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", openCodeBaseUrl() + "/session/" + remoteSessionId + "/message", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            root.loading = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    var arr = JSON.parse(xhr.responseText);
                    if (Array.isArray(arr)) {
                        var newMsgs = [];
                        for (var i = 0; i < arr.length; i++) {
                            var item = arr[i] || {
                            };
                            var info = item.info || {
                            };
                            var parts = item.parts || [];
                            var role = info.role || "user";
                            var modelLabel = (info.providerID && info.modelID) ? (info.providerID + "/" + info.modelID) : (info.modelID || "OpenCode");
                            var combinedText = "";
                            var ctx = [];
                            for (var p = 0; p < parts.length; p++) {
                                var part = parts[p] || {
                                };
                                if (part.type === "text") {
                                    combinedText += part.text || part.content || "";
                                } else if (part.type === "tool-invocation") {
                                    var toolName = part.toolName || part.tool || "";
                                    var toolArgs = part.args || part.input || {
                                    };
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
                            // Normalize tokens
                            var normalizedTokens = {
                            };
                            if (item.tokens) {
                                var rawTokens = item.tokens || {
                                };
                                normalizedTokens.input = rawTokens.input !== undefined ? rawTokens.input : (rawTokens.prompt_tokens !== undefined ? rawTokens.prompt_tokens : (rawTokens.input_tokens !== undefined ? rawTokens.input_tokens : undefined));
                                normalizedTokens.output = rawTokens.output !== undefined ? rawTokens.output : (rawTokens.completion_tokens !== undefined ? rawTokens.completion_tokens : (rawTokens.output_tokens !== undefined ? rawTokens.output_tokens : undefined));
                                if (rawTokens.reasoning !== undefined)
                                    normalizedTokens.reasoning = rawTokens.reasoning;

                                if (rawTokens.cache !== undefined)
                                    normalizedTokens.cache = rawTokens.cache;

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
                            var idx = root.currentSessionIndex();
                            if (idx >= 0) {
                                root.messages = newMsgs;
                                root.sessions[idx].messages = newMsgs;
                                saveCurrentSessionState(true);
                                Qt.callLater(scrollToBottom);
                            }
                        }
                    }
                } catch (err) {
                    console.log("Failed to parse synced messages: " + err);
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

        var xhr = new XMLHttpRequest();
        var buffer = "";
        var offset = 0;
        var url = openCodeBaseUrl() + "/event";
        root.openCodeEventXhr = xhr;
        xhr.open("GET", url, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            var delta = xhr.responseText.slice(offset);
            offset = xhr.responseText.length;
            buffer += delta;
            while (true) {
                var split = buffer.indexOf("\n\n");
                if (split < 0)
                    break;

                var block = buffer.slice(0, split);
                buffer = buffer.slice(split + 2);
                var lines = block.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("data:") !== 0)
                        continue;

                    try {
                        var eventObj = JSON.parse(lines[i].slice(5).trim());
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
        var props = eventObj && eventObj.properties ? eventObj.properties : {
        };
        var sessionId = props.sessionID || "";
        if (!sessionId || sessionId !== root.openCodeActiveSessionId)
            return ;

        if (eventObj.type === "message.updated") {
            var info = props.info || {
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
            var part = props.part || {
            };
            if (part.type === "text" && root.openCodeAssistantServerMessageId !== "" && part.messageID === root.openCodeAssistantServerMessageId)
                updateAssistantStreamingContent(part.text || "", "OpenCode");

            // Track tool invocations as context items on the assistant message
            if (part.type === "tool-invocation" && root.openCodeAssistantMessageIndex >= 0) {
                var toolName = part.toolName || part.tool || "";
                var toolArgs = part.args || part.input || {
                };
                var toolState = part.state || "";
                if (toolName !== "") {
                    var copy = root.messages.slice();
                    var item = Object.assign({
                    }, copy[root.openCodeAssistantMessageIndex]);
                    var ctx = item.contextItems || [];
                    // Build a concise description of the tool call
                    var desc = toolName;
                    if (toolArgs.filePath || toolArgs.path || toolArgs.file)
                        desc += ": " + (toolArgs.filePath || toolArgs.path || toolArgs.file);
                    else if (toolArgs.command)
                        desc += ": " + String(toolArgs.command).substring(0, 60);
                    else if (toolArgs.query || toolArgs.pattern)
                        desc += ": " + (toolArgs.query || toolArgs.pattern);
                    // Avoid duplicates
                    var exists = false;
                    for (var ci = 0; ci < ctx.length; ci++) {
                        if (ctx[ci] === desc) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists) {
                        ctx = ctx.concat([desc]);
                        item.contextItems = ctx;
                        copy[root.openCodeAssistantMessageIndex] = item;
                        root.messages = copy;
                    }
                }
            }
        } else if (eventObj.type === "session.error") {
            if (!root.openCodeErrorShownForRequest) {
                root.openCodeErrorShownForRequest = true;
                pushErrorMessage(extractReadableError("OpenCode: ", props.error, "Session error."));
            }
        } else if (eventObj.type === "session.status") {
            var status = props.status || {
            };
            if (status.type === "idle")
                finishOpenCodeRequest();

        } else if (eventObj.type === "session.idle") {
            finishOpenCodeRequest();
        } else if (eventObj.type === "permission.asked") {
            var p = props.permission || {
            };
            var permId = p.id || "";
            if (permId !== "") {
                var tool = p.tool || "";
                var args = p.arguments || {
                };
                var argStr = "";
                try {
                    argStr = typeof args === "string" ? args : JSON.stringify(args, null, 2);
                } catch (e) {
                    argStr = String(args);
                }
                var msg = {
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
            var pr = props.permission || {
            };
            var pId = pr.id || "";
            var response = pr.response || "";
            var copy = root.messages.slice();
            var updated = false;
            for (var i = copy.length - 1; i >= 0; i--) {
                if (copy[i].role === "permission_request" && copy[i].permissionId === pId) {
                    copy[i].status = (response === "allow" ? "allowed" : "denied");
                    updated = true;
                    break;
                }
            }
            if (updated) {
                root.messages = copy;
                saveCurrentSessionState(true);
            }
        } else if (eventObj.type === "session.next.step.ended") {
            var copy = root.messages.slice();
            var updated = false;
            for (var idx = copy.length - 1; idx >= 0; idx--) {
                if (copy[idx].role === "assistant") {
                    var item = Object.assign({
                    }, copy[idx]);
                    var normalizedTokens = {
                    };
                    var rawTokens = props.tokens || {
                    };
                    normalizedTokens.input = rawTokens.input !== undefined ? rawTokens.input : (rawTokens.prompt_tokens !== undefined ? rawTokens.prompt_tokens : (rawTokens.input_tokens !== undefined ? rawTokens.input_tokens : undefined));
                    normalizedTokens.output = rawTokens.output !== undefined ? rawTokens.output : (rawTokens.completion_tokens !== undefined ? rawTokens.completion_tokens : (rawTokens.output_tokens !== undefined ? rawTokens.output_tokens : undefined));
                    if (rawTokens.reasoning !== undefined)
                        normalizedTokens.reasoning = rawTokens.reasoning;

                    if (rawTokens.cache !== undefined)
                        normalizedTokens.cache = rawTokens.cache;

                    item.tokens = normalizedTokens;
                    item.cost = props.cost;
                    copy[idx] = item;
                    updated = true;
                    break;
                }
            }
            if (updated) {
                root.messages = copy;
                saveCurrentSessionState(true);
            }
        } else if (eventObj.type === "question.asked") {
            var requestID = props.requestID || props.id || eventObj.id || "";
            if (requestID !== "") {
                // Parse full structured questions array from OpenCode
                var questions = props.questions || [];
                var qText = "";
                var parsedQuestions = [];
                var allowCustom = true;
                if (questions.length > 0) {
                    // Structured question(s) with options
                    var parts = [];
                    for (var qi = 0; qi < questions.length; qi++) {
                        var qItem = questions[qi];
                        var header = qItem.header || "";
                        var questionText = qItem.question || "";
                        var opts = qItem.options || [];
                        var multiple = qItem.multiple || false;
                        var custom = qItem.custom !== undefined ? qItem.custom : true;
                        if (!custom)
                            allowCustom = false;

                        var partText = "";
                        if (header)
                            partText += "**" + header + "**: ";

                        partText += questionText;
                        if (opts.length > 0) {
                            var optLabels = [];
                            for (var oi = 0; oi < opts.length; oi++) optLabels.push(opts[oi].label || "")
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
                    var q = props.question || {
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
                var alreadyExists = false;
                for (var i = 0; i < root.messages.length; i++) {
                    if (root.messages[i].role === "question_request" && root.messages[i].questionId === requestID) {
                        alreadyExists = true;
                        break;
                    }
                }
                if (!alreadyExists) {
                    var msg = {
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
            var qId = props.requestID || props.id || eventObj.id || "";
            var copy = root.messages.slice();
            var updated = false;
            for (var i = copy.length - 1; i >= 0; i--) {
                if (copy[i].role === "question_request" && copy[i].questionId === qId) {
                    if (copy[i].status === "pending" || copy[i].status === "answering...") {
                        copy[i].status = "answered";
                        updated = true;
                    }
                    break;
                }
            }
            if (updated) {
                root.messages = copy;
                saveCurrentSessionState(true);
            }
        } else if (eventObj.type === "question.rejected" || eventObj.type === "question.cancelled") {
            var qId = props.requestID || props.id || eventObj.id || "";
            var copy = root.messages.slice();
            var updated = false;
            for (var i = copy.length - 1; i >= 0; i--) {
                if (copy[i].role === "question_request" && copy[i].questionId === qId) {
                    if (copy[i].status === "pending" || copy[i].status === "dismissing...") {
                        copy[i].status = "dismissed";
                        updated = true;
                    }
                    break;
                }
            }
            if (updated) {
                root.messages = copy;
                saveCurrentSessionState(true);
            }
        }
    }

    function appendSystemMessageToSession(chatId, text) {
        var ts = Date.now();
        var msgObj = {
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
        var idx = sessionIndexById(chatId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var s = Object.assign({}, updated[idx]);
        var msgs = (s.messages || []).slice();
        var originalLength = msgs.length;
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
        var timerObj = Qt.createQmlObject("import QtQuick; Timer { interval: " + delayMs + "; repeat: false; running: true; }", root, "dynamicRemoveTimer");
        timerObj.triggered.connect(function() {
            removeMessageFromSessionByTimestamp(chatId, timestamp);
            timerObj.destroy();
        });
    }

    function setOpenCodeSessionIdForChatId(chatId, remoteSessionId) {
        var idx = sessionIndexById(chatId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var item = Object.assign({
        }, updated[idx]);
        item.openCodeSessionId = remoteSessionId || "";
        updated[idx] = item;
        root.sessions = updated;
        persistSessions();
    }

    function ensureOpenCodeSessionForChatId(chatId, successCallback, failureCallback) {
        var targetIdx = sessionIndexById(chatId);
        if (targetIdx < 0) {
            failureCallback("Session not found");
            return ;
        }
        var existing = root.sessions[targetIdx].openCodeSessionId || "";
        if (existing !== "") {
            successCallback(existing);
            return ;
        }
        var fail = function fail(msg) {
            if (typeof failureCallback === "function")
                failureCallback(msg);
            else
                pushErrorMessage(msg);
        };
        var xhr = new XMLHttpRequest();
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
                    var obj = JSON.parse(xhr.responseText);
                    var remoteId = obj.id || "";
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
            var sTitle = root.sessions[targetIdx].title || "KDE AI Chat";
            xhr.send(JSON.stringify({
                "title": sTitle
            }));
        } catch (sendError) {
            fail("OpenCode: failed to create session: " + sendError);
        }
    }

    function ensureCurrentOpenCodeSession(successCallback, failureCallback) {
        var existing = currentOpenCodeSessionId();
        if (existing !== "") {
            successCallback(existing);
            return ;
        }
        var fail = function fail(msg) {
            if (typeof failureCallback === "function")
                failureCallback(msg);
            else
                pushErrorMessage(msg);
        };
        var xhr = new XMLHttpRequest();
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
                    var obj = JSON.parse(xhr.responseText);
                    var remoteId = obj.id || "";
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
                var sCbs = root.openCodeStartSuccessCallbacks.slice();
                sCbs.push(successCallback);
                root.openCodeStartSuccessCallbacks = sCbs;
            }
            if (failureCallback) {
                var fCbs = root.openCodeStartFailureCallbacks.slice();
                fCbs.push(failureCallback);
                root.openCodeStartFailureCallbacks = fCbs;
            }
            return;
        }

        root.openCodeStarting = true;
        root.openCodeStartSuccessCallbacks = successCallback ? [successCallback] : [];
        root.openCodeStartFailureCallbacks = failureCallback ? [failureCallback] : [];

        var checkFinished = false;
        var completed = false;
        var resolveSuccess = function() {
            if (completed) return;
            completed = true;
            root.openCodeStarting = false;
            var successCbs = root.openCodeStartSuccessCallbacks;
            root.openCodeStartSuccessCallbacks = [];
            root.openCodeStartFailureCallbacks = [];
            for (var i = 0; i < successCbs.length; i++) {
                successCbs[i]();
            }
        };

        var resolveFailure = function(msg) {
            if (completed) return;
            completed = true;
            root.openCodeStarting = false;
            var failureCbs = root.openCodeStartFailureCallbacks;
            root.openCodeStartSuccessCallbacks = [];
            root.openCodeStartFailureCallbacks = [];
            
            if (failureCbs.length > 0) {
                for (var i = 0; i < failureCbs.length; i++) {
                    failureCbs[i](msg);
                }
            } else {
                if (chatId)
                    appendSystemMessageToSession(chatId, "⚠️ " + msg);
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
                var startCmd = (plasmoid.configuration.openCodeStartCommand || "nohup opencode serve --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 & echo ok").trim();
                opencodeServerDs.connectSource("sh -lc '" + startCmd.replace(/'/g, "'\\''") + "' #ensure-opencode-startup-" + Date.now());
                if (chatId) {
                    var ts1 = appendSystemMessageToSession(chatId, translate("Starting OpenCode server, please wait..."));
                    scheduleMessageRemoval(chatId, ts1, 60000);
                }

                openCodeStartPollTimer.successCb = function() {
                    if (chatId) {
                        var ts2 = appendSystemMessageToSession(chatId, translate("Session restarted."));
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

        var checkUrl = openCodeBaseUrl() + "/config/providers";
        var xhr = new XMLHttpRequest();
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

        var requestFinalized = false;
        ensureOpenCodeServerRunning(root.currentSessionId, function() {
            ensureOpenCodeEventStream();
            root.loading = true;
            root.streamingResponse = false;
            root.openCodeAssistantMessageIndex = -1;
            root.openCodeAssistantServerMessageId = "";
            root.openCodeErrorShownForRequest = false;
            ensureCurrentOpenCodeSession(function(remoteSessionId) {
                var xhr = new XMLHttpRequest();
                var modelId = (plasmoid.configuration.openCodeModel || "").trim();
                var providerId = (plasmoid.configuration.openCodeProvider || "").trim();
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

                        var suffix = xhr.status > 0 ? ("HTTP " + xhr.status) : "transport error";
                        failOpenCodeRequest("OpenCode request failed (" + suffix + ") at " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message.");
                        return ;
                    }
                    try {
                        var obj = JSON.parse(xhr.responseText);
                        if (obj.info && obj.info.id)
                            root.openCodeAssistantServerMessageId = obj.info.id;

                        if (obj.info && obj.info.error && !root.openCodeErrorShownForRequest) {
                            root.openCodeErrorShownForRequest = true;
                            pushErrorMessage(extractReadableError("OpenCode: ", obj.info.error, "Request failed."));
                        }
                        if (obj.parts && obj.parts.length > 0) {
                            var combined = "";
                            for (var i = 0; i < obj.parts.length; i++) {
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
                    var lastMsg = null;
                    for (var mIdx = root.messages.length - 1; mIdx >= 0; mIdx--) {
                        if (root.messages[mIdx].role === "user") {
                            lastMsg = root.messages[mIdx];
                            break;
                        }
                    }
                    if (!lastMsg) {
                        failOpenCodeRequest("No user message found to send.");
                        return ;
                    }
                    var parts = [];
                    if (lastMsg.attachments && lastMsg.attachments.length > 0) {
                        var payload = buildMessageContent(lastMsg.content, lastMsg.attachments, "openai");
                        if (typeof payload === "string") {
                            parts.push({
                                "type": "text",
                                "text": payload
                            });
                        } else {
                            for (var p = 0; p < payload.length; p++) {
                                var item = payload[p];
                                if (item.type === "text") {
                                    parts.push({
                                        "type": "text",
                                        "text": item.text
                                    });
                                } else if (item.type === "image_url") {
                                    var mType = item.image_url.url.split(";")[0].split(":")[1];
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
                            "text": lastMsg.content || ""
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
        // If the last user message was a schedule, show a desktop notification of the execution failure!
        var isSched = false;
        for (var i = root.messages.length - 1; i >= 0; i--) {
            if (root.messages[i].role === "user") {
                if (root.messages[i].sc)
                    isSched = true;

                break;
            }
        }
        if (isSched) {
            var escapedErr = text.replace(/'/g, "'\\''");
            var errTitle = "Schedule Execution Failed";
            var escapedErrTitle = errTitle.replace(/'/g, "'\\''");
            soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning '" + escapedErrTitle + "' '" + escapedErr + "' #sched-execution-notify-err");
        }
    }

    function pushInfoMessage(text) {
        var ts = Date.now();
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
        var ts = Date.now();
        root.messages = root.messages.concat([{
            "role": role || "user",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": role === "queued" ? (++root.queueCounter) : 0,
            "attachments": attachments || [],
            "sc": !!isScheduled
        }]);
        saveCurrentSessionState(true);
    }

    function appendSystemMessage(text) {
        var ts = Date.now();
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
        var res = [];
        for (var i = 0; i < root.schedulesList.length; i++) {
            var s = root.schedulesList[i];
            if (s && s.chatId === sessionId && !s.archived) {
                var isExecuted = false;
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

        var provider = plasmoid.configuration.provider || "openai";
        var providerCfg = getProviderConfig(provider);
        return validateProviderConfig(provider, providerCfg);
    }

    function sendMessageByIndex(index) {
        resetOpenCodeIdleKillTimer();
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
        setCurrentSessionSource(root.openCodeMode ? "opencode" : "provider");
        if (root.openCodeMode) {
            if (text.startsWith("/")) {
                runLocalOpenCodeCommand(text);
                return ;
            }
            doOpenCodeRequest();
            return ;
        }
        var provider = plasmoid.configuration.provider || "openai";
        var providerCfg = getProviderConfig(provider);
        if (providerCfg.type === "anthropic")
            doAnthropicRequest(providerCfg.apiKey, providerCfg.model);
        else
            doOpenAICompatRequest(providerCfg.baseUrl, providerCfg.apiKey, providerCfg.model, providerCfg.headers, providerCfg.model);
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
    }

    function providerDisplayName(providerId) {
        if (providerId === "openai")
            return "OpenAI";

        if (providerId === "anthropic")
            return "Anthropic";

        if (providerId === "groq")
            return "Groq";

        if (providerId === "deepseek")
            return "DeepSeek";

        if (providerId === "minimax")
            return "MiniMax";

        if (providerId === "fireworks")
            return "Fireworks";

        if (providerId === "google")
            return "Google Gemini";

        if (providerId === "openrouter")
            return "OpenRouter";

        if (providerId === "mistral")
            return "Mistral";

        if (providerId === "cloudflare")
            return "Cloudflare";

        if (providerId === "nvidia")
            return "NVIDIA NIM";

        if (providerId === "huggingface")
            return "Hugging Face";

        if (providerId === "xai")
            return "xAI";

        if (providerId === "litellm")
            return "LiteLLM Proxy";

        if (providerId === "lmstudio")
            return "LM Studio";

        if (providerId === "local")
            return "Local";

        return providerId || "Selected provider";
    }

    function validateOpenCodeConfig() {
        var missing = [];
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

        var missing = [];
        var name = providerDisplayName(providerId);
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

        return "";
    }

    function sendMessage() {
        // ──────────────────────────────────────────────────────────────

        try {
            var text = (root.chatInputText || "").trim();
            var attachments = root.attachedFiles || [];
            if (text === "" && attachments.length === 0)
                return ;

            // ── /schedule command ──────────────────────────────────────────
            var lowerText = text.toLowerCase().replace(/^\//, "").trim();
            if (lowerText === "schedule" || lowerText === "schedules" || lowerText === "scheduler" || text.toLowerCase().startsWith("/schedule")) {
                var schedText = "";
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
                    var ts = Date.now();
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
        if (provider === "anthropic")
            return {
            "type": "anthropic",
            "apiKey": (plasmoid.configuration.anthropicApiKey || "").trim(),
            "model": plasmoid.configuration.anthropicModel || "",
            "allowEmptyKey": false
        };

        if (provider === "local")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.localBaseUrl || "http://localhost:11434/v1",
            "apiKey": "",
            "model": plasmoid.configuration.localModel || "",
            "headers": null,
            "allowEmptyKey": true
        };

        if (provider === "ollama")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.ollamaBaseUrl || "http://localhost:11434/v1",
            "apiKey": "",
            "model": plasmoid.configuration.ollamaModel || "",
            "headers": null,
            "allowEmptyKey": true
        };

        if (provider === "litellm")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.litellmBaseUrl || "http://localhost:4000/v1",
            "apiKey": (plasmoid.configuration.litellmApiKey || "").trim(),
            "model": plasmoid.configuration.litellmModel || "",
            "headers": null,
            "allowEmptyKey": true
        };

        if (provider === "lmstudio")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.lmStudioBaseUrl || "http://localhost:1234/v1",
            "apiKey": "",
            "model": plasmoid.configuration.lmStudioModel || "",
            "headers": null,
            "allowEmptyKey": true
        };

        if (provider === "groq")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.groqBaseUrl || "https://api.groq.com/openai/v1",
            "apiKey": (plasmoid.configuration.groqApiKey || "").trim(),
            "model": plasmoid.configuration.groqModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "deepseek")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.deepSeekBaseUrl || "https://api.deepseek.com",
            "apiKey": (plasmoid.configuration.deepSeekApiKey || "").trim(),
            "model": plasmoid.configuration.deepSeekModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "minimax")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.miniMaxBaseUrl || "https://api.minimax.io/v1",
            "apiKey": (plasmoid.configuration.miniMaxApiKey || "").trim(),
            "model": plasmoid.configuration.miniMaxModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "fireworks")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.fireworksBaseUrl || "https://api.fireworks.ai/inference/v1",
            "apiKey": (plasmoid.configuration.fireworksApiKey || "").trim(),
            "model": plasmoid.configuration.fireworksModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "google")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.googleBaseUrl || "https://generativelanguage.googleapis.com/v1beta/openai/",
            "apiKey": (plasmoid.configuration.googleApiKey || "").trim(),
            "model": plasmoid.configuration.googleModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "openrouter") {
            var headers = {
            };
            var referer = plasmoid.configuration.openRouterReferer || "https://github.com/racstan/KDE-AI-Chat";
            var title = plasmoid.configuration.openRouterTitle || "KDE AI Chat";
            headers["HTTP-Referer"] = referer;
            headers["X-Title"] = title;
            return {
                "type": "openai-compat",
                "baseUrl": plasmoid.configuration.openRouterBaseUrl || "https://openrouter.ai/api/v1",
                "apiKey": (plasmoid.configuration.openRouterApiKey || "").trim(),
                "model": plasmoid.configuration.openRouterModel || "",
                "headers": headers,
                "allowEmptyKey": false
            };
        }
        if (provider === "mistral")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.mistralBaseUrl || "https://api.mistral.ai/v1",
            "apiKey": (plasmoid.configuration.mistralApiKey || "").trim(),
            "model": plasmoid.configuration.mistralModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "cloudflare")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.cloudflareBaseUrl || "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1",
            "apiKey": (plasmoid.configuration.cloudflareApiKey || "").trim(),
            "model": plasmoid.configuration.cloudflareModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "nvidia")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.nvidiaBaseUrl || "https://integrate.api.nvidia.com/v1",
            "apiKey": (plasmoid.configuration.nvidiaApiKey || "").trim(),
            "model": plasmoid.configuration.nvidiaModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "huggingface")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.huggingFaceBaseUrl || "https://router.huggingface.co/v1",
            "apiKey": (plasmoid.configuration.huggingFaceApiKey || "").trim(),
            "model": plasmoid.configuration.huggingFaceModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "xai")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.xaiBaseUrl || "https://api.x.ai/v1",
            "apiKey": (plasmoid.configuration.xaiApiKey || "").trim(),
            "model": plasmoid.configuration.xaiModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "qwen")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.qwenBaseUrl || "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
            "apiKey": (plasmoid.configuration.qwenApiKey || "").trim(),
            "model": plasmoid.configuration.qwenModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "moonshot")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.moonshotBaseUrl || "https://api.moonshot.ai/v1",
            "apiKey": (plasmoid.configuration.moonshotApiKey || "").trim(),
            "model": plasmoid.configuration.moonshotModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "mimo")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.mimoBaseUrl || "https://api.xiaomimimo.com/v1",
            "apiKey": (plasmoid.configuration.mimoApiKey || "").trim(),
            "model": plasmoid.configuration.mimoModel || "",
            "headers": null,
            "allowEmptyKey": false
        };

        if (provider === "maritaca")
            return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.maritacaBaseUrl || "https://chat.maritaca.ai/api",
            "apiKey": (plasmoid.configuration.maritacaApiKey || "").trim(),
            "model": plasmoid.configuration.maritacaModel || "sabia-4",
            "headers": null,
            "allowEmptyKey": false
        };

        return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.baseUrl || "https://api.openai.com/v1",
            "apiKey": (plasmoid.configuration.apiKey || "").trim(),
            "model": plasmoid.configuration.model || "",
            "headers": null,
            "allowEmptyKey": false
        };
    }

    function translate(text) {
        return Translations.translate(text, plasmoid.configuration.language);
    }

    function isSessionScheduled(sessionId, messagesList) {
        var msgs = messagesList;
        if (!msgs) {
            var idx = sessionIndexById(sessionId || root.currentSessionId);
            if (idx >= 0)
                msgs = root.sessions[idx].messages || [];
        }
        if (!msgs || msgs.length === 0)
            return false;
        // Search from the end for the last user message
        for (var i = msgs.length - 1; i >= 0; i--) {
            var m = msgs[i];
            if (m.role === "user" && !m.isSystem) {
                return !!m.sc;
            }
        }
        return false;
    }

    function buildEffectiveSystemPrompt(sessionId) {
        var sId = sessionId || root.currentSessionId;
        var base = plasmoid.configuration.systemPrompt || "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.";
        var memoryOn = plasmoid.configuration.memoryEnabled || false;
        var memoryTxt = (plasmoid.configuration.userMemory || "").trim();
        if (memoryOn && memoryTxt !== "")
            base = base + "\n\n--- User Memory ---\n" + memoryTxt + "\n--- End of User Memory ---";

        if (!isSessionScheduled(sId)) {
            var summary = getSessionProperty(sId, "compactedSummary", "");
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
        var sId = sessionId || root.currentSessionId;
        var override = getSessionProperty(sId, "contextOverride", false);
        var contextEnabled = override ? getSessionProperty(sId, "contextEnabled", true) : (plasmoid.configuration.globalContextEnabled !== false);
        var limit = override ? getSessionProperty(sId, "contextLimit", 1) : (plasmoid.configuration.globalContextLimit !== undefined && plasmoid.configuration.globalContextLimit !== null ? plasmoid.configuration.globalContextLimit : 1);
        var isSched = isSessionScheduled(sId, messagesList);
        var compactedCount = isSched ? 0 : getSessionProperty(sId, "compactedMessageCount", 0);
        var clean = [];
        for (var i = 0; i < messagesList.length; i++) {
            var m = messagesList[i];
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
            for (var k = clean.length - 1; k >= 0; k--) {
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
        var sys = buildEffectiveSystemPrompt();
        var arr = [{
            "role": "system",
            "content": sys
        }];
        var window = buildContextWindow(root.messages);
        for (var i = 0; i < window.length; i++) {
            var m = window[i];
            if (m.role === "user" && m.attachments && m.attachments.length > 0)
                arr.push({
                    "role": m.role,
                    "content": buildMessageContent(m.content, m.attachments, "openai")
                });
            else
                arr.push({
                    "role": m.role,
                    "content": m.content
                });
        }
        return arr;
    }

    function buildAnthropicPayload() {
        var arr = [];
        var window = buildContextWindow(root.messages);
        for (var i = 0; i < window.length; i++) {
            var m = window[i];
            if (m.role === "user" && m.attachments && m.attachments.length > 0)
                arr.push({
                    "role": m.role,
                    "content": buildMessageContent(m.content, m.attachments, "anthropic")
                });
            else
                arr.push({
                    "role": m.role,
                    "content": m.content
                });
        }
        return arr;
    }

    function buildOpenAICompatPayloadForMessages(messagesList, chatId) {
        var sys = buildEffectiveSystemPrompt(chatId);
        var arr = [{
            "role": "system",
            "content": sys
        }];
        var window = buildContextWindow(messagesList, chatId);
        for (var i = 0; i < window.length; i++) {
            var m = window[i];
            if (m.role === "user" && m.attachments && m.attachments.length > 0)
                arr.push({
                    "role": m.role,
                    "content": buildMessageContent(m.content, m.attachments, "openai")
                });
            else
                arr.push({
                    "role": m.role,
                    "content": m.content
                });
        }
        return arr;
    }

    function buildAnthropicPayloadForMessages(messagesList, chatId) {
        var arr = [];
        var window = buildContextWindow(messagesList, chatId);
        for (var i = 0; i < window.length; i++) {
            var m = window[i];
            if (m.role === "user" && m.attachments && m.attachments.length > 0)
                arr.push({
                    "role": m.role,
                    "content": buildMessageContent(m.content, m.attachments, "anthropic")
                });
            else
                arr.push({
                    "role": m.role,
                    "content": m.content
                });
        }
        return arr;
    }

    function appendMessageToSession(chatId, msgObj) {
        var idx = sessionIndexById(chatId);
        if (idx < 0)
            return ;

        var updated = root.sessions.slice();
        var s = Object.assign({
        }, updated[idx]);
        var msgs = (s.messages || []).slice();
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
        var errTs = Date.now();
        var errMsgObj = {
            "role": "assistant",
            "content": "⚠️ Schedule failed: " + errorMsg,
            "time": nowTime(errTs),
            "at": errTs,
            "model": ""
        };
        appendMessageToSession(chatId, errMsgObj);
        if (notify) {
            var escapedErr = errorMsg.replace(/'/g, "'\\''");
            var errTitle = "Schedule Failed: " + (schedName || "Chat");
            var escapedErrTitle = errTitle.replace(/'/g, "'\\''");
            soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning '" + escapedErrTitle + "' '" + escapedErr + "' #sched-notify-err");
        }
        if (schedId) {
            var payload = {
                "schedId": schedId,
                "status": errorMsg
            };
            var b64Payload = base64Encode(JSON.stringify(payload));
            var cmd = "python3 '" + getHelperPath() + "' update_schedule_history_status '" + b64Payload + "'";
            soundDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #sched-history-err");
        }
    }

    function doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName) {
        function failBackgroundOpenCodeRequest(message) {
            if (requestFinalized)
                return ;

            requestFinalized = true;
            handleBackgroundError(chatId, message, notify, schedId, schedName);
        }

        var requestFinalized = false;
        ensureOpenCodeServerRunning(chatId, function() {
            ensureOpenCodeSessionForChatId(chatId, function(remoteSessionId) {
                var xhr = new XMLHttpRequest();
                var modelId = (plasmoid.configuration.openCodeModel || "").trim();
                var providerId = (plasmoid.configuration.openCodeProvider || "").trim();
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

                        var suffix = xhr.status > 0 ? ("HTTP " + xhr.status) : "transport error";
                        failBackgroundOpenCodeRequest("OpenCode request failed (" + suffix + ") at " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message.");
                        return ;
                    }
                    try {
                        var obj = JSON.parse(xhr.responseText);
                        var combined = "";
                        if (obj.parts && obj.parts.length > 0) {
                            for (var i = 0; i < obj.parts.length; i++) {
                                if (obj.parts[i].type === "text")
                                    combined += obj.parts[i].text || obj.parts[i].content || "";

                            }
                        }
                        if (obj.info && obj.info.error) {
                            failBackgroundOpenCodeRequest(extractReadableError("OpenCode: ", obj.info.error, "Request failed."));
                            return ;
                        }
                        if (combined !== "") {
                            var doneTs = Date.now();
                            var msgObj = {
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
                                var escapedText = combined.substring(0, 150).replace(/'/g, "'\\''") + (combined.length > 150 ? "…" : "");
                                var title = (schedName || "Scheduled message response ready");
                                var escapedTitle = title.replace(/'/g, "'\\''");
                                soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information '" + escapedTitle + "' '" + escapedText + "' #sched-notify-resp");
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
        var url = (baseUrl || "").replace(/\/$/, "") + "/chat/completions";
        var xhr = new XMLHttpRequest();
        var errorHandled = false;
        var targetIdx = sessionIndexById(chatId);
        if (targetIdx < 0)
            return ;

        var targetSession = root.sessions[targetIdx];
        var messagesList = targetSession.messages || [];
        try {
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            if (apiKey !== "")
                xhr.setRequestHeader("Authorization", "Bearer " + apiKey);

            if (extraHeaders) {
                for (var headerName in extraHeaders) {
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
                var err = "Request to " + url + " failed";
                if (xhr.status)
                    err += " (HTTP " + xhr.status + ")";

                try {
                    var eobj = JSON.parse(xhr.responseText);
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
                var parsed = JSON.parse(xhr.responseText);
                var finalText = (parsed.choices && parsed.choices[0] && parsed.choices[0].message && parsed.choices[0].message.content) || "";
                if (finalText !== "") {
                    var doneTs = Date.now();
                    var msgObj = {
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
                        var escapedText = finalText.substring(0, 150).replace(/'/g, "'\\''") + (finalText.length > 150 ? "…" : "");
                        var title = (schedName || "Scheduled message response ready");
                        var escapedTitle = title.replace(/'/g, "'\\''");
                        soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information '" + escapedTitle + "' '" + escapedText + "' #sched-notify-resp");
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
        var xhr = new XMLHttpRequest();
        var errorHandled = false;
        var targetIdx = sessionIndexById(chatId);
        if (targetIdx < 0)
            return ;

        var targetSession = root.sessions[targetIdx];
        var messagesList = targetSession.messages || [];
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
                    var obj = JSON.parse(xhr.responseText);
                    var text = "";
                    if (obj.content && obj.content.length) {
                        for (var i = 0; i < obj.content.length; i++) {
                            if (obj.content[i].type === "text")
                                text += obj.content[i].text;

                        }
                    }
                    var ts = Date.now();
                    var msgObj = {
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
                        var escapedText = (text || "").substring(0, 150).replace(/'/g, "'\\''") + ((text || "").length > 150 ? "…" : "");
                        var title = (schedName || "Scheduled message response ready");
                        var escapedTitle = title.replace(/'/g, "'\\''");
                        soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information '" + escapedTitle + "' '" + escapedText + "' #sched-notify-resp");
                    }
                } catch (e) {
                    handleBackgroundError(chatId, "Failed to parse Anthropic response", notify, schedId, schedName);
                }
            } else {
                if (errorHandled)
                    return ;

                errorHandled = true;
                var err = "Anthropic HTTP " + xhr.status;
                try {
                    var eobj = JSON.parse(xhr.responseText);
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
        var soundCmd = "pw-play /usr/share/sounds/ocean/stereo/service-login.oga || " + "paplay /usr/share/sounds/ocean/stereo/service-login.oga || " + "pw-play /usr/share/sounds/ocean/stereo/window-attention.oga || " + "paplay /usr/share/sounds/ocean/stereo/window-attention.oga || " + "aplay /usr/share/sounds/freedesktop/stereo/bell.oga || " + "canberra-gtk-play -i service-login";
        soundDs.connectSource(soundCmd + " #sched-sound-" + Date.now());
        var validationError = validateCurrentSendTarget();
        if (validationError !== "") {
            handleBackgroundError(chatId, validationError, notify, schedId, schedName);
            return ;
        }
        var userTs = Date.now();
        var userMsgObj = {
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
            var escapedText = messageText.substring(0, 150).replace(/'/g, "'\\''") + (messageText.length > 150 ? "…" : "");
            var sIdx = sessionIndexById(chatId);
            var sTitle = (sIdx >= 0 && root.sessions[sIdx].title) ? root.sessions[sIdx].title : "Chat";
            var title = "Scheduled: " + sTitle;
            var escapedTitle = title.replace(/'/g, "'\\''");
            soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -i dialog-information '" + escapedTitle + "' '" + escapedText + "' #sched-notify");
        }
        if (root.openCodeMode) {
            doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName);
            return ;
        }
        var provider = plasmoid.configuration.provider || "openai";
        var providerCfg = getProviderConfig(provider);
        if (providerCfg.type === "anthropic")
            doBackgroundAnthropicRequest(chatId, providerCfg.apiKey, providerCfg.model, messageText, notify, schedId, schedName);
        else
            doBackgroundOpenAICompatRequest(chatId, providerCfg.baseUrl, providerCfg.apiKey, providerCfg.model, providerCfg.headers, providerCfg.model, messageText, notify, schedId, schedName);
    }

    function doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel) {
        var url = (baseUrl || "").replace(/\/$/, "") + "/chat/completions";
        var xhr = new XMLHttpRequest();
        var errorHandled = false;
        try {
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            if (apiKey !== "")
                xhr.setRequestHeader("Authorization", "Bearer " + apiKey);

            if (extraHeaders) {
                for (var headerName in extraHeaders) {
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
            if (xhr.status < 200 || xhr.status >= 300) {
                if (errorHandled)
                    return ;

                errorHandled = true;
                var err = "Request to " + url + " failed";
                if (xhr.status)
                    err += " (HTTP " + xhr.status + ")";

                try {
                    var eobj = JSON.parse(xhr.responseText);
                    if (eobj.error) {
                        if (typeof eobj.error === "string") {
                            err += " | " + eobj.error;
                        } else {
                            if (eobj.error.message)
                                err = "API Error (" + xhr.status + "): " + eobj.error.message;

                            if (eobj.error.metadata) {
                                try {
                                    err += " | " + JSON.stringify(eobj.error.metadata);
                                } catch (ex) {
                                    err += " | " + eobj.error.metadata;
                                }
                            }
                        }
                    } else if (eobj.detail)
                        err += " | " + eobj.detail;
                    else if (eobj.message)
                        err += " | " + eobj.message;
                } catch (e2) {
                }
                pushErrorMessage(err);
                processNextQueuedMessage();
                return ;
            }
            try {
                var parsed = JSON.parse(xhr.responseText);
                var finalText = (parsed.choices && parsed.choices[0] && parsed.choices[0].message && parsed.choices[0].message.content) || "";
                if (finalText !== "") {
                    var doneTs = Date.now();
                    var msgObj = {
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
            pushErrorMessage("Could not reach " + url + ". Check the server URL and whether that endpoint accepts API requests.");
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
            pushErrorMessage("Failed to send request: " + sendError);
        }
    }

    function doAnthropicRequest(apiKey, model) {
        if (!apiKey) {
            pushErrorMessage("Anthropic API key missing in settings.");
            processNextQueuedMessage();
            return ;
        }
        var xhr = new XMLHttpRequest();
        var errorHandled = false;
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
            pushErrorMessage("Request timed out after 60 seconds.");
            processNextQueuedMessage();
        };
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            root.loading = false;
            root.activeXhr = null;
            if (xhr.status >= 200 && xhr.status < 300) {
                triggerNotificationSound();
                try {
                    var obj = JSON.parse(xhr.responseText);
                    var text = "";
                    if (obj.content && obj.content.length) {
                        for (var i = 0; i < obj.content.length; i++) {
                            if (obj.content[i].type === "text")
                                text += obj.content[i].text;

                        }
                    }
                    var ts = Date.now();
                    var msgObj = {
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
                var err = "Anthropic HTTP " + xhr.status;
                try {
                    var eobj = JSON.parse(xhr.responseText);
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
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                            copy[i].status = approved ? "allowed" : "denied";
                            break;
                        }
                    }
                    root.messages = copy;
                    saveCurrentSessionState(true);
                } else if (xhr.status === 404 && !isRetry) {
                    sendToUrl(fallbackUrl, true);
                } else {
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                            copy[i].status = "pending";
                            break;
                        }
                    }
                    root.messages = copy;
                    pushErrorMessage("OpenCode: failed to reply to permission (HTTP " + xhr.status + ").");
                }
            };
            xhr.onerror = function() {
                if (!isRetry) {
                    sendToUrl(fallbackUrl, true);
                } else {
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                            copy[i].status = "pending";
                            break;
                        }
                    }
                    root.messages = copy;
                    pushErrorMessage("OpenCode: could not reach permission reply server endpoint.");
                }
            };
            xhr.send(JSON.stringify({
                "response": responseValue
            }));
        }

        var sessionId = root.openCodeActiveSessionId;
        if (!sessionId) {
            var idx = sessionIndexById(root.currentSessionId);
            if (idx >= 0)
                sessionId = root.sessions[idx].openCodeSessionId || "";

        }
        if (!sessionId || !permissionId)
            return ;

        var copy = root.messages.slice();
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                copy[i].status = approved ? "allowing..." : "denying...";
                break;
            }
        }
        root.messages = copy;
        var xhr = new XMLHttpRequest();
        var primaryUrl = openCodeBaseUrl() + "/session/" + sessionId + "/permission/" + permissionId;
        var fallbackUrl = openCodeBaseUrl() + "/session/" + sessionId + "/permissions/" + permissionId;
        var responseValue = approved ? "allow" : "deny";
        sendToUrl(primaryUrl, false);
    }

    // Collect selected options from the question UI and submit the answer
    function submitQuestionAnswer(questionId, questions, customField) {
        // Find the question_request message to access its question data
        var msgIdx = -1;
        for (var i = 0; i < root.messages.length; i++) {
            if (root.messages[i].role === "question_request" && root.messages[i].questionId === questionId) {
                msgIdx = i;
                break;
            }
        }
        if (msgIdx < 0)
            return ;

        var customText = customField ? (customField.text || "").trim() : "";
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
                var copy = root.messages.slice();
                for (var i = 0; i < copy.length; i++) {
                    if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                        copy[i].status = "pending";
                        break;
                    }
                }
                root.messages = copy;
                pushErrorMessage("OpenCode: failed to reply to question endpoint.");
                return ;
            }
            var url = urls[currentUrlIdx];
            currentUrlIdx++;
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                if (xhr.status >= 200 && xhr.status < 300) {
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                            copy[i].status = isReject ? "dismissed" : "answered";
                            copy[i].submittedAnswer = answerValue;
                            break;
                        }
                    }
                    root.messages = copy;
                    saveCurrentSessionState(true);
                } else if (xhr.status === 404) {
                    tryNextUrl();
                } else {
                    var copy = root.messages.slice();
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                            copy[i].status = "pending";
                            break;
                        }
                    }
                    root.messages = copy;
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
                    var answers = [];
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

        var sessionId = root.openCodeActiveSessionId;
        if (!sessionId) {
            var idx = sessionIndexById(root.currentSessionId);
            if (idx >= 0)
                sessionId = root.sessions[idx].openCodeSessionId || "";

        }
        if (!questionId)
            return ;

        var copy = root.messages.slice();
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                copy[i].status = isReject ? "dismissing..." : "answering...";
                break;
            }
        }
        root.messages = copy;
        var xhr = new XMLHttpRequest();
        var action = isReject ? "reject" : "reply";
        var urls = [openCodeBaseUrl() + "/question/" + questionId + "/" + action, openCodeBaseUrl() + "/session/" + sessionId + "/question/" + questionId + "/" + action, openCodeBaseUrl() + "/session/" + sessionId + "/questions/" + questionId + "/" + action];
        var currentUrlIdx = 0;
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
        saveCurrentSessionState(true);
        processNextQueuedMessage();
    }

    function convertMarkdownToHtml(markdown) {
        if (!markdown)
            return "";

        var isDark = root.popupIsDark;
        var codeBg = isDark ? "#2d3139" : "#f0f2f5";
        var codeColor = isDark ? "#abb2bf" : "#383a42";
        var inlineBg = isDark ? "#3e4452" : "#e5e5e5";
        var inlineColor = isDark ? "#e06c75" : "#a626a4";
        var linkColor = isDark ? "#61afef" : "#4078f2";
        var borderColor = isDark ? "#3e4452" : "#d0d4dc";
        var tableBorderColor = isDark ? "#4a5165" : "#c8cdd8";
        var tableHeadBg = isDark ? "#363b48" : "#e8eaf0";
        var tableRowAltBg = isDark ? "rgba(255,255,255,0.03)" : "rgba(0,0,0,0.02)";
        var html = markdown;
        // 1. Escape HTML
        html = html.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        // 2. Extract fenced code blocks (with or without language)
        var codeBlocks = [];
        html = html.replace(/```([a-zA-Z0-9+#\-_]*)\n([\s\S]*?)```/g, function(match, lang, code) {
            var blockIdx = codeBlocks.length;
            var rendered = '<div style="background-color: ' + codeBg + '; color: ' + codeColor + '; font-family: monospace; padding: 10px 12px; margin: 8px 0; border-radius: 6px; border: 1px solid ' + borderColor + '; overflow-x: auto;">' + '<div style="font-size: 0.8em; color: ' + (isDark ? "#5c6370" : "#a0a1a7") + '; margin-bottom: 6px; font-weight: bold; border-bottom: 1px solid ' + borderColor + '; padding-bottom: 4px;">' + (lang ? lang : 'code') + '</div>' + '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; line-height: 1.5;">' + code.replace(/\n$/, '') + '</pre></div>';
            codeBlocks.push(rendered);
            return "%%CB" + blockIdx + "%%";
        });
        html = html.replace(/```([\s\S]*?)```/g, function(match, code) {
            var blockIdx = codeBlocks.length;
            var rendered = '<div style="background-color: ' + codeBg + '; color: ' + codeColor + '; font-family: monospace; padding: 10px 12px; margin: 8px 0; border-radius: 6px; border: 1px solid ' + borderColor + '; overflow-x: auto;">' + '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; line-height: 1.5;">' + code.replace(/\n$/, '') + '</pre></div>';
            codeBlocks.push(rendered);
            return "%%CB" + blockIdx + "%%";
        });
        // 3. Markdown tables  |col|col| with optional alignment row
        html = html.replace(/((?:[ \t]*\|.+\|[ \t]*\n)+)/g, function(block) {
            var rows = block.trim().split("\n");
            if (rows.length < 2)
                return block;

            // Check row 1 is separator (---|---)
            var isSep = /^[\s|:\-]+$/.test(rows[1]);
            var headerRow = rows[0];
            var bodyRows = isSep ? rows.slice(2) : rows.slice(1);
            var parseCells = function parseCells(row) {
                return row.replace(/^\s*\|/, '').replace(/\|\s*$/, '').split("|").map(function(c) {
                    return c.trim();
                });
            };
            var t = '<table style="border-collapse: collapse; width: 100%; margin: 8px 0; font-size: 0.9em;">';
            // Header
            t += '<thead><tr>';
            parseCells(headerRow).forEach(function(cell) {
                t += '<th style="border: 1px solid ' + tableBorderColor + '; padding: 6px 10px; background: ' + tableHeadBg + '; text-align: left; font-weight: bold;">' + cell + '</th>';
            });
            t += '</tr></thead><tbody>';
            // Body rows
            bodyRows.forEach(function(row, ri) {
                if (row.trim() === '' || /^[\s|:\-]+$/.test(row))
                    return ;

                var bg = (ri % 2 === 1) ? ' background: ' + tableRowAltBg + ';' : '';
                t += '<tr>';
                parseCells(row).forEach(function(cell) {
                    t += '<td style="border: 1px solid ' + tableBorderColor + '; padding: 5px 10px;' + bg + '">' + cell + '</td>';
                });
                t += '</tr>';
            });
            t += '</tbody></table>';
            return t;
        });
        // 4. Inline code
        html = html.replace(/`([^`\n]+)`/g, '<code style="background-color: ' + inlineBg + '; color: ' + inlineColor + '; font-family: monospace; padding: 2px 5px; border-radius: 3px; font-size: 0.92em;">$1</code>');
        // 5. Headers
        html = html.replace(/^#### (.*?)$/gm, '<h4 style="margin: 8px 0; font-weight: bold;">$1</h4>');
        html = html.replace(/^### (.*?)$/gm, '<h3 style="margin: 10px 0; font-weight: bold;">$1</h3>');
        html = html.replace(/^## (.*?)$/gm, '<h2 style="margin: 12px 0; font-weight: bold;">$1</h2>');
        html = html.replace(/^# (.*?)$/gm, '<h1 style="margin: 14px 0; font-weight: bold;">$1</h1>');
        // 6. Bold & Italic
        html = html.replace(/\*\*([^\*\n]+)\*\*/g, '<b>$1</b>');
        html = html.replace(/__([^\_\n]+)__/g, '<b>$1</b>');
        html = html.replace(/\*([^\*\n]+)\*/g, '<i>$1</i>');
        html = html.replace(/_([^\_\n]+)_/g, '<i>$1</i>');
        // 7. Links [text](url)
        html = html.replace(/\[([^\]\n]+)\]\(([^)\n]+)\)/g, '<a href="$2" style="color: ' + linkColor + '; text-decoration: underline;">$1</a>');
        // 8. Horizontal rule
        html = html.replace(/^---+$/gm, '<hr style="border: none; border-top: 1px solid ' + borderColor + '; margin: 10px 0;"/>');
        // 9. Blockquote
        html = html.replace(/^&gt;\s?(.*?)$/gm, '<blockquote style="margin: 4px 0 4px 12px; padding: 4px 10px; border-left: 3px solid ' + borderColor + '; opacity: 0.8;">$1</blockquote>');
        // 10. Bullet lists
        html = html.replace(/^\s*[-*+]\s+(.*?)$/gm, '<ul><li>$1</li></ul>');
        html = html.replace(/<\/ul>\s*\n?\s*<ul>/g, '');
        // 11. Numbered lists
        html = html.replace(/^\s*(\d+)\.\s+(.*?)$/gm, '<ol><li value="$1">$2</li></ol>');
        html = html.replace(/<\/ol>\s*\n?\s*<ol>/g, '');
        // 12. Paragraph breaks
        html = html.replace(/\n\n/g, '<br/><br/>');
        html = html.replace(/\n/g, '<br/>');
        // 13. Restore code blocks
        for (var idx = 0; idx < codeBlocks.length; idx++) {
            html = html.replace("%%CB" + idx + "%%", codeBlocks[idx]);
        }
        return html;
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

    function removeAttachedFile(index) {
        var files = root.attachedFiles.slice();
        if (index >= 0 && index < files.length) {
            files.splice(index, 1);
            root.attachedFiles = files;
        }
    }

    function getDocExtractorPath() {
        var urlStr = String(Qt.resolvedUrl("doc_extractor.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);

        return decodeURIComponent(urlStr);
    }

    function getHelperPath() {
        var urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);

        return decodeURIComponent(urlStr);
    }

    function getScriptsPath() {
        var helper = getHelperPath();
        var parts = helper.split("/");
        if (parts.length >= 2) {
            parts.splice(parts.length - 2, 2);
            return parts.join("/") + "/scripts";
        }
        return "";
    }

    function attachFile(fileUrl) {
        var localPath = String(fileUrl);
        if (localPath.indexOf("file://") === 0)
            localPath = localPath.substring(7);

        localPath = decodeURIComponent(localPath);
        var files = root.attachedFiles.slice();
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
        var escapedPath = localPath.replace(/'/g, "'\\''");
        var cmd = "python3 '" + docExtractorPath + "' '" + escapedPath + "'";
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

        var blocks = [];
        var lines = markdown.split("\n");
        var i = 0;
        while (i < lines.length) {
            // Detect fenced code block
            var fenceMatch = lines[i].match(/^```([a-zA-Z0-9+#\-_]*)\s*$/);
            if (fenceMatch) {
                var lang = fenceMatch[1] || "";
                var codeLines = [];
                i++;
                while (i < lines.length && !lines[i].match(/^```\s*$/)) {
                    codeLines.push(lines[i]);
                    i++;
                }
                i++; // skip closing ```
                blocks.push({
                    "type": "code",
                    "content": codeLines.join("\n"),
                    "lang": lang
                });
                continue;
            }
            // Detect markdown table block (consecutive lines with |)
            if (/^\s*\|/.test(lines[i])) {
                var tableLines = [];
                while (i < lines.length && /^\s*\|/.test(lines[i])) {
                    tableLines.push(lines[i]);
                    i++;
                }
                blocks.push({
                    "type": "table",
                    "content": tableLines.join("\n") + "\n",
                    "lang": ""
                });
                continue;
            }
            // Regular text — accumulate until next code/table block
            var textLines = [];
            while (i < lines.length && !lines[i].match(/^```/) && !/^\s*\|/.test(lines[i])) {
                textLines.push(lines[i]);
                i++;
            }
            var textContent = textLines.join("\n").replace(/^\n+/, "").replace(/\n+$/, "");
            if (textContent !== "")
                blocks.push({
                "type": "text",
                "content": textContent,
                "lang": ""
            });

        }
        if (blocks.length === 0)
            blocks.push({
            "type": "text",
            "content": markdown,
            "lang": ""
        });

        return blocks;
    }

    // Convert markdown table to CSV string
    function tableMarkdownToCsv(tableMarkdown) {
        var rows = tableMarkdown.trim().split("\n");
        var csvRows = [];
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            // Skip separator rows (---|---)
            if (/^[\s|:\-]+$/.test(row))
                continue;

            var cells = row.replace(/^\s*\|/, "").replace(/\|\s*$/, "").split("|");
            var csvCells = cells.map(function(c) {
                var v = c.trim();
                if (v.indexOf(",") >= 0 || v.indexOf("\"") >= 0 || v.indexOf("\n") >= 0)
                    v = "\"" + v.replace(/"/g, "\"\"") + "\"";

                return v;
            });
            csvRows.push(csvCells.join(","));
        }
        return csvRows.join("\n");
    }

    function buildMessageContent(text, attachments, apiType) {
        var docs = [];
        var imgs = [];
        for (var i = 0; i < attachments.length; i++) {
            var att = attachments[i];
            if (att.type === "image")
                imgs.push(att);
            else if (att.type === "text")
                docs.push(att);
        }
        var compiledPrompt = "";
        for (var d = 0; d < docs.length; d++) {
            compiledPrompt += "[Attached File: " + docs[d].name + " (" + Math.round((docs[d].size || 0) / 1024) + " KB)]\n";
            compiledPrompt += "--- START OF FILE CONTENT ---\n";
            compiledPrompt += (docs[d].content || "") + "\n";
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
        var cmd = "python3 '" + docExtractorPath + "' --clipboard";
        fileReaderDs.connectSource(cmd);
    }

    function readClipboardText() {
        clipboardHelper.text = "";
        clipboardHelper.paste();
        return clipboardHelper.text;
    }

    function applyKWalletKeyToMemory(targetId, secretValue) {
        if (targetId === "openai")
            plasmoid.configuration.apiKey = secretValue;
        else if (targetId === "anthropic")
            plasmoid.configuration.anthropicApiKey = secretValue;
        else if (targetId === "groq")
            plasmoid.configuration.groqApiKey = secretValue;
        else if (targetId === "deepseek")
            plasmoid.configuration.deepSeekApiKey = secretValue;
        else if (targetId === "minimax")
            plasmoid.configuration.miniMaxApiKey = secretValue;
        else if (targetId === "fireworks")
            plasmoid.configuration.fireworksApiKey = secretValue;
        else if (targetId === "google")
            plasmoid.configuration.googleApiKey = secretValue;
        else if (targetId === "openrouter")
            plasmoid.configuration.openRouterApiKey = secretValue;
        else if (targetId === "mistral")
            plasmoid.configuration.mistralApiKey = secretValue;
        else if (targetId === "cloudflare")
            plasmoid.configuration.cloudflareApiKey = secretValue;
        else if (targetId === "nvidia")
            plasmoid.configuration.nvidiaApiKey = secretValue;
        else if (targetId === "huggingface")
            plasmoid.configuration.huggingFaceApiKey = secretValue;
        else if (targetId === "xai")
            plasmoid.configuration.xaiApiKey = secretValue;
        else if (targetId === "litellm")
            plasmoid.configuration.litellmApiKey = secretValue;
        else if (targetId === "qwen")
            plasmoid.configuration.qwenApiKey = secretValue;
        else if (targetId === "moonshot")
            plasmoid.configuration.moonshotApiKey = secretValue;
        else if (targetId === "mimo")
            plasmoid.configuration.mimoApiKey = secretValue;
        else if (targetId === "maritaca")
            plasmoid.configuration.maritacaApiKey = secretValue;
    }

    function walletBulkReadCommand(walletName) {
        var escapedWallet = (walletName || "").replace(/'/g, "'\\''");
        var escapedFolder = "KaiChat";
        var escapedAppId = "org.kde.plasma.kdeaichat";
        return "sh -lc '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "wallets=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null); " + "if ! printf %s \"$wallets\" | grep -Fxq \"$wallet\"; then printf \"__KAI_BULK__:NO_WALLET\"; exit 0; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_BULK__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; printf \"__KAI_BULK__:NO_FOLDER\"; exit 0; fi; " + "for target in openai anthropic groq deepseek minimax fireworks google openrouter mistral cloudflare nvidia huggingface xai litellm qwen moonshot mimo maritaca; do " + "key=\"kai-chat-${target}-api-key\"; " + "hasEntry=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasEntry \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasEntry\" = true ]; then secret=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.readPassword \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null); printf \"__KAI_SECRET__:%s:%s\\n\" \"$target\" \"$secret\"; fi; " + "done; " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "printf \"__KAI_BULK__:DONE\"'";
    }

    function loadKWalletKeysIfNeeded() {
        if (root.kwalletKeysLoaded)
            return ;

        if (root.kwalletOpenAttempts >= 3) {
            console.log("[KAI-DEBUG] loadKWalletKeysIfNeeded open attempts limit of 3 exceeded. Skipping KWallet load.");
            return ;
        }
        if (plasmoid.configuration.keyStorageMode === 2) {
            root.kwalletKeysLoaded = true;
            var walletName = (plasmoid.configuration.kwalletName || "").trim() || "kdewallet";
            kwalletStartupDs.connectSource(walletBulkReadCommand(walletName) + " #kwallet-startup-load");
        }
    }

    function performExportChat(filePath) {
        var isMarkdown = filePath.toLowerCase().endsWith(".md") || filePath.toLowerCase().endsWith(".markdown");
        var content = "";
        var sessionTitle = root.currentSessionTitle || "Untitled Session";
        if (isMarkdown) {
            content += "# KDE AI Chat: " + sessionTitle + "\n";
            content += "*Exported on " + root.formatDateTime(Date.now()) + "*\n\n";
            content += "---\n\n";
            for (var i = 0; i < root.messages.length; i++) {
                var m = root.messages[i];
                var dateStrMsg = m.at ? root.formatDateTime(m.at) : (m.time || "");
                if (m.role === "user") {
                    content += "### **User**\n";
                    content += "*Sent on: " + dateStrMsg + "*\n\n";
                    content += m.content + "\n\n";
                    content += "---\n\n";
                } else if (m.role === "assistant") {
                    var modelName = m.model || plasmoid.configuration.model || "Assistant";
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
                var dateStrMsg = m.at ? root.formatDateTime(m.at) : (m.time || "");
                if (m.role === "user") {
                    var userHeader = "User (" + dateStrMsg + "):";
                    content += " ".repeat(Math.max(0, 80 - userHeader.length)) + userHeader + "\n";
                    content += rightAlignTxt(m.content, 80) + "\n\n";
                    content += "--------------------------------------------------\n\n";
                } else if (m.role === "assistant") {
                    var modelName = m.model || plasmoid.configuration.model || "Assistant";
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
        var b64Str = base64Encode(content);
        var payload = {
            "filePath": filePath,
            "b64Content": b64Str
        };
        var b64Payload = base64Encode(JSON.stringify(payload));
        var cmd = "python3 '" + getHelperPath() + "' export_chat '" + b64Payload + "' && notify-send -i document-export 'KDE AI Chat' 'Chat session successfully exported to " + filePath.replace(/'/g, "'\\''") + "'";
        fileReaderDs.connectSource(cmd + " #export-chat-save");
    }

    function removeLastErrorMessages() {
        var copy = root.messages.slice();
        while (copy.length > 0) {
            var lastRole = copy[copy.length - 1].role;
            var lastContent = copy[copy.length - 1].content || "";
            if (lastRole === "error" || (lastRole === "assistant" && lastContent.indexOf("Attempting to start") !== -1))
                copy.pop();
            else
                break;
        }
        root.messages = copy;
        saveCurrentSessionState(true);
    }

    function retryLastFailedMessage() {
        var lastUserIdx = -1;
        for (var i = root.messages.length - 1; i >= 0; i--) {
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
            var mins = root.configOpenCodeAutoKillMinutes || 5;
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
        var newPath = configCustomHistoryPath.trim();
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
        resetOpenCodeIdleKillTimer();
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

        var customDir = (plasmoid.configuration.customHistoryPath || "").trim();
        root.activeHistoryPath = customDir;
        if (customDir !== "") {
            var fullPath = getHistoryFilePath(customDir);
            var escapedPath = fullPath.replace(/'/g, "'\\''");
            var readCmd = "python3 -c \"import base64, os; path=os.path.expanduser('" + escapedPath + "'); print(base64.b64encode(open(path, 'rb').read()).decode('utf-8') if os.path.exists(path) else '')\"";
            customStorageDs.connectSource(readCmd + " #custom-history-read-" + Date.now());
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
            var schedulerScriptPath = StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/kdeaichat/kde-ai-scheduler.py";
            var startCmd = "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || " + "(pkill -f kde-ai-scheduler.py; sleep 0.5; " + "python3 '" + schedulerScriptPath + "' &) ; " + "echo SCHED_AUTOSTART_OK";
            schedulerDs.connectSource("sh -lc '" + startCmd.replace(/'/g, "'\\''") + "' #sched-startup");
        }
        checkAndMarkCurrentSessionAsRead();
    }
    onMessagesChanged: {
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
        id: schedulerDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim();
            disconnectSource(sourceName);
            if (sourceName.indexOf("#sched-poll") >= 0)
                root.schedPolling = false;

            if (sourceName.indexOf("#sched-delete") >= 0 || sourceName.indexOf("#sched-save") >= 0 || sourceName.indexOf("#sched-toggle") >= 0)
                schedulerPollTimer.triggered();

            if (stdout !== "") {
                try {
                    var parsed = JSON.parse(stdout);
                    // 1. Sync schedulesList
                    if (parsed && Array.isArray(parsed.schedules))
                        root.schedulesList = parsed.schedules;

                    // 2. Handle pending triggers
                    var triggers = (parsed && parsed.pending) || [];
                    if (Array.isArray(triggers) && triggers.length > 0) {
                        for (var i = 0; i < triggers.length; i++) {
                            var t = triggers[i];
                            if (t && t.message) {
                                var cid = t.chatId || "";
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
                    console.log("[KAI-DEBUG] Failed to parse poll data:", e);
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

    Timer {
        id: openCodeIdleKillTimer

        interval: 300000 // 5 minutes
        repeat: false
        onTriggered: {
            if (root.openCodeMode && plasmoid.configuration.autoStartOpenCodeServer && root.configOpenCodeAutoKill) {
                var stopCmd = (plasmoid.configuration.openCodeStopCommand || "pkill -f opencode >/dev/null 2>&1 && echo ok").trim();
                opencodeServerDs.connectSource("sh -lc '" + stopCmd.replace(/'/g, "'\\''") + "' #autokill-opencode");
                console.log("[KAI-DEBUG] OpenCode server auto-killed due to idleness/chat switch.");
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
            var checkUrl = openCodeBaseUrl() + "/config/providers";
            var xhr = new XMLHttpRequest();
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

        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (root.schedPolling)
                return ;

            root.schedPolling = true;
            var cmd = "python3 '" + getHelperPath() + "' poll_pending_triggers";
            schedulerDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #sched-poll-" + Date.now());
        }
    }

    // Fires after a short delay on startup when autoStartOpenCodeServer is enabled,
    // so session loading completes before we spawn the server process.
    Timer {
        id: autoStartOpenCodeTimer

        interval: 1500
        repeat: false
        onTriggered: {
            var cmd = (plasmoid.configuration.openCodeStartCommand || "nohup opencode serve --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 & echo ok").trim();
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
            var exitCode = data["exit code"];
            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            if (sourceName.indexOf("--clipboard") !== -1) {
                if (exitCode === 0 && stderr.trim() === "") {
                    try {
                        var res = JSON.parse(stdout);
                        if (res.status === "success") {
                            var currentFiles = root.attachedFiles.slice();
                            if (res.mode === "files" && res.files) {
                                for (var f = 0; f < res.files.length; f++) {
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
                            } else if (res.mode === "image" && res.file) {
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
            var matchedIndex = -1;
            var files = root.attachedFiles.slice();
            for (var i = 0; i < files.length; i++) {
                var filePath = files[i].path;
                if (sourceName.indexOf(filePath) !== -1) {
                    matchedIndex = i;
                    break;
                }
            }
            if (matchedIndex === -1) {
                disconnectSource(sourceName);
                return ;
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

    P5Support.DataSource {
        id: customStorageDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var exitCode = data["exit code"];
            var stdout = data["stdout"] || "";
            if (sourceName.indexOf("#custom-history-read-") !== -1) {
                if (exitCode === 0 && stdout.trim() !== "") {
                    try {
                        var jsonStr = base64Decode(stdout.trim());
                        var arr = JSON.parse(jsonStr);
                        if (Array.isArray(arr)) {
                            root.sessions = parseSessions(arr);
                            if (root.sessions.length === 0)
                                createSession(true);

                            var preferred = plasmoid.configuration.lastSessionId || "";
                            var idx = sessionIndexById(preferred);
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
                        console.log("Failed to parse custom history: " + e);
                    }
                }
                // Fallback & Seamless Migration:
                var oldJson = plasmoid.configuration.chatSessionsJson || "";
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
                        var jsonRaw = base64Decode(stdout.trim());
                        var res = JSON.parse(jsonRaw);
                        if (res.status === "ok") {
                            if (res.action === "load" && res.content) {
                                var arrVal = JSON.parse(base64Decode(res.content));
                                if (Array.isArray(arrVal)) {
                                    root.sessions = parseSessions(arrVal);
                                    if (root.sessions.length === 0)
                                        createSession(true);

                                    var pref = plasmoid.configuration.lastSessionId || "";
                                    var idxVal = sessionIndexById(pref);
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
            var stdout = data["stdout"] || "";
            if (sourceName.indexOf("kwallet-startup-load") >= 0) {
                var lines = stdout.split(/?\n/);
                var openFailed = false;
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (line.indexOf("__KAI_BULK__:OPEN_FAILED") === 0) {
                        openFailed = true;
                    } else if (line.indexOf("__KAI_SECRET__:") === 0) {
                        var rest = line.slice("__KAI_SECRET__:".length);
                        var sep = rest.indexOf(":");
                        if (sep > 0) {
                            var targetId = rest.slice(0, sep);
                            var secretValue = rest.slice(sep + 1);
                            applyKWalletKeyToMemory(targetId, secretValue);
                        }
                    }
                }
                if (openFailed) {
                    root.kwalletKeysLoaded = false;
                    root.kwalletOpenAttempts++;
                    console.log("[KAI-DEBUG] KWallet open failed on startup (attempt " + root.kwalletOpenAttempts + " of 3)");
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
            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            var exitCode = data["exit code"];
            if (sourceName.indexOf("opencode-cli-") >= 0) {
                var output = stdout || stderr;
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
            var xhr = new XMLHttpRequest();
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
                pushErrorMessage("OpenCode server failed to start in time. Check logs in /tmp/kdeaichat-opencode.log");
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
                    for (var i = 0; i < drop.urls.length; i++) {
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

                            var rawText = root.currentSessionTitle || "New Chat";
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

                    PC3.Label {
                        visible: !root.historyOnlyMode && root.currentSessionId !== ""
                        text: "ID: " + root.currentSessionId
                        font.pixelSize: 9
                        opacity: 0.55
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        Layout.fillWidth: true
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
                    onClicked: {
                        console.log("[KDE AIChat] Gear button clicked! Opening chatSettingsDialog...");
                        chatSettingsDialog.open();
                        console.log("[KDE AIChat] chatSettingsDialog state: visible=" + chatSettingsDialog.visible + ", x=" + chatSettingsDialog.x + ", y=" + chatSettingsDialog.y + ", width=" + chatSettingsDialog.width + ", height=" + chatSettingsDialog.height + ", parent=" + chatSettingsDialog.parent);
                    }
                }

                PC3.ToolButton {
                    visible: !root.historyOnlyMode
                    icon.name: "go-top"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Jump to first message"
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
                    onClicked: root.jumpOneMessageAbove()
                }

                PC3.ToolButton {
                    visible: !root.historyOnlyMode
                    icon.name: "go-down"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Jump to one message below"
                    onClicked: root.jumpOneMessageBelow()
                }

                PC3.ToolButton {
                    visible: !root.historyOnlyMode
                    icon.name: "go-bottom"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Jump to latest message"
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
                    enabled: !root.loading
                    onClicked: {
                        var cleanTitle = (root.currentSessionTitle || "New Chat").replace(/[\/\?<>\\:\*\|":\s]+/g, "_");
                        var now = new Date();
                        var year = now.getFullYear();
                        var month = String(now.getMonth() + 1).padStart(2, "0");
                        var day = String(now.getDate()).padStart(2, "0");
                        var hour = String(now.getHours()).padStart(2, "0");
                        var min = String(now.getMinutes()).padStart(2, "0");
                        var sec = String(now.getSeconds()).padStart(2, "0");
                        var timestamp = year + "-" + month + "-" + day + "_" + hour + "-" + min + "-" + sec;
                        exportFileDialog.currentFile = "file://" + StandardPaths.writableLocation(StandardPaths.DocumentsLocation) + "/" + cleanTitle + "_" + timestamp + ".md";
                        exportFileDialog.open();
                    }
                }

                PC3.ToolButton {
                    icon.name: "list-add"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: root.translate("New chat")
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
                        var opencodeSessionFile = StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/kdeaichat/.opencode-session";
                        root.ensureCurrentOpenCodeSession(function(sid) {
                            var opencodeCmd = "opencode" + (sid !== "" ? " --session " + sid : "");
                            clipboardHelper.text = opencodeCmd;
                            clipboardHelper.selectAll();
                            clipboardHelper.copy();
                            var termCmd = "echo -n '" + sid + "' > '" + opencodeSessionFile + "' && konsole --workdir '" + getScriptsPath() + "' -e bash ./opencode-terminal.sh";
                            customStorageDs.connectSource(termCmd + " #opencode-terminal-launch");
                        }, function(err) {
                            root.pushErrorMessage(err);
                            clipboardHelper.text = "opencode";
                            clipboardHelper.selectAll();
                            clipboardHelper.copy();
                            var termCmd = "echo -n '' > '" + opencodeSessionFile + "' && konsole --workdir '" + getScriptsPath() + "' -e bash ./opencode-terminal.sh";
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
                                var idx = sessionIndexById(root.currentSessionId);
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
                                            var idx = sessionIndexById(root.currentSessionId);
                                            if (idx < 0)
                                                return "";

                                            var parentTitle = root.sessions[idx].parentSessionTitle || "Original Chat";
                                            if (parentTitle.indexOf("[FK] ") === 0)
                                                parentTitle = parentTitle.substring(5);

                                            var parentId = root.sessions[idx].parentSessionId;
                                            var exists = parentId && sessionIndexById(parentId) >= 0;
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
                                            var idx = sessionIndexById(root.currentSessionId);
                                            if (idx >= 0) {
                                                var parentId = root.sessions[idx].parentSessionId;
                                                if (sessionIndexById(parentId) >= 0) {
                                                    root.switchSession(parentId);
                                                    root.historyOnlyMode = false;
                                                } else {
                                                    root.appendSystemMessage("⚠️ The original chat no longer exists.");
                                                }
                                            }
                                        }
                                    }

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
                                cacheBuffer: 20000
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
                                                color: modelData.role === "user" ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2) : modelData.role === "queued" ? Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.18) : modelData.role === "error" ? Kirigami.Theme.negativeBackgroundColor : (modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list" || modelData.role === "compact_request") ? Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.12) : Kirigami.Theme.backgroundColor
                                                border.width: modelData.role === "error" || modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list" || modelData.role === "compact_request" ? 2 : 1
                                                border.color: modelData.role === "error" ? Kirigami.Theme.negativeTextColor : (modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list" || modelData.role === "compact_request") ? Kirigami.Theme.focusColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
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
                                                    Column {
                                                        visible: root.editingMessageIndex !== index || modelData.role === "error"
                                                        width: parent.width
                                                        spacing: 4

                                                        // For error messages just render plain selectable text
                                                        TextEdit {
                                                            visible: modelData.role === "error"
                                                            width: parent.width
                                                            wrapMode: Text.Wrap
                                                            textFormat: Text.PlainText
                                                            text: modelData.content
                                                            color: Kirigami.Theme.negativeTextColor
                                                            readOnly: true
                                                            selectByMouse: true
                                                            selectByKeyboard: true
                                                            selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                            selectionColor: Kirigami.Theme.highlightColor
                                                            font: Kirigami.Theme.defaultFont
                                                        }

                                                        // For non-error messages render block-by-block
                                                        Repeater {
                                                            visible: modelData.role !== "error" && modelData.role !== "schedules_list"
                                                            model: modelData.role !== "error" && modelData.role !== "schedules_list" ? root.parseMessageBlocks(modelData.content) : []

                                                            delegate: Item {
                                                                required property var modelData

                                                                width: parent.width
                                                                implicitHeight: modelData.type === "code" ? codeLoader.implicitHeight : htmlEdit.implicitHeight

                                                                // ── HTML / Markdown text block ───────────────────────
                                                                TextEdit {
                                                                    id: htmlEdit

                                                                    visible: modelData.type === "text"
                                                                    width: parent.width
                                                                    wrapMode: Text.Wrap
                                                                    textFormat: Text.RichText
                                                                    text: root.convertMarkdownToHtml(modelData.content)
                                                                    color: Kirigami.Theme.textColor
                                                                    readOnly: true
                                                                    selectByMouse: true
                                                                    selectByKeyboard: true
                                                                    selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                                    selectionColor: Kirigami.Theme.highlightColor
                                                                    font: Kirigami.Theme.defaultFont
                                                                    onLinkActivated: function(link) {
                                                                        Qt.openUrlExternally(link);
                                                                    }
                                                                }

                                                                // ── Code block with copy button ───────────────────────
                                                                Item {
                                                                    id: codeLoader

                                                                    visible: modelData.type === "code"
                                                                    width: parent.width
                                                                    implicitHeight: codeContainer.implicitHeight + 2

                                                                    Rectangle {
                                                                        id: codeContainer

                                                                        width: parent.width
                                                                        implicitHeight: codeLangRow.implicitHeight + codeBody.implicitHeight + Kirigami.Units.smallSpacing * 3
                                                                        radius: 6
                                                                        color: root.popupIsDark ? "#2d3139" : "#f0f2f5"
                                                                        border.width: 1
                                                                        border.color: root.popupIsDark ? "#3e4452" : "#d0d4dc"
                                                                        clip: true

                                                                        // Lang label + copy button row
                                                                        Row {
                                                                            id: codeLangRow

                                                                            width: parent.width
                                                                            height: Math.max(langLabel.implicitHeight + Kirigami.Units.smallSpacing, copyCodeBtn.implicitHeight + Kirigami.Units.smallSpacing)
                                                                            spacing: 0

                                                                            PC3.Label {
                                                                                id: langLabel

                                                                                anchors.verticalCenter: parent.verticalCenter
                                                                                leftPadding: Kirigami.Units.smallSpacing + 4
                                                                                text: modelData.lang || "code"
                                                                                font.pointSize: 8
                                                                                font.bold: true
                                                                                color: root.popupIsDark ? "#5c6370" : "#a0a1a7"
                                                                                width: parent.width - copyCodeBtn.width - Kirigami.Units.smallSpacing
                                                                            }

                                                                            PC3.ToolButton {
                                                                                id: copyCodeBtn

                                                                                anchors.verticalCenter: parent.verticalCenter
                                                                                icon.name: "edit-copy"
                                                                                display: PC3.AbstractButton.IconOnly
                                                                                flat: true
                                                                                QQC2.ToolTip.visible: hovered
                                                                                QQC2.ToolTip.text: "Copy code"
                                                                                onClicked: {
                                                                                    clipboardHelper.text = modelData.content;
                                                                                    clipboardHelper.selectAll();
                                                                                    clipboardHelper.copy();
                                                                                }
                                                                            }

                                                                        }

                                                                        // Thin divider
                                                                        Rectangle {
                                                                            y: codeLangRow.height
                                                                            width: parent.width
                                                                            height: 1
                                                                            color: root.popupIsDark ? "#3e4452" : "#d0d4dc"
                                                                        }

                                                                        // Code text
                                                                        TextEdit {
                                                                            id: codeBody

                                                                            y: codeLangRow.height + 1
                                                                            width: parent.width
                                                                            leftPadding: Kirigami.Units.smallSpacing + 4
                                                                            rightPadding: Kirigami.Units.smallSpacing + 4
                                                                            topPadding: Kirigami.Units.smallSpacing
                                                                            bottomPadding: Kirigami.Units.smallSpacing
                                                                            wrapMode: Text.Wrap
                                                                            textFormat: Text.PlainText
                                                                            text: modelData.content
                                                                            color: root.popupIsDark ? "#abb2bf" : "#383a42"
                                                                            font.family: "monospace"
                                                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
                                                                            readOnly: true
                                                                            selectByMouse: true
                                                                            selectByKeyboard: true
                                                                            selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                                            selectionColor: Kirigami.Theme.highlightColor
                                                                        }

                                                                    }

                                                                }

                                                                // ── Markdown table with CSV export button ─────────────
                                                                Item {
                                                                    visible: modelData.type === "table"
                                                                    width: parent.width
                                                                    implicitHeight: tableOuterCol.implicitHeight

                                                                    Column {
                                                                        id: tableOuterCol

                                                                        width: parent.width
                                                                        spacing: 2

                                                                        // Export button row
                                                                        Row {
                                                                            width: parent.width
                                                                            layoutDirection: Qt.RightToLeft

                                                                            PC3.ToolButton {
                                                                                icon.name: "document-export"
                                                                                display: PC3.AbstractButton.IconOnly
                                                                                flat: true
                                                                                QQC2.ToolTip.visible: hovered
                                                                                QQC2.ToolTip.text: "Export table as CSV"
                                                                                onClicked: {
                                                                                    var csv = root.tableMarkdownToCsv(modelData.content);
                                                                                    var ts = new Date().getTime();
                                                                                    var path = "/tmp/kdeaichat-table-" + ts + ".csv";
                                                                                    var escaped = path.replace(/'/g, "'\\''");
                                                                                    clipboardHelper.text = csv;
                                                                                    clipboardHelper.selectAll();
                                                                                    clipboardHelper.copy();
                                                                                    customStorageDs.connectSource("bash -c \"printf '%s' '" + csv.replace(/'/g, "'\\''") + "' > '" + escaped + "' && xdg-open '" + escaped + "'\" #csv-export-" + ts);
                                                                                }
                                                                            }

                                                                        }

                                                                        // Table rendered as HTML
                                                                        TextEdit {
                                                                            width: parent.width
                                                                            wrapMode: Text.Wrap
                                                                            textFormat: Text.RichText
                                                                            text: root.convertMarkdownToHtml(modelData.content)
                                                                            color: Kirigami.Theme.textColor
                                                                            readOnly: true
                                                                            selectByMouse: true
                                                                            selectByKeyboard: true
                                                                            selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                                            selectionColor: Kirigami.Theme.highlightColor
                                                                            font: Kirigami.Theme.defaultFont
                                                                        }

                                                                    }

                                                                }

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
                                                        visible: modelData.attachments && modelData.attachments.length > 0
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
                                                                            source: "file://" + modelData.path
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
                                                                    onClicked: Qt.openUrlExternally("file://" + modelData.path)
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
                                                                                    var schedId = modelData.id;
                                                                                    var payload = {
                                                                                        "schedId": schedId
                                                                                    };
                                                                                    var b64Payload = base64Encode(JSON.stringify(payload));
                                                                                    var cmd = "python3 '" + getHelperPath() + "' delete_schedule '" + b64Payload + "'";
                                                                                    schedulerDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #sched-delete-" + Date.now());
                                                                                    // Remove immediately from UI to be responsive!
                                                                                    var copy = root.schedulesList.slice();
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
                                                    source: "file://" + modelData.path
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
                                onClicked: fileDialog.open()
                            }

                            PC3.ToolButton {
                                icon.name: "edit-paste"
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                                enabled: !root.loading
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: "Paste file or text from clipboard"
                                onClicked: {
                                    root.checkClipboardForAttachments();
                                    var txt = root.readClipboardText();
                                    if (txt && txt.trim() !== "") {
                                        var curPos = msgInput.cursorPosition;
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
                                                var selected = root.filteredCommands[root.autocompleteSelectedIndex];
                                                if (selected) {
                                                    msgInput.text = selected.name;
                                                    root.chatInputText = selected.name;
                                                    root.sendMessage();
                                                }
                                                root.autocompleteActive = false;
                                                if (false) {
                                                }
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
                                onClicked: root.sendMessage()
                            }

                            PC3.ToolButton {
                                visible: root.loading
                                icon.name: "process-stop"
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: "Stop current response"
                                onClicked: root.stopStreaming()
                            }

                            PC3.Label {
                                text: {
                                    var chars = root.chatInputText.length;
                                    var tokens = Math.ceil(chars / 4);
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

                    ListView {
                        id: historyList

                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        model: root.sessions
                        spacing: Kirigami.Units.smallSpacing
                        clip: true
                        cacheBuffer: 5000

                        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                        }

                        delegate: Rectangle {
                            required property var modelData

                            width: historyList.width
                            height: historyCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                            radius: 8
                            opacity: modelData.archived ? 0.72 : 1
                            color: root.historySessionTint(modelData)

                            Column {
                                id: historyCol

                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing / 2

                                Row {
                                    width: parent.width
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    Rectangle {
                                        id: modeBadge

                                        visible: modelData.source === "opencode"
                                        width: modeBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 2
                                        height: modeBadgeText.implicitHeight + Kirigami.Units.smallSpacing
                                        radius: 999
                                        color: Qt.rgba(0.2, 0.48, 0.92, 0.18)

                                        PC3.Label {
                                            id: modeBadgeText

                                            anchors.centerIn: parent
                                            text: "OC"
                                            font.bold: true
                                            color: Qt.rgba(0.12, 0.35, 0.78, 1)
                                        }

                                    }

                                    Rectangle {
                                        id: schedBadge

                                        visible: root.sessionHasSchedules(modelData.value)
                                        width: schedBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 2
                                        height: schedBadgeText.implicitHeight + Kirigami.Units.smallSpacing
                                        radius: 999
                                        color: Qt.rgba(0.92, 0.48, 0.2, 0.18)

                                        PC3.Label {
                                            id: schedBadgeText

                                            anchors.centerIn: parent
                                            text: "SC"
                                            font.bold: true
                                            color: Qt.rgba(0.78, 0.35, 0.12, 1)
                                        }

                                    }

                                    Rectangle {
                                        id: forkBadge

                                        visible: modelData.value && modelData.value.indexOf("fork-") === 0
                                        width: forkBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 2
                                        height: forkBadgeText.implicitHeight + Kirigami.Units.smallSpacing
                                        radius: 999
                                        color: Qt.rgba(0.48, 0.2, 0.92, 0.18)

                                        PC3.Label {
                                            id: forkBadgeText

                                            anchors.centerIn: parent
                                            text: "FK"
                                            font.bold: true
                                            color: Qt.rgba(0.35, 0.12, 0.78, 1)
                                        }

                                    }

                                    QQC2.TextField {
                                        visible: root.editingSessionId === modelData.value
                                        width: parent.width - saveRename.width - archiveChat.width - removeChat.width - (modeBadge.visible ? modeBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - (schedBadge.visible ? schedBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - (forkBadge.visible ? forkBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - (countBadge.visible ? countBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - Kirigami.Units.smallSpacing * 4
                                        text: root.editingSessionDraft
                                        onTextChanged: root.editingSessionDraft = text
                                        onAccepted: root.saveSessionRename(modelData.value)
                                    }

                                    PC3.Label {
                                        id: sessionTitleLabel

                                        visible: root.editingSessionId !== modelData.value
                                        width: parent.width - saveRename.width - archiveChat.width - removeChat.width - (modeBadge.visible ? modeBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - (schedBadge.visible ? schedBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - (forkBadge.visible ? forkBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - (countBadge.visible ? countBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - Kirigami.Units.smallSpacing * 4
                                        text: {
                                            var rawText = modelData.text || "New Chat";
                                            if (rawText.indexOf("[FK] ") === 0)
                                                rawText = rawText.substring(5);

                                            return root.translate(rawText);
                                        }
                                        font.bold: modelData.value === root.currentSessionId
                                        color: root.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.switchSession(modelData.value);
                                                root.historyOnlyMode = false;
                                            }
                                        }

                                    }

                                    Rectangle {
                                        id: countBadge

                                        property int totalCount: (modelData.messages || []).length
                                        property int readCount: modelData.readCount !== undefined ? modelData.readCount : totalCount
                                        property int unreadCount: Math.max(0, totalCount - readCount)

                                        visible: unreadCount > 0
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

                                    PC3.ToolButton {
                                        id: saveRename

                                        icon.name: root.editingSessionId === modelData.value ? "dialog-ok-apply" : "document-edit"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: root.editingSessionId === modelData.value ? "Save title" : "Rename chat"
                                        onClicked: {
                                            if (root.editingSessionId === modelData.value)
                                                root.saveSessionRename(modelData.value);
                                            else
                                                root.startSessionRename(modelData.value);
                                        }
                                    }

                                    PC3.ToolButton {
                                        id: archiveChat

                                        icon.name: modelData.archived ? "archive-remove" : "archive-insert"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: modelData.archived ? "Unarchive chat" : "Archive chat"
                                        onClicked: root.setSessionArchived(modelData.value, !modelData.archived)
                                    }

                                    PC3.ToolButton {
                                        id: removeChat

                                        icon.name: root.editingSessionId === modelData.value ? "dialog-cancel" : "edit-delete"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: root.editingSessionId === modelData.value ? "Cancel rename" : "Delete chat"
                                        onClicked: {
                                            if (root.editingSessionId === modelData.value)
                                                root.cancelSessionRename();
                                            else
                                                root.deleteSession(modelData.value);
                                        }
                                    }

                                }

                                PC3.Label {
                                    opacity: root.popupIsDark ? 1 : 0.7
                                    color: root.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                                    text: root.sessionSubtitle(modelData)
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
                    var dx = mouse.x - startX;
                    var dy = mouse.y - startY;
                    var newW = Math.max(500, startW + dx);
                    var newH = Math.max(620, startH + dy);
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
                        var ctx = getContext("2d");
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
            var sId = root.currentSessionId;
            console.log("[KDE AIChat] chatSettingsDialog about to show for session ID: " + sId);
            var overrideVal = getSessionProperty(sId, "contextOverride", false);
            var enabledVal = getSessionProperty(sId, "contextEnabled", true);
            var limitVal = getSessionProperty(sId, "contextLimit", (plasmoid.configuration.globalContextLimit !== undefined && plasmoid.configuration.globalContextLimit !== null ? plasmoid.configuration.globalContextLimit : 1));
            var autoCompactVal = getSessionProperty(sId, "contextAutoCompact", plasmoid.configuration.globalContextAutoCompact || false);
            var compactThresholdVal = getSessionProperty(sId, "contextCompactThreshold", plasmoid.configuration.globalContextCompactThreshold || 10);

            console.log("[KDE AIChat] Loaded settings: override=" + overrideVal + ", enabled=" + enabledVal + ", limit=" + limitVal + ", autoCompact=" + autoCompactVal + ", compactThreshold=" + compactThresholdVal);

            // Sync controls imperatively to avoid QML binding breakage
            overrideToggle.checked = overrideVal;
            contextEnabledToggle.checked = enabledVal;
            contextLimitSpin.value = limitVal;
            autoCompactToggle.checked = autoCompactVal;
            compactThresholdSpin.value = compactThresholdVal;
        }
        onAccepted: {
            var sId = root.currentSessionId;
            var overrideVal = overrideToggle.checked;
            var enabledVal = contextEnabledToggle.checked;
            var limitVal = contextLimitSpin.value;
            var autoCompactVal = autoCompactToggle.checked;
            var compactThresholdVal = compactThresholdSpin.value;

            console.log("[KDE AIChat] Saving settings for session ID: " + sId);
            console.log("[KDE AIChat] Saving values: override=" + overrideVal + ", enabled=" + enabledVal + ", limit=" + limitVal + ", autoCompact=" + autoCompactVal + ", compactThreshold=" + compactThresholdVal);

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
            var t = schedType, n = schedEvery;
            var tp = schedTime.split(":"), hr = parseInt(tp[0]) || 9, mn = parseInt(tp[1]) || 0;
            if (t === "minutes")
                return "*/" + n + " * * * *";

            if (t === "hours")
                return "0 */" + n + " * * *";

            if (t === "days")
                return (n === 1 ? mn + " " + hr + " * * *" : mn + " " + hr + " */" + n + " * *");

            if (t === "weeks") {
                var ds = schedDays.length > 0 ? schedDays.slice().sort().join(",") : "1";
                return mn + " " + hr + " * * " + ds;
            }
            return (n === 1 ? mn + " " + hr + " " + schedDayOfMonth + " * *" : mn + " " + hr + " " + schedDayOfMonth + " */" + n + " *");
        }

        function humanText() {
            var t = schedType, n = schedEvery;
            var tp = schedTime.split(":"), hr = parseInt(tp[0]) || 9, mn = parseInt(tp[1]) || 0;
            var ap = hr >= 12 ? "PM" : "AM", h12 = hr % 12 || 12, ms = mn < 10 ? "0" + mn : "" + mn;
            var ts = h12 + ":" + ms + " " + ap;
            if (t === "minutes")
                return "Every " + (n === 1 ? "minute" : n + " minutes");

            if (t === "hours")
                return "Every " + (n === 1 ? "hour" : n + " hours");

            if (t === "days")
                return "Every " + (n === 1 ? "day" : n + " days") + " at " + ts;

            if (t === "weeks") {
                var dn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                return "Every " + (n === 1 ? "week" : n + " weeks") + " on " + schedDays.map(function(x) {
                    return dn[x];
                }).join(", ") + " at " + ts;
            }
            var sfx = schedDayOfMonth === 1 ? "st" : schedDayOfMonth === 2 ? "nd" : schedDayOfMonth === 3 ? "rd" : "th";
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
                            var t = scheduleCommandDialog.schedType, n = scheduleCommandDialog.schedEvery;
                            var m = {
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
                            var h2 = parseInt(scheduleCommandDialog.schedTime.split(":")[0]) || 9;
                            return (h2 % 12) || 12;
                        }
                        textFromValue: function(v) {
                            return (v < 10 ? "0" : "") + v;
                        }
                        onValueChanged: {
                            var parts = scheduleCommandDialog.schedTime.split(":");
                            var curH = parseInt(parts[0]) || 0;
                            var m2 = parseInt(parts[1]) || 0;
                            var isPm = curH >= 12;
                            var targetH = value;
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
                            var parts = scheduleCommandDialog.schedTime.split(":");
                            var h2 = parseInt(parts[0]) || 9;
                            scheduleCommandDialog.schedTime = (h2 < 10 ? "0" : "") + h2 + ":" + (value < 10 ? "0" : "") + value;
                        }
                    }

                    QQC2.Button {
                        text: (parseInt(scheduleCommandDialog.schedTime.split(":")[0]) >= 12 ? "PM" : "AM")
                        font.bold: true
                        onClicked: {
                            var parts = scheduleCommandDialog.schedTime.split(":");
                            var curH = parseInt(parts[0]) || 0;
                            var m2 = parseInt(parts[1]) || 0;
                            var targetH = curH;
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
                                    var ds2 = scheduleCommandDialog.schedDays.slice(), pos = ds2.indexOf(index);
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
                        var hr2 = scheduleCommandDialog.humanText();
                        var msg = cmdMessage.text.trim();
                        var entry = {
                            "id": "s-" + Date.now() + "-" + Math.floor(Math.random() * 100000),
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
                        var payload = {
                            "entry": entry
                        };
                        var b64Payload = base64Encode(JSON.stringify(payload));
                        var cmd = "python3 '" + getHelperPath() + "' add_schedule '" + b64Payload + "'";
                        schedulerDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #sched-save-" + Date.now());
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
            var res = [];
            for (var i = 0; i < root.schedulesList.length; i++) {
                var s = root.schedulesList[i];
                if (s && s.chatId === chatScheduleManagerDialog.chatId)
                    res.push(s);

            }
            return res;
        }

        function deleteSchedule(schedId) {
            var payload = {
                "schedId": schedId
            };
            var b64Payload = base64Encode(JSON.stringify(payload));
            var cmd = "python3 '" + getHelperPath() + "' delete_schedule '" + b64Payload + "'";
            schedulerDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #sched-delete-" + Date.now());
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
