.pragma library

// Providers for direct API mode.
//
// The user's providers are one list, stored as JSON in the `providersJson`
// setting: [{id, name, type, baseUrl, model, variant?, headers?}]. `type` is
// "openai-compat", "anthropic" or "image". An image provider (AI Horde,
// Pollinations) makes pictures from the message instead of answering with text:
// it also has `service` (see IMAGE_SERVICES), `accepted` (the user switched it on
// after reading what it sends where) and `options` {width, height, steps, n, seed}. `variant` is the id of the model's variant
// (reasoning / thinking level, Variants.js) chosen for it; only the id is stored.
// API keys are not part of it: each lives in KWallet under the provider's id
// (see store/Wallet.qml).
//
// PRESETS fill in a new provider's URL and type. Versions before 1.4.0 had a
// fixed set of providers with their own settings (LEGACY); legacyProviders()
// turns those into list entries with the same ids, so KWallet keys and
// per-chat provider choices keep working.

var PRESETS = [
    {"id": "openai", "name": "OpenAI", "type": "openai-compat", "baseUrl": "https://api.openai.com/v1"},
    {"id": "anthropic", "name": "Anthropic", "type": "anthropic", "baseUrl": "https://api.anthropic.com/v1"},
    {"id": "openrouter", "name": "OpenRouter", "type": "openai-compat", "baseUrl": "https://openrouter.ai/api/v1", "model": "openrouter/auto",
     "headers": {"HTTP-Referer": "https://github.com/racstan/KDE-AI-Chat", "X-Title": "KDE AI Chat"}},
    {"id": "google", "name": "Google Gemini", "type": "openai-compat", "baseUrl": "https://generativelanguage.googleapis.com/v1beta/openai"},
    {"id": "groq", "name": "Groq", "type": "openai-compat", "baseUrl": "https://api.groq.com/openai/v1"},
    {"id": "deepseek", "name": "DeepSeek", "type": "openai-compat", "baseUrl": "https://api.deepseek.com"},
    {"id": "mistral", "name": "Mistral", "type": "openai-compat", "baseUrl": "https://api.mistral.ai/v1"},
    {"id": "xai", "name": "xAI", "type": "openai-compat", "baseUrl": "https://api.x.ai/v1"},
    {"id": "nvidia", "name": "NVIDIA NIM", "type": "openai-compat", "baseUrl": "https://integrate.api.nvidia.com/v1"},
    {"id": "fireworks", "name": "Fireworks", "type": "openai-compat", "baseUrl": "https://api.fireworks.ai/inference/v1"},
    {"id": "huggingface", "name": "Hugging Face", "type": "openai-compat", "baseUrl": "https://router.huggingface.co/v1"},
    {"id": "perplexity", "name": "Perplexity", "type": "openai-compat", "baseUrl": "https://api.perplexity.ai"},
    {"id": "minimax", "name": "MiniMax", "type": "openai-compat", "baseUrl": "https://api.minimax.io/v1"},
    {"id": "qwen", "name": "Qwen", "type": "openai-compat", "baseUrl": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"},
    {"id": "moonshot", "name": "Moonshot", "type": "openai-compat", "baseUrl": "https://api.moonshot.ai/v1"},
    {"id": "cloudflare", "name": "Cloudflare Workers AI", "type": "openai-compat", "baseUrl": "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1"},
    {"id": "ollama", "name": "Ollama (local)", "type": "openai-compat", "baseUrl": "http://localhost:11434/v1", "local": true},
    {"id": "lmstudio", "name": "LM Studio (local)", "type": "openai-compat", "baseUrl": "http://localhost:1234/v1", "local": true},
    {"id": "llamacpp", "name": "llama.cpp server (local)", "type": "openai-compat", "baseUrl": "http://localhost:8080/v1", "local": true},
    {"id": "litellm", "name": "LiteLLM proxy", "type": "openai-compat", "baseUrl": "http://localhost:4000/v1", "local": true},
    {"id": "custom", "name": "Other OpenAI-compatible", "type": "openai-compat", "baseUrl": ""},
    // Image services: the chat's messages become pictures. Off until the user switches them on.
    {"id": "aihorde", "name": "AI Horde (images)", "type": "image", "service": "horde", "baseUrl": "https://aihorde.net/api/v2", "model": ""},
    {"id": "pollinations", "name": "Pollinations.ai (images, your key)", "type": "image", "service": "pollinations", "baseUrl": "https://gen.pollinations.ai", "model": "z-image-turbo"},
    {"id": "pollinations_free", "name": "Pollinations.ai (older free service)", "type": "image", "service": "pollinations-legacy", "baseUrl": "https://image.pollinations.ai", "model": "sana"}
];

// The image services: display name and whether a key is needed.
var IMAGE_SERVICES = {
    "horde": {"name": "AI Horde", "keyRequired": false},
    "pollinations": {"name": "Pollinations", "keyRequired": true},
    "pollinations-legacy": {"name": "Pollinations", "keyRequired": false}
};

// Pre-1.4.0 provider settings: id -> [baseUrl setting, model setting, default URL].
var LEGACY = {
    "openai": ["baseUrl", "model", "https://api.openai.com/v1"],
    "anthropic": ["", "anthropicModel", "https://api.anthropic.com/v1"],
    "local": ["localBaseUrl", "localModel", "http://localhost:11434/v1"],
    "ollama": ["ollamaBaseUrl", "ollamaModel", "http://localhost:11434/v1"],
    "litellm": ["litellmBaseUrl", "litellmModel", "http://localhost:4000/v1"],
    "lmstudio": ["lmStudioBaseUrl", "lmStudioModel", "http://localhost:1234/v1"],
    "groq": ["groqBaseUrl", "groqModel", "https://api.groq.com/openai/v1"],
    "deepseek": ["deepSeekBaseUrl", "deepSeekModel", "https://api.deepseek.com"],
    "minimax": ["miniMaxBaseUrl", "miniMaxModel", "https://api.minimax.io/v1"],
    "fireworks": ["fireworksBaseUrl", "fireworksModel", "https://api.fireworks.ai/inference/v1"],
    "google": ["googleBaseUrl", "googleModel", "https://generativelanguage.googleapis.com/v1beta/openai/"],
    "openrouter": ["openRouterBaseUrl", "openRouterModel", "https://openrouter.ai/api/v1"],
    "mistral": ["mistralBaseUrl", "mistralModel", "https://api.mistral.ai/v1"],
    "cloudflare": ["cloudflareBaseUrl", "cloudflareModel", "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1"],
    "nvidia": ["nvidiaBaseUrl", "nvidiaModel", "https://integrate.api.nvidia.com/v1"],
    "huggingface": ["huggingFaceBaseUrl", "huggingFaceModel", "https://router.huggingface.co/v1"],
    "xai": ["xaiBaseUrl", "xaiModel", "https://api.x.ai/v1"],
    "qwen": ["qwenBaseUrl", "qwenModel", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"],
    "moonshot": ["moonshotBaseUrl", "moonshotModel", "https://api.moonshot.ai/v1"],
    "mimo": ["mimoBaseUrl", "mimoModel", "https://api.xiaomimimo.com/v1"],
    "maritaca": ["maritacaBaseUrl", "maritacaModel", "https://chat.maritaca.ai/api"],
    "perplexity": ["perplexityBaseUrl", "perplexityModel", "https://api.perplexity.ai/router/v1"]
};
var LEGACY_NAMES = {"local": "Local", "mimo": "MiMo", "maritaca": "Maritaca", "lmstudio": "LM Studio", "ollama": "Ollama", "litellm": "LiteLLM Proxy"};
var LOCAL_IDS = ["local", "ollama", "lmstudio", "litellm"];

function presetById(id) {
    for (var i = 0; i < PRESETS.length; i++)
        if (PRESETS[i].id === id) return PRESETS[i];
    return null;
}

// Picture settings of an image provider: whole numbers inside what the services allow; anything else is dropped.
function _imageOptions(options) {
    var o = options && typeof options === "object" ? options : {};
    var limits = {"width": [64, 1024], "height": [64, 1024], "steps": [1, 50], "n": [1, 4], "seed": [0, 2147483647]};
    var out = {};
    for (var key in limits) {
        var n = Number(o[key]);
        if (o[key] !== undefined && o[key] !== null && o[key] !== "" && isFinite(n) && Math.round(n) >= limits[key][0] && Math.round(n) <= limits[key][1])
            out[key] = Math.round(n);
    }
    return out;
}

function _clean(entry) {
    if (!entry || !entry.id) return null;
    var type = entry.type === "anthropic" ? "anthropic" : (entry.type === "image" && IMAGE_SERVICES[entry.service] ? "image" : "openai-compat");
    var out = {"id": String(entry.id), "name": String(entry.name || entry.id), "type": type,
               "baseUrl": String(entry.baseUrl || "").trim(), "model": String(entry.model || "").trim()};
    if (type === "image") {
        out.service = entry.service;
        out.accepted = entry.accepted === true;
        out.options = _imageOptions(entry.options);
    }
    if (entry.headers && typeof entry.headers === "object") out.headers = entry.headers;
    if (entry.variant !== undefined && String(entry.variant).trim() !== "") out.variant = String(entry.variant).trim();
    return out;
}

// The user's providers. Empty until the 1.4.0 migration has run.
function parseProviders(configuration) {
    var raw = configuration ? String(configuration.providersJson || "") : "";
    var list = [];
    try { list = raw ? JSON.parse(raw) : []; } catch (e) { list = []; }
    var out = [];
    for (var i = 0; Array.isArray(list) && i < list.length; i++) {
        var entry = _clean(list[i]);
        if (entry) out.push(entry);
    }
    return out;
}

function serializeProviders(list) {
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var entry = _clean(list[i]);
        if (entry) out.push(entry);
    }
    return JSON.stringify(out);
}

// A new id for a provider made from `presetId`, unique within `list`.
function newProviderId(list, presetId) {
    var base = presetId && presetId !== "custom" ? presetId : "custom";
    var taken = {};
    for (var i = 0; i < list.length; i++) taken[list[i].id] = true;
    if (!taken[base] && base !== "custom") return base;
    var n = 2;
    while (taken[base + "_" + n]) n++;
    return base + "_" + n;
}

// A provider entry for one pre-1.4.0 provider id, from its old settings.
function _legacyEntry(id, configuration) {
    var spec = LEGACY[id];
    var preset = presetById(id);
    var baseUrl = (spec[0] && configuration[spec[0]]) || spec[2];
    var entry = {"id": id, "name": (preset && preset.name) || LEGACY_NAMES[id] || id,
                 "type": id === "anthropic" ? "anthropic" : "openai-compat",
                 "baseUrl": String(baseUrl).trim(), "model": String(configuration[spec[1]] || "").trim()};
    if (id === "openrouter")
        entry.headers = {"HTTP-Referer": configuration.openRouterReferer || preset.headers["HTTP-Referer"],
                         "X-Title": configuration.openRouterTitle || preset.headers["X-Title"]};
    return entry;
}

// Builds the provider list from pre-1.4.0 settings. A built-in provider is
// kept if it has a key in KWallet (`walletKeys`), is the selected provider, or
// had a model set; custom providers are always kept.
function legacyProviders(configuration, walletKeys) {
    var list = [];
    var keys = walletKeys || {};
    for (var id in LEGACY) {
        var spec = LEGACY[id];
        var used = !!keys[id] || configuration.provider === id || String(configuration[spec[1]] || "").trim() !== "";
        if (used) list.push(_legacyEntry(id, configuration));
    }
    var customs = [];
    try { customs = JSON.parse(configuration.customProvidersJson || "[]"); } catch (e) { customs = []; }
    for (var i = 0; Array.isArray(customs) && i < customs.length; i++) {
        var entry = _clean(customs[i]);
        if (entry) list.push(entry);
    }
    return list;
}

// Runtime settings for a provider id. The API key comes from KWallet, so
// `apiKey` is always "" here.
function getProviderConfig(providerId, configuration) {
    var list = parseProviders(configuration);
    var entry = null;
    for (var i = 0; i < list.length; i++)
        if (list[i].id === providerId) entry = list[i];
    // Before the migration has run, read the old settings directly.
    if (!entry && list.length === 0 && LEGACY[providerId])
        entry = _legacyEntry(providerId, configuration || {});
    if (!entry)
        return {"type": "openai-compat", "baseUrl": "", "apiKey": "", "model": "", "variant": "", "headers": null, "allowEmptyKey": false, "found": false};
    var local = LOCAL_IDS.indexOf(entry.id) >= 0 || /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])[:/]/i.test(entry.baseUrl);
    var config = {"type": entry.type, "baseUrl": entry.baseUrl, "apiKey": "", "model": entry.model, "variant": entry.variant || "",
                  "headers": entry.headers || null, "allowEmptyKey": local, "found": true};
    if (entry.type === "image") {
        // AI Horde works without a key (anonymously), the older free Pollinations service too.
        config.service = entry.service;
        config.accepted = entry.accepted === true;
        config.options = entry.options || {};
        config.allowEmptyKey = !IMAGE_SERVICES[entry.service].keyRequired;
    }
    return config;
}

// The user's image providers (entries of the provider list).
function imageProviders(configuration) {
    return parseProviders(configuration).filter(function(entry) { return entry.type === "image"; });
}

// The image provider /image uses: the one chosen in the `imageProvider` setting if it still exists,
// otherwise the first one the user has; "" when there is none.
function defaultImageProvider(configuration) {
    var list = imageProviders(configuration);
    var chosen = configuration ? String(configuration.imageProvider || "") : "";
    for (var i = 0; i < list.length; i++)
        if (list[i].id === chosen) return chosen;
    return list.length > 0 ? list[0].id : "";
}

function getProviderDisplayName(providerId, configuration) {
    var list = parseProviders(configuration);
    for (var i = 0; i < list.length; i++)
        if (list[i].id === providerId) return list[i].name;
    var preset = presetById(providerId);
    return (preset && preset.name) || LEGACY_NAMES[providerId] || providerId || "Selected provider";
}

// Indexes into `list` (entries with `id`, or plain ids) with the default
// first; the rest keep their order. The saved list is never reordered.
function defaultFirstOrder(list, defaultId) {
    var first = [];
    var rest = [];
    for (var i = 0; i < (list || []).length; i++) {
        var id = list[i] && typeof list[i] === "object" ? list[i].id : list[i];
        if (defaultId && id === defaultId && first.length === 0) first.push(i);
        else rest.push(i);
    }
    return first.concat(rest);
}

// `list` (entries or plain ids) as a new array with the default first.
function sortDefaultFirst(list, defaultId) {
    return defaultFirstOrder(list, defaultId).map(function(i) { return list[i]; });
}

// Provider ids the user can pick from, the default provider first.
function getSupportedProviders(configuration) {
    var list = parseProviders(configuration);
    if (list.length === 0 && configuration)
        list = legacyProviders(configuration, {});
    var ids = [];
    for (var i = 0; i < list.length; i++) ids.push(list[i].id);
    return sortDefaultFirst(ids, configuration ? String(configuration.provider || "") : "");
}

function getConfiguredProviders(configuration) {
    return getSupportedProviders(configuration);
}

function isHttpUrlAllowed(url) {
    if (url === null || url === undefined) return false;
    var value = String(url).trim();
    if (!/^(?:http|https):\/\//i.test(value) || /[\u0000-\u001f\u007f]/.test(value)) return false;
    var authority = value.substring(value.indexOf("://") + 3).split(/[\/?#]/, 1)[0];
    return authority !== "" && !/[\s<>"'`]/.test(authority) && authority.indexOf("@") < 0;
}
