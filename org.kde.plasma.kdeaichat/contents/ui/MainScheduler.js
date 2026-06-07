// MainScheduler.js - Extracted logic for Main

function handleScheduleCommand(root, messageText) {
scheduleCommandDialog.prefillMessage = messageText;
scheduleCommandDialog.chatId = root.currentSessionId;
scheduleCommandDialog.chatName = root.currentSessionTitle || "Current chat";
scheduleCommandDialog.open();
}


function toggleScheduleEnabled(root, schedId, newEnabled) {
let payload = {
"schedId": schedId,
"enabled": newEnabled
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " toggle_schedule " + Sec.quoteForShell(b64Payload);
schedulerDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-toggle-" + Date.now());
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


function injectScheduledMessage(root, chatId, messageText, notify, schedId, schedName) {
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
// If KWallet mode is active and keys are not loaded yet, load them first.
if (!root.openCodeMode && plasmoid.configuration.keyStorageMode === 2 && !root.kwalletKeysLoaded) {
loadKWalletKeysIfNeeded(
function onSuccess() {
injectScheduledMessage(chatId, messageText, notify, schedId, schedName);
},
function onFailure(err) {
let errMsg = "KWallet access failed: " + err;
pushErrorMessage(errMsg);
if (notify) {
let safeErr = Sec.sanitizeForShell(errMsg);
let errTitle = "Schedule Failed: " + (schedName || root.currentSessionTitle || "Chat");
let safeErrTitle = Sec.sanitizeForShell(errTitle);
soundDs.connectSource("notify-send --app-name=\"KDE AI Chat\" -u critical -i dialog-warning " + Sec.quoteForShell(safeErrTitle) + " " + Sec.quoteForShell(safeErr) + " #sched-notify-err");
}
if (schedId) {
let historyPayload = {
"schedId": schedId,
"status": errMsg
};
let b64HistoryPayload = base64Encode(JSON.stringify(historyPayload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " update_schedule_history_status " + Sec.quoteForShell(b64HistoryPayload);
soundDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-history-err");
}
}
);
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
soundDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-history-err");
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


function executeScheduledMessageInBackground(root, chatId, messageText, notify, schedId, schedName) {
// If KWallet mode is active and keys are not loaded yet, load them first.
if (!root.openCodeMode && plasmoid.configuration.keyStorageMode === 2 && !root.kwalletKeysLoaded) {
loadKWalletKeysIfNeeded(
function onSuccess() {
executeScheduledMessageInBackground(chatId, messageText, notify, schedId, schedName);
},
function onFailure(err) {
handleBackgroundError(chatId, "KWallet access failed: " + err, notify, schedId, schedName);
}
);
return ;
}
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


function applyKWalletKeyToMemory(root, targetId, secretValue) {
let configKey = ProviderService.getApiKeyConfigKey(targetId);
if (configKey) {
plasmoid.configuration[configKey] = secretValue;
}
}


function triggerKWalletCallbacks(root, success, errorMsg) {
let successList = root.kwalletLoadSuccessCallbacks || [];
let failureList = root.kwalletLoadFailureCallbacks || [];
root.kwalletLoadSuccessCallbacks = [];
root.kwalletLoadFailureCallbacks = [];
root.kwalletLoading = false;
if (success) {
for (let i = 0; i < successList.length; i++) {
try {
successList[i]();
} catch(e) {
console.error("Error in KWallet success callback:", e);
}
}
} else {
for (let j = 0; j < failureList.length; j++) {
try {
failureList[j](errorMsg);
} catch(e) {
console.error("Error in KWallet failure callback:", e);
}
}
}
}


function loadKWalletKeysIfNeeded(root, onSuccess, onFailure) {
if (plasmoid.configuration.keyStorageMode !== 2) {
if (typeof onSuccess === "function")
onSuccess();
return ;
}
if (root.kwalletKeysLoaded) {
if (typeof onSuccess === "function")
onSuccess();
return ;
}
if (typeof onSuccess === "function") {
root.kwalletLoadSuccessCallbacks.push(onSuccess);
}
if (typeof onFailure === "function") {
root.kwalletLoadFailureCallbacks.push(onFailure);
}
if (root.kwalletLoading) {
return ;
}
if (root.kwalletOpenAttempts >= 3) {
debugLog("[KAI-DEBUG] loadKWalletKeysIfNeeded open attempts limit of 3 exceeded. Skipping KWallet load.");
triggerKWalletCallbacks(false, "KWallet open attempts limit exceeded");
return ;
}
root.kwalletLoading = true;
let walletName = (plasmoid.configuration.kwalletName || "").trim() || "kdewallet";
kwalletStartupDs.connectSource(walletBulkReadCommand(walletName) + " #kwallet-startup-load");
}

