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

var _guideTexts = {
    "openai": "<b>OpenAI Setup Guide:</b><br/>1. Get your API key at <b>platform.openai.com \u2192 API Keys</b> (starts with <code>sk-</code>).<br/>2. Paste it into the <b>OpenAI key</b> field below.<br/>3. Choose a model from the <b>OpenAI model</b> dropdown or type one (e.g. <code>gpt-4o</code>, <code>gpt-4o-mini</code>).<br/>4. (Optional) Override the base URL only if using a compatible proxy.<br/>5. Click <b>Apply</b>/<b>OK</b> to save.",
    "anthropic": "<b>Anthropic Setup Guide:</b><br/>1. Get your API key at <b>console.anthropic.com \u2192 API Keys</b> (starts with <code>sk-ant-</code>).<br/>2. Paste it into the <b>Anthropic key</b> field below.<br/>3. Choose a model (e.g. <code>claude-opus-4-5</code>, <code>claude-3-5-sonnet-latest</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "groq": "<b>Groq Setup Guide:</b><br/>1. Get your free API key at <b>console.groq.com \u2192 API Keys</b>.<br/>2. Paste it into the <b>Groq key</b> field below.<br/>3. Choose a model (e.g. <code>llama-3.3-70b-versatile</code>, <code>gemma2-9b-it</code>) \u2014 Groq inference is extremely fast.<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "deepseek": "<b>DeepSeek Setup Guide:</b><br/>1. Get your API key at <b>platform.deepseek.com \u2192 API Keys</b>.<br/>2. Paste it into the <b>DeepSeek key</b> field below.<br/>3. Choose a model (e.g. <code>deepseek-chat</code> or <code>deepseek-reasoner</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "minimax": "<b>MiniMax Setup Guide:</b><br/>1. Get your API key at <b>www.minimaxi.com \u2192 API Key</b>.<br/>2. Paste it into the <b>MiniMax key</b> field below.<br/>3. Choose a model (e.g. <code>MiniMax-M2.7</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "fireworks": "<b>Fireworks AI Setup Guide:</b><br/>1. Get your API key at <b>fireworks.ai \u2192 Account \u2192 API Keys</b>.<br/>2. Paste it into the <b>Fireworks key</b> field below.<br/>3. Choose a model (e.g. <code>accounts/fireworks/models/llama-v3p3-70b-instruct</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "google": "<b>Google Gemini Setup Guide:</b><br/>1. Get your free API key at <b>aistudio.google.com \u2192 Get API Key</b>.<br/>2. Paste it into the <b>Google key</b> field below.<br/>3. Choose a model (e.g. <code>gemini-2.5-flash-preview-05-20</code>, <code>gemini-2.0-flash</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "openrouter": "<b>OpenRouter Setup Guide:</b><br/>1. Get your API key at <b>openrouter.ai \u2192 Keys</b>.<br/>2. Paste it into the <b>OpenRouter key</b> field below.<br/>3. Choose any model from 100+ providers (e.g. <code>openai/gpt-4o-mini</code>, <code>google/gemini-flash-1.5</code>, <code>openrouter/auto</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "mistral": "<b>Mistral Setup Guide:</b><br/>1. Get your API key at <b>console.mistral.ai \u2192 API Keys</b>.<br/>2. Paste it into the <b>Mistral key</b> field below.<br/>3. Choose a model (e.g. <code>mistral-small-latest</code>, <code>mistral-large-latest</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "cloudflare": "<b>Cloudflare Workers AI Setup Guide:</b><br/>1. Log in to <b>dash.cloudflare.com \u2192 AI \u2192 Workers AI</b>.<br/>2. Copy your <b>Account ID</b> from the right sidebar and replace <code>YOUR_ACCOUNT_ID</code> in the <b>Cloudflare URL</b> field below.<br/>3. Create an API Token (with Workers AI permission) at <b>dash.cloudflare.com \u2192 Profile \u2192 API Tokens</b> and paste it into the <b>Cloudflare key</b> field.<br/>4. Choose a model (e.g. <code>@cf/meta/llama-3.1-8b-instruct</code>).<br/>5. Click <b>Apply</b>/<b>OK</b> to save.",
    "nvidia": "<b>NVIDIA NIM Setup Guide:</b><br/>1. Get your API key at <b>build.nvidia.com \u2192 Get API Key</b>.<br/>2. Paste it into the <b>NVIDIA key</b> field below.<br/>3. Choose a NIM model (e.g. <code>meta/llama-3.1-70b-instruct</code>, <code>nvidia/nemotron-4-340b-instruct</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "huggingface": "<b>Hugging Face Router Setup Guide:</b><br/>1. Get your access token at <b>huggingface.co \u2192 Settings \u2192 Access Tokens</b> (use a token with Inference permissions).<br/>2. Paste it into the <b>Hugging Face key</b> field below.<br/>3. Enter a supported inference model (e.g. <code>openai/gpt-oss-120b:groq</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "xai": "<b>xAI (Grok) Setup Guide:</b><br/>1. Get your API key at <b>console.x.ai \u2192 API Keys</b>.<br/>2. Paste it into the <b>xAI key</b> field below.<br/>3. Choose a model (e.g. <code>grok-3-mini</code>, <code>grok-2-latest</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "lmstudio": "<b>LM Studio Setup Guide:</b><br/>1. Download and open <b>LM Studio</b> (lmstudio.ai) \u2014 no API key needed.<br/>2. In LM Studio, go to the <b>Local Server</b> tab and load a model.<br/>3. Click <b>Start Server</b> in LM Studio (default URL: <code>http://localhost:1234/v1</code>).<br/>4. Enter the loaded model name in the <b>LM Studio model</b> field below.<br/>5. Click <b>Apply</b>/<b>OK</b> to save.",
    "local": "<b>Local Server (OpenAI-compatible) Setup Guide:</b><br/>1. Start your local server (e.g. <b>vLLM</b>, <b>llama.cpp</b>, <b>Jan</b>) \u2014 no API key needed.<br/>2. Enter the server\u2019s base URL in the <b>Local URL</b> field below (e.g. <code>http://localhost:8000/v1</code>).<br/>3. Enter the model identifier your server is serving in the <b>Local model</b> field.<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "ollama": "<b>Ollama Setup Guide:</b><br/>1. Install Ollama from <b>ollama.com</b> and run it \u2014 no API key needed.<br/>2. Pull a model by running <code>ollama pull llama3.2</code> in a terminal.<br/>3. Ollama starts automatically (default URL: <code>http://localhost:11434</code>).<br/>4. Verify/update the <b>Ollama URL</b> field below and enter your model name (e.g. <code>llama3.2</code>).<br/>5. Click <b>Apply</b>/<b>OK</b> to save.",
    "litellm": "<b>LiteLLM Proxy Setup Guide:</b><br/>1. Install LiteLLM: <code>pip install litellm</code> \u2014 no API key needed for the proxy itself.<br/>2. Start your proxy: <code>litellm --model ollama/llama3.2</code> (or your preferred model).<br/>3. Enter the proxy URL in the <b>LiteLLM URL</b> field below (default: <code>http://localhost:4000</code>).<br/>4. Enter the model identifier in the <b>LiteLLM model</b> field.<br/>5. Click <b>Apply</b>/<b>OK</b> to save.",
    "qwen": "<b>Qwen (Alibaba Cloud) Setup Guide:</b><br/>1. Register at <b>dashscope.aliyuncs.com</b> and go to <b>API Keys</b>.<br/>2. Paste your key into the <b>Qwen key</b> field below.<br/>3. Choose a model (e.g. <code>qwen-max</code>, <code>qwen-plus</code>, <code>qwen-turbo</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "moonshot": "<b>Moonshot AI (Kimi) Setup Guide:</b><br/>1. Get your API key at <b>platform.moonshot.cn \u2192 API Keys</b>.<br/>2. Paste it into the <b>Moonshot key</b> field below.<br/>3. Choose a model (e.g. <code>moonshot-v1-8k</code>, <code>moonshot-v1-32k</code>, <code>moonshot-v1-128k</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "mimo": "<b>MiMo (Xiaomi) Setup Guide:</b><br/>1. Get access at <b>api.xiaomimimo.com</b> and copy your API key.<br/>2. Paste it into the <b>MiMo key</b> field below.<br/>3. Choose a model (e.g. <code>mimo-v2-pro</code>, <code>mimo-v2</code>).<br/>4. Click <b>Apply</b>/<b>OK</b> to save.",
    "maritaca": "<b>Maritaca AI (Sabi\u00e1) Setup Guide:</b><br/>1. Get your API key at <b>chat.maritaca.ai \u2192 Settings \u2192 API Keys</b>.<br/>2. Paste it into the <b>Maritaca key</b> field below.<br/>3. Choose a model (e.g. <code>sabia-4</code> \u2014 optimised for Portuguese).<br/>4. The default URL <code>https://chat.maritaca.ai/api</code> is correct \u2014 do not change it.<br/>5. Click <b>Apply</b>/<b>OK</b> to save."
};

function guideText(id) {
    return _guideTexts[id] || "";
}

function hasUrlField(id) {
    return id === "openai" || id === "lmstudio" || id === "local" || id === "ollama" || id === "litellm";
}

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
