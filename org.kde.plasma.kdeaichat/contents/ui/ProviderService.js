.pragma library

/**
 * @typedef {Object} ProviderEntry
 * @property {string} type            `"openai-compat"` or `"anthropic"`.
 * @property {string} configKey       `plasmoid.configuration` key holding the API key (empty if none).
 * @property {string} modelKey        Configuration key holding the model name.
 * @property {string} [baseUrlKey]    Configuration key for a user-editable base URL.
 * @property {string} [defaultBaseUrl]  Fallback base URL if `baseUrlKey` is unset/empty.
 * @property {string} [defaultModel]  Default model name suggestion.
 * @property {boolean} [allowEmptyKey]  If true, requests work without an API key.
 * @property {boolean} [hasHeaders]   If true, the provider needs custom HTTP headers (e.g. OpenRouter).
 */

/**
 * @typedef {Object} ProviderConfig
 * @property {string} type            Wire protocol family.
 * @property {string} baseUrl         Resolved base URL.
 * @property {string} apiKey          Resolved (trimmed) API key.
 * @property {string} model           Resolved model name.
 * @property {?Object} headers        Optional extra HTTP headers.
 * @property {boolean} allowEmptyKey  Whether the provider tolerates empty key.
 */

let PROVIDER_CONFIGS = {
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

let DISPLAY_NAMES = {
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

let API_KEY_CONFIG_MAP = {
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

/**
 * ProviderService — data-driven provider configuration registry.
 *
 * Single source of truth for every supported LLM provider. All
 * previously hard-coded if/else chains in main.qml and
 * ConfigGeneral.qml delegate here so adding a new provider only
 * requires editing the `PROVIDER_CONFIGS` map below.
 *
 * @module ProviderService
 */

/**
 * Display name for a provider, falling back to the id and then to a
 * generic label.
 *
 * @param {string} providerId  Provider id (e.g. `"openai"`).
 * @returns {string} Human-readable name, or the id, or `"Selected provider"`.
 */
function getProviderDisplayName(providerId) {
    return DISPLAY_NAMES[providerId] || providerId || "Selected provider";
}

/**
 * Build a runtime provider config object by resolving all keys against
 * the user's `plasmoid.configuration` map. Returns a plain object the
 * request layer can consume directly.
 *
 * Output shape:
 *   - `type`: `"openai-compat"` or `"anthropic"`
 *   - `baseUrl`: resolved base URL (omitted for anthropic)
 *   - `apiKey`: trimmed key (empty string if `configKey` is empty)
 *   - `model`: resolved model name
 *   - `headers`: extra HTTP headers (only set for OpenRouter)
 *   - `allowEmptyKey`: whether the provider works without a key
 *     (e.g. local Ollama, LM Studio)
 *
 * If `providerId` is unknown, falls back to OpenAI-compatible defaults
 * driven by the `baseUrl`/`apiKey`/`model` configuration fields.
 *
 * @param {string} providerId  Provider id.
 * @param {Object} configuration  The user's `plasmoid.configuration` map.
 * @returns {{type: string, baseUrl: string, apiKey: string, model: string, headers: ?Object, allowEmptyKey: boolean}}
 *   Runtime provider config.
 */
function getProviderConfig(providerId, configuration) {
    let entry = PROVIDER_CONFIGS[providerId];
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

    let apiKey = "";
    if (entry.configKey) {
        apiKey = (configuration[entry.configKey] || "").trim();
    }

    let model = configuration[entry.modelKey] || entry.defaultModel || "";
    let baseUrl = "";
    if (entry.type !== "anthropic") {
        let baseUrlKey = entry.baseUrlKey || (providerId === "openai" ? "baseUrl" : null);
        baseUrl = (baseUrlKey ? configuration[baseUrlKey] : "") || entry.defaultBaseUrl || "";
    }

    let headers = null;
    if (entry.hasHeaders && providerId === "openrouter") {
        headers = {};
        let referer = configuration.openRouterReferer || "https://github.com/racstan/KDE-AI-Chat";
        let title = configuration.openRouterTitle || "KDE AI Chat";
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

/**
 * Look up the `plasmoid.configuration` key that holds a given
 * provider's API key.
 *
 * @param {string} targetId  Provider id.
 * @returns {?string} The configuration key, or `null` if the provider
 *   has no separate API key field (e.g. local providers).
 */
function getApiKeyConfigKey(targetId) {
    return API_KEY_CONFIG_MAP[targetId] || null;
}

/**
 * List all provider ids that have a dedicated API key configuration
 * field. Used by the KWallet bulk reader to know which entries to pull.
 *
 * @returns {string[]} Provider ids (e.g. `["openai", "anthropic", ...]`).
 */
function getApiKeyProviderIds() {
    return Object.keys(API_KEY_CONFIG_MAP);
}

/**
 * List all provider ids known to the registry, including local
 * providers (Ollama, LM Studio, etc.) that have no API key field.
 *
 * @returns {string[]} Provider ids.
 */
function getSupportedProviders() {
    return Object.keys(PROVIDER_CONFIGS);
}
