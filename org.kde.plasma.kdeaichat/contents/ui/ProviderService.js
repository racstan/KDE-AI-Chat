.pragma library

var PROVIDER_CONFIGS = {
    "anthropic": {
        type: "anthropic",
        configKey: "anthropicApiKey",
        modelKey: "anthropicModel",
        defaultBaseUrl: "",
        defaultModel: "",
        allowEmptyKey: false
    },
    "openai": {
        type: "openai-compat",
        configKey: "apiKey",
        modelKey: "model",
        defaultBaseUrl: "https://api.openai.com/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "local": {
        type: "openai-compat",
        configKey: "",
        modelKey: "localModel",
        defaultBaseUrl: "http://localhost:11434/v1",
        defaultModel: "",
        allowEmptyKey: true
    },
    "ollama": {
        type: "openai-compat",
        configKey: "",
        modelKey: "ollamaModel",
        defaultBaseUrl: "http://localhost:11434/v1",
        defaultModel: "",
        allowEmptyKey: true
    },
    "litellm": {
        type: "openai-compat",
        configKey: "litellmApiKey",
        modelKey: "litellmModel",
        baseUrlKey: "litellmBaseUrl",
        defaultBaseUrl: "http://localhost:4000/v1",
        defaultModel: "",
        allowEmptyKey: true
    },
    "lmstudio": {
        type: "openai-compat",
        configKey: "",
        modelKey: "lmStudioModel",
        baseUrlKey: "lmStudioBaseUrl",
        defaultBaseUrl: "http://localhost:1234/v1",
        defaultModel: "",
        allowEmptyKey: true
    },
    "groq": {
        type: "openai-compat",
        configKey: "groqApiKey",
        modelKey: "groqModel",
        baseUrlKey: "groqBaseUrl",
        defaultBaseUrl: "https://api.groq.com/openai/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "deepseek": {
        type: "openai-compat",
        configKey: "deepSeekApiKey",
        modelKey: "deepSeekModel",
        baseUrlKey: "deepSeekBaseUrl",
        defaultBaseUrl: "https://api.deepseek.com",
        defaultModel: "",
        allowEmptyKey: false
    },
    "minimax": {
        type: "openai-compat",
        configKey: "miniMaxApiKey",
        modelKey: "miniMaxModel",
        baseUrlKey: "miniMaxBaseUrl",
        defaultBaseUrl: "https://api.minimax.io/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "fireworks": {
        type: "openai-compat",
        configKey: "fireworksApiKey",
        modelKey: "fireworksModel",
        baseUrlKey: "fireworksBaseUrl",
        defaultBaseUrl: "https://api.fireworks.ai/inference/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "google": {
        type: "openai-compat",
        configKey: "googleApiKey",
        modelKey: "googleModel",
        baseUrlKey: "googleBaseUrl",
        defaultBaseUrl: "https://generativelanguage.googleapis.com/v1beta/openai/",
        defaultModel: "",
        allowEmptyKey: false
    },
    "openrouter": {
        type: "openai-compat",
        configKey: "openRouterApiKey",
        modelKey: "openRouterModel",
        baseUrlKey: "openRouterBaseUrl",
        defaultBaseUrl: "https://openrouter.ai/api/v1",
        defaultModel: "",
        allowEmptyKey: false,
        hasHeaders: true
    },
    "mistral": {
        type: "openai-compat",
        configKey: "mistralApiKey",
        modelKey: "mistralModel",
        baseUrlKey: "mistralBaseUrl",
        defaultBaseUrl: "https://api.mistral.ai/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "cloudflare": {
        type: "openai-compat",
        configKey: "cloudflareApiKey",
        modelKey: "cloudflareModel",
        baseUrlKey: "cloudflareBaseUrl",
        defaultBaseUrl: "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "nvidia": {
        type: "openai-compat",
        configKey: "nvidiaApiKey",
        modelKey: "nvidiaModel",
        baseUrlKey: "nvidiaBaseUrl",
        defaultBaseUrl: "https://integrate.api.nvidia.com/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "huggingface": {
        type: "openai-compat",
        configKey: "huggingFaceApiKey",
        modelKey: "huggingFaceModel",
        baseUrlKey: "huggingFaceBaseUrl",
        defaultBaseUrl: "https://router.huggingface.co/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "xai": {
        type: "openai-compat",
        configKey: "xaiApiKey",
        modelKey: "xaiModel",
        baseUrlKey: "xaiBaseUrl",
        defaultBaseUrl: "https://api.x.ai/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "qwen": {
        type: "openai-compat",
        configKey: "qwenApiKey",
        modelKey: "qwenModel",
        baseUrlKey: "qwenBaseUrl",
        defaultBaseUrl: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "moonshot": {
        type: "openai-compat",
        configKey: "moonshotApiKey",
        modelKey: "moonshotModel",
        baseUrlKey: "moonshotBaseUrl",
        defaultBaseUrl: "https://api.moonshot.ai/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "mimo": {
        type: "openai-compat",
        configKey: "mimoApiKey",
        modelKey: "mimoModel",
        baseUrlKey: "mimoBaseUrl",
        defaultBaseUrl: "https://api.xiaomimimo.com/v1",
        defaultModel: "",
        allowEmptyKey: false
    },
    "maritaca": {
        type: "openai-compat",
        configKey: "maritacaApiKey",
        modelKey: "maritacaModel",
        baseUrlKey: "maritacaBaseUrl",
        defaultBaseUrl: "https://chat.maritaca.ai/api",
        defaultModel: "sabia-4",
        allowEmptyKey: false
    }
};

var DISPLAY_NAMES = {
    "openai": "OpenAI",
    "anthropic": "Anthropic",
    "groq": "Groq",
    "deepseek": "DeepSeek",
    "minimax": "MiniMax",
    "fireworks": "Fireworks",
    "google": "Google Gemini",
    "openrouter": "OpenRouter",
    "mistral": "Mistral",
    "cloudflare": "Cloudflare",
    "nvidia": "NVIDIA NIM",
    "huggingface": "Hugging Face",
    "xai": "xAI",
    "litellm": "LiteLLM Proxy",
    "lmstudio": "LM Studio",
    "local": "Local",
    "ollama": "Ollama",
    "qwen": "Qwen",
    "moonshot": "Moonshot",
    "mimo": "MiMo",
    "maritaca": "Maritaca"
};

var API_KEY_CONFIG_MAP = {
    "openai": "apiKey",
    "anthropic": "anthropicApiKey",
    "groq": "groqApiKey",
    "deepseek": "deepSeekApiKey",
    "minimax": "miniMaxApiKey",
    "fireworks": "fireworksApiKey",
    "google": "googleApiKey",
    "openrouter": "openRouterApiKey",
    "mistral": "mistralApiKey",
    "cloudflare": "cloudflareApiKey",
    "nvidia": "nvidiaApiKey",
    "huggingface": "huggingFaceApiKey",
    "xai": "xaiApiKey",
    "litellm": "litellmApiKey",
    "qwen": "qwenApiKey",
    "moonshot": "moonshotApiKey",
    "mimo": "mimoApiKey",
    "maritaca": "maritacaApiKey"
};

function getProviderDisplayName(providerId) {
    return DISPLAY_NAMES[providerId] || providerId || "Selected provider";
}

function getProviderConfig(providerId, configuration) {
    var entry = PROVIDER_CONFIGS[providerId];
    if (!entry) {
        return {
            "type": "openai-compat",
            "baseUrl": (configuration.baseUrl || "https://api.openai.com/v1"),
            "apiKey": (configuration.apiKey || "").trim(),
            "model": configuration.model || "",
            "headers": null,
            "allowEmptyKey": false
        };
    }

    var apiKey = "";
    if (entry.configKey) {
        apiKey = (configuration[entry.configKey] || "").trim();
    }

    var model = configuration[entry.modelKey] || entry.defaultModel || "";
    var baseUrl = "";
    if (entry.type !== "anthropic") {
        var baseUrlKey = entry.baseUrlKey || (providerId === "openai" ? "baseUrl" : null);
        baseUrl = (baseUrlKey ? configuration[baseUrlKey] : "") || entry.defaultBaseUrl || "";
    }

    var headers = null;
    if (entry.hasHeaders && providerId === "openrouter") {
        headers = {};
        var referer = configuration.openRouterReferer || "https://github.com/racstan/KDE-AI-Chat";
        var title = configuration.openRouterTitle || "KDE AI Chat";
        headers["HTTP-Referer"] = referer;
        headers["X-Title"] = title;
    }

    return {
        "type": entry.type,
        "baseUrl": baseUrl,
        "apiKey": apiKey,
        "model": model,
        "headers": headers,
        "allowEmptyKey": entry.allowEmptyKey
    };
}

function getApiKeyConfigKey(targetId) {
    return API_KEY_CONFIG_MAP[targetId] || null;
}

function getSupportedProviders() {
    return Object.keys(PROVIDER_CONFIGS);
}
