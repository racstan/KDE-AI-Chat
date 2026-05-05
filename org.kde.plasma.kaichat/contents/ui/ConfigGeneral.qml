import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support

// KDE Plasma 6 configuration page – Kai Chat
Kirigami.ScrollablePage {
    id: configPage
    title: "Kai Chat – Settings"

    // ── Model suggestion lists ─────────────────────────────────────────────
    readonly property var openaiModels: [
        "gpt-4o", "gpt-4o-mini",
        "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano",
        "gpt-4-turbo", "gpt-4",
        "o1", "o1-mini", "o3", "o3-mini", "o4-mini"
    ]
    readonly property var anthropicModels: [
        "claude-sonnet-4-5",
        "claude-3-7-sonnet-20250219",
        "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022",
        "claude-3-opus-20240229", "claude-3-haiku-20240307"
    ]
    readonly property var geminiModels: [
        "gemini-2.0-flash", "gemini-2.0-flash-lite",
        "gemini-1.5-pro", "gemini-1.5-flash",
        "gemini-2.5-pro-preview-05-06"
    ]
    readonly property var mistralModels: [
        "mistral-large-latest", "mistral-small-latest",
        "mistral-medium-latest", "codestral-latest",
        "open-mixtral-8x22b", "open-codestral-mamba"
    ]
    readonly property var grokModels: [
        "grok-3", "grok-3-fast", "grok-3-mini", "grok-3-mini-fast",
        "grok-2-1212", "grok-vision-beta"
    ]
    readonly property var deepseekModels: [
        "deepseek-chat", "deepseek-reasoner"
    ]
    readonly property var nvidiaModels: [
        "nvidia/llama-3.1-nemotron-70b-instruct",
        "nvidia/llama-3.3-70b-instruct",
        "nvidia/mistral-nemo-12b-instruct",
        "meta/llama-3.1-405b-instruct",
        "meta/llama-3.1-70b-instruct",
        "mistralai/mistral-large-2-instruct"
    ]
    readonly property var cerebrasModels: [
        "llama3.1-8b", "llama3.1-70b",
        "llama-4-scout-17b-16e-instruct",
        "qwen-3-32b"
    ]
    readonly property var cfModels: [
        "@cf/meta/llama-3.1-8b-instruct",
        "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
        "@cf/mistral/mistral-7b-instruct-v0.2",
        "@cf/google/gemma-3-12b-it",
        "@cf/qwen/qwq-32b"
    ]
    readonly property var hfModels: [
        "meta-llama/Llama-3.2-3B-Instruct",
        "meta-llama/Llama-3.1-8B-Instruct",
        "mistralai/Mistral-7B-Instruct-v0.3",
        "Qwen/Qwen2.5-7B-Instruct",
        "microsoft/Phi-3.5-mini-instruct"
    ]
    readonly property var openrouterModels: [
        "openai/gpt-4o-mini", "openai/gpt-4o",
        "anthropic/claude-3.5-sonnet", "anthropic/claude-3-haiku",
        "google/gemini-2.0-flash", "mistralai/mistral-large",
        "deepseek/deepseek-chat", "x-ai/grok-3",
        "meta-llama/llama-3.1-8b-instruct:free"
    ]

    // ── CLI availability tester ────────────────────────────────────────────
    P5Support.DataSource {
        id: testDs
        engine: "executable"
        connectedSources: []
        property var resultLabel: null
        onNewData: function(sourceName, data) {
            var found = ((data["stdout"] || "").trim() !== "")
            if (resultLabel) {
                resultLabel.color = found ? Kirigami.Theme.positiveTextColor
                                          : Kirigami.Theme.negativeTextColor
                resultLabel.text  = found ? "✔ found" : "✘ not found"
                resultLabel = null
            }
            disconnectSource(sourceName)
        }
    }
    P5Support.DataSource {
        id: secretToolDs
        engine: "executable"
        connectedSources: []
        property var statusLabel: null
        onNewData: function(sourceName, data) {
            var out = (data["stdout"] || "").trim()
            var err = (data["stderr"] || "").trim()
            if (statusLabel) {
                if (err !== "") {
                    statusLabel.color = Kirigami.Theme.negativeTextColor
                    statusLabel.text = "✘ " + err
                } else {
                    statusLabel.color = Kirigami.Theme.positiveTextColor
                    statusLabel.text = out !== "" ? out : "✔ Done"
                }
                statusLabel = null
            }
            disconnectSource(sourceName)
        }
    }

    function testCli(cmd, lbl) {
        lbl.text  = "checking…"
        lbl.color = Kirigami.Theme.textColor
        testDs.resultLabel = lbl
        testDs.connectSource("which " + cmd)
    }

    function providerKeyValue(provider) {
        switch (provider) {
        case "openai": return plasmoid.configuration.openaiApiKey
        case "anthropic": return plasmoid.configuration.anthropicApiKey
        case "gemini": return plasmoid.configuration.geminiApiKey
        case "mistral": return plasmoid.configuration.mistralApiKey
        case "grok": return plasmoid.configuration.grokApiKey
        case "deepseek": return plasmoid.configuration.deepseekApiKey
        case "nvidia": return plasmoid.configuration.nvidiaApiKey
        case "cerebras": return plasmoid.configuration.cerebrasApiKey
        case "cloudflare": return plasmoid.configuration.cfApiToken
        case "huggingface": return plasmoid.configuration.hfApiKey
        case "openrouter": return plasmoid.configuration.openrouterApiKey
        case "litellm": return plasmoid.configuration.litellmApiKey
        default: return ""
        }
    }

    function clearProviderKeyValue(provider) {
        switch (provider) {
        case "openai": plasmoid.configuration.openaiApiKey = ""; break
        case "anthropic": plasmoid.configuration.anthropicApiKey = ""; break
        case "gemini": plasmoid.configuration.geminiApiKey = ""; break
        case "mistral": plasmoid.configuration.mistralApiKey = ""; break
        case "grok": plasmoid.configuration.grokApiKey = ""; break
        case "deepseek": plasmoid.configuration.deepseekApiKey = ""; break
        case "nvidia": plasmoid.configuration.nvidiaApiKey = ""; break
        case "cerebras": plasmoid.configuration.cerebrasApiKey = ""; break
        case "cloudflare": plasmoid.configuration.cfApiToken = ""; break
        case "huggingface": plasmoid.configuration.hfApiKey = ""; break
        case "openrouter": plasmoid.configuration.openrouterApiKey = ""; break
        case "litellm": plasmoid.configuration.litellmApiKey = ""; break
        }
    }

    function storeKeyInSecretService(provider, lbl) {
        var key = providerKeyValue(provider)
        if (!key || key === "") {
            lbl.color = Kirigami.Theme.negativeTextColor
            lbl.text = "✘ No key in field to store"
            return
        }
        var escaped = key.replace(/'/g, "'\\''")
        var cmd = "sh -lc \"printf '%s' '" + escaped + "' | secret-tool store --label='Kai Chat API Key' service kai-chat-" + provider + " account default && echo '✔ Stored in Secret Service'\""
        secretToolDs.statusLabel = lbl
        secretToolDs.connectSource(cmd)
        clearProviderKeyValue(provider)
    }

    function checkKeyInSecretService(provider, lbl) {
        var cmd = "sh -lc \"if secret-tool lookup service kai-chat-" + provider + " account default >/dev/null 2>&1; then echo '✔ Key found in Secret Service'; else echo '✘ No key stored yet'; fi\""
        secretToolDs.statusLabel = lbl
        secretToolDs.connectSource(cmd)
    }

    // Returns { url, key } for the currently selected provider
    function activeProviderConfig() {
        var p = plasmoid.configuration.provider
        switch (p) {
        case "openai":      return { url: plasmoid.configuration.openaiBaseUrl,   key: plasmoid.configuration.openaiApiKey }
        case "anthropic":   return { url: "https://api.anthropic.com/v1",         key: plasmoid.configuration.anthropicApiKey }
        case "gemini":      return { url: "https://generativelanguage.googleapis.com/v1beta/openai", key: plasmoid.configuration.geminiApiKey }
        case "mistral":     return { url: "https://api.mistral.ai/v1",            key: plasmoid.configuration.mistralApiKey }
        case "grok":        return { url: "https://api.x.ai/v1",                  key: plasmoid.configuration.grokApiKey }
        case "deepseek":    return { url: "https://api.deepseek.com/v1",          key: plasmoid.configuration.deepseekApiKey }
        case "nvidia":      return { url: "https://integrate.api.nvidia.com/v1",  key: plasmoid.configuration.nvidiaApiKey }
        case "cerebras":    return { url: "https://api.cerebras.ai/v1",           key: plasmoid.configuration.cerebrasApiKey }
        case "cloudflare":  return { url: "https://api.cloudflare.com/client/v4/accounts/" +
                                          plasmoid.configuration.cfAccountId + "/ai/v1",
                                     key: plasmoid.configuration.cfApiToken }
        case "huggingface": return { url: "https://api-inference.huggingface.co/v1", key: plasmoid.configuration.hfApiKey }
        case "openrouter":  return { url: "https://openrouter.ai/api/v1",         key: plasmoid.configuration.openrouterApiKey }
        case "litellm":     return { url: plasmoid.configuration.litellmBaseUrl,  key: plasmoid.configuration.litellmApiKey || "" }
        case "local":       return { url: plasmoid.configuration.localBaseUrl,    key: "" }
        default:            return null
        }
    }

    // Fire GET {baseUrl}/models and update statusLabel with ✔/✘
    function testApiConnection(statusLabel) {
        var cfg = activeProviderConfig()
        if (!cfg) {
            statusLabel.text  = "✘ select a provider first"
            statusLabel.color = Kirigami.Theme.negativeTextColor
            return
        }
        statusLabel.text  = "testing…"
        statusLabel.color = Kirigami.Theme.disabledTextColor
        var xhr = new XMLHttpRequest()
        var url = cfg.url.replace(/\/$/, "") + "/models"
        xhr.open("GET", url, true)
        xhr.setRequestHeader("Content-Type", "application/json")
        if (cfg.key && cfg.key !== "") xhr.setRequestHeader("Authorization", "Bearer " + cfg.key)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                statusLabel.color = Kirigami.Theme.positiveTextColor
                try {
                    var resp  = JSON.parse(xhr.responseText)
                    var count = (resp.data || resp.models || []).length
                    statusLabel.text = "✔ Connected" + (count > 0 ? " (" + count + " models)" : "")
                } catch (e) {
                    statusLabel.text = "✔ Connected"
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                statusLabel.color = Kirigami.Theme.negativeTextColor
                statusLabel.text  = "✘ Auth failed — check API key"
            } else {
                statusLabel.color = Kirigami.Theme.negativeTextColor
                statusLabel.text  = "✘ HTTP " + xhr.status
            }
        }
        xhr.onerror = function() {
            statusLabel.color = Kirigami.Theme.negativeTextColor
            statusLabel.text  = "✘ Cannot reach " + cfg.url
        }
        xhr.send()
    }

    // Fetch model list from {baseUrl}/models and populate a ComboBox
    function fetchModels(baseUrl, apiKey, targetComboBox) {
        if (!baseUrl || baseUrl === "") return
        var xhr = new XMLHttpRequest()
        var url = baseUrl.replace(/\/$/, "") + "/models"
        xhr.open("GET", url, true)
        if (apiKey && apiKey !== "") xhr.setRequestHeader("Authorization", "Bearer " + apiKey)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var resp   = JSON.parse(xhr.responseText)
                    var raw    = resp.data || resp.models || []
                    var models = raw.map(function(m) { return (typeof m === "string") ? m : (m.id || m.name || "") })
                                    .filter(function(s) { return s !== "" })
                    models.sort()
                    if (models.length > 0) targetComboBox.model = models
                } catch (e) {}
            }
        }
        xhr.send()
    }

    Kirigami.FormLayout {
        wideMode: true

        // ══ Active Provider ════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Active Provider"
        }
        PC3.ComboBox {
            Kirigami.FormData.label: "Provider:"
            Layout.minimumWidth: 300
            model: [
                { value: "openai",      text: "OpenAI" },
                { value: "anthropic",   text: "Anthropic" },
                { value: "gemini",      text: "Google Gemini" },
                { value: "mistral",     text: "Mistral AI" },
                { value: "grok",        text: "xAI Grok" },
                { value: "deepseek",    text: "DeepSeek" },
                { value: "nvidia",      text: "NVIDIA NIMs" },
                { value: "cerebras",    text: "Cerebras" },
                { value: "cloudflare",  text: "Cloudflare Workers AI" },
                { value: "huggingface", text: "HuggingFace" },
                { value: "openrouter",  text: "OpenRouter" },
                { value: "litellm",     text: "LiteLLM (proxy)" },
                { value: "local",       text: "Local (Ollama / LM Studio)" },
                { value: "opencode",    text: "[BETA] OpenCode Bridge" }
            ]
            textRole: "text"
            valueRole: "value"
            currentIndex: {
                for (var i = 0; i < model.length; i++) {
                    if (model[i].value === plasmoid.configuration.provider) return i
                }
                return 0
            }
            onActivated: plasmoid.configuration.provider = currentValue
        }
        RowLayout {
            Kirigami.FormData.label: "Connection:"
            spacing: Kirigami.Units.smallSpacing
            PC3.Button {
                text: "Test Connection"
                icon.name: "network-connect"
                onClicked: testApiConnection(connStatus)
            }
            PC3.Label {
                id: connStatus
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: "Not tested yet"
                color: Kirigami.Theme.disabledTextColor
            }
        }
        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.neutralTextColor
            text: "⚠ API keys are stored in plain text in the KDE config file for now. " +
                  "Secure KWallet storage will be added in a future update."
        }

        // ══ OpenAI ══════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "OpenAI"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: oaiKey
                Layout.minimumWidth: 260
                echoMode: showOai.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.openaiApiKey
                onTextEdited: plasmoid.configuration.openaiApiKey = text
                placeholderText: "sk-…"
            }
            PC3.CheckBox { id: showOai; text: "Show" }
        }
        PC3.TextField {
            Kirigami.FormData.label: "Base URL:"
            Layout.minimumWidth: 300
            text: plasmoid.configuration.openaiBaseUrl
            onTextEdited: plasmoid.configuration.openaiBaseUrl = text
            placeholderText: "https://api.openai.com/v1"
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            spacing: Kirigami.Units.smallSpacing
            PC3.ComboBox {
                id: oaiModelCombo
                Layout.minimumWidth: 230
                editable: true
                model: configPage.openaiModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.openaiModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.openaiModel
                }
                onEditTextChanged: plasmoid.configuration.openaiModel = editText
                onActivated:       plasmoid.configuration.openaiModel = currentText
            }
            PC3.Button {
                text: "Fetch"
                icon.name: "view-refresh"
                ToolTip.text: "Auto-fetch model list from the configured Base URL"
                ToolTip.visible: hovered
                onClicked: fetchModels(plasmoid.configuration.openaiBaseUrl,
                                       plasmoid.configuration.openaiApiKey,
                                       oaiModelCombo)
            }
            PC3.Label { text: "(or type any model ID)"; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize }
        }

        // ══ Anthropic ════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Anthropic"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: antKey
                Layout.minimumWidth: 260
                echoMode: showAnt.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.anthropicApiKey
                onTextEdited: plasmoid.configuration.anthropicApiKey = text
                placeholderText: "sk-ant-…"
            }
            PC3.CheckBox { id: showAnt; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            PC3.ComboBox {
                Layout.minimumWidth: 280
                editable: true
                model: configPage.anthropicModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.anthropicModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.anthropicModel
                }
                onEditTextChanged: plasmoid.configuration.anthropicModel = editText
                onActivated:       plasmoid.configuration.anthropicModel = currentText
            }
        }

        // ══ Google Gemini ════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Google Gemini"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: gemKey
                Layout.minimumWidth: 260
                echoMode: showGem.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.geminiApiKey
                onTextEdited: plasmoid.configuration.geminiApiKey = text
                placeholderText: "AIza…"
            }
            PC3.CheckBox { id: showGem; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            PC3.ComboBox {
                Layout.minimumWidth: 260
                editable: true
                model: configPage.geminiModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.geminiModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.geminiModel
                }
                onEditTextChanged: plasmoid.configuration.geminiModel = editText
                onActivated:       plasmoid.configuration.geminiModel = currentText
            }
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Uses Gemini's OpenAI-compatible endpoint – no extra libraries needed."
        }

        // ══ Mistral AI ═══════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Mistral AI"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: mistrKey
                Layout.minimumWidth: 260
                echoMode: showMistr.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.mistralApiKey
                onTextEdited: plasmoid.configuration.mistralApiKey = text
                placeholderText: "…"
            }
            PC3.CheckBox { id: showMistr; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            PC3.ComboBox {
                Layout.minimumWidth: 260
                editable: true
                model: configPage.mistralModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.mistralModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.mistralModel
                }
                onEditTextChanged: plasmoid.configuration.mistralModel = editText
                onActivated:       plasmoid.configuration.mistralModel = currentText
            }
        }

        // ══ xAI Grok ════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "xAI Grok"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: grokKey
                Layout.minimumWidth: 260
                echoMode: showGrok.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.grokApiKey
                onTextEdited: plasmoid.configuration.grokApiKey = text
                placeholderText: "xai-…"
            }
            PC3.CheckBox { id: showGrok; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            PC3.ComboBox {
                Layout.minimumWidth: 220
                editable: true
                model: configPage.grokModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.grokModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.grokModel
                }
                onEditTextChanged: plasmoid.configuration.grokModel = editText
                onActivated:       plasmoid.configuration.grokModel = currentText
            }
        }

        // ══ DeepSeek ═════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "DeepSeek"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: dsKey
                Layout.minimumWidth: 260
                echoMode: showDs.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.deepseekApiKey
                onTextEdited: plasmoid.configuration.deepseekApiKey = text
                placeholderText: "sk-…"
            }
            PC3.CheckBox { id: showDs; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            PC3.ComboBox {
                Layout.minimumWidth: 220
                editable: true
                model: configPage.deepseekModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.deepseekModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.deepseekModel
                }
                onEditTextChanged: plasmoid.configuration.deepseekModel = editText
                onActivated:       plasmoid.configuration.deepseekModel = currentText
            }
        }

        // ══ NVIDIA NIMs ══════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "NVIDIA NIMs"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: nvKey
                Layout.minimumWidth: 260
                echoMode: showNv.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.nvidiaApiKey
                onTextEdited: plasmoid.configuration.nvidiaApiKey = text
                placeholderText: "nvapi-…"
            }
            PC3.CheckBox { id: showNv; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            PC3.ComboBox {
                Layout.minimumWidth: 320
                editable: true
                model: configPage.nvidiaModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.nvidiaModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.nvidiaModel
                }
                onEditTextChanged: plasmoid.configuration.nvidiaModel = editText
                onActivated:       plasmoid.configuration.nvidiaModel = currentText
            }
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Get your API key at build.nvidia.com. Models are referenced as namespace/model-name."
        }

        // ══ Cerebras ═════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Cerebras"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: cbKey
                Layout.minimumWidth: 260
                echoMode: showCb.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.cerebrasApiKey
                onTextEdited: plasmoid.configuration.cerebrasApiKey = text
                placeholderText: "csk-…"
            }
            PC3.CheckBox { id: showCb; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            PC3.ComboBox {
                Layout.minimumWidth: 260
                editable: true
                model: configPage.cerebrasModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.cerebrasModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.cerebrasModel
                }
                onEditTextChanged: plasmoid.configuration.cerebrasModel = editText
                onActivated:       plasmoid.configuration.cerebrasModel = currentText
            }
        }

        // ══ Cloudflare Workers AI ════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Cloudflare Workers AI"
        }
        PC3.TextField {
            Kirigami.FormData.label: "Account ID:"
            Layout.minimumWidth: 260
            text: plasmoid.configuration.cfAccountId
            onTextEdited: plasmoid.configuration.cfAccountId = text
            placeholderText: "32-char hex ID from dash.cloudflare.com"
        }
        RowLayout {
            Kirigami.FormData.label: "API Token:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: cfTok
                Layout.minimumWidth: 260
                echoMode: showCf.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.cfApiToken
                onTextEdited: plasmoid.configuration.cfApiToken = text
                placeholderText: "Workers AI API Token"
            }
            PC3.CheckBox { id: showCf; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            PC3.ComboBox {
                Layout.minimumWidth: 320
                editable: true
                model: configPage.cfModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.cfModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.cfModel
                }
                onEditTextChanged: plasmoid.configuration.cfModel = editText
                onActivated:       plasmoid.configuration.cfModel = currentText
            }
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Account ID and Workers AI token: dash.cloudflare.com → AI → Workers AI."
        }

        // ══ HuggingFace ══════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "HuggingFace Inference"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: hfKey
                Layout.minimumWidth: 260
                echoMode: showHf.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.hfApiKey
                onTextEdited: plasmoid.configuration.hfApiKey = text
                placeholderText: "hf_…"
            }
            PC3.CheckBox { id: showHf; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            PC3.ComboBox {
                Layout.minimumWidth: 300
                editable: true
                model: configPage.hfModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.hfModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.hfModel
                }
                onEditTextChanged: plasmoid.configuration.hfModel = editText
                onActivated:       plasmoid.configuration.hfModel = currentText
            }
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Uses the HuggingFace serverless Inference API (OpenAI-compatible at /v1)."
        }

        // ══ OpenRouter ═══════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "OpenRouter"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: orKey
                Layout.minimumWidth: 260
                echoMode: showOr.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.openrouterApiKey
                onTextEdited: plasmoid.configuration.openrouterApiKey = text
                placeholderText: "sk-or-…"
            }
            PC3.CheckBox { id: showOr; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            PC3.ComboBox {
                Layout.minimumWidth: 300
                editable: true
                model: configPage.openrouterModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.openrouterModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.openrouterModel
                }
                onEditTextChanged: plasmoid.configuration.openrouterModel = editText
                onActivated:       plasmoid.configuration.openrouterModel = currentText
            }
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "400+ models via one API key. Get yours at openrouter.ai.\nUseful model format: provider/model-name (e.g. openai/gpt-4o-mini)."
        }

        // ══ LiteLLM ══════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "LiteLLM (local proxy)"
        }
        PC3.TextField {
            Kirigami.FormData.label: "Base URL:"
            Layout.minimumWidth: 280
            text: plasmoid.configuration.litellmBaseUrl
            onTextEdited: plasmoid.configuration.litellmBaseUrl = text
            placeholderText: "http://localhost:4000"
        }
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: llKey
                Layout.minimumWidth: 220
                echoMode: showLl.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.litellmApiKey
                onTextEdited: plasmoid.configuration.litellmApiKey = text
                placeholderText: "(optional)"
            }
            PC3.CheckBox { id: showLl; text: "Show" }
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: llModelField
                Layout.minimumWidth: 250
                text: plasmoid.configuration.litellmModel
                onTextEdited: plasmoid.configuration.litellmModel = text
                placeholderText: "gpt-4o, claude-3-5-sonnet, ollama/mistral…"
            }
            PC3.Button {
                text: "Fetch"
                icon.name: "view-refresh"
                ToolTip.text: "Auto-fetch model list from the LiteLLM proxy"
                ToolTip.visible: hovered
                onClicked: fetchModels(plasmoid.configuration.litellmBaseUrl,
                                       plasmoid.configuration.litellmApiKey,
                                       llModelCombo)
            }
            PC3.ComboBox {
                id: llModelCombo
                Layout.minimumWidth: 0
                visible: false
                onActivated: {
                    llModelField.text = currentText
                    plasmoid.configuration.litellmModel = currentText
                }
                onModelChanged: {
                    if (model && model.length > 0) {
                        visible = true
                        currentIndex = 0
                    }
                }
            }
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Quick start: litellm --model openai/gpt-4o\nOr use a litellm_config.yaml for multiple models."
        }

        // ══ Local (Ollama / LM Studio) ═══════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Local Server  (Ollama / LM Studio / llama.cpp)"
        }
        PC3.TextField {
            Kirigami.FormData.label: "Base URL:"
            Layout.minimumWidth: 280
            text: plasmoid.configuration.localBaseUrl
            onTextEdited: plasmoid.configuration.localBaseUrl = text
            placeholderText: "http://localhost:11434/v1"
        }
        RowLayout {
            Kirigami.FormData.label: "Model:"
            spacing: Kirigami.Units.smallSpacing
            PC3.ComboBox {
                id: localModelCombo
                Layout.minimumWidth: 230
                editable: true
                model: [plasmoid.configuration.localModel]
                Component.onCompleted: { editText = plasmoid.configuration.localModel }
                onEditTextChanged: plasmoid.configuration.localModel = editText
                onActivated:       plasmoid.configuration.localModel = currentText
            }
            PC3.Button {
                text: "Fetch"
                icon.name: "view-refresh"
                ToolTip.text: "Auto-fetch model list from the local server"
                ToolTip.visible: hovered
                onClicked: fetchModels(plasmoid.configuration.localBaseUrl, "", localModelCombo)
            }
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Ollama:    http://localhost:11434/v1\nLM Studio: http://localhost:1234/v1\nllama.cpp: http://localhost:8080/v1"
        }

        // ══ Chat Behaviour ════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Chat Behaviour"
        }
        QQC2.TextArea {
            Kirigami.FormData.label: "System Prompt:"
            Layout.minimumWidth: 320
            Layout.minimumHeight: 80
            wrapMode: Text.WordWrap
            text: plasmoid.configuration.systemPrompt
            onTextChanged: plasmoid.configuration.systemPrompt = text
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: "Temperature:"
            from: 0; to: 200; stepSize: 5
            value: Math.round(plasmoid.configuration.temperature * 100)
            onValueModified: plasmoid.configuration.temperature = value / 100.0
            textFromValue: function(val) { return (val / 100.0).toFixed(2) }
            valueFromText: function(text) { return Math.round(parseFloat(text) * 100) }
            ToolTip.text: "Randomness of responses: 0.0 = deterministic, 1.0 = default, 2.0 = very random"
            ToolTip.visible: hovered
        }
        PC3.SpinBox {
            Kirigami.FormData.label: "Max history messages:"
            from: 10; to: 500; stepSize: 10
            value: plasmoid.configuration.maxHistory
            onValueModified: plasmoid.configuration.maxHistory = value
        }
        PC3.Label {
            Kirigami.FormData.label: "Global Shortcut:"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.75
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "No shortcut is set by default. In the widget settings dialog, open the Shortcuts tab and assign one to open Kai Chat from anywhere."
        }
        PC3.CheckBox {
            Kirigami.FormData.label: "Notifications:"
            text: "Notify when response finishes in background"
            checked: plasmoid.configuration.notifyOnBackgroundCompletion
            onToggled: plasmoid.configuration.notifyOnBackgroundCompletion = checked
        }

        // ══ Secret Service / KWallet (BETA) ═════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Secret Service (KWallet backend)"
        }
        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.75
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Store API keys in Secret Service using secret-tool. Click Store for the active provider after entering a key. The plain-text config field is then cleared."
        }
        RowLayout {
            Kirigami.FormData.label: "Active Provider Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.Button {
                text: "Store Securely"
                icon.name: "document-encrypt"
                onClicked: storeKeyInSecretService(plasmoid.configuration.provider, secretStatus)
            }
            PC3.Button {
                text: "Check"
                icon.name: "dialog-ok"
                onClicked: checkKeyInSecretService(plasmoid.configuration.provider, secretStatus)
            }
            PC3.Label {
                id: secretStatus
                Layout.fillWidth: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: ""
                wrapMode: Text.Wrap
            }
        }

        // ══ CLI Bridges ════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "CLI Bridges  (forward AI responses → coding tools)"
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "These bridges let you forward any AI response to an external coding CLI tool. " +
                  "They work with any provider above."
        }

        // Opencode CLI bridge
        PC3.CheckBox {
            Kirigami.FormData.label: "Opencode CLI:"
            text: "Enable"
            checked: plasmoid.configuration.enableOpencodeBridge
            onToggled: plasmoid.configuration.enableOpencodeBridge = checked
        }
        RowLayout {
            Kirigami.FormData.label: "Command:"
            spacing: Kirigami.Units.smallSpacing
            enabled: plasmoid.configuration.enableOpencodeBridge
            PC3.TextField {
                id: ocPath
                Layout.minimumWidth: 180
                text: plasmoid.configuration.opencodePath
                onTextEdited: plasmoid.configuration.opencodePath = text
                placeholderText: "opencode"
            }
            PC3.Button { text: "Test"; onClicked: testCli(ocPath.text || "opencode", ocStatus) }
            PC3.Label { id: ocStatus; font.pointSize: Kirigami.Theme.smallFont.pointSize }
        }

        // Aider
        PC3.CheckBox {
            Kirigami.FormData.label: "Aider:"
            text: "Enable"
            checked: plasmoid.configuration.enableAiderBridge
            onToggled: plasmoid.configuration.enableAiderBridge = checked
        }
        RowLayout {
            Kirigami.FormData.label: "Command:"
            spacing: Kirigami.Units.smallSpacing
            enabled: plasmoid.configuration.enableAiderBridge
            PC3.TextField {
                id: aiderPath
                Layout.minimumWidth: 180
                text: plasmoid.configuration.aiderPath
                onTextEdited: plasmoid.configuration.aiderPath = text
                placeholderText: "aider"
            }
            PC3.Button { text: "Test"; onClicked: testCli(aiderPath.text || "aider", aiderStatus) }
            PC3.Label { id: aiderStatus; font.pointSize: Kirigami.Theme.smallFont.pointSize }
        }

        // Claude Code
        PC3.CheckBox {
            Kirigami.FormData.label: "Claude Code:"
            text: "Enable"
            checked: plasmoid.configuration.enableClaudeCodeBridge
            onToggled: plasmoid.configuration.enableClaudeCodeBridge = checked
        }
        RowLayout {
            Kirigami.FormData.label: "Command:"
            spacing: Kirigami.Units.smallSpacing
            enabled: plasmoid.configuration.enableClaudeCodeBridge
            PC3.TextField {
                id: ccPath
                Layout.minimumWidth: 180
                text: plasmoid.configuration.claudeCodePath
                onTextEdited: plasmoid.configuration.claudeCodePath = text
                placeholderText: "claude"
            }
            PC3.Button { text: "Test"; onClicked: testCli(ccPath.text || "claude", ccStatus) }
            PC3.Label { id: ccStatus; font.pointSize: Kirigami.Theme.smallFont.pointSize }
        }

        // ══ [BETA] OpenCode Bridge ════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "⚗ OpenCode Bridge  [BETA]"
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: betaNote.implicitHeight + Kirigami.Units.smallSpacing * 2
            color: Qt.rgba(Kirigami.Theme.neutralTextColor.r,
                           Kirigami.Theme.neutralTextColor.g,
                           Kirigami.Theme.neutralTextColor.b, 0.12)
            radius: Kirigami.Units.smallSpacing
            PC3.Label {
                id: betaNote
                anchors { fill: parent; margins: Kirigami.Units.smallSpacing }
                wrapMode: Text.Wrap
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: "When the OpenCode Bridge provider is selected, Kai Chat talks to your locally-running " +
                      "OpenCode server instead of calling any cloud API. OpenCode manages its own model " +
                      "selection and provider credentials — you don't need to configure API keys here.\n\n" +
                      "Start OpenCode first:\n" +
                      "  opencode serve        (defaults to port 4096)\n\n" +
                      "Then switch the Provider dropdown to "[BETA] OpenCode Bridge".\n" +
                      "Use the + button in the chat header to start a fresh OpenCode session at any time."
            }
        }
        PC3.TextField {
            Kirigami.FormData.label: "Server URL:"
            Layout.minimumWidth: 280
            text: plasmoid.configuration.opencodeServerUrl
            onTextEdited: plasmoid.configuration.opencodeServerUrl = text
            placeholderText: "http://localhost:4096"
        }
    }
}
