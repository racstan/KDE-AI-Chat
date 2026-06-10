.import "Security.js" as Sec

// MainNetwork.js - Extracted logic for Main

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


function finishOpenCodeRequest() {
flushStreamingBuffer();
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


function validateCurrentSendTarget() {
if (root.openCodeMode)
return validateOpenCodeConfig();
let provider = plasmoid.configuration.provider || "openai";
let providerCfg = getProviderConfig(provider);
return validateProviderConfig(provider, providerCfg);
}


function buildAnthropicPayloadForMessages(messagesList, chatId) {
return _buildMessageArray(messagesList, chatId, "anthropic");
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
soundDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-history-err");
}
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
if (chatId === root.currentSessionId && plasmoid.configuration.voiceEnabled && plasmoid.configuration.voiceTtsEnabled) {
MainDatabase.triggerTts(text || "");
}
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
let dedupKey = root.reqDedupKey(plasmoid.configuration.provider || "openai", model, lastUserText, root.currentSessionId);
if (!root.reqDedupTryClaim(dedupKey)) {
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
xhr.timeout = 90000;
xhr.ontimeout = function() {
if (errorHandled)
return ;
errorHandled = true;
finishOpenCodeRequest();
pushErrorMessage("Request timed out after 90 seconds.");
};
} catch (setupError) {
root.reqDedupRelease(dedupKey);
pushErrorMessage("Failed to start request: " + setupError);
return ;
}
root.loading = true;
root.activeXhr = xhr;
beginAssistantStreaming(modelLabel || model || "");

let offset = 0;
let buffer = "";
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
return ;
let delta = xhr.responseText.slice(offset);
offset = xhr.responseText.length;
buffer += delta;
let lines = buffer.split("\n");
buffer = lines.pop();
for (let i = 0; i < lines.length; i++) {
let line = lines[i].trim();
if (!line || line.indexOf("data:") !== 0)
continue;
let data = line.slice(5).trim();
if (data === "[DONE]") {
errorHandled = true;
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
return ;
}
try {
let parsed = JSON.parse(data);
let content = (parsed.choices && parsed.choices[0] && parsed.choices[0].delta && parsed.choices[0].delta.content) || "";
if (content) {
updateAssistantStreamingContent(content, modelLabel || model);
}
} catch (e) {
}
}
if (xhr.readyState === XMLHttpRequest.DONE) {
root.reqDedupRelease(dedupKey);
if (!errorHandled) {
if (xhr.status < 200 || xhr.status >= 300) {
let err = "Request to " + Sec.scrubSecrets(url) + " failed (HTTP " + xhr.status + ")";
pushErrorMessage(err);
}
finishOpenCodeRequest();
}
}
};
xhr.onerror = function() {
if (errorHandled)
return ;
errorHandled = true;
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
pushErrorMessage("Could not reach " + Sec.scrubSecrets(url));
};
try {
xhr.send(JSON.stringify({
"model": model,
"messages": buildOpenAICompatPayload(),
"stream": true
}));
} catch (sendError) {
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
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
let dedupKey = root.reqDedupKey("anthropic", model, lastUserText, root.currentSessionId);
if (!root.reqDedupTryClaim(dedupKey)) {
pushErrorMessage("Duplicate request ignored: a response to this message is already in flight.");
return ;
}
root.loading = true;
root.activeXhr = xhr;
beginAssistantStreaming(model || "");
xhr.open("POST", "https://api.anthropic.com/v1/messages", true);
xhr.setRequestHeader("Content-Type", "application/json");
xhr.setRequestHeader("x-api-key", apiKey);
xhr.setRequestHeader("anthropic-version", "2023-06-01");
xhr.timeout = 90000;
xhr.ontimeout = function() {
if (errorHandled)
return ;
errorHandled = true;
finishOpenCodeRequest();
root.reqDedupRelease(dedupKey);
pushErrorMessage("Request timed out after 90 seconds.");
};
let offset = 0;
let buffer = "";
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
return ;
let delta = xhr.responseText.slice(offset);
offset = xhr.responseText.length;
buffer += delta;
let lines = buffer.split("\n");
buffer = lines.pop();
for (let i = 0; i < lines.length; i++) {
let line = lines[i].trim();
if (!line || line.indexOf("data:") !== 0)
continue;
let dataStr = line.slice(5).trim();
try {
let data = JSON.parse(dataStr);
if (data.type === "content_block_delta" && data.delta && data.delta.text) {
updateAssistantStreamingContent(data.delta.text, model);
} else if (data.type === "message_stop") {
errorHandled = true;
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
return ;
}
} catch (e) {
}
}
if (xhr.readyState === XMLHttpRequest.DONE) {
root.reqDedupRelease(dedupKey);
if (!errorHandled) {
if (xhr.status < 200 || xhr.status >= 300) {
pushErrorMessage("Anthropic request failed (HTTP " + xhr.status + ")");
}
finishOpenCodeRequest();
}
}
};
xhr.onerror = function() {
if (errorHandled)
return ;
errorHandled = true;
root.reqDedupRelease(dedupKey);
finishOpenCodeRequest();
pushErrorMessage("Could not reach https://api.anthropic.com/v1/messages.");
};
xhr.send(JSON.stringify({
"model": model,
"max_tokens": 1024,
"system": buildEffectiveSystemPrompt(),
"messages": buildAnthropicPayload(),
"stream": true
}));
}

