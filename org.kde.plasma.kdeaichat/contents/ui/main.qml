import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid
import "translations.js" as Translations
import "ProviderData.js" as ProviderData

PlasmoidItem {
    // No custom text and no way to read options from here,
    // so prompt user to type something or click an option
    // The option buttons themselves handle single-click submit
    // for non-multiple mode

    id: root

    property var sessions: []
    property string currentSessionId: ""
    property string currentSessionTitle: ""
    property var messages: []
    property var attachedFiles: []
    property bool historyOnlyMode: false
    property bool loading: false
    property bool connectionTimedOut: false
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
    property var plasmoidRef: plasmoid
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

    MarkdownRenderer {
        id: markdownRenderer
        isDark: root.popupIsDark
    }

    Timer {
        id: connectionTimeoutTimer
        interval: 45000
        running: root.loading && !root.streamingResponse
        repeat: false
        onTriggered: {
            if (root.loading && !root.streamingResponse)
                root.connectionTimedOut = true;
        }
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

    // ── /schedule command handler ──────────────────────────────────────────────
    function handleScheduleCommand(messageText) {
        scheduleCommandDialog.prefillMessage = messageText;
        scheduleCommandDialog.chatId = root.currentSessionId;
        scheduleCommandDialog.chatName = root.currentSessionTitle || "Current chat";
        scheduleCommandDialog.open();
    }

    function toggleScheduleEnabled(schedId, newEnabled) {
        var py = "import json, os; p=os.path.expanduser('~/.local/share/kdeaichat/schedules.json'); " + "data=json.load(open(p)) if os.path.exists(p) else {'version':1,'schedules':[]}; " + "if isinstance(data, list): data={'version':1,'schedules':data}; " + "for s in data.get('schedules', []): " + "    if s.get('id') == '" + schedId + "': s['enabled'] = " + (newEnabled ? "True" : "False") + "; " + "json.dump(data, open(p,'w'), indent=2)";
        schedulerDs.connectSource("sh -lc 'python3 -c \"" + py + "\" && pkill -HUP -f kde-ai-scheduler.py' #sched-toggle-" + Date.now());
        // Update local schedulesList immediately
        var copy = root.schedulesList.slice();
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].id === schedId) {
                var s = Object.assign({
                }, copy[i]);
                s.enabled = newEnabled;
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
        if (chatId !== root.currentSessionId)
            switchSession(chatId);

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
                var historyPy = "import json, os; " +
                    "p = os.path.expanduser('~/.local/share/kdeaichat/schedules.json'); " +
                    "if os.path.exists(p): " +
                    "  try: " +
                    "    data = json.load(open(p)); " +
                    "    history = data.setdefault('history', []); " +
                    "    for entry in reversed(history): " +
                    "      if entry.get('scheduleId') == '" + schedId + "': " +
                    "        entry['status'] = '" + validationError.replace(/'/g, "\\'") + "'; " +
                    "        break; " +
                    "    json.dump(data, open(p, 'w'), indent=2); " +
                    "  except Exception: pass";
                soundDs.connectSource("python3 -c \"" + historyPy + "\" #sched-history-err");
            }
            return ;
        }

        // Append user message
        appendUserMessage(messageText, "user", []);
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

    function parseSessions() {
        var raw = plasmoid.configuration.chatSessionsJson || "[]";
        try {
            var arr = JSON.parse(raw);
            if (Array.isArray(arr)) {
                for (var i = 0; i < arr.length; i++) {
                    if (!arr[i].messages)
                        arr[i].messages = [];

                    if (arr[i].archived === undefined)
                        arr[i].archived = false;

                    if (!arr[i].source)
                        arr[i].source = arr[i].openCodeSessionId ? "opencode" : "provider";

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

    function persistSessions() {
        var jsonStr = JSON.stringify(root.sessions);
        plasmoid.configuration.chatSessionsJson = jsonStr;
        plasmoid.configuration.lastSessionId = root.currentSessionId;
        var customDir = (plasmoid.configuration.customHistoryPath || "").trim();
        if (customDir !== "") {
            var fullPath = customDir;
            if (!fullPath.endsWith(".json")) {
                if (fullPath.endsWith("/"))
                    fullPath += "kdeaichat_history.json";
                else
                    fullPath += "/kdeaichat_history.json";
            }
            var b64Str = Qt.btoa(jsonStr);
            var escapedPath = fullPath.replace(/'/g, "'\\''");
            var writeCmd = "python3 -c \"import base64, os; path=os.path.expanduser('" + escapedPath + "'); folder=os.path.dirname(path); os.makedirs(folder, exist_ok=True); f=open(path, 'w', encoding='utf-8'); f.write(base64.b64decode('" + b64Str + "').decode('utf-8')); f.close()\"";
            customStorageDs.connectSource(writeCmd);
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
        var idx = sessionIndexById(root.currentSessionId);
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
        root.connectionTimedOut = false;
        root.activeXhr = null;
        root.openCodeActiveSessionId = "";
        root.openCodeAssistantMessageIndex = -1;
        root.openCodeAssistantServerMessageId = "";
        root.openCodeErrorShownForRequest = false;
        root.streamingResponse = false;
        saveCurrentSessionState(true);
        triggerNotificationSound();
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
                    Qt.callLater(ensureOpenCodeEventStream);

            }
        };
        xhr.onerror = function() {
            root.openCodeEventXhr = null;
        };
        try {
            xhr.send();
        } catch (streamError) {
            root.openCodeEventXhr = null;
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

    function ensureCurrentOpenCodeSession(successCallback, failureCallback) {
        var existing = currentOpenCodeSessionId();
        if (existing !== "") {
            successCallback(existing);
            return ;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("POST", openCodeBaseUrl() + "/session", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status >= 200 && xhr.status < 300) {
                triggerNotificationSound();
                try {
                    var obj = JSON.parse(xhr.responseText);
                    var remoteId = obj.id || "";
                    if (remoteId === "") {
                        failureCallback("OpenCode: server created a session without an id.");
                        return ;
                    }
                    setCurrentOpenCodeSessionId(remoteId);
                    successCallback(remoteId);
                } catch (parseError) {
                    failureCallback("OpenCode: could not parse session creation response.");
                }
            } else {
                failureCallback("OpenCode: failed to create a server session (HTTP " + xhr.status + ").");
            }
        };
        xhr.onerror = function() {
            failureCallback("OpenCode: could not reach " + openCodeBaseUrl() + "/session. Check that the server is still running.");
        };
        try {
            xhr.send(JSON.stringify({
                "title": root.currentSessionTitle || "KDE AI Chat"
            }));
        } catch (sendError) {
            failureCallback("OpenCode: failed to create session: " + sendError);
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

        ensureOpenCodeEventStream();
        root.loading = true;
        root.connectionTimedOut = false;
        root.streamingResponse = false;
        root.openCodeAssistantMessageIndex = -1;
        root.openCodeAssistantServerMessageId = "";
        root.openCodeErrorShownForRequest = false;
        ensureCurrentOpenCodeSession(function(remoteSessionId) {
            var xhr = new XMLHttpRequest();
            var modelId = (plasmoid.configuration.openCodeModel || "").trim();
            var providerId = (plasmoid.configuration.openCodeProvider || "").trim();
            var requestFinalized = false;
            root.activeXhr = xhr;
            root.openCodeActiveSessionId = remoteSessionId;
            xhr.open("POST", openCodeBaseUrl() + "/session/" + remoteSessionId + "/message", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                if (requestFinalized)
                    return ;

                if (xhr.status < 200 || xhr.status >= 300) {
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
    }

    function pushInfoMessage(text) {
        var ts = Date.now();
        root.messages = root.messages.concat([{
            "role": "assistant",
            "content": text,
            "time": nowTime(ts),
            "at": ts,
            "model": "OpenCode"
        }]);
        scrollToBottom();
        saveCurrentSessionState(true);
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

    function appendSystemMessage(text) {
        var ts = Date.now();
        root.messages = root.messages.concat([{
            "role": "assistant",
            "content": text,
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

    function getSchedulesForSession(sessionId) {
        var res = [];
        for (var i = 0; i < root.schedulesList.length; i++) {
            var s = root.schedulesList[i];
            if (s && s.chatId === sessionId && !s.archived)
                res.push(s);

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
        return ProviderData.displayName(providerId);
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
        try {
            // ──────────────────────────────────────────────────────────────

            var text = (root.chatInputText || "").trim();
            var attachments = root.attachedFiles || [];
            if (text === "" && attachments.length === 0)
                return ;

            // ── /schedule command ──────────────────────────────────────────
            if (text.toLowerCase().startsWith("/schedule")) {
                var schedText = text.slice("/schedule".length).trim();
                root.attachedFiles = [];
                root.chatInputText = "";
                root.clearChatInput();
                // 1. Append the user message "/schedule" or "/schedule <msg>"
                appendUserMessage(text, "user", []);
                if (schedText !== "") {
                    // Open dialog prefilled with message
                    root.handleScheduleCommand(schedText);
                } else {
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
        return ProviderData.buildRuntimeConfig(provider, plasmoid.configuration);
    }

    function translate(text) {
        return Translations.translate(text, plasmoid.configuration.language);
    }

    function buildEffectiveSystemPrompt() {
        var base = plasmoid.configuration.systemPrompt || "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.";
        var memoryOn = plasmoid.configuration.memoryEnabled || false;
        var memoryTxt = (plasmoid.configuration.userMemory || "").trim();
        if (memoryOn && memoryTxt !== "")
            base = base + "\n\n--- User Memory ---\n" + memoryTxt + "\n--- End of User Memory ---";

        return base;
    }

    function buildOpenAICompatPayload() {
        var sys = buildEffectiveSystemPrompt();
        var arr = [{
            "role": "system",
            "content": sys
        }];
        for (var i = 0; i < root.messages.length; i++) {
            var m = root.messages[i];
            if (m.role === "user" || m.role === "assistant") {
                if (m.role === "user" && m.attachments && m.attachments.length > 0) {
                    var payloadContent = buildMessageContent(m.content, m.attachments, "openai");
                    arr.push({
                        "role": m.role,
                        "content": payloadContent
                    });
                } else {
                    arr.push({
                        "role": m.role,
                        "content": m.content
                    });
                }
            }
        }
        return arr;
    }

    function buildAnthropicPayload() {
        var arr = [];
        for (var i = 0; i < root.messages.length; i++) {
            var m = root.messages[i];
            if (m.role === "user" || m.role === "assistant") {
                if (m.role === "user" && m.attachments && m.attachments.length > 0) {
                    var payloadContent = buildMessageContent(m.content, m.attachments, "anthropic");
                    arr.push({
                        "role": m.role,
                        "content": payloadContent
                    });
                } else {
                    arr.push({
                        "role": m.role,
                        "content": m.content
                    });
                }
            }
        }
        return arr;
    }

    function doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel) {
        var url = (baseUrl || "").replace(/\/$/, "") + "/chat/completions";
        var xhr = new XMLHttpRequest();
        var errorHandled = false;
        try {
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            if (apiKey !== "") {
                var safeKey = apiKey.substring(0, Math.min(8, apiKey.length)) + "... (" + apiKey.length + " chars)";
                console.log("DEBUG: Sending request to " + url + " with auth key starting with: " + safeKey);
                xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
            } else {
                console.log("DEBUG: Sending request to " + url + " without Authorization header (empty key)");
            }
            if (extraHeaders) {
                for (var headerName in extraHeaders) {
                    if (Object.prototype.hasOwnProperty.call(extraHeaders, headerName) && extraHeaders[headerName])
                        xhr.setRequestHeader(headerName, extraHeaders[headerName]);

                }
            }
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
            var idx = findSessionIndex(root.currentSessionId);
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
            var idx = findSessionIndex(root.currentSessionId);
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
        root.connectionTimedOut = false;
        saveCurrentSessionState(true);
        processNextQueuedMessage();
    }

    function convertMarkdownToHtml(markdown) {
        return markdownRenderer.toHtml(markdown);
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
        return markdownRenderer.parseBlocks(markdown);
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
        var keyName = ProviderData.apiKeyConfigName(targetId);
        if (keyName)
            plasmoid.configuration[keyName] = secretValue;
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
        var b64Str = Qt.btoa(content);
        var pythonCode = "import base64; f = open('" + filePath.replace(/'/g, "'\\''") + "', 'w', encoding='utf-8'); f.write(base64.b64decode('" + b64Str + "').decode('utf-8')); f.close()";
        var cmd = "python3 -c \"" + pythonCode + "\" && notify-send -i document-export 'KDE AI Chat' 'Chat session successfully exported to " + filePath.replace(/'/g, "'\\''") + "'";
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

    Plasmoid.title: plasmoid.configuration.appDisplayName || "KDE AI Chat"
    preferredRepresentation: compactRepresentation
    onOpenCodeModeChanged: {
        if (!openCodeMode)
            loadKWalletKeysIfNeeded();

    }
    onExpandedChanged: {
        if (expanded)
            root.focusInput();

    }
    onHistoryOnlyModeChanged: {
        if (!historyOnlyMode)
            root.focusInput();

    }
    Component.onCompleted: {
        root.openCodeMode = plasmoid.configuration.useOpenCode;
        if (!root.openCodeMode)
            loadKWalletKeysIfNeeded();

        var customDir = (plasmoid.configuration.customHistoryPath || "").trim();
        if (customDir !== "") {
            var fullPath = customDir;
            if (!fullPath.endsWith(".json")) {
                if (fullPath.endsWith("/"))
                    fullPath += "kdeaichat_history.json";
                else
                    fullPath += "/kdeaichat_history.json";
            }
            var escapedPath = fullPath.replace(/'/g, "'\\''");
            var readCmd = "python3 -c \"import base64, os; path=os.path.expanduser('" + escapedPath + "'); print(base64.b64encode(open(path, 'rb').read()).decode('utf-8') if os.path.exists(path) else '')\"";
            customStorageDs.connectSource(readCmd);
        } else {
            loadSessions();
        }
        // Auto-start OpenCode server if the feature is enabled
        if (root.openCodeMode && plasmoid.configuration.autoStartOpenCodeServer)
            autoStartOpenCodeTimer.start();

        // Auto-start scheduler if the autoStart is enabled in settings
        if (plasmoid.configuration.schedulerAutoStart) {
            plasmoid.configuration.schedulerEnabled = true;
            var startCmd = "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || " + "(pkill -f kde-ai-scheduler.py; sleep 0.5; " + "python3 ~/.local/share/kdeaichat/kde-ai-scheduler.py &) ; " + "echo SCHED_AUTOSTART_OK";
            schedulerDs.connectSource("sh -lc '" + startCmd.replace(/'/g, "'\\''") + "' #sched-startup");
        }
    }
    onMessagesChanged: {
        if (!root.historyOnlyMode && !root.userScrolledUp)
            Qt.callLater(scrollToBottom);

    }

    Connections {
        function onUseOpenCodeChanged() {
            if (root.messages.length === 0) {
                root.openCodeMode = plasmoid.configuration.useOpenCode;
                setCurrentSessionSource(root.openCodeMode ? "opencode" : "provider");
            }
        }

        function onKeyStorageModeChanged() {
            if (plasmoid.configuration.keyStorageMode === 2) {
                root.kwalletKeysLoaded = false;
                root.kwalletOpenAttempts = 0;
                loadKWalletKeysIfNeeded();
            }
        }

        target: plasmoid.configuration
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
                                // Double check if this schedule was deleted, paused, or archived in the meantime
                                var activeSched = null;
                                for (var k = 0; k < root.schedulesList.length; k++) {
                                    if (root.schedulesList[k] && root.schedulesList[k].id === t.id) {
                                        activeSched = root.schedulesList[k];
                                        break;
                                    }
                                }
                                if (activeSched) {
                                    if (activeSched.enabled === false || activeSched.archived) {
                                        console.log("[KAI-DEBUG] Skipping trigger for paused/archived schedule:", t.id);
                                        continue;
                                    }
                                } else {
                                    console.log("[KAI-DEBUG] Skipping trigger for deleted schedule:", t.id);
                                    continue;
                                }

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
        id: schedulerPollTimer

        interval: 4000
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: {
            var py = "import os, json; " + "d = os.path.expanduser('~/.local/share/kdeaichat/pending'); " + "res = []; " + "if os.path.exists(d): " + "  for f in os.listdir(d): " + "    if f.endswith('.json'): " + "      p = os.path.join(d, f); " + "      try: " + "        res.append(json.load(open(p))); " + "        os.remove(p); " + "      except Exception: pass; " + "ps = os.path.expanduser('~/.local/share/kdeaichat/schedules.json'); " + "scheds = []; " + "if os.path.exists(ps): " + "  try: " + "    s_data = json.load(open(ps)); " + "    scheds = s_data.get('schedules', []) if isinstance(s_data, dict) else s_data; " + "  except Exception: pass; " + "print(json.dumps({'pending': res, 'schedules': scheds}))";
            schedulerDs.connectSource("python3 -c \"" + py + "\" #sched-poll-" + Date.now());
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
            if (sourceName.indexOf("open(path, 'rb').read()") !== -1) {
                if (exitCode === 0 && stdout.trim() !== "") {
                    try {
                        var jsonStr = Qt.atob(stdout.trim());
                        var arr = JSON.parse(jsonStr);
                        if (Array.isArray(arr)) {
                            root.sessions = arr;
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
        width: Math.min(parent ? parent.width * 0.92 : 600, 540)
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
                        var jsonEntry = JSON.stringify({
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
                        });
                        var b64 = Qt.btoa(encodeURIComponent(jsonEntry));
                        var py = "import base64,json,os,urllib.parse; p=os.path.expanduser('~/.local/share/kdeaichat/schedules.json'); " +
                                 "data=json.load(open(p)) if os.path.exists(p) else {'version':1,'schedules':[]}; " +
                                 "if isinstance(data, list): data={'version':1,'schedules':data}; " +
                                 "entry_str = urllib.parse.unquote(base64.b64decode('" + b64 + "').decode('utf-8')); " +
                                 "data.setdefault('schedules', []).append(json.loads(entry_str)); " +
                                 "json.dump(data,open(p,'w'),indent=2)";
                        schedulerDs.connectSource("sh -lc 'python3 -c \"" + py + "\" && pkill -HUP -f kde-ai-scheduler.py' #sched-save-" + Date.now());
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
            var py = "import json, os; p=os.path.expanduser('~/.local/share/kdeaichat/schedules.json'); " + "data=json.load(open(p)) if os.path.exists(p) else {'version':1,'schedules':[]}; " + "if isinstance(data, list): data={'version':1,'schedules':data}; " + "data['schedules'] = [s for s in data.get('schedules', []) if s.get('id') != '" + schedId + "']; " + "json.dump(data, open(p,'w'), indent=2)";
            schedulerDs.connectSource("sh -lc 'python3 -c \"" + py + "\" && pkill -HUP -f kde-ai-scheduler.py' #sched-delete-" + Date.now());
            root.appendSystemMessage("🗑️ Schedule deleted successfully.");
        }

        title: "Chat Schedule Manager"
        modal: true
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent ? parent.width * 0.92 : 600, 500)
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
            LayoutMirroring.enabled: Translations.isRtlLanguage(plasmoid.configuration.language)
            LayoutMirroring.childrenInherit: true

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
                        text: root.historyOnlyMode ? ((plasmoid.configuration.appDisplayName || "KDE AI Chat") + " History") : root.translate(root.currentSessionTitle || "New Chat")
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
                        exportFileDialog.currentFile = "file:///home/home/Documents/" + cleanTitle + "_" + timestamp + ".md";
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
                        root.ensureCurrentOpenCodeSession(function(sid) {
                            var opencodeCmd = "opencode" + (sid !== "" ? " --session " + sid : "");
                            clipboardHelper.text = opencodeCmd;
                            clipboardHelper.selectAll();
                            clipboardHelper.copy();
                            var termCmd = "echo -n '" + sid + "' > /home/home/Programming/rachitkdeaichat/.opencode-session && konsole --workdir /home/home/Programming/rachitkdeaichat -e bash ./opencode-terminal.sh";
                            customStorageDs.connectSource(termCmd + " #opencode-terminal-launch");
                        }, function(err) {
                            root.pushErrorMessage(err);
                            clipboardHelper.text = "opencode";
                            clipboardHelper.selectAll();
                            clipboardHelper.copy();
                            var termCmd = "echo -n '' > /home/home/Programming/rachitkdeaichat/.opencode-session && konsole --workdir /home/home/Programming/rachitkdeaichat -e bash ./opencode-terminal.sh";
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

                                delegate: ChatBubble {
                                    modelData: modelData
                                    index: index
                                    rootRef: root
                                    availableWidth: msgList.width
                                    clipboardHelper: clipboardHelper
                                    customStorageDs: customStorageDs
                                    schedulerDs: schedulerDs
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

                            PC3.Label {
                                visible: root.connectionTimedOut
                                text: "⚠ " + translate("No response yet — check if the server is running")
                                color: "#e74c3c"
                                font.bold: true
                            }

                            QQC2.Button {
                                visible: root.connectionTimedOut
                                text: translate("Cancel request")
                                icon.name: "dialog-cancel"
                                flat: true
                                onClicked: stopStreaming()
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

                                    QQC2.TextField {
                                        visible: root.editingSessionId === modelData.value
                                        width: parent.width - saveRename.width - archiveChat.width - removeChat.width - (modeBadge.visible ? modeBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - (schedBadge.visible ? schedBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - Kirigami.Units.smallSpacing * 3
                                        text: root.editingSessionDraft
                                        onTextChanged: root.editingSessionDraft = text
                                        onAccepted: root.saveSessionRename(modelData.value)
                                    }

                                    PC3.Label {
                                        visible: root.editingSessionId !== modelData.value
                                        width: parent.width - saveRename.width - archiveChat.width - removeChat.width - (modeBadge.visible ? modeBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - (schedBadge.visible ? schedBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - Kirigami.Units.smallSpacing * 3
                                        text: root.translate(modelData.text || "New Chat")
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

    }

}
