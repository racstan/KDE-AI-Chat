// ConfigGeneralLogic.js - Extracted logic for ConfigGeneral

function debugLog(page) {
if (debugMode) {
let args = Array.prototype.slice.call(arguments);
console.log.apply(console, args);
}
}


function translate(page, text) {
return Translations.translate(text, cfg_language);
}


function updateFilteredProviderModels(page, searchText) {
let search = (searchText || "").toLowerCase();
if (search === "") {
filteredProviderModels = providerModelCandidates;
} else {
let filtered = [];
for (let i = 0; i < providerModelCandidates.length; i++) {
if (providerModelCandidates[i].toLowerCase().indexOf(search) >= 0)
filtered.push(providerModelCandidates[i]);
}
filteredProviderModels = filtered;
}
}


function updateFilteredOpenCodeModels(page, searchText) {
let search = (searchText || "").toLowerCase();
if (search === "") {
filteredOpenCodeModels = openCodeModelCandidates;
} else {
let filtered = [];
for (let i = 0; i < openCodeModelCandidates.length; i++) {
if (openCodeModelCandidates[i].toLowerCase().indexOf(search) >= 0)
filtered.push(openCodeModelCandidates[i]);
}
filteredOpenCodeModels = filtered;
}
}


function effectiveWalletName(page) {
let configuredName = (walletNameField.text || "").trim();
if (configuredName !== "")
return configuredName;
if (availableWalletNames.length > 0)
return availableWalletNames[0];
return "kdewallet";
}


function maybeAdoptDetectedWalletName(page) {
if (availableWalletNames.length === 0)
return ;
let configured = (walletNameField.text || "").trim();
if (configured === "") {
walletNameField.text = availableWalletNames[0];
return ;
}
for (let i = 0; i < availableWalletNames.length; i++) {
if (availableWalletNames[i].toLowerCase() === configured.toLowerCase()) {
walletNameField.text = availableWalletNames[i];
return ;
}
}
}


function detectWallets(page) {
utilityDs.connectSource("sh -c \"if ! command -v qdbus6 >/dev/null 2>&1 && ! command -v qdbus >/dev/null 2>&1; then echo '__NO_QDBUS__'; else qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null || qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null; fi\" #kwallet-wallet-list");
}


function setActiveProviderModelValue(page, value) {
currentProviderConfig().modelField.text = value || "";
}


function activeProviderModelValue(page) {
return currentProviderConfig().modelField.text || "";
}


function walletReadCommand(page, walletName, keyName) {
let escapedWallet = shellEscape(walletName);
let escapedFolder = shellEscape(walletFolderName);
let escapedKey = shellEscape(keyName);
let escapedAppId = shellEscape(walletAppId);
return "sh -c '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "key='\''" + escapedKey + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "wallets=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null); " + "if ! printf %s \"$wallets\" | grep -Fxq \"$wallet\"; then printf \"__KAI_LOAD__:NO_WALLET\"; exit 0; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_LOAD__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; printf \"__KAI_LOAD__:NO_FOLDER\"; exit 0; fi; " + "hasEntry=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasEntry \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasEntry\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; printf \"__KAI_LOAD__:NO_ENTRY\"; exit 0; fi; " + "secret=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.readPassword \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null); " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "printf \"__KAI_SECRET__:%s\" \"$secret\"'";
}


function walletWriteCommand(page, walletName, keyName, value) {
let escapedWallet = shellEscape(walletName);
let escapedFolder = shellEscape(walletFolderName);
let escapedKey = shellEscape(keyName);
let escapedValue = shellEscape(value);
let escapedAppId = shellEscape(walletAppId);
return "sh -c '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "key='\''" + escapedKey + "'\''; " + "value='\''" + escapedValue + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_STORE__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.createFolder \"$handle\" \"$folder\" \"$appid\" >/dev/null 2>&1; fi; " + "result=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.writePassword \"$handle\" \"$folder\" \"$key\" \"$value\" \"$appid\" 2>/dev/null | tail -n 1); " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "printf \"__KAI_STORE__:%s\" \"$result\"'";
}


function walletInitCommand(page, walletName) {
let escapedWallet = shellEscape(walletName);
let escapedFolder = shellEscape(walletFolderName);
let escapedAppId = shellEscape(walletAppId);
return "sh -c '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_INIT__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" = true ]; then printf \"__KAI_INIT__:READY\"; else created=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.createFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); if [ \"$created\" = true ]; then printf \"__KAI_INIT__:CREATED\"; else printf \"__KAI_INIT__:CREATE_FAILED\"; fi; fi; " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1'";
}


function walletStatusCommand(page, walletName) {
let escapedWallet = shellEscape(walletName);
let escapedFolder = shellEscape(walletFolderName);
let escapedAppId = shellEscape(walletAppId);
return "sh -c '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "wallets=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null); " + "if ! printf %s \"$wallets\" | grep -Fxq \"$wallet\"; then printf \"__KAI_STATUS__:NO_WALLET:%s\" \"$wallets\"; exit 0; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_STATUS__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "if [ \"$hasFolder\" = true ]; then printf \"__KAI_STATUS__:READY\"; else printf \"__KAI_STATUS__:NO_FOLDER\"; fi'";
}


function walletBulkReadCommand(page, walletName) {
return WalletService.buildBulkReadCommand(walletName, ProviderService.getApiKeyProviderIds(), walletFolderName, walletAppId);
}


function shellEscape(page, s) {
return Sec.sanitizeForShell(s || "").replace(/'/g, "'\\''");
}


function copyToClipboard(page, textValue) {
let text = textValue || "";
// Sanitize first so the value cannot be re-evaluated as shell
// grammar by the outer `sh -c` wrapper. See the same function
// in main.qml for the rationale.
let safe = Sec.sanitizeForShell(text);
let cmd = "sh -c 'if command -v wl-copy >/dev/null 2>&1; then printf %s " + Sec.quoteForShell(safe) + " | wl-copy; " + "elif command -v xclip >/dev/null 2>&1; then printf %s " + Sec.quoteForShell(safe) + " | xclip -selection clipboard; " + "else echo \"Clipboard tool missing: install wl-clipboard or xclip\" 1>&2; exit 1; fi'";
utilityDs.connectSource(cmd + " #clipboard-copy");
}


function providerEnabled(page, providerId) {
return !openCodeToggle.checked && providerBox.currentValue === providerId;
}


function providerNeedsApiKey(page, providerId) {
return providerId !== "local" && providerId !== "lmstudio" && providerId !== "ollama" && providerId !== "litellm";
}


function providerHasConfiguredKey(page, providerId) {
if (providerId === "anthropic")
return (anthropicApiKeyField.text || "").trim() !== "";
if (providerId === "groq")
return (groqApiKeyField.text || "").trim() !== "";
if (providerId === "deepseek")
return (deepSeekApiKeyField.text || "").trim() !== "";
if (providerId === "minimax")
return (miniMaxApiKeyField.text || "").trim() !== "";
if (providerId === "fireworks")
return (fireworksApiKeyField.text || "").trim() !== "";
if (providerId === "google")
return (googleApiKeyField.text || "").trim() !== "";
if (providerId === "openrouter")
return (openRouterApiKeyField.text || "").trim() !== "";
if (providerId === "mistral")
return (mistralApiKeyField.text || "").trim() !== "";
if (providerId === "cloudflare")
return (cloudflareApiKeyField.text || "").trim() !== "";
if (providerId === "nvidia")
return (nvidiaApiKeyField.text || "").trim() !== "";
if (providerId === "huggingface")
return (huggingFaceApiKeyField.text || "").trim() !== "";
if (providerId === "xai")
return (xaiApiKeyField.text || "").trim() !== "";
if (providerId === "litellm")
return (litellmApiKeyField.text || "").trim() !== "";
if (providerId === "qwen")
return (qwenApiKeyField.text || "").trim() !== "";
if (providerId === "moonshot")
return (moonshotApiKeyField.text || "").trim() !== "";
if (providerId === "mimo")
return (mimoApiKeyField.text || "").trim() !== "";
if (providerId === "maritaca")
return (maritacaApiKeyField.text || "").trim() !== "";
if (providerId === "openai")
return (apiKeyField.text || "").trim() !== "";
return true;
}


function refreshIfActiveProvider(page, providerId) {
if (providerBox.currentValue === providerId)
refreshCurrentProviderModels();
}


function providerModelVisible(page, providerId) {
return providerEnabled(providerId) && (!providerNeedsApiKey(providerId) || providerHasConfiguredKey(providerId));
}


function providerNeedsKeyHintVisible(page, providerId) {
return providerEnabled(providerId) && providerNeedsApiKey(providerId) && !providerHasConfiguredKey(providerId);
}


function currentProviderDisplayName(page) {
return providerBox.currentText || "Provider";
}


function currentProviderConfig(page) {
let p = providerBox.currentValue || "openai";
if (p === "anthropic")
return {
"id": p,
"type": "anthropic",
"baseUrl": "https://api.anthropic.com/v1",
"apiKey": anthropicApiKeyField.text,
"modelField": anthropicModelField
};
if (p === "local")
return {
"id": p,
"type": "openai-compat",
"baseUrl": localBaseUrlField.text,
"apiKey": "",
"modelField": localModelField
};
if (p === "groq")
return {
"id": p,
"type": "openai-compat",
"baseUrl": groqBaseUrlField.text,
"apiKey": groqApiKeyField.text,
"modelField": groqModelField
};
if (p === "deepseek")
return {
"id": p,
"type": "openai-compat",
"baseUrl": deepSeekBaseUrlField.text,
"apiKey": deepSeekApiKeyField.text,
"modelField": deepSeekModelField
};
if (p === "minimax")
return {
"id": p,
"type": "openai-compat",
"baseUrl": miniMaxBaseUrlField.text,
"apiKey": miniMaxApiKeyField.text,
"modelField": miniMaxModelField
};
if (p === "fireworks")
return {
"id": p,
"type": "openai-compat",
"baseUrl": fireworksBaseUrlField.text,
"apiKey": fireworksApiKeyField.text,
"modelField": fireworksModelField
};
if (p === "google")
return {
"id": p,
"type": "openai-compat",
"baseUrl": googleBaseUrlField.text,
"apiKey": googleApiKeyField.text,
"modelField": googleModelField
};
if (p === "openrouter")
return {
"id": p,
"type": "openai-compat",
"baseUrl": openRouterBaseUrlField.text,
"apiKey": openRouterApiKeyField.text,
"modelField": openRouterModelField
};
if (p === "mistral")
return {
"id": p,
"type": "openai-compat",
"baseUrl": mistralBaseUrlField.text,
"apiKey": mistralApiKeyField.text,
"modelField": mistralModelField
};
if (p === "cloudflare")
return {
"id": p,
"type": "openai-compat",
"baseUrl": cloudflareBaseUrlField.text,
"apiKey": cloudflareApiKeyField.text,
"modelField": cloudflareModelField
};
if (p === "nvidia")
return {
"id": p,
"type": "openai-compat",
"baseUrl": nvidiaBaseUrlField.text,
"apiKey": nvidiaApiKeyField.text,
"modelField": nvidiaModelField
};
if (p === "huggingface")
return {
"id": p,
"type": "openai-compat",
"baseUrl": huggingFaceBaseUrlField.text,
"apiKey": huggingFaceApiKeyField.text,
"modelField": huggingFaceModelField
};
if (p === "xai")
return {
"id": p,
"type": "openai-compat",
"baseUrl": xaiBaseUrlField.text,
"apiKey": xaiApiKeyField.text,
"modelField": xaiModelField
};
if (p === "lmstudio")
return {
"id": p,
"type": "openai-compat",
"baseUrl": lmStudioBaseUrlField.text,
"apiKey": "",
"modelField": lmStudioModelField
};
if (p === "ollama")
return {
"id": p,
"type": "openai-compat",
"baseUrl": ollamaBaseUrlField.text,
"apiKey": "",
"modelField": ollamaModelField
};
if (p === "litellm")
return {
"id": p,
"type": "openai-compat",
"baseUrl": litellmBaseUrlField.text,
"apiKey": litellmApiKeyField.text,
"modelField": litellmModelField
};
if (p === "qwen")
return {
"id": p,
"type": "openai-compat",
"baseUrl": qwenBaseUrlField.text,
"apiKey": qwenApiKeyField.text,
"modelField": qwenModelField
};
if (p === "moonshot")
return {
"id": p,
"type": "openai-compat",
"baseUrl": moonshotBaseUrlField.text,
"apiKey": moonshotApiKeyField.text,
"modelField": moonshotModelField
};
if (p === "mimo")
return {
"id": p,
"type": "openai-compat",
"baseUrl": mimoBaseUrlField.text,
"apiKey": mimoApiKeyField.text,
"modelField": mimoModelField
};
if (p === "maritaca")
return {
"id": p,
"type": "openai-compat",
"baseUrl": maritacaBaseUrlField.text,
"apiKey": maritacaApiKeyField.text,
"modelField": maritacaModelField
};
return {
"id": "openai",
"type": "openai-compat",
"baseUrl": baseUrlField.text,
"apiKey": apiKeyField.text,
"modelField": modelField
};
}


function makeOpenAiModelsUrl(page, baseUrl) {
return (baseUrl || "").replace(/\/$/, "") + "/models";
}


function parseModelIds(page, responseObj) {
function pushId(v) {
if (!v)
return ;
if (ids.indexOf(v) < 0)
ids.push(v);
}
let ids = [];
if (Array.isArray(responseObj)) {
for (let i = 0; i < responseObj.length; i++) {
if (typeof responseObj[i] === "string")
pushId(responseObj[i]);
else if (responseObj[i] && responseObj[i].id)
pushId(responseObj[i].id);
else if (responseObj[i] && responseObj[i].name)
pushId(responseObj[i].name);
}
} else if (responseObj && Array.isArray(responseObj.data)) {
for (let j = 0; j < responseObj.data.length; j++) {
if (responseObj.data[j] && responseObj.data[j].id)
pushId(responseObj.data[j].id);
else if (responseObj.data[j] && responseObj.data[j].name)
pushId(responseObj.data[j].name);
}
} else if (responseObj && Array.isArray(responseObj.models)) {
for (let k = 0; k < responseObj.models.length; k++) {
if (typeof responseObj.models[k] === "string")
pushId(responseObj.models[k]);
else if (responseObj.models[k] && responseObj.models[k].id)
pushId(responseObj.models[k].id);
else if (responseObj.models[k] && responseObj.models[k].name)
pushId(responseObj.models[k].name);
}
}
return ids;
}


function requestJson(page, url, headers, onSuccess, onError) {
let xhr = new XMLHttpRequest();
xhr.open("GET", url, true);
for (let h in headers) {
if (Object.prototype.hasOwnProperty.call(headers, h) && headers[h])
xhr.setRequestHeader(h, headers[h]);
}
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status >= 200 && xhr.status < 300) {
try {
onSuccess(JSON.parse(xhr.responseText));
} catch (e) {
onError("Invalid JSON from " + url);
}
} else {
onError("HTTP " + xhr.status + " from " + url);
}
};
xhr.onerror = function() {
onError("Network error while requesting " + url);
};
xhr.send();
}


function refreshCurrentProviderModels(page) {
let cfg = currentProviderConfig();
let headers = {
};
if (providerNeedsApiKey(cfg.id) && (!cfg.apiKey || cfg.apiKey.trim() === "")) {
providerModelCandidates = [];
providerModelSearch = "";
updateFilteredProviderModels("");
discoveryStatus = "API key is missing for " + currentProviderDisplayName() + ". Add key first, then refresh models.";
return ;
}
if (cfg.apiKey)
headers["Authorization"] = "Bearer " + cfg.apiKey;
if (cfg.type === "anthropic") {
headers["x-api-key"] = cfg.apiKey;
headers["anthropic-version"] = "2023-06-01";
requestJson("https://api.anthropic.com/v1/models", headers, function(obj) {
let ids = parseModelIds(obj);
providerModelCandidates = ids;
providerModelSearch = "";
updateFilteredProviderModels("");
discoveryStatus = ids.length > 0 ? ("Loaded " + ids.length + " models for " + currentProviderDisplayName() + ".") : "No models returned for this provider/API key.";
}, function(err) {
providerModelCandidates = [];
providerModelSearch = "";
updateFilteredProviderModels("");
discoveryStatus = err;
});
return ;
}
requestJson(makeOpenAiModelsUrl(cfg.baseUrl), headers, function(obj) {
let ids = parseModelIds(obj);
providerModelCandidates = ids;
providerModelSearch = "";
updateFilteredProviderModels("");
discoveryStatus = ids.length > 0 ? ("Loaded " + ids.length + " models for " + currentProviderDisplayName() + ".") : "No models returned for this provider/API key.";
}, function(err) {
providerModelCandidates = [];
providerModelSearch = "";
updateFilteredProviderModels("");
discoveryStatus = err;
});
}


function applyDetectedModelToActiveProvider(page, modelId) {
let cfg = currentProviderConfig();
cfg.modelField.text = modelId || "";
}


function activeOpenCodeProvider(page) {
return openCodeProviderValueField.text || "";
}


function setOpenCodeProviderValue(page, v) {
openCodeProviderValueField.text = v || "";
}


function setOpenCodeModelValue(page, v) {
openCodeModelValueField.text = v || "";
}


function openCodeServerRoot(page, baseUrl) {
let value = (baseUrl || "").replace(/\/$/, "");
if (value.slice(-3) === "/v1")
return value.slice(0, -3);
return value;
}


function parseOpenCodeProviderModels(page, providerObj) {
function pushId(v) {
if (!v)
return ;
if (ids.indexOf(v) < 0)
ids.push(v);
}
let ids = [];
if (!providerObj || !providerObj.models)
return ids;
if (Array.isArray(providerObj.models)) {
for (let i = 0; i < providerObj.models.length; i++) {
if (typeof providerObj.models[i] === "string")
pushId(providerObj.models[i]);
else if (providerObj.models[i] && providerObj.models[i].id)
pushId(providerObj.models[i].id);
}
return ids;
}
for (let modelId in providerObj.models) {
if (!Object.prototype.hasOwnProperty.call(providerObj.models, modelId))
continue;
pushId(providerObj.models[modelId].id || modelId);
}
return ids;
}


function syncOpenCodeProviderSelection(page, providerId, preferredModel) {
let selectedProvider = providerId || "";
let candidateModels = openCodeProviderModelMap[selectedProvider] || [];
let chosenModel = preferredModel || openCodeModelValueField.text || "";
if (candidateModels.indexOf(chosenModel) < 0)
chosenModel = candidateModels.length > 0 ? candidateModels[0] : "";
setOpenCodeProviderValue(selectedProvider);
openCodeModelCandidates = candidateModels;
openCodeModelSearch = "";
updateFilteredOpenCodeModels("");
setOpenCodeModelValue(chosenModel);
if (openCodeProvidersCombo) {
let pidx = openCodeProviderCandidates.indexOf(selectedProvider);
if (pidx >= 0)
openCodeProvidersCombo.currentIndex = pidx;
}
if (openCodeModelTextField) {
// No manual synchronization needed for openCodeModelTextField as it binds to openCodeModelValueField.text
}
}


function refreshOpenCodeDiscovery(page) {
probeOpenCodeProviders(openCodeUrlField.text);
}


function startOpenCodeServerAutomatically(page) {
discoveryStatus = "Starting OpenCode server automatically...";
let envPrefix = "export PATH=\"$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/local/bin:$HOME/.opencode/bin\"; ";
let startCmd = openCodeStartCommandField.text || "logf=\"${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log\"; nohup opencode serve --port 4096 --hostname 127.0.0.1 >\"$logf\" 2>&1 &";
let cmd = "sh -c " + Sec.rawShellSnippetQuote(envPrefix + startCmd);
utilityDs.connectSource(cmd + " #opencode-autostart");
// After a short delay, attempt discovery again
openCodeAutoStartTimer.restart();
}


function checkAndAutoStartOpenCodeServer(page) {
let url = openCodeServerRoot(openCodeUrlField.text) + "/config/providers";
discoveryStatus = "Checking OpenCode server...";
requestJson(url, {
}, function(obj) {
// Server is already running — just do normal discovery
refreshOpenCodeDiscovery();
}, function(err) {
// Server not reachable — auto-start it
if (autoStartOpenCodeToggle.checked)
startOpenCodeServerAutomatically();
else
discoveryStatus = "OpenCode server check failed: " + err + ". Click \"Start server\" or enable Auto-start.";
});
}


function probeOpenCodeProviders(page, baseUrl) {
let url = openCodeServerRoot(baseUrl) + "/config/providers";
discoveryStatus = "Checking OpenCode server...";
requestJson(url, {
}, function(obj) {
let providers = (obj && obj.providers) || [];
let ids = [];
let defaults = (obj && obj.default) || {
};
let modelsByProvider = {
};
for (let i = 0; i < providers.length; i++) {
let provider = providers[i];
let providerId = provider && provider.id ? provider.id : (provider && provider.name ? provider.name : "");
if (!providerId)
continue;
if (ids.indexOf(providerId) < 0)
ids.push(providerId);
modelsByProvider[providerId] = parseOpenCodeProviderModels(provider);
}
openCodeProviderCandidates = ids;
openCodeProviderModelMap = modelsByProvider;
if (ids.length === 0) {
discoveryStatus = "OpenCode server is reachable, but it returned no configured providers.";
return ;
}
let selectedProvider = activeOpenCodeProvider();
if (ids.indexOf(selectedProvider) < 0)
selectedProvider = ids[0];
let rememberedModel = openCodeModelValueField.text || "";
let fallbackModel = defaults[selectedProvider] || "";
syncOpenCodeProviderSelection(selectedProvider, rememberedModel || fallbackModel);
discoveryStatus = "OpenCode server reachable. Loaded " + ids.length + " providers from /config/providers.";
}, function(err) {
discoveryStatus = "OpenCode server check failed: " + err;
});
}


function probeOpenCodeModels(page, baseUrl, providerId) {
let selectedProvider = providerId || activeOpenCodeProvider();
if (!selectedProvider) {
openCodeModelCandidates = [];
openCodeModelSearch = "";
updateFilteredOpenCodeModels("");
discoveryStatus = "Select an OpenCode provider first.";
return ;
}
syncOpenCodeProviderSelection(selectedProvider, openCodeModelValueField.text);
discoveryStatus = openCodeModelCandidates.length > 0 ? ("Loaded " + openCodeModelCandidates.length + " models for OpenCode provider " + selectedProvider + ".") : ("OpenCode provider " + selectedProvider + " has no models listed by /config/providers.");
}


function refreshRunningOpenCodeSessions(page) {
let baseUrl = openCodeUrlField.text;
let rootUrl = openCodeServerRoot(baseUrl);
let urlSessions = rootUrl + "/session";
let urlStatus = rootUrl + "/session/status";
openCodeSessionsStatus = translate("Loading active OpenCode sessions...");
requestJson(urlStatus, {}, function(statusMap) {
loadSessionsList(urlSessions, statusMap);
}, function(statusErr) {
console.warn("Failed to load session statuses (ignoring): " + statusErr);
loadSessionsList(urlSessions, null);
});
}


function loadSessionsList(page, urlSessions, statusMap) {
requestJson(urlSessions, {}, function(sessionsArray) {
if (Array.isArray(sessionsArray)) {
let list = [];
for (let i = 0; i < sessionsArray.length; i++) {
let s = sessionsArray[i];
if (s && s.id) {
// If statusMap is available, only include sessions loaded in memory (present in statusMap).
// If statusMap is not available (null fallback), include all sessions.
if (statusMap && !statusMap[s.id]) {
continue;
}
let statusObj = (statusMap && statusMap[s.id]) ? statusMap[s.id] : null;
s.statusType = (statusObj && statusObj.type) ? statusObj.type : "active";
list.push(s);
}
}
runningOpenCodeSessions = list;
openCodeSessionsStatus = translate("Found %1 active session(s).").arg(list.length);
} else {
runningOpenCodeSessions = [];
openCodeSessionsStatus = translate("Invalid response format from OpenCode server.");
}
}, function(err) {
runningOpenCodeSessions = [];
openCodeSessionsStatus = translate("Failed to load sessions: %1").arg(err);
});
}


function killRunningOpenCodeSession(page, sessionId) {
let baseUrl = openCodeUrlField.text;
// Refuse any session id that does not match the expected
// character set. This blocks path traversal (`../`) and query
// string injection (`?evil=…`).
let safeSessionId = Sec.validateSessionId(sessionId);
if (safeSessionId === "") {
openCodeSessionsStatus = translate("Refusing to delete session: invalid id.");
return;
}
let url = openCodeServerRoot(baseUrl) + "/session/" + safeSessionId;
openCodeSessionsStatus = translate("Killing session %1...").arg(safeSessionId);
let xhr = new XMLHttpRequest();
xhr.open("DELETE", url, true);
xhr.onreadystatechange = function() {
if (xhr.readyState !== XMLHttpRequest.DONE)
return ;
if (xhr.status >= 200 && xhr.status < 300) {
openCodeSessionsStatus = translate("Session %1 successfully killed.").arg(sessionId);
refreshRunningOpenCodeSessions();
} else {
openCodeSessionsStatus = translate("Failed to kill session: HTTP %1").arg(xhr.status);
}
};
xhr.onerror = function() {
openCodeSessionsStatus = translate("Failed to kill session: Network error.");
};
xhr.send();
}


function kwalletStore(page, targetId, value, isBulk) {
if (!value || value.trim() === "")
return ;
if (!isBulk)
cancelKeyringOps();
let walletName = effectiveWalletName();
let keyName = "kai-chat-" + targetId + "-api-key";
let cmd = walletWriteCommand(walletName, keyName, value);
let ops = page.pendingOps;
ops[cmd] = {
"mode": "store",
"target": targetId,
"bulk": !!isBulk
};
page.pendingOps = ops;
keyringDs.connectSource(cmd);
}


function saveKey(page, targetId, value) {
let val = (value || "").trim();
if (cfg_keyStorageMode === 1)
syncKeysToDisk();
else if (cfg_keyStorageMode === 2)
kwalletStore(targetId, val, false);
}


function kwalletLoad(page, targetId, isBulk) {
if (!isBulk)
cancelKeyringOps();
let walletName = effectiveWalletName();
let keyName = "kai-chat-" + targetId + "-api-key";
let cmd = walletReadCommand(walletName, keyName);
let ops = page.pendingOps;
ops[cmd] = {
"mode": "load",
"target": targetId,
"bulk": !!isBulk
};
page.pendingOps = ops;
keyringDs.connectSource(cmd);
}


function applyLoadedKey(page, targetId, secretValue) {
let normalized = (secretValue || "").trim();
if (normalized === "")
return ;
// Reject only the structured KWallet error sentinels emitted by
// the shell helper. Do NOT reject arbitrary text containing the
// word "wallet" — legitimate API keys (e.g. `sk-wallet-abc123`)
// would otherwise be silently discarded.
if (/^__KAI_(?:LOAD|INIT|STATUS|BULK)__:/.test(normalized))
return ;
let before = apiKeyForTarget(targetId);
if (targetId === "openai")
apiKeyField.text = normalized;
else if (targetId === "anthropic")
anthropicApiKeyField.text = normalized;
else if (targetId === "groq")
groqApiKeyField.text = normalized;
else if (targetId === "deepseek")
deepSeekApiKeyField.text = normalized;
else if (targetId === "minimax")
miniMaxApiKeyField.text = normalized;
else if (targetId === "fireworks")
fireworksApiKeyField.text = normalized;
else if (targetId === "google")
googleApiKeyField.text = normalized;
else if (targetId === "openrouter")
openRouterApiKeyField.text = normalized;
else if (targetId === "mistral")
mistralApiKeyField.text = normalized;
else if (targetId === "cloudflare")
cloudflareApiKeyField.text = normalized;
else if (targetId === "nvidia")
nvidiaApiKeyField.text = normalized;
else if (targetId === "huggingface")
huggingFaceApiKeyField.text = normalized;
else if (targetId === "xai")
xaiApiKeyField.text = normalized;
else if (targetId === "litellm")
litellmApiKeyField.text = normalized;
else if (targetId === "qwen")
qwenApiKeyField.text = normalized;
else if (targetId === "moonshot")
moonshotApiKeyField.text = normalized;
else if (targetId === "mimo")
mimoApiKeyField.text = normalized;
else if (targetId === "maritaca")
maritacaApiKeyField.text = normalized;
let after = apiKeyForTarget(targetId);
if (before !== after && providerBox.currentValue === targetId)
refreshCurrentProviderModels();
}


function keyTargetIds(page) {
return ["openai", "anthropic", "groq", "deepseek", "minimax", "fireworks", "google", "openrouter", "mistral", "cloudflare", "nvidia", "huggingface", "xai", "litellm", "qwen", "moonshot", "mimo", "maritaca"];
}


function apiKeyForTarget(page, targetId) {
if (targetId === "openai")
return apiKeyField.text;
if (targetId === "anthropic")
return anthropicApiKeyField.text;
if (targetId === "groq")
return groqApiKeyField.text;
if (targetId === "deepseek")
return deepSeekApiKeyField.text;
if (targetId === "minimax")
return miniMaxApiKeyField.text;
if (targetId === "fireworks")
return fireworksApiKeyField.text;
if (targetId === "google")
return googleApiKeyField.text;
if (targetId === "openrouter")
return openRouterApiKeyField.text;
if (targetId === "mistral")
return mistralApiKeyField.text;
if (targetId === "cloudflare")
return cloudflareApiKeyField.text;
if (targetId === "nvidia")
return nvidiaApiKeyField.text;
if (targetId === "huggingface")
return huggingFaceApiKeyField.text;
if (targetId === "xai")
return xaiApiKeyField.text;
if (targetId === "litellm")
return litellmApiKeyField.text;
if (targetId === "qwen")
return qwenApiKeyField.text;
if (targetId === "moonshot")
return moonshotApiKeyField.text;
if (targetId === "mimo")
return mimoApiKeyField.text;
if (targetId === "maritaca")
return maritacaApiKeyField.text;
return "";
}


function kwalletLoadAll(page) {
cancelKeyringOps();
let walletName = effectiveWalletName();
debugLog("[KAI-DEBUG] kwalletLoadAll walletName:", walletName);
let cmd = walletBulkReadCommand(walletName) + " #kwallet-refresh-all";
// Scrub the full pipeline (which includes the wallet/folder/appid
// single-quote variables) before logging, so debug-mode output
// does not contain the live wallet identifier.
debugLog("[KAI-DEBUG] kwalletLoadAll command:", Sec.scrubSecrets(cmd));
keyringStatus = "Refreshing API keys from KWallet...";
utilityDs.connectSource(cmd);
}


function kwalletStoreAll(page) {
cancelKeyringOps();
let ids = keyTargetIds();
let count = 0;
for (let i = 0; i < ids.length; i++) {
let value = (apiKeyForTarget(ids[i]) || "").trim();
if (value === "")
continue;
kwalletStore(ids[i], value, true);
count++;
}
keyringStatus = count > 0 ? ("Synced the above key as well as other keys (" + count + " total).") : "No API keys to sync.";
}


function clearAllApiKeyFields(page) {
apiKeyField.text = "";
anthropicApiKeyField.text = "";
groqApiKeyField.text = "";
deepSeekApiKeyField.text = "";
miniMaxApiKeyField.text = "";
fireworksApiKeyField.text = "";
googleApiKeyField.text = "";
openRouterApiKeyField.text = "";
mistralApiKeyField.text = "";
cloudflareApiKeyField.text = "";
nvidiaApiKeyField.text = "";
huggingFaceApiKeyField.text = "";
xaiApiKeyField.text = "";
litellmApiKeyField.text = "";
qwenApiKeyField.text = "";
moonshotApiKeyField.text = "";
mimoApiKeyField.text = "";
maritacaApiKeyField.text = "";
}


function base64Encode(page, str) {
try {
return Qt.btoa(unescape(encodeURIComponent(str)));
} catch (e) {
console.error("base64Encode error:", e);
return "";
}
}


function getHelperPath(page) {
// Resolve the helper path and refuse anything outside the
// package's `contents/ui/` directory. See the same function in
// main.qml for the rationale.
let urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
if (urlStr.indexOf("file://") === 0)
urlStr = urlStr.substring(7);
let path = decodeURIComponent(urlStr);
if (path.indexOf("/contents/ui/") === -1)
return "";
return path;
}


function loadKeysFromPlainConfig(page) {
let payload = {
"configPath": configFilePath
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " load_config_keys " + Sec.quoteForShell(b64Payload);
utilityDs.connectSource(cmd + " #plainconfig-load");
}


function applyPlainConfigKeys(page, keys) {
apiKeyField.text = keys["apiKey"] || "";
anthropicApiKeyField.text = keys["anthropicApiKey"] || "";
groqApiKeyField.text = keys["groqApiKey"] || "";
deepSeekApiKeyField.text = keys["deepSeekApiKey"] || "";
miniMaxApiKeyField.text = keys["miniMaxApiKey"] || "";
fireworksApiKeyField.text = keys["fireworksApiKey"] || "";
googleApiKeyField.text = keys["googleApiKey"] || "";
openRouterApiKeyField.text = keys["openRouterApiKey"] || "";
mistralApiKeyField.text = keys["mistralApiKey"] || "";
cloudflareApiKeyField.text = keys["cloudflareApiKey"] || "";
nvidiaApiKeyField.text = keys["nvidiaApiKey"] || "";
huggingFaceApiKeyField.text = keys["huggingFaceApiKey"] || "";
xaiApiKeyField.text = keys["xaiApiKey"] || "";
litellmApiKeyField.text = keys["litellmApiKey"] || "";
qwenApiKeyField.text = keys["qwenApiKey"] || "";
moonshotApiKeyField.text = keys["moonshotApiKey"] || "";
mimoApiKeyField.text = keys["mimoApiKey"] || "";
maritacaApiKeyField.text = keys["maritacaApiKey"] || "";
}


function writeKeysToDiskAndOpen(page) {
let keysPayload = {
"apiKey": apiKeyField.text,
"anthropicApiKey": anthropicApiKeyField.text,
"groqApiKey": groqApiKeyField.text,
"deepSeekApiKey": deepSeekApiKeyField.text,
"miniMaxApiKey": miniMaxApiKeyField.text,
"fireworksApiKey": fireworksApiKeyField.text,
"googleApiKey": googleApiKeyField.text,
"openRouterApiKey": openRouterApiKeyField.text,
"mistralApiKey": mistralApiKeyField.text,
"cloudflareApiKey": cloudflareApiKeyField.text,
"nvidiaApiKey": nvidiaApiKeyField.text,
"huggingFaceApiKey": huggingFaceApiKeyField.text,
"xaiApiKey": xaiApiKeyField.text,
"litellmApiKey": litellmApiKeyField.text,
"qwenApiKey": qwenApiKeyField.text,
"moonshotApiKey": moonshotApiKeyField.text,
"mimoApiKey": mimoApiKeyField.text,
"maritacaApiKey": maritacaApiKeyField.text
};
let payload = {
"configPath": configFilePath,
"keys": keysPayload
};
let b64Payload = base64Encode(JSON.stringify(payload));
let safeConfigPath = Sec.validateFilePath(configFilePath);
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " sync_config_keys " + Sec.quoteForShell(b64Payload);
if (safeConfigPath !== "")
cmd += " && xdg-open " + Sec.quoteForShell(safeConfigPath);
utilityDs.connectSource(cmd + " #open-config");
}


function syncKeysToDisk(page) {
// Write current key fields to ~/.config/kdeaichatrc (plain-config extra copy).
// cfg_ aliases handle saving to the Plasma config automatically on OK/Apply.
let keysPayload = {
"apiKey": apiKeyField.text,
"anthropicApiKey": anthropicApiKeyField.text,
"groqApiKey": groqApiKeyField.text,
"deepSeekApiKey": deepSeekApiKeyField.text,
"miniMaxApiKey": miniMaxApiKeyField.text,
"fireworksApiKey": fireworksApiKeyField.text,
"googleApiKey": googleApiKeyField.text,
"openRouterApiKey": openRouterApiKeyField.text,
"mistralApiKey": mistralApiKeyField.text,
"cloudflareApiKey": cloudflareApiKeyField.text,
"nvidiaApiKey": nvidiaApiKeyField.text,
"huggingFaceApiKey": huggingFaceApiKeyField.text,
"xaiApiKey": xaiApiKeyField.text,
"litellmApiKey": litellmApiKeyField.text,
"qwenApiKey": qwenApiKeyField.text,
"moonshotApiKey": moonshotApiKeyField.text,
"mimoApiKey": mimoApiKeyField.text,
"maritacaApiKey": maritacaApiKeyField.text
};
let payload = {
"configPath": configFilePath,
"keys": keysPayload
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " sync_config_keys " + Sec.quoteForShell(b64Payload);
utilityDs.connectSource(cmd + " #plainconfig-sync");
}


function clearKeysFromDisk(page) {
let payload = {
"configPath": configFilePath,
"keys": ['apiKey', 'anthropicApiKey', 'groqApiKey', 'deepSeekApiKey', 'miniMaxApiKey', 'fireworksApiKey', 'googleApiKey', 'openRouterApiKey', 'mistralApiKey', 'cloudflareApiKey', 'nvidiaApiKey', 'huggingFaceApiKey', 'xaiApiKey', 'litellmApiKey', 'qwenApiKey', 'moonshotApiKey', 'mimoApiKey', 'maritacaApiKey']
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " clear_config_keys " + Sec.quoteForShell(b64Payload);
utilityDs.connectSource(cmd + " #plainconfig-clear");
plasmoid.configuration.apiKey = "";
plasmoid.configuration.anthropicApiKey = "";
plasmoid.configuration.groqApiKey = "";
plasmoid.configuration.deepSeekApiKey = "";
plasmoid.configuration.miniMaxApiKey = "";
plasmoid.configuration.fireworksApiKey = "";
plasmoid.configuration.googleApiKey = "";
plasmoid.configuration.openRouterApiKey = "";
plasmoid.configuration.mistralApiKey = "";
plasmoid.configuration.cloudflareApiKey = "";
plasmoid.configuration.nvidiaApiKey = "";
plasmoid.configuration.huggingFaceApiKey = "";
plasmoid.configuration.xaiApiKey = "";
plasmoid.configuration.litellmApiKey = "";
plasmoid.configuration.qwenApiKey = "";
plasmoid.configuration.moonshotApiKey = "";
plasmoid.configuration.mimoApiKey = "";
plasmoid.configuration.maritacaApiKey = "";
}


function saveGeneralSettingsOnly(page) {
plasmoid.configuration.appDisplayName = appDisplayNameField.text;
plasmoid.configuration.appearanceMode = appearanceModeCombo.currentIndex;
plasmoid.configuration.keyStorageMode = cfg_keyStorageMode;
plasmoid.configuration.provider = cfg_provider;
plasmoid.configuration.baseUrl = baseUrlField.text;
plasmoid.configuration.model = modelField.text;
plasmoid.configuration.anthropicModel = anthropicModelField.text;
plasmoid.configuration.groqBaseUrl = groqBaseUrlField.text;
plasmoid.configuration.groqModel = groqModelField.text;
plasmoid.configuration.deepSeekBaseUrl = deepSeekBaseUrlField.text;
plasmoid.configuration.deepSeekModel = deepSeekModelField.text;
plasmoid.configuration.miniMaxBaseUrl = miniMaxBaseUrlField.text;
plasmoid.configuration.miniMaxModel = miniMaxModelField.text;
plasmoid.configuration.fireworksBaseUrl = fireworksBaseUrlField.text;
plasmoid.configuration.fireworksModel = fireworksModelField.text;
plasmoid.configuration.googleBaseUrl = googleBaseUrlField.text;
plasmoid.configuration.googleModel = googleModelField.text;
plasmoid.configuration.openRouterBaseUrl = openRouterBaseUrlField.text;
plasmoid.configuration.openRouterModel = openRouterModelField.text;
plasmoid.configuration.mistralBaseUrl = mistralBaseUrlField.text;
plasmoid.configuration.mistralModel = mistralModelField.text;
plasmoid.configuration.cloudflareBaseUrl = cloudflareBaseUrlField.text;
plasmoid.configuration.cloudflareModel = cloudflareModelField.text;
plasmoid.configuration.nvidiaBaseUrl = nvidiaBaseUrlField.text;
plasmoid.configuration.nvidiaModel = nvidiaModelField.text;
plasmoid.configuration.huggingFaceBaseUrl = huggingFaceBaseUrlField.text;
plasmoid.configuration.huggingFaceModel = huggingFaceModelField.text;
plasmoid.configuration.xaiBaseUrl = xaiBaseUrlField.text;
plasmoid.configuration.xaiModel = xaiModelField.text;
plasmoid.configuration.lmStudioBaseUrl = lmStudioBaseUrlField.text;
plasmoid.configuration.lmStudioModel = lmStudioModelField.text;
plasmoid.configuration.localBaseUrl = localBaseUrlField.text;
plasmoid.configuration.localModel = localModelField.text;
plasmoid.configuration.ollamaBaseUrl = ollamaBaseUrlField.text;
plasmoid.configuration.ollamaModel = ollamaModelField.text;
plasmoid.configuration.litellmBaseUrl = litellmBaseUrlField.text;
plasmoid.configuration.litellmModel = litellmModelField.text;
plasmoid.configuration.qwenBaseUrl = qwenBaseUrlField.text;
plasmoid.configuration.qwenApiKey = qwenApiKeyField.text;
plasmoid.configuration.qwenModel = qwenModelField.text;
plasmoid.configuration.moonshotBaseUrl = moonshotBaseUrlField.text;
plasmoid.configuration.moonshotApiKey = moonshotApiKeyField.text;
plasmoid.configuration.moonshotModel = moonshotModelField.text;
plasmoid.configuration.mimoBaseUrl = mimoBaseUrlField.text;
plasmoid.configuration.mimoApiKey = mimoApiKeyField.text;
plasmoid.configuration.mimoModel = mimoModelField.text;
plasmoid.configuration.maritacaBaseUrl = maritacaBaseUrlField.text;
plasmoid.configuration.maritacaApiKey = maritacaApiKeyField.text;
plasmoid.configuration.maritacaModel = maritacaModelField.text;
plasmoid.configuration.language = cfg_language || "";
plasmoid.configuration.showInteractiveGuides = showGuidesToggle.checked;
plasmoid.configuration.autoStartOpenCodeServer = autoStartOpenCodeToggle.checked;
plasmoid.configuration.useOpenCode = openCodeToggle.checked;
plasmoid.configuration.playNotificationSound = playSoundToggle.checked;
plasmoid.configuration.openCodeUrl = openCodeUrlField.text;
plasmoid.configuration.openCodeModel = openCodeModelValueField.text;
plasmoid.configuration.openCodeProvider = openCodeProviderValueField.text;
plasmoid.configuration.openCodeStartCommand = openCodeStartCommandField.text;
plasmoid.configuration.openCodeStopCommand = openCodeStopCommandField.text;
plasmoid.configuration.openCodeAutoKill = openCodeAutoKillToggle.checked;
plasmoid.configuration.openCodeAutoKillMinutes = openCodeAutoKillMinutesSpin.value;
plasmoid.configuration.kwalletName = walletNameField.text;
plasmoid.configuration.systemPrompt = systemPromptArea.text;
plasmoid.configuration.memoryEnabled = memoryEnabledToggle.checked;
plasmoid.configuration.userMemory = userMemoryArea.text;
plasmoid.configuration.globalContextEnabled = globalContextEnabledToggle.checked;
plasmoid.configuration.globalContextLimit = globalContextLimitSpin.value;
plasmoid.configuration.globalContextAutoCompact = globalContextAutoCompactToggle.checked;
plasmoid.configuration.globalContextCompactThreshold = globalContextCompactThresholdSpin.value;
}


function cancelKeyringOps(page) {
let running = keyringDs.connectedSources;
for (let i = 0; i < running.length; i++) keyringDs.disconnectSource(running[i])
let utilityRunning = utilityDs.connectedSources;
for (let j = 0; j < utilityRunning.length; j++) {
if (utilityRunning[j].indexOf("#kwallet-") >= 0)
utilityDs.disconnectSource(utilityRunning[j]);
}
pendingOps = ({
});
}


function resetToDefaults(page) {
appDisplayNameField.text = "KDE AI Chat";
providerBox.currentIndex = 0;
baseUrlField.text = "https://api.openai.com/v1";
apiKeyField.text = "";
modelField.text = "gpt-4o-mini";
anthropicApiKeyField.text = "";
anthropicModelField.text = "claude-3-5-sonnet-latest";
groqBaseUrlField.text = "https://api.groq.com/openai/v1";
groqApiKeyField.text = "";
groqModelField.text = "llama-3.3-70b-versatile";
deepSeekBaseUrlField.text = "https://api.deepseek.com";
deepSeekApiKeyField.text = "";
deepSeekModelField.text = "deepseek-v4-pro";
miniMaxBaseUrlField.text = "https://api.minimax.io/v1";
miniMaxApiKeyField.text = "";
miniMaxModelField.text = "MiniMax-M2.7";
fireworksBaseUrlField.text = "https://api.fireworks.ai/inference/v1";
fireworksApiKeyField.text = "";
fireworksModelField.text = "accounts/fireworks/models/llama-v3p3-70b-instruct";
googleBaseUrlField.text = "https://generativelanguage.googleapis.com/v1beta/openai/";
googleApiKeyField.text = "";
googleModelField.text = "gemini-3-flash-preview";
openRouterBaseUrlField.text = "https://openrouter.ai/api/v1";
openRouterApiKeyField.text = "";
openRouterModelField.text = "openai/gpt-4o-mini";
mistralBaseUrlField.text = "https://api.mistral.ai/v1";
mistralApiKeyField.text = "";
mistralModelField.text = "mistral-small-latest";
cloudflareBaseUrlField.text = "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1";
cloudflareApiKeyField.text = "";
cloudflareModelField.text = "@cf/meta/llama-3.1-8b-instruct";
nvidiaBaseUrlField.text = "https://integrate.api.nvidia.com/v1";
nvidiaApiKeyField.text = "";
nvidiaModelField.text = "meta/llama-3.1-70b-instruct";
huggingFaceBaseUrlField.text = "https://router.huggingface.co/v1";
huggingFaceApiKeyField.text = "";
huggingFaceModelField.text = "openai/gpt-oss-120b:groq";
xaiBaseUrlField.text = "https://api.x.ai/v1";
xaiApiKeyField.text = "";
xaiModelField.text = "grok-2-latest";
lmStudioBaseUrlField.text = "http://localhost:1234/v1";
lmStudioModelField.text = "";
localBaseUrlField.text = "http://localhost:11434/v1";
localModelField.text = "llama3.2";
ollamaBaseUrlField.text = "http://localhost:11434/v1";
ollamaModelField.text = "llama3.2";
litellmBaseUrlField.text = "http://localhost:4000/v1";
litellmApiKeyField.text = "";
litellmModelField.text = "";
qwenBaseUrlField.text = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1";
qwenApiKeyField.text = "";
qwenModelField.text = "qwen-max";
moonshotBaseUrlField.text = "https://api.moonshot.ai/v1";
moonshotApiKeyField.text = "";
moonshotModelField.text = "moonshot-v1-8k";
mimoBaseUrlField.text = "https://api.xiaomimimo.com/v1";
mimoApiKeyField.text = "";
mimoModelField.text = "mimo-v2-pro";
maritacaBaseUrlField.text = "https://chat.maritaca.ai/api";
maritacaApiKeyField.text = "";
maritacaModelField.text = "sabia-4";
languageCombo.currentIndex = 0;
showGuidesToggle.checked = true;
autoStartOpenCodeToggle.checked = false;
openCodeToggle.checked = false;
openCodeUrlField.text = "http://127.0.0.1:4096/v1";
openCodeProviderValueField.text = "";
openCodeModelValueField.text = "";
openCodeStartCommandField.text = "logf=\"${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log\"; nohup opencode serve --port 4096 --hostname 127.0.0.1 >\"$logf\" 2>&1 & echo OpenCode start command launched.";
openCodeStopCommandField.text = "pkill -f opencode >/dev/null 2>&1 && echo OpenCode stop command launched. || echo No OpenCode process matched.";
openCodeAutoKillToggle.checked = true;
openCodeAutoKillMinutesSpin.value = 5;
walletNameField.text = availableWalletNames.length > 0 ? availableWalletNames[0] : "kdewallet";
systemPromptArea.text = "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.";
memoryEnabledToggle.checked = false;
userMemoryArea.text = "";
customHistoryPathField.text = StandardPaths.writableLocation(StandardPaths.ConfigLocation);
globalContextEnabledToggle.checked = true;
globalContextLimitSpin.value = 1;
globalContextAutoCompactToggle.checked = false;
globalContextCompactThresholdSpin.value = 10;
providerModelCandidates = [];
openCodeProviderCandidates = [];
openCodeModelCandidates = [];
openCodeProviderModelMap = ({
});
discoveryStatus = "Settings reset to defaults.";
}


function schedAutoSetup(page) {
let srcPath = String(Qt.resolvedUrl("../scripts/kde-ai-scheduler.py")).replace("file://", "");
let serviceContent = "[Unit]\nDescription=KDE AI Chat Scheduler Daemon\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=/usr/bin/python3 %h/.local/share/kdeaichat/kde-ai-scheduler.py\nRestart=on-failure\nRestartSec=30\nStandardOutput=journal\nStandardError=journal\nExecReload=/bin/kill -HUP $MAINPID\nKillMode=process\n\n[Install]\nWantedBy=default.target\n";
let payload = {
"srcPath": srcPath,
"destPath": schedulerScriptPath,
"serviceContent": serviceContent
};
let payloadStr = JSON.stringify(payload);
// Audit 5.6: skip I/O when content is unchanged since last run.
if (payloadStr === page._lastSchedSetupPayload)
return;
page._lastSchedSetupPayload = payloadStr;
let b64Payload = base64Encode(payloadStr);
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " setup_scheduler_service " + Sec.quoteForShell(b64Payload);
utilityDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-auto-setup");
}


function pollSchedulerState(page) {
utilityDs.connectSource("sh -c 'pgrep -f kde-ai-scheduler.py > /dev/null 2>&1 && echo SCHED_RUNNING || echo SCHED_STOPPED' #sched-poll-" + Date.now());
}


function schedLoadSchedules(page) {
let safePath = Sec.validateFilePath(schedulesFilePath);
if (safePath === "")
return;
let cmd = "cat " + Sec.quoteForShell(safePath) + " 2>/dev/null || echo '{\"schedules\":[],\"history\":[]}'";
utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-load");
}


function schedSaveSchedules(page, items) {
page.schedulerList = items;
page.schedSaveAll();
}


function getHistoryLimitValue(page) {
return 100;
}


function schedSaveAll(page) {
page.schedSaving = true;
let all = [];
// Add active
for (let i = 0; i < page.schedulerList.length; i++) {
let s = Object.assign({}, page.schedulerList[i]);
s.archived = false;
all.push(s);
}
// Add archived
for (let j = 0; j < page.schedulerArchivedList.length; j++) {
let sa = Object.assign({}, page.schedulerArchivedList[j]);
sa.archived = true;
all.push(sa);
}
let limit = page.getHistoryLimitValue();
let hist = page.schedulerHistory || [];
if (hist.length > limit) {
hist = hist.slice(hist.length - limit);
page.schedulerHistory = hist;
}
let payload = {
"version": 1,
"schedules": all,
"history": hist,
"settings": {
"executeMissedSchedules": !!executeMissedSchedulesToggle.checked,
"historyLimit": limit
}
};
let b64Payload = base64Encode(JSON.stringify(payload));
let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " save_all_schedules " + Sec.quoteForShell(b64Payload);
utilityDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-save");
}


function schedTriggerNow(page, index) {
let copy = page.schedulerList.slice();
if (index < 0 || index >= copy.length)
return ;
let s = JSON.parse(JSON.stringify(copy[index]));
s.triggerNow = true;
copy[index] = s;
page.schedulerList = copy;
page.schedSaveAll();
}


function schedMakeUuid(page) {
return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
let r = Math.random() * 16 | 0;
return (c === "x" ? r : (r & 3 | 8)).toString(16);
});
}


function openPrefilledScheduleDialog(page, pId, pName) {
if (!pId || pId === "")
return;
let now = new Date();
now.setMinutes(now.getMinutes() + 5);
scheduleDialog.draft = {
"id": page.schedMakeUuid(),
"name": "",
"enabled": true,
"chatId": pId,
"chatName": pName || "Chat",
"message": "",
"taskType": "single",
"startDate": now.toISOString(),
"schedType": "days",
"schedEvery": 1,
"schedTime": "09:00",
"schedDays": [1],
"schedDayOfMonth": 1,
"limitEnabled": false,
"limitCount": 5,
"notify": true,
"createdAt": new Date().toISOString()
};
scheduleDialog.editingIndex = -2;
scheduleDialog.open();
// Clear configuration values immediately so it doesn't pop up again next time!
if (typeof page.cfg_preselectedChatId !== "undefined") {
page.cfg_preselectedChatId = "";
page.cfg_preselectedChatName = "";
}
if (plasmoid.configuration && "preselectedChatId" in plasmoid.configuration) {
plasmoid.configuration.preselectedChatId = "";
plasmoid.configuration.preselectedChatName = "";
}
}


function schedDefaultBaseUrl(page, provider) {
let urls = {
"openai": "https://api.openai.com/v1",
"anthropic": "https://api.anthropic.com/v1",
"groq": "https://api.groq.com/openai/v1",
"google": "https://generativelanguage.googleapis.com/v1beta/openai/",
"deepseek": "https://api.deepseek.com",
"mistral": "https://api.mistral.ai/v1",
"openrouter": "https://openrouter.ai/api/v1",
"xai": "https://api.x.ai/v1",
"nvidia": "https://integrate.api.nvidia.com/v1",
"fireworks": "https://api.fireworks.ai/inference/v1",
"minimax": "https://api.minimax.io/v1",
"cloudflare": "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1",
"huggingface": "https://router.huggingface.co/v1",
"ollama": "http://localhost:11434/v1",
"lmstudio": "http://localhost:1234/v1",
"local": "http://localhost:11434/v1",
"litellm": "http://localhost:4000/v1",
"qwen": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
"moonshot": "https://api.moonshot.ai/v1",
"mimo": "https://api.xiaomimimo.com/v1",
"maritaca": "https://chat.maritaca.ai/api"
};
return urls[provider] || "https://api.openai.com/v1";
}


function schedHumanCron(page, expr) {
if (!expr)
return "No schedule";
let parts = expr.trim().split(/\s+/);
if (parts.length !== 5)
return expr;
let min = parts[0], hr = parts[1], dom = parts[2], mon = parts[3], dow = parts[4];
if (min === "0" && hr !== "*" && dom === "*" && mon === "*") {
let h = parseInt(hr), ampm = h >= 12 ? "PM" : "AM", h12 = h % 12 || 12;
let dayStr = dow === "*" ? "every day" : dow === "1-5" ? "weekdays" : dow === "6,0" || dow === "0,6" ? "weekends" : "on selected days";
return "Daily at " + h12 + ":00 " + ampm + " " + dayStr;
}
if (hr.startsWith && hr.startsWith("*/"))
return "Every " + hr.slice(2) + " hours";
return expr;
}

