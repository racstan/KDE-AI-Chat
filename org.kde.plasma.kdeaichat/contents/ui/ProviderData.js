// ProviderData.js — Central provider definitions to eliminate 21x if/else chains

var providerList = [
    { id: "openai",      name: "OpenAI",              needsKey: true,  type: "openai-compat", defaultUrl: "https://api.openai.com/v1",                                         defaultModel: "gpt-4o-mini" },
    { id: "anthropic",   name: "Anthropic",           needsKey: true,  type: "anthropic",     defaultUrl: "https://api.anthropic.com/v1",                                      defaultModel: "claude-3-5-sonnet-latest" },
    { id: "groq",        name: "Groq",                needsKey: true,  type: "openai-compat", defaultUrl: "https://api.groq.com/openai/v1",                                    defaultModel: "llama-3.3-70b-versatile" },
    { id: "deepseek",    name: "DeepSeek",            needsKey: true,  type: "openai-compat", defaultUrl: "https://api.deepseek.com",                                           defaultModel: "deepseek-v4-pro" },
    { id: "minimax",     name: "MiniMax",             needsKey: true,  type: "openai-compat", defaultUrl: "https://api.minimax.io/v1",                                           defaultModel: "MiniMax-M2.7" },
    { id: "fireworks",   name: "Fireworks",           needsKey: true,  type: "openai-compat", defaultUrl: "https://api.fireworks.ai/inference/v1",                               defaultModel: "accounts/fireworks/models/llama-v3p3-70b-instruct" },
    { id: "google",      name: "Google Gemini",       needsKey: true,  type: "openai-compat", defaultUrl: "https://generativelanguage.googleapis.com/v1beta/openai/",              defaultModel: "gemini-3-flash-preview" },
    { id: "openrouter",  name: "OpenRouter",          needsKey: true,  type: "openai-compat", defaultUrl: "https://openrouter.ai/api/v1",                                        defaultModel: "openai/gpt-4o-mini" },
    { id: "mistral",     name: "Mistral",             needsKey: true,  type: "openai-compat", defaultUrl: "https://api.mistral.ai/v1",                                           defaultModel: "mistral-small-latest" },
    { id: "cloudflare",  name: "Cloudflare Workers AI", needsKey: true,  type: "openai-compat", defaultUrl: "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1", defaultModel: "@cf/meta/llama-3.1-8b-instruct" },
    { id: "nvidia",      name: "NVIDIA NIM",          needsKey: true,  type: "openai-compat", defaultUrl: "https://integrate.api.nvidia.com/v1",                                  defaultModel: "meta/llama-3.1-70b-instruct" },
    { id: "huggingface", name: "Hugging Face",        needsKey: true,  type: "openai-compat", defaultUrl: "https://router.huggingface.co/v1",                                     defaultModel: "openai/gpt-oss-120b:groq" },
    { id: "xai",         name: "xAI Grok",            needsKey: true,  type: "openai-compat", defaultUrl: "https://api.x.ai/v1",                                                defaultModel: "grok-2-latest" },
    { id: "lmstudio",    name: "LM Studio",           needsKey: false, type: "openai-compat", defaultUrl: "http://localhost:1234/v1",                                            defaultModel: "" },
    { id: "local",       name: "Local / OpenAI-compatible", needsKey: false, type: "openai-compat", defaultUrl: "http://localhost:11434/v1",                                        defaultModel: "llama3.2" },
    { id: "ollama",      name: "Ollama",              needsKey: false, type: "openai-compat", defaultUrl: "http://localhost:11434/v1",                                            defaultModel: "llama3.2" },
    { id: "litellm",     name: "LiteLLM",             needsKey: true,  type: "openai-compat", defaultUrl: "http://localhost:4000/v1",                                             defaultModel: "" },
    { id: "qwen",        name: "Alibaba Qwen",        needsKey: true,  type: "openai-compat", defaultUrl: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",               defaultModel: "qwen-max" },
    { id: "moonshot",    name: "Moonshot AI",         needsKey: true,  type: "openai-compat", defaultUrl: "https://api.moonshot.ai/v1",                                          defaultModel: "moonshot-v1-8k" },
    { id: "mimo",        name: "Xiaomi MiMo",         needsKey: true,  type: "openai-compat", defaultUrl: "https://api.xiaomimimo.com/v1",                                       defaultModel: "mimo-v2-pro" },
    { id: "maritaca",    name: "Maritaca AI",         needsKey: true,  type: "openai-compat", defaultUrl: "https://chat.maritaca.ai/api",                                        defaultModel: "sabia-4" }
];

function getProvider(id) {
    for (var i = 0; i < providerList.length; i++) {
        if (providerList[i].id === id)
            return providerList[i];
    }
    return providerList[0];
}

function displayName(id) {
    var p = getProvider(id);
    return p ? p.name : (id || "Selected provider");
}

function needsApiKey(id) {
    var p = getProvider(id);
    return p ? p.needsKey : true;
}

function defaultUrl(id) {
    var p = getProvider(id);
    return p ? p.defaultUrl : "";
}

function defaultModel(id) {
    var p = getProvider(id);
    return p ? p.defaultModel : "";
}

// Multi-word provider IDs need camelCase config prefixes (deepseek → deepSeek, etc.)
var _prefixMap = {
    "openai": "",
    "deepseek": "deepSeek",
    "minimax": "miniMax",
    "openrouter": "openRouter",
    "huggingface": "huggingFace",
    "lmstudio": "lmStudio"
};

function _configPrefix(id) {
    return _prefixMap[id] !== undefined ? _prefixMap[id] : id;
}

function configField(id, suffix) {
    var prefix = _configPrefix(id);
    if (prefix === "" && suffix === "ApiKey") return "apiKey";
    if (prefix === "" && suffix === "Model") return "model";
    if (prefix === "" && suffix === "BaseUrl") return "baseUrl";
    return prefix + suffix;
}

function idList() {
    var ids = [];
    for (var i = 0; i < providerList.length; i++)
        ids.push(providerList[i].id);
    return ids;
}

function comboModel() {
    var m = [];
    for (var i = 0; i < providerList.length; i++)
        m.push({ value: providerList[i].id, text: providerList[i].name });
    return m;
}

function walletKeyName(targetId) {
    return "kai-chat-" + targetId + "-api-key";
}

function apiKeyConfigName(targetId) {
    return configField(targetId, "ApiKey");
}

// Build provider runtime config object used by main.qml send functions
function buildRuntimeConfig(providerId, config) {
    var p = getProvider(providerId);
    if (!p)
        return null;

    var cfg = {
        type: p.type,
        apiKey: (config[configField(p.id, "ApiKey")] || "").trim(),
        model: config[configField(p.id, "Model")] || p.defaultModel,
        baseUrl: config[configField(p.id, "BaseUrl")] || p.defaultUrl,
        headers: null,
        allowEmptyKey: !p.needsKey
    };

    // OpenRouter has extra headers
    if (providerId === "openrouter") {
        cfg.headers = {
            "HTTP-Referer": config.openRouterReferer || "https://github.com/racstan/KDE-AI-Chat",
            "X-Title": config.openRouterTitle || "KDE AI Chat"
        };
    }

    return cfg;
}
