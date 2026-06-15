// MainOpenCode.js - Extracted logic for Main

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


function sanitizeOpenCodeStartCommand(cmd) {
    let raw = (cmd || "").trim();
    if (raw === "") {
        return 'logf="${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log"; (nohup opencode serve --port 4096 --hostname 127.0.0.1 >"$logf" 2>&1 < /dev/null &) && echo ok';
    }
    if (raw.indexOf("opencode serve") >= 0 && raw.indexOf("< /dev/null") < 0) {
        if (raw.indexOf("2>&1") >= 0) {
            raw = raw.replace("2>&1", "2>&1 < /dev/null");
        } else {
            if (raw.endsWith("&")) {
                raw = raw.slice(0, -1).trim() + " < /dev/null &";
            } else {
                raw = raw + " < /dev/null";
            }
        }
    }
    if (raw.indexOf("nohup") >= 0 && raw.indexOf("(nohup") < 0) {
        let parts = raw.split(";");
        for (let i = 0; i < parts.length; i++) {
            let part = parts[i].trim();
            if (part.indexOf("nohup") >= 0 && part.endsWith("&") && !part.startsWith("(")) {
                parts[i] = "(" + part + ")";
            }
        }
        raw = parts.join("; ");
    }
    return raw;
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
let startCmd = sanitizeOpenCodeStartCommand(plasmoid.configuration.openCodeStartCommand);
let envPrefix = "export PATH=\"$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/local/bin:$HOME/.opencode/bin\"; ";
opencodeServerDs.connectSource("sh -c '" + envPrefix + startCmd.replace(/'/g, "'\\''") + "' #ensure-opencode-startup-" + Date.now());
if (chatId) {
let ts1 = appendSystemMessageToSession(chatId, translate("Starting OpenCode server, please wait..."));
scheduleMessageRemoval(chatId, ts1, 3000);
}
openCodeStartPollTimer.successCb = function() {
if (chatId) {
let ts2 = appendSystemMessageToSession(chatId, translate("Session restarted."));
scheduleMessageRemoval(chatId, ts2, 3000);
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
let requestFinalized = false;
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
userContent = injectMemoriesToUserMessage(userContent, root.currentSessionId);
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


function doBackgroundOpenCodeRequest(chatId, messageText, notify, schedId, schedName) {
let requestFinalized = false;
function failBackgroundOpenCodeRequest(message) {
if (requestFinalized)
return ;
requestFinalized = true;
handleBackgroundError(chatId, message, notify, schedId, schedName);
}
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
let finalContent = injectMemoriesToUserMessage(messageText, chatId);
xhr.send(JSON.stringify({
"role": "user",
"content": finalContent,
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

