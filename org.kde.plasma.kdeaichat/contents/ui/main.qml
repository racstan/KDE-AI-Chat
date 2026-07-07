import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import "api.js" as Api
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    // Handled lazily by startupTimer / expanded triggers

    id: root

    property var sessions: []
    property string currentSessionId: ""
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
    property string currentStreamText: ""
    property string currentStreamReasoning: ""
    property int currentStreamIndex: -1
    property int editingMessageIndex: -1
    property string editingDraft: ""
    property string editingSessionId: ""
    property string editingSessionDraft: ""
    property bool renamingCurrentChat: false
    property string currentChatRenameDraft: ""
    property bool openCodeMode: plasmoid.configuration.useOpenCode
    property string compiledSystemPrompt: ""
    property string compiledMemoryBlock: ""
    property var sysInfo: ({
    })
    property var pendingSysInfoCommands: ({
    })
    property int sysInfoPending: 0
    property bool compactingContext: false
    // Root-level proxies so root-scope functions can reach UI elements in fullRepresentation
    property string chatInputText: ""
    property var msgListViewRef: null
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
    property bool keysLoaded: false
    property bool _initialLoadDone: false

    signal clearChatInput()

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
            let esc = errorText.replace(/'/g, "'\\''");
            root.fileReaderDs.connectSource("notify-send -i dialog-error 'Voice Error' '" + esc + "' #voice-error");
        }
    }

    // Expose voiceManager as a root property so dynamically loaded children
    // (e.g. FullRepresentationContent via Loader) can access it via root.voiceManager
    property var voiceManagerRef: voiceManager

    function ensureWalletLoaded() {
        if (!keysLoaded) {
            keysLoaded = true;
            loadKWalletKeysAtStartup();
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

    function triggerInitialLoad() {
        if (_initialLoadDone)
            return ;

        _initialLoadDone = true;
        startupTimer.stop(); // Stop background timer if we triggered early
        // Load sessions immediately so UI has chat list / current chat ready
        loadSessions();
        // Defer wallet and sys info slightly so initial layout/rendering is unblocked
        lazyWalletTimer.start();
        lazySysInfoTimer.start();
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
        plasmoid.configuration.chatSessionsJson = JSON.stringify(root.sessions);
        plasmoid.configuration.lastSessionId = root.currentSessionId;
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
        var s = {
            "value": makeSessionId(),
            "text": "New Chat",
            "createdAt": Date.now(),
            "updatedAt": Date.now(),
            "archived": false,
            "source": root.openCodeMode ? "opencode" : "provider",
            "openCodeSessionId": "",
            "messages": []
        };
        root.sessions = [s].concat(root.sessions);
        if (switchToNew) {
            root.currentSessionId = s.value;
            root.currentSessionTitle = s.text;
            root.messages = [];
            root.currentStreamIndex = -1;
            root.currentStreamText = "";
            root.currentStreamReasoning = "";
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
        root.currentStreamIndex = -1;
        root.currentStreamText = "";
        root.currentStreamReasoning = "";
        root.streamingResponse = false;
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
                "content": "",
                "reasoning": "",
                "time": nowTime(ts),
                "at": ts,
                "model": root.openCodeAssistantModelLabel || "OpenCode"
            }]);
            root.openCodeAssistantMessageIndex = root.messages.length - 1;
            root.currentStreamIndex = root.openCodeAssistantMessageIndex;
            root.currentStreamText = incoming;
            root.streamingResponse = true;
            if (!root.userScrolledUp)
                Qt.callLater(scrollToBottom);

            return ;
        }
        var existing = root.currentStreamText || "";
        var newText = "";
        if (incoming.indexOf(existing) === 0)
            newText = incoming;
        else if (existing.indexOf(incoming) === 0)
            newText = existing;
        else
            newText = existing + incoming;
        root.currentStreamText = newText;
        root.streamingResponse = newText !== "";
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom);

    }

    function appendAssistantReasoning(text) {
        var incoming = text || "";
        if (incoming === "")
            return;

        if (root.openCodeAssistantMessageIndex < 0 && root.currentStreamIndex < 0) {
            var ts = Date.now();
            root.messages = root.messages.concat([{
                "role": "assistant",
                "content": "",
                "reasoning": "",
                "time": nowTime(ts),
                "at": ts,
                "model": root.openCodeAssistantModelLabel || ""
            }]);
            root.openCodeAssistantMessageIndex = root.messages.length - 1;
            root.currentStreamIndex = root.openCodeAssistantMessageIndex;
            root.streamingResponse = true;
        }
        root.currentStreamReasoning += incoming;
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom);
    }

    function finishOpenCodeRequest() {
        if (root.openCodeAssistantMessageIndex >= 0 && root.currentStreamIndex === root.openCodeAssistantMessageIndex) {
            var msgs = root.messages.slice();
            msgs[root.openCodeAssistantMessageIndex].content = root.currentStreamText;
            msgs[root.openCodeAssistantMessageIndex].reasoning = root.currentStreamReasoning;
            root.messages = msgs;
            root.currentStreamIndex = -1;
            root.currentStreamText = "";
            root.currentStreamReasoning = "";
        }
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom);

        root.loading = false;
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

            if ((part.type === "reasoning" || part.type === "thinking" || part.type === "step-start" || part.type === "step") && root.openCodeAssistantServerMessageId !== "" && part.messageID === root.openCodeAssistantServerMessageId)
                appendAssistantReasoning(part.text || part.content || part.summary || part.title || "");

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
                    item.tokens = props.tokens;
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
                        var combinedReasoning = "";
                        for (var i = 0; i < obj.parts.length; i++) {
                            if (obj.parts[i].type === "text")
                                combined += obj.parts[i].text || obj.parts[i].content || "";
                            else if (obj.parts[i].type === "reasoning" || obj.parts[i].type === "thinking" || obj.parts[i].type === "step")
                                combinedReasoning += obj.parts[i].text || obj.parts[i].content || obj.parts[i].summary || "";

                        }
                        if (combinedReasoning !== "")
                            appendAssistantReasoning(combinedReasoning);
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
                var lastMsg = root.messages[root.messages.length - 1];
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
                var sysValue = "";
                if (compiledMemoryBlock && compiledMemoryBlock.length > 0)
                    sysValue = compiledMemoryBlock;

                var reqPayload = {
                    "model": {
                        "providerID": providerId,
                        "modelID": modelId
                    },
                    "parts": parts
                };
                if (sysValue && sysValue.length > 0)
                    reqPayload.system = sysValue;

                xhr.send(JSON.stringify(reqPayload));
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
        Qt.callLater(function() {
            if (root.msgListViewRef && root.msgListViewRef.count > 0) {
                root.msgListViewRef.positionViewAtIndex(root.msgListViewRef.count - 1, ListView.End);
                root.msgListViewRef.positionViewAtEnd();
            }
        });
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
            "content": "DEBUG: " + text,
            "time": nowTime(ts),
            "at": ts,
            "model": ""
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
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom);

    }

    function validateCurrentSendTarget() {
        if (root.openCodeMode)
            return validateOpenCodeConfig();

        var provider = plasmoid.configuration.provider || "openai";
        var providerCfg = getProviderConfig(provider);
        return validateProviderConfig(provider, providerCfg);
    }

    function sendMessageByIndex(index) {
        root.currentStreamIndex = -1;
        root.currentStreamText = "";
        root.currentStreamReasoning = "";
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
        setCurrentSessionSource(root.openCodeMode ? "opencode" : "provider");
        if (root.openCodeMode) {
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
        ensureWalletLoaded();
        try {
            var text = (root.chatInputText || "").trim();
            var attachments = root.attachedFiles || [];
            if (text === "" && attachments.length === 0)
                return ;

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

        return {
            "type": "openai-compat",
            "baseUrl": plasmoid.configuration.baseUrl || "https://api.openai.com/v1",
            "apiKey": (plasmoid.configuration.apiKey || "").trim(),
            "model": plasmoid.configuration.model || "",
            "headers": null,
            "allowEmptyKey": false
        };
    }

    function buildOpenAICompatPayload() {
        var arr = [];
        if (plasmoid.configuration.enableSystemPrompt && compiledSystemPrompt && compiledSystemPrompt.length > 0 && root.messages.length <= 1)
            arr.push({
                "role": "system",
                "content": compiledSystemPrompt
            });

        if (compiledMemoryBlock && compiledMemoryBlock.length > 0)
            arr.push({
                "role": "system",
                "content": compiledMemoryBlock
            });

        var messageRoles = [];
        var latestCompactedContent = "";
        
        for (var i = 0; i < root.messages.length; i++) {
            var m = root.messages[i];
            if (m.role === "system_compacted") {
                latestCompactedContent = m.content;
                messageRoles = []; // clear earlier messages!
            } else if (m.role === "user" || m.role === "assistant") {
                messageRoles.push(m);
            }
        }
        
        if (latestCompactedContent) {
            arr.push({
                "role": "system",
                "content": "Previous conversation summary: " + latestCompactedContent
            });
        }
        
        var limit = plasmoid.configuration.contextMessageLimit !== undefined ? plasmoid.configuration.contextMessageLimit : -1;
        if (limit >= 0 && messageRoles.length > limit) {
            messageRoles = messageRoles.slice(messageRoles.length - limit);
        }

        for (var j = 0; j < messageRoles.length; j++) {
            var rm = messageRoles[j];
            if (rm.role === "user" && rm.attachments && rm.attachments.length > 0) {
                var payloadContent = buildMessageContent(rm.content, rm.attachments, "openai");
                arr.push({
                    "role": rm.role,
                    "content": payloadContent
                });
            } else {
                arr.push({
                    "role": rm.role,
                    "content": rm.content
                });
            }
        }
        return arr;
    }

    function buildAnthropicPayload() {
        var arr = [];
        var messageRoles = [];
        for (var i = 0; i < root.messages.length; i++) {
            var m = root.messages[i];
            if (m.role === "user" || m.role === "assistant") {
                messageRoles.push(m);
            }
        }
        
        var limit = plasmoid.configuration.contextMessageLimit !== undefined ? plasmoid.configuration.contextMessageLimit : -1;
        if (limit >= 0 && messageRoles.length > limit) {
            messageRoles = messageRoles.slice(messageRoles.length - limit);
        }

        for (var j = 0; j < messageRoles.length; j++) {
            var rm = messageRoles[j];
            if (rm.role === "user" && rm.attachments && rm.attachments.length > 0) {
                var payloadContent = buildMessageContent(rm.content, rm.attachments, "anthropic");
                arr.push({
                    "role": rm.role,
                    "content": payloadContent
                });
            } else {
                arr.push({
                    "role": rm.role,
                    "content": rm.content
                });
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
        var buffer = "";
        var offset = 0;
        var fullText = "";
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status < 200 || xhr.status >= 300) {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    root.loading = false;
                    root.activeXhr = null;
                    if (errorHandled)
                        return ;

                    errorHandled = true;
                    var err = "Request to " + url + " failed (HTTP " + xhr.status + ")";
                    try {
                        var eobj = JSON.parse(xhr.responseText);
                        if (eobj.error && eobj.error.message)
                            err += ": " + eobj.error.message;
                        else if (eobj.error)
                            err += ": " + JSON.stringify(eobj.error);
                    } catch (e) {
                    }
                    pushErrorMessage(err);
                    processNextQueuedMessage();
                }
                return ;
            }
            var delta = xhr.responseText.slice(offset);
            offset = xhr.responseText.length;
            buffer += delta;
            while (true) {
                var split = buffer.indexOf("\n");
                if (split < 0)
                    break;

                var line = buffer.slice(0, split).trim();
                buffer = buffer.slice(split + 1);
                if (line.indexOf("data: ") === 0) {
                    var dataStr = line.slice(6);
                    if (dataStr === "[DONE]")
                        continue;

                    try {
                        var obj = JSON.parse(dataStr);
                        if (obj.choices && obj.choices.length > 0 && obj.choices[0].delta) {
                            var streamDelta = obj.choices[0].delta;
                            var reasoningDelta = streamDelta.reasoning || streamDelta.reasoning_content || streamDelta.thinking || "";
                            if (reasoningDelta !== "")
                                root.currentStreamReasoning += reasoningDelta;

                            if (streamDelta.content) {
                                fullText += streamDelta.content;
                            }
                            if (streamDelta.content || reasoningDelta !== "") {
                            if (root.currentStreamIndex < 0) {
                                var ts = Date.now();
                                root.messages = root.messages.concat([{
                                    "role": "assistant",
                                    "content": "",
                                    "reasoning": "",
                                    "time": nowTime(ts),
                                    "at": ts,
                                    "model": modelLabel || model || ""
                                }]);
                                root.currentStreamIndex = root.messages.length - 1;
                                root.streamingResponse = true;
                            }
                            root.currentStreamText = fullText;
                            if (!root.userScrolledUp)
                                Qt.callLater(scrollToBottom);

                            }
                        }
                    } catch (e) {
                    }
                }
            }
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.loading = false;
                root.activeXhr = null;
                if (root.currentStreamIndex >= 0) {
                    var msgs = root.messages.slice();
                    msgs[root.currentStreamIndex].content = root.currentStreamText;
                    msgs[root.currentStreamIndex].reasoning = root.currentStreamReasoning;
                    root.messages = msgs;
                } else if (fullText === "" && xhr.status >= 200 && xhr.status < 300) {
                    pushErrorMessage("The model returned an empty response.");
                }
                root.currentStreamIndex = -1;
                root.currentStreamText = "";
                root.currentStreamReasoning = "";
                root.streamingResponse = false;
                if (!root.userScrolledUp)
                    Qt.callLater(scrollToBottom);

                triggerNotificationSound();
                saveCurrentSessionState(true);
                processNextQueuedMessage();
            }
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
                "stream": true
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
                    var reasoningText = "";
                    if (obj.content && obj.content.length) {
                        for (var i = 0; i < obj.content.length; i++) {
                            if (obj.content[i].type === "text")
                                text += obj.content[i].text;
                            else if (obj.content[i].type === "thinking" || obj.content[i].type === "reasoning")
                                reasoningText += obj.content[i].thinking || obj.content[i].text || "";

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
                    if (reasoningText !== "")
                        msgObj.reasoning = reasoningText;
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
        var anthropicReqBody = {
            "model": model,
            "max_tokens": 1024,
            "messages": buildAnthropicPayload()
        };
        var systemPromptParts = [];
        if (plasmoid.configuration.enableSystemPrompt && compiledSystemPrompt && compiledSystemPrompt.length > 0 && root.messages.length <= 1)
            systemPromptParts.push(compiledSystemPrompt);

        if (compiledMemoryBlock && compiledMemoryBlock.length > 0)
            systemPromptParts.push(compiledMemoryBlock);

        if (systemPromptParts.length > 0)
            anthropicReqBody.system = systemPromptParts.join("\n\n");

        xhr.send(JSON.stringify(anthropicReqBody));
    }

    function triggerNotificationSound() {
        if (plasmoid.configuration.playNotificationSound) {
            soundDs.connectSource("pw-play /usr/share/sounds/ocean/stereo/message-new-instant.oga || paplay /usr/share/sounds/ocean/stereo/message-new-instant.oga || aplay /usr/share/sounds/freedesktop/stereo/bell.oga || canberra-gtk-play -i message-new-instant");
        }

        if (voiceManager && voiceManager.enabled && voiceManager.ttsAuto) {
            // Find the last assistant message
            for (var i = root.messages.length - 1; i >= 0; i--) {
                if (root.messages[i].role === "assistant") {
                    var text = (root.messages[i].content || "").trim();
                    if (text) {
                        voiceManager.playTTS(text);
                    }
                    break;
                }
            }
        }
        
        Qt.callLater(checkAndTriggerCompaction);
    }

    function checkAndTriggerCompaction() {
        if (!plasmoid.configuration.compactContextEnabled || root.compactingContext) return;
        var limit = plasmoid.configuration.compactContextAfter || 0;
        if (limit <= 0) return;
        
        var count = 0;
        var lastCompactedIdx = -1;
        for (var i = root.messages.length - 1; i >= 0; i--) {
            if (root.messages[i].role === "system_compacted") {
                lastCompactedIdx = i;
                break;
            }
            if (root.messages[i].role === "user" || root.messages[i].role === "assistant") {
                count++;
            }
        }
        
        if (count > limit) {
            runContextCompaction(lastCompactedIdx + 1, root.messages.length);
        }
    }

    function runContextCompaction(startIdx, endIdx) {
        root.compactingContext = true;
        
        var textToSummarize = "";
        for (var i = startIdx; i < endIdx; i++) {
            var m = root.messages[i];
            if (m.role === "user" || m.role === "assistant") {
                textToSummarize += m.role.toUpperCase() + ": " + m.content + "\n\n";
            }
        }
        
        var prompt = "Please summarize the following conversation concisely to serve as context for future turns. Only return the summary, nothing else.\n\n" + textToSummarize;
        
        var provider = plasmoid.configuration.provider || "openai";
        
        if (provider === "openai" || provider === "openrouter" || provider === "deepseek" || provider === "grok" || provider === "lmstudio") {
            var payload = buildOpenAICompatPayload();
            // Replace messages with just our summary request
            payload = Object.assign({}, payload); // shallow copy
            var headers = {};
            var apiKey = (plasmoid.configuration.apiKey || "").trim();
            if (apiKey) headers["Authorization"] = "Bearer " + apiKey;
            if (provider === "openrouter") {
                headers["HTTP-Referer"] = "https://github.com/racstan/KDE-AI-Chat";
                headers["X-Title"] = "KDE AI Chat";
            }
            var msgs = [{"role": "user", "content": prompt}];
            var xhr = new XMLHttpRequest();
            var url = payload.baseUrl;
            if (url && !url.endsWith("/chat/completions")) url += "/chat/completions";
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            for (var key in headers) {
                xhr.setRequestHeader(key, headers[key]);
            }
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    root.compactingContext = false;
                    if (xhr.status >= 200 && xhr.status < 300) {
                        try {
                            var resp = JSON.parse(xhr.responseText);
                            var summary = resp.choices[0].message.content;
                            var msgsCopy = root.messages.slice();
                            msgsCopy.push({"role": "system_compacted", "content": summary, "date": new Date()});
                            root.messages = msgsCopy;
                            saveCurrentSessionState(true);
                        } catch (e) {}
                    }
                }
            };
            xhr.send(JSON.stringify({"model": payload.model, "messages": msgs}));
        } else {
            // Unhandled providers for compaction for now
            root.compactingContext = false;
        }
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
        // No custom text and no way to read options from here,
        // so prompt user to type something or click an option
        // The option buttons themselves handle single-click submit
        // for non-multiple mode

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
        root.currentStreamIndex = -1;
        root.currentStreamText = "";
        root.currentStreamReasoning = "";
        root.streamingResponse = false;
        root.loading = false;
        saveCurrentSessionState(true);
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

    function copyTextToClipboard(textToCopy) {
        clipboardHelper.text = textToCopy || "";
        clipboardHelper.selectAll();
        clipboardHelper.copy();
    }

    function walletCall(member, args, resolve, reject) {
        var reply = DBus.SessionBus.asyncCall({
            "service": "org.kde.kwalletd6",
            "path": "/modules/kwalletd6",
            "iface": "org.kde.KWallet",
            "member": member,
            "arguments": args
        });
        reply.finished.connect(function() {
            if (reply.isError) {
                if (reject)
                    reject(reply.error);

            } else {
                var val = reply.value;
                if (val !== null && val !== undefined && val.hasOwnProperty("value"))
                    val = val.value;

                if (resolve)
                    resolve(val);

            }
        });
    }

    function applyKWalletKeyToMemory(targetId, secretValue) {
        var strVal = String(secretValue || "");
        if (targetId === "openai")
            plasmoid.configuration.apiKey = strVal;
        else if (targetId === "anthropic")
            plasmoid.configuration.anthropicApiKey = strVal;
        else if (targetId === "groq")
            plasmoid.configuration.groqApiKey = strVal;
        else if (targetId === "deepseek")
            plasmoid.configuration.deepSeekApiKey = strVal;
        else if (targetId === "minimax")
            plasmoid.configuration.miniMaxApiKey = strVal;
        else if (targetId === "fireworks")
            plasmoid.configuration.fireworksApiKey = strVal;
        else if (targetId === "google")
            plasmoid.configuration.googleApiKey = strVal;
        else if (targetId === "openrouter")
            plasmoid.configuration.openRouterApiKey = strVal;
        else if (targetId === "mistral")
            plasmoid.configuration.mistralApiKey = strVal;
        else if (targetId === "cloudflare")
            plasmoid.configuration.cloudflareApiKey = strVal;
        else if (targetId === "nvidia")
            plasmoid.configuration.nvidiaApiKey = strVal;
        else if (targetId === "huggingface")
            plasmoid.configuration.huggingFaceApiKey = strVal;
        else if (targetId === "xai")
            plasmoid.configuration.xaiApiKey = strVal;
        else if (targetId === "litellm")
            plasmoid.configuration.litellmApiKey = strVal;
    }

    function loadKWalletKeysAtStartup() {
        var walletName = "kdewallet";
        walletCall("wallets", [], function(wallets) {
            if (wallets.indexOf(walletName) === -1)
                return ;

            walletCall("open", [walletName, new DBus.int64(0), "org.kde.plasma.kdeaichat"], function(handle) {
                if (handle < 0)
                    return ;

                walletCall("hasFolder", [new DBus.int32(handle), "KaiChat", "org.kde.plasma.kdeaichat"], function(hasFolder) {
                    if (!hasFolder) {
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "org.kde.plasma.kdeaichat"]);
                        return ;
                    }
                    walletCall("passwordList", [new DBus.int32(handle), "KaiChat", "org.kde.plasma.kdeaichat"], function(passwordsMap) {
                        if (passwordsMap) {
                            var targets = ["openai", "anthropic", "groq", "deepseek", "minimax", "fireworks", "google", "openrouter", "mistral", "cloudflare", "nvidia", "huggingface", "xai", "litellm"];
                            for (var i = 0; i < targets.length; i++) {
                                var targetId = targets[i];
                                var key = "kai-chat-" + targetId + "-api-key";
                                if (passwordsMap[key])
                                    applyKWalletKeyToMemory(targetId, passwordsMap[key]);

                            }
                        }
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "org.kde.plasma.kdeaichat"]);
                    });
                });
            });
        });
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

    function initSystemPrompt() {
        var options = {
            "sysInfoDateTime": plasmoid.configuration.sysInfoDateTime,
            "enableMemory": plasmoid.configuration.enableMemory,
            "userMemory": plasmoid.configuration.userMemory
        };
        compiledSystemPrompt = Api.buildSystemPrompt(sysInfo, plasmoid.configuration.systemPrompt, options);
        compiledMemoryBlock = Api.buildMemoryBlock(options);
    }

    function regatherSysInfo() {
        sysInfo = {
        };
        var cmds = [];
        if (plasmoid.configuration.sysInfoOS)
            cmds.push("cat /etc/os-release");

        if (plasmoid.configuration.sysInfoShell)
            cmds.push("echo $SHELL");

        if (plasmoid.configuration.sysInfoHostname)
            cmds.push("hostname");

        if (plasmoid.configuration.sysInfoKernel)
            cmds.push("uname -a");

        if (plasmoid.configuration.sysInfoDesktop)
            cmds.push("echo $XDG_CURRENT_DESKTOP");

        if (plasmoid.configuration.sysInfoUser)
            cmds.push("whoami");

        if (plasmoid.configuration.sysInfoCPU)
            cmds.push("lscpu");

        if (plasmoid.configuration.sysInfoMemory)
            cmds.push("free -h");

        if (plasmoid.configuration.sysInfoGPU)
            cmds.push("bash -c \"lspci -nn | grep -iE 'vga|3d|display'\"");

        if (plasmoid.configuration.sysInfoDisk)
            cmds.push("lsblk -o NAME,SIZE,TYPE,MOUNTPOINT");

        if (plasmoid.configuration.sysInfoNetwork)
            cmds.push("ip -br addr show");

        if (plasmoid.configuration.sysInfoLocale)
            cmds.push("echo $LANG");

        if (cmds.length === 0) {
            initSystemPrompt();
            return ;
        }
        sysInfoPending = cmds.length;
        pendingSysInfoCommands = {
        };
        for (var i = 0; i < cmds.length; i++) {
            pendingSysInfoCommands[cmds[i]] = true;
            sysInfoDs.connectSource(cmds[i]);
        }
    }

    Plasmoid.title: plasmoid.configuration.appDisplayName || "KDE AI Chat"
    preferredRepresentation: compactRepresentation
    onHistoryOnlyModeChanged: {
        if (!historyOnlyMode) {
            root.focusInput();
            Qt.callLater(root.scrollToBottom);
        }
    }
    onExpandedChanged: {
        if (expanded) {
            root.triggerInitialLoad();
            root.focusInput();
            deferredScrollTimer.restart();
        }
    }
    Component.onCompleted: {
    }
    onMessagesChanged: {
        if (!root.historyOnlyMode && !root.userScrolledUp)
            Qt.callLater(scrollToBottom);

    }

    Timer {
        id: deferredScrollTimer

        interval: 100
        repeat: false
        onTriggered: {
            root.scrollToBottom();
        }
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
        id: lazySysInfoTimer

        interval: 300
        repeat: false
        onTriggered: {
            if (plasmoid.configuration.gatheredSysInfo) {
                try {
                    root.sysInfo = JSON.parse(plasmoid.configuration.gatheredSysInfo);
                    root.initSystemPrompt();
                } catch (e) {
                    root.regatherSysInfo();
                }
            } else {
                root.regatherSysInfo();
            }
        }
    }

    Connections {
        function onSysInfoOSChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoShellChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoHostnameChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoKernelChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoDesktopChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoUserChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoCPUChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoMemoryChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoGPUChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoDiskChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoNetworkChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoLocaleChanged() {
            plasmoid.configuration.gatheredSysInfo = "";
            regatherSysInfo();
        }

        function onSysInfoDateTimeChanged() {
            initSystemPrompt();
        }

        function onSystemPromptChanged() {
            initSystemPrompt();
        }

        function onEnableMemoryChanged() {
            initSystemPrompt();
        }

        function onUserMemoryChanged() {
            initSystemPrompt();
        }

        target: plasmoid.configuration
    }

    P5Support.DataSource {
        id: soundDs

        engine: "executable"
        connectedSources: []
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

    P5Support.DataSource {
        id: sysInfoDs

        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var output = data["stdout"] ? data["stdout"].trim() : "";
            if (pendingSysInfoCommands[source]) {
                delete pendingSysInfoCommands[source];
                switch (source) {
                case "hostname":
                    sysInfo.hostname = output;
                    break;
                case "uname -a":
                    sysInfo.kernel = output;
                    break;
                case "whoami":
                    sysInfo.user = output;
                    break;
                case "echo $SHELL":
                    sysInfo.shell = output;
                    break;
                case "cat /etc/os-release":
                    var lines = output.split("\n");
                    for (var i = 0; i < lines.length; i++) {
                        if (lines[i].indexOf("PRETTY_NAME=") === 0) {
                            sysInfo.osRelease = lines[i].replace("PRETTY_NAME=", "").replace(/"/g, "");
                            break;
                        }
                    }
                    if (!sysInfo.osRelease)
                        sysInfo.osRelease = output.substring(0, 100);

                    break;
                case "echo $XDG_CURRENT_DESKTOP":
                    sysInfo.desktop = output;
                    break;
                case "lscpu":
                    var cpuLines = output.split("\n");
                    var cpuInfo = {
                    };
                    for (var j = 0; j < cpuLines.length; j++) {
                        var parts = cpuLines[j].split(":");
                        if (parts.length >= 2) {
                            var key = parts[0].trim();
                            var val = parts.slice(1).join(":").trim();
                            if (["Model name", "CPU(s)", "Architecture", "Thread(s) per core", "Core(s) per socket"].indexOf(key) !== -1)
                                cpuInfo[key] = val;

                        }
                    }
                    sysInfo.cpu = cpuInfo["Model name"] || "unknown";
                    sysInfo.cpuCores = (cpuInfo["CPU(s)"] || "?") + " threads, " + (cpuInfo["Core(s) per socket"] || "?") + " cores";
                    sysInfo.cpuArch = cpuInfo["Architecture"] || "";
                    break;
                case "free -h":
                    sysInfo.memory = output;
                    break;
                case "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT":
                    sysInfo.disk = output;
                    break;
                case "bash -c \"lspci -nn | grep -iE 'vga|3d|display'\"":
                    sysInfo.gpu = output || "unknown";
                    break;
                case "ip -br addr show":
                    sysInfo.network = output;
                    break;
                case "echo $LANG":
                    sysInfo.locale = output;
                    break;
                }
                sysInfoPending--;
                if (sysInfoPending === 0) {
                    plasmoid.configuration.gatheredSysInfo = JSON.stringify(sysInfo);
                    initSystemPrompt();
                }
                disconnectSource(source);
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
