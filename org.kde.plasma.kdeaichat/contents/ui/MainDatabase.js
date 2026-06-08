.import "Security.js" as Sec
.import "SessionManager.js" as SessionManager
.import "ProviderService.js" as ProviderService
.import "WalletService.js" as WalletService
.import "translations.js" as Translations
.import "MarkdownRenderer.js" as MarkdownRenderer
// MainDatabase.js - Extracted logic for Main

function debugLog() {
if (debugMode) {
let args = Array.prototype.slice.call(arguments);
console.log.apply(console, args);
}
}


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
let realTs = (ts === undefined && typeof root !== "object") ? root : ts;
let d = realTs ? new Date(realTs) : new Date();
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


function sortSessionsByUpdated(arg1) {
    let r = arg1;
    if (r === undefined) {
        r = root;
    }
    if (!r || !r.sessions)
        return;
    // Audit 5.3: skip the O(n log n) sort + array reassignment cascade
    // when the list is already in canonical order. The reassignment
    // was the dominant cost during streaming because it invalidated
    // all sidebar binding caches on every save.
    if (SessionManager.isSessionOrderCorrect(r.sessions))
        return ;
    let copy = SessionManager.sortSessionsByUpdated(r.sessions);
    r.sessions = copy;
}


function historySessionTint(sessionData) {
if (!sessionData)
return Qt.rgba(root.Kirigami.Theme.textColor.r, root.Kirigami.Theme.textColor.g, root.Kirigami.Theme.textColor.b, 0.05);
if (sessionData.value === root.currentSessionId && sessionData.source === "opencode")
return Qt.rgba(0.2, 0.48, 0.92, 0.22);
if (sessionData.source === "opencode")
return Qt.rgba(0.2, 0.48, 0.92, 0.1);
if (sessionData.value === root.currentSessionId)
return Qt.rgba(root.Kirigami.Theme.highlightColor.r, root.Kirigami.Theme.highlightColor.g, root.Kirigami.Theme.highlightColor.b, 0.18);
return Qt.rgba(root.Kirigami.Theme.textColor.r, root.Kirigami.Theme.textColor.g, root.Kirigami.Theme.textColor.b, 0.05);
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


function sessionIndexById(arg1, arg2) {
    let r = arg1;
    let sId = arg2;
    if (sId === undefined) {
        sId = arg1;
        r = root;
    }
    if (!r || !r.sessions)
        return -1;
    for (let i = 0; i < r.sessions.length; i++) {
        if (r.sessions[i].value === sId)
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
schedulerDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-session-delete-" + Date.now());
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


function isLatestUserMessage(index) {
if (index < 0 || index >= root.messages.length)
return false;
if (root.messages[index].role !== "user")
return false;
for (let i = index + 1; i < root.messages.length; i++) {
if (root.messages[i].role === "user")
return false;
}
return true;
}


function hasSubsequentAssistantMessage(index) {
if (index < 0 || index >= root.messages.length - 1)
return false;
return root.messages[index + 1].role === "assistant";
}


function regenerateReply(index, type) {
if (index < 0 || index >= root.messages.length - 1)
return ;
let userMsg = root.messages[index];
let aiMsg = root.messages[index + 1];
let instruction = type === "shorter" ? "generate a much shorter version" : "generate a much more detailed and longer version";
let prompt = "I'm looking for a different version of your last response. \n\n" + "My original question was: \"" + userMsg.content + "\"\n" + "Your previous response was: \"" + aiMsg.content + "\"\n\n" + "Please " + instruction + " of that response.";
root.chatInputText = prompt;
sendMessage();
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
root._pendingStreamingText = incoming;
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
if (!streamingBatchTimer.running) {
streamingBatchTimer.start();
}
}


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


function sendMessageByIndex(index) {
resetOpenCodeIdleKillTimer();
let source = root.messages[index] || {
};
let text = (source.content || "").trim();
let hasAttachments = source.attachments && source.attachments.length > 0;
if (!text && !hasAttachments)
return ;
if (!root.openCodeMode && plasmoid.configuration.keyStorageMode === 2 && !root.kwalletKeysLoaded) {
root.loading = true;
loadKWalletKeysIfNeeded(
function onSuccess() {
root.loading = false;
sendMessageByIndex(index);
},
function onFailure(err) {
root.loading = false;
pushErrorMessage(root.translate("KWallet access failed: ") + err + ". " + root.translate("Please check settings or unlock your wallet."));
}
);
return ;
}
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


function walletBulkReadCommand(walletName) {
return WalletService.buildBulkReadCommand(walletName, ProviderService.getApiKeyProviderIds());
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


function copyToClipboard(textValue) {
let text = textValue || "";
// Sanitize first so the entire single-quote payload is harmless
// even if the surrounding wrapper is re-evaluated. The wrapper
// now uses a single-quoted string around the inner command so
// the outer `sh -c` cannot perform command substitution on
// the value.
let safe = Sec.sanitizeForShell(text);
let cmd = "sh -c 'if command -v wl-copy >/dev/null 2>&1; then printf %s " + Sec.quoteForShell(safe) + " | wl-copy; " + "elif command -v xclip >/dev/null 2>&1; then printf %s " + Sec.quoteForShell(safe) + " | xclip -selection clipboard; " + "else echo \"Clipboard tool missing: install wl-clipboard or xclip\" 1>&2; exit 1; fi'";
clipboardDs.connectSource(cmd + " #clipboard-copy");
}


function flushStreamingBuffer() {
if (!_streamingDirty)
return;
_streamingDirty = false;
streamingBatchTimer.stop();
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

