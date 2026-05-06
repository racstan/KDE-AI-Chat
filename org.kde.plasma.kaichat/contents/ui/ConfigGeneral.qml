import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

KCM.SimpleKCM {
    id: page

    property alias cfg_provider: providerBox.currentValue

    property alias cfg_baseUrl: baseUrlField.text
    property alias cfg_apiKey: apiKeyField.text
    property alias cfg_model: modelField.text

    property alias cfg_anthropicApiKey: anthropicApiKeyField.text
    property alias cfg_anthropicModel: anthropicModelField.text

    property alias cfg_groqBaseUrl: groqBaseUrlField.text
    property alias cfg_groqApiKey: groqApiKeyField.text
    property alias cfg_groqModel: groqModelField.text

    property alias cfg_openRouterBaseUrl: openRouterBaseUrlField.text
    property alias cfg_openRouterApiKey: openRouterApiKeyField.text
    property alias cfg_openRouterModel: openRouterModelField.text
    property alias cfg_openRouterReferer: openRouterRefererField.text
    property alias cfg_openRouterTitle: openRouterTitleField.text

    property alias cfg_mistralBaseUrl: mistralBaseUrlField.text
    property alias cfg_mistralApiKey: mistralApiKeyField.text
    property alias cfg_mistralModel: mistralModelField.text

    property alias cfg_cloudflareBaseUrl: cloudflareBaseUrlField.text
    property alias cfg_cloudflareApiKey: cloudflareApiKeyField.text
    property alias cfg_cloudflareModel: cloudflareModelField.text

    property alias cfg_nvidiaBaseUrl: nvidiaBaseUrlField.text
    property alias cfg_nvidiaApiKey: nvidiaApiKeyField.text
    property alias cfg_nvidiaModel: nvidiaModelField.text

    property alias cfg_huggingFaceBaseUrl: huggingFaceBaseUrlField.text
    property alias cfg_huggingFaceApiKey: huggingFaceApiKeyField.text
    property alias cfg_huggingFaceModel: huggingFaceModelField.text

    property alias cfg_xaiBaseUrl: xaiBaseUrlField.text
    property alias cfg_xaiApiKey: xaiApiKeyField.text
    property alias cfg_xaiModel: xaiModelField.text

    property alias cfg_localBaseUrl: localBaseUrlField.text
    property alias cfg_localModel: localModelField.text

    property alias cfg_useOpenCode: openCodeToggle.checked
    property alias cfg_openCodeUrl: openCodeUrlField.text
    property alias cfg_openCodeModel: openCodeModelValueField.text
    property alias cfg_openCodeProvider: openCodeProviderValueField.text

    property alias cfg_kwalletName: walletNameField.text

    property alias cfg_systemPrompt: systemPromptArea.text

    property string keyringStatus: ""
    property string discoveryStatus: ""
    property var pendingOps: ({})

    property var providerModelCandidates: []
    property var openCodeProviderCandidates: []
    property var openCodeModelCandidates: []

    function shellEscape(s) {
        return (s || "").replace(/'/g, "'\\''")
    }

    function providerEnabled(providerId) {
        return !openCodeToggle.checked && providerBox.currentValue === providerId
    }

    function currentProviderDisplayName() {
        return providerBox.currentText || "Provider"
    }

    function currentProviderConfig() {
        var p = providerBox.currentValue || "openai"
        if (p === "anthropic") {
            return {
                id: p,
                type: "anthropic",
                baseUrl: "https://api.anthropic.com/v1",
                apiKey: anthropicApiKeyField.text,
                modelField: anthropicModelField
            }
        }
        if (p === "local") {
            return {
                id: p,
                type: "openai-compat",
                baseUrl: localBaseUrlField.text,
                apiKey: "",
                modelField: localModelField
            }
        }
        if (p === "groq") {
            return {
                id: p,
                type: "openai-compat",
                baseUrl: groqBaseUrlField.text,
                apiKey: groqApiKeyField.text,
                modelField: groqModelField
            }
        }
        if (p === "openrouter") {
            return {
                id: p,
                type: "openai-compat",
                baseUrl: openRouterBaseUrlField.text,
                apiKey: openRouterApiKeyField.text,
                modelField: openRouterModelField
            }
        }
        if (p === "mistral") {
            return {
                id: p,
                type: "openai-compat",
                baseUrl: mistralBaseUrlField.text,
                apiKey: mistralApiKeyField.text,
                modelField: mistralModelField
            }
        }
        if (p === "cloudflare") {
            return {
                id: p,
                type: "openai-compat",
                baseUrl: cloudflareBaseUrlField.text,
                apiKey: cloudflareApiKeyField.text,
                modelField: cloudflareModelField
            }
        }
        if (p === "nvidia") {
            return {
                id: p,
                type: "openai-compat",
                baseUrl: nvidiaBaseUrlField.text,
                apiKey: nvidiaApiKeyField.text,
                modelField: nvidiaModelField
            }
        }
        if (p === "huggingface") {
            return {
                id: p,
                type: "openai-compat",
                baseUrl: huggingFaceBaseUrlField.text,
                apiKey: huggingFaceApiKeyField.text,
                modelField: huggingFaceModelField
            }
        }
        if (p === "xai") {
            return {
                id: p,
                type: "openai-compat",
                baseUrl: xaiBaseUrlField.text,
                apiKey: xaiApiKeyField.text,
                modelField: xaiModelField
            }
        }
        return {
            id: "openai",
            type: "openai-compat",
            baseUrl: baseUrlField.text,
            apiKey: apiKeyField.text,
            modelField: modelField
        }
    }

    function makeOpenAiModelsUrl(baseUrl) {
        return (baseUrl || "").replace(/\/$/, "") + "/models"
    }

    function parseModelIds(responseObj) {
        var ids = []
        function pushId(v) {
            if (!v)
                return
            if (ids.indexOf(v) < 0)
                ids.push(v)
        }

        if (Array.isArray(responseObj)) {
            for (var i = 0; i < responseObj.length; i++) {
                if (typeof responseObj[i] === "string")
                    pushId(responseObj[i])
                else if (responseObj[i] && responseObj[i].id)
                    pushId(responseObj[i].id)
                else if (responseObj[i] && responseObj[i].name)
                    pushId(responseObj[i].name)
            }
        } else if (responseObj && Array.isArray(responseObj.data)) {
            for (var j = 0; j < responseObj.data.length; j++) {
                if (responseObj.data[j] && responseObj.data[j].id)
                    pushId(responseObj.data[j].id)
                else if (responseObj.data[j] && responseObj.data[j].name)
                    pushId(responseObj.data[j].name)
            }
        } else if (responseObj && Array.isArray(responseObj.models)) {
            for (var k = 0; k < responseObj.models.length; k++) {
                if (typeof responseObj.models[k] === "string")
                    pushId(responseObj.models[k])
                else if (responseObj.models[k] && responseObj.models[k].id)
                    pushId(responseObj.models[k].id)
                else if (responseObj.models[k] && responseObj.models[k].name)
                    pushId(responseObj.models[k].name)
            }
        }
        return ids
    }

    function parseProviderIds(responseObj) {
        var ids = []
        function pushId(v) {
            if (!v)
                return
            if (ids.indexOf(v) < 0)
                ids.push(v)
        }

        if (Array.isArray(responseObj)) {
            for (var i = 0; i < responseObj.length; i++) {
                if (typeof responseObj[i] === "string")
                    pushId(responseObj[i])
                else if (responseObj[i] && responseObj[i].id)
                    pushId(responseObj[i].id)
                else if (responseObj[i] && responseObj[i].name)
                    pushId(responseObj[i].name)
                else if (responseObj[i] && responseObj[i].provider)
                    pushId(responseObj[i].provider)
            }
        } else if (responseObj && Array.isArray(responseObj.providers)) {
            for (var j = 0; j < responseObj.providers.length; j++) {
                if (typeof responseObj.providers[j] === "string")
                    pushId(responseObj.providers[j])
                else if (responseObj.providers[j] && responseObj.providers[j].id)
                    pushId(responseObj.providers[j].id)
                else if (responseObj.providers[j] && responseObj.providers[j].name)
                    pushId(responseObj.providers[j].name)
            }
        } else if (responseObj && Array.isArray(responseObj.data)) {
            for (var k = 0; k < responseObj.data.length; k++) {
                if (responseObj.data[k] && responseObj.data[k].provider)
                    pushId(responseObj.data[k].provider)
            }
        }

        return ids
    }

    function requestJson(url, headers, onSuccess, onError) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url, true)
        for (var h in headers) {
            if (Object.prototype.hasOwnProperty.call(headers, h) && headers[h])
                xhr.setRequestHeader(h, headers[h])
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    onSuccess(JSON.parse(xhr.responseText))
                } catch (e) {
                    onError("Invalid JSON from " + url)
                }
            } else {
                onError("HTTP " + xhr.status + " from " + url)
            }
        }
        xhr.onerror = function() {
            onError("Network error while requesting " + url)
        }
        xhr.send()
    }

    function refreshCurrentProviderModels() {
        var cfg = currentProviderConfig()
        var headers = {}
        if (cfg.apiKey)
            headers["Authorization"] = "Bearer " + cfg.apiKey

        if (cfg.type === "anthropic") {
            headers["x-api-key"] = cfg.apiKey
            headers["anthropic-version"] = "2023-06-01"
            requestJson(
                "https://api.anthropic.com/v1/models",
                headers,
                function(obj) {
                    var ids = parseModelIds(obj)
                    providerModelCandidates = ids
                    discoveryStatus = ids.length > 0
                        ? ("Loaded " + ids.length + " models for " + currentProviderDisplayName() + ".")
                        : "No models returned for this provider/API key."
                },
                function(err) {
                    providerModelCandidates = []
                    discoveryStatus = err
                }
            )
            return
        }

        requestJson(
            makeOpenAiModelsUrl(cfg.baseUrl),
            headers,
            function(obj) {
                var ids = parseModelIds(obj)
                providerModelCandidates = ids
                discoveryStatus = ids.length > 0
                    ? ("Loaded " + ids.length + " models for " + currentProviderDisplayName() + ".")
                    : "No models returned for this provider/API key."
            },
            function(err) {
                providerModelCandidates = []
                discoveryStatus = err
            }
        )
    }

    function applyDetectedModelToActiveProvider(modelId) {
        var cfg = currentProviderConfig()
        cfg.modelField.text = modelId || ""
    }

    function activeOpenCodeProvider() {
        return openCodeProviderValueField.text || ""
    }

    function setOpenCodeProviderValue(v) {
        openCodeProviderValueField.text = v || ""
    }

    function setOpenCodeModelValue(v) {
        openCodeModelValueField.text = v || ""
    }

    function probeOpenCodeProviders(baseUrl) {
        var urls = [
            (baseUrl || "").replace(/\/$/, "") + "/providers",
            (baseUrl || "").replace(/\/$/, "") + "/v1/providers",
            (baseUrl || "").replace(/\/$/, "") + "/api/providers",
            (baseUrl || "").replace(/\/$/, "") + "/models"
        ]

        function nextProbe(i) {
            if (i >= urls.length) {
                discoveryStatus = "Could not discover OpenCode providers from known endpoints."
                openCodeProviderCandidates = []
                return
            }
            requestJson(
                urls[i],
                {},
                function(obj) {
                    var ids = parseProviderIds(obj)
                    if (ids.length === 0)
                        ids = parseModelIds(obj)
                    if (ids.length > 0) {
                        openCodeProviderCandidates = ids
                        setOpenCodeProviderValue(ids[0])
                        discoveryStatus = "Loaded " + ids.length + " OpenCode providers."
                        probeOpenCodeModels(baseUrl, ids[0])
                    } else {
                        nextProbe(i + 1)
                    }
                },
                function() {
                    nextProbe(i + 1)
                }
            )
        }
        nextProbe(0)
    }

    function probeOpenCodeModels(baseUrl, providerId) {
        var b = (baseUrl || "").replace(/\/$/, "")
        var urls = [
            b + "/models?provider=" + encodeURIComponent(providerId || ""),
            b + "/v1/models?provider=" + encodeURIComponent(providerId || ""),
            b + "/models",
            b + "/v1/models"
        ]

        function nextProbe(i) {
            if (i >= urls.length) {
                openCodeModelCandidates = []
                discoveryStatus = "Could not discover OpenCode models from known endpoints."
                return
            }
            requestJson(
                urls[i],
                {},
                function(obj) {
                    var ids = parseModelIds(obj)
                    if (ids.length > 0) {
                        openCodeModelCandidates = ids
                        setOpenCodeModelValue(ids[0])
                        discoveryStatus = "Loaded " + ids.length + " OpenCode models."
                    } else {
                        nextProbe(i + 1)
                    }
                },
                function() {
                    nextProbe(i + 1)
                }
            )
        }
        nextProbe(0)
    }

    function kwalletStore(targetId, value) {
        var walletName = (walletNameField.text || "KaiChatWallet").trim() || "KaiChatWallet"
        var keyName = "kai-chat-" + targetId + "-api-key"
        var payload = shellEscape(value)
        var cmd = "sh -lc \"command -v kwallet-query >/dev/null 2>&1 || { echo 'kwallet-query not found' 1>&2; exit 127; }; "
                + "command -v qdbus6 >/dev/null 2>&1 || { echo 'qdbus6 not found' 1>&2; exit 127; }; "
                + "handle=$(qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open '" + shellEscape(walletName) + "' 0 kaichat-config); "
                + "[ \"$handle\" != \"-1\" ] || { echo 'Could not open wallet (unlock/create it first in KDE Wallet Manager)' 1>&2; exit 1; }; "
                + "qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.createFolder \"$handle\" 'Passwords' kaichat-config >/dev/null 2>&1 || true; "
                + "printf '%s' '" + payload + "' | kwallet-query -f 'Passwords' -w '"
                + shellEscape(keyName) + "' '" + shellEscape(walletName) + "'\""
        var ops = page.pendingOps
        ops[cmd] = { mode: "store" }
        page.pendingOps = ops
        keyringDs.connectSource(cmd)
    }

    function kwalletLoad(targetId) {
        var walletName = (walletNameField.text || "KaiChatWallet").trim() || "KaiChatWallet"
        var keyName = "kai-chat-" + targetId + "-api-key"
        var cmd = "sh -lc \"command -v kwallet-query >/dev/null 2>&1 || { echo 'kwallet-query not found' 1>&2; exit 127; }; "
                + "command -v qdbus6 >/dev/null 2>&1 || { echo 'qdbus6 not found' 1>&2; exit 127; }; "
                + "handle=$(qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open '" + shellEscape(walletName) + "' 0 kaichat-config); "
                + "[ \"$handle\" != \"-1\" ] || { echo 'Could not open wallet (unlock/create it first in KDE Wallet Manager)' 1>&2; exit 1; }; "
                + "kwallet-query -f 'Passwords' -r '" + shellEscape(keyName) + "' '"
                + shellEscape(walletName) + "' 2>/dev/null\""
        var ops = page.pendingOps
        ops[cmd] = { mode: "load", target: targetId }
        page.pendingOps = ops
        keyringDs.connectSource(cmd)
    }

    function applyLoadedKey(targetId, secretValue) {
        if (targetId === "openai")
            apiKeyField.text = secretValue
        else if (targetId === "anthropic")
            anthropicApiKeyField.text = secretValue
        else if (targetId === "groq")
            groqApiKeyField.text = secretValue
        else if (targetId === "openrouter")
            openRouterApiKeyField.text = secretValue
        else if (targetId === "mistral")
            mistralApiKeyField.text = secretValue
        else if (targetId === "cloudflare")
            cloudflareApiKeyField.text = secretValue
        else if (targetId === "nvidia")
            nvidiaApiKeyField.text = secretValue
        else if (targetId === "huggingface")
            huggingFaceApiKeyField.text = secretValue
        else if (targetId === "xai")
            xaiApiKeyField.text = secretValue
    }

    P5Support.DataSource {
        id: keyringDs
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            var stderr = (data["stderr"] || "").trim()

            var op = page.pendingOps[sourceName]
            if (op) {
                var copy = page.pendingOps
                delete copy[sourceName]
                page.pendingOps = copy
            }

            if (!op) {
                page.keyringStatus = stderr !== "" ? ("Keyring error: " + stderr) : "Keyring operation finished."
                disconnectSource(sourceName)
                return
            }

            if (op.mode === "load") {
                if (stdout !== "") {
                    page.applyLoadedKey(op.target, stdout)
                    page.keyringStatus = "Loaded key from KWallet."
                } else {
                    page.keyringStatus = "No key found for this provider in KWallet."
                }
            } else {
                page.keyringStatus = stderr !== "" ? ("Keyring error: " + stderr) : "Saved key to KWallet."
            }

            disconnectSource(sourceName)
        }
    }

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.Label {
            Kirigami.FormData.label: "Tip:"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "For best layout, open Kai Chat in a larger popup or fullscreen-like panel width."
            opacity: 0.8
        }

        QQC2.CheckBox {
            id: openCodeToggle
            Kirigami.FormData.label: "OpenCode mode:"
            text: "Enable OpenCode mode"
        }

        Kirigami.Separator {
            visible: !openCodeToggle.checked
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Provider"
        }

        QQC2.ComboBox {
            id: providerBox
            visible: !openCodeToggle.checked
            Kirigami.FormData.label: "Default provider:"
            textRole: "text"
            valueRole: "value"
            model: [
                { value: "openai", text: "OpenAI compatible" },
                { value: "anthropic", text: "Anthropic" },
                { value: "groq", text: "Groq" },
                { value: "openrouter", text: "OpenRouter" },
                { value: "mistral", text: "Mistral" },
                { value: "cloudflare", text: "Cloudflare Workers AI" },
                { value: "nvidia", text: "NVIDIA" },
                { value: "huggingface", text: "Hugging Face Router" },
                { value: "xai", text: "xAI (Grok)" },
                { value: "local", text: "Local (OpenAI-compatible)" }
            ]
        }

        QQC2.Button {
            visible: !openCodeToggle.checked
            Kirigami.FormData.label: "Model discovery:"
            text: "Refresh models for active provider"
            onClicked: refreshCurrentProviderModels()
        }

        QQC2.ComboBox {
            id: providerModelsCombo
            visible: !openCodeToggle.checked && providerModelCandidates.length > 0
            Kirigami.FormData.label: "Detected models:"
            model: providerModelCandidates
            onActivated: applyDetectedModelToActiveProvider(currentText)
        }

        QQC2.Label {
            visible: discoveryStatus !== ""
            Kirigami.FormData.label: "Status:"
            text: discoveryStatus
            wrapMode: Text.Wrap
            opacity: 0.8
        }

        Kirigami.Separator {
            visible: openCodeToggle.checked
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "OpenCode"
        }

        QQC2.TextField {
            id: openCodeUrlField
            visible: openCodeToggle.checked
            Kirigami.FormData.label: "OpenCode URL:"
            placeholderText: "http://127.0.0.1:4096/v1"
        }

        QQC2.Button {
            visible: openCodeToggle.checked
            Kirigami.FormData.label: "OpenCode discovery:"
            text: "Refresh providers"
            onClicked: probeOpenCodeProviders(openCodeUrlField.text)
        }

        QQC2.ComboBox {
            id: openCodeProvidersCombo
            visible: openCodeToggle.checked && openCodeProviderCandidates.length > 0
            Kirigami.FormData.label: "Providers:"
            model: openCodeProviderCandidates
            onActivated: {
                setOpenCodeProviderValue(currentText)
                probeOpenCodeModels(openCodeUrlField.text, currentText)
            }
        }

        QQC2.Button {
            visible: openCodeToggle.checked
            Kirigami.FormData.label: "OpenCode models:"
            text: "Refresh models"
            onClicked: probeOpenCodeModels(openCodeUrlField.text, activeOpenCodeProvider())
        }

        QQC2.ComboBox {
            id: openCodeModelsCombo
            visible: openCodeToggle.checked && openCodeModelCandidates.length > 0
            Kirigami.FormData.label: "Models:"
            model: openCodeModelCandidates
            onActivated: setOpenCodeModelValue(currentText)
        }

        QQC2.TextField {
            id: openCodeProviderValueField
            visible: false
            text: ""
        }

        QQC2.TextField {
            id: openCodeModelValueField
            visible: false
            text: ""
        }

        Kirigami.Separator {
            visible: !openCodeToggle.checked
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "KWallet"
        }

        QQC2.TextField {
            id: walletNameField
            visible: !openCodeToggle.checked
            Kirigami.FormData.label: "Wallet name:"
            text: "KaiChatWallet"
            placeholderText: "KaiChatWallet"
        }

        QQC2.Label {
            visible: !openCodeToggle.checked
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Use a dedicated wallet (KaiChatWallet). Create/unlock it in KDE Wallet Manager first."
            opacity: 0.8
        }

        QQC2.Label {
            visible: !openCodeToggle.checked && keyringStatus !== ""
            Kirigami.FormData.label: "Keyring:"
            text: keyringStatus
            opacity: 0.8
        }

        QQC2.TextField {
            id: baseUrlField
            Kirigami.FormData.label: "OpenAI URL:"
            visible: page.providerEnabled("openai")
            placeholderText: "https://api.openai.com/v1"
        }

        QQC2.TextField {
            id: modelField
            Kirigami.FormData.label: "OpenAI model:"
            visible: page.providerEnabled("openai")
            placeholderText: "gpt-4o-mini"
        }

        RowLayout {
            Kirigami.FormData.label: "OpenAI key:"
            visible: page.providerEnabled("openai")
            QQC2.TextField {
                id: apiKeyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "sk-..."
            }
            QQC2.Button { text: "Save"; onClicked: page.kwalletStore("openai", apiKeyField.text) }
            QQC2.Button { text: "Load"; onClicked: page.kwalletLoad("openai") }
        }

        QQC2.TextField {
            id: anthropicModelField
            Kirigami.FormData.label: "Anthropic model:"
            visible: page.providerEnabled("anthropic")
            placeholderText: "claude-3-5-sonnet-latest"
        }

        RowLayout {
            Kirigami.FormData.label: "Anthropic key:"
            visible: page.providerEnabled("anthropic")
            QQC2.TextField { id: anthropicApiKeyField; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "sk-ant-..." }
            QQC2.Button { text: "Save"; onClicked: page.kwalletStore("anthropic", anthropicApiKeyField.text) }
            QQC2.Button { text: "Load"; onClicked: page.kwalletLoad("anthropic") }
        }

        QQC2.TextField { id: groqBaseUrlField; Kirigami.FormData.label: "Groq URL:"; visible: page.providerEnabled("groq"); placeholderText: "https://api.groq.com/openai/v1" }
        QQC2.TextField { id: groqModelField; Kirigami.FormData.label: "Groq model:"; visible: page.providerEnabled("groq"); placeholderText: "llama-3.3-70b-versatile" }
        RowLayout {
            Kirigami.FormData.label: "Groq key:"; visible: page.providerEnabled("groq")
            QQC2.TextField { id: groqApiKeyField; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "gsk_..." }
            QQC2.Button { text: "Save"; onClicked: page.kwalletStore("groq", groqApiKeyField.text) }
            QQC2.Button { text: "Load"; onClicked: page.kwalletLoad("groq") }
        }

        QQC2.TextField { id: openRouterBaseUrlField; Kirigami.FormData.label: "OpenRouter URL:"; visible: page.providerEnabled("openrouter"); placeholderText: "https://openrouter.ai/api/v1" }
        QQC2.TextField { id: openRouterModelField; Kirigami.FormData.label: "OpenRouter model:"; visible: page.providerEnabled("openrouter"); placeholderText: "openai/gpt-4o-mini" }
        QQC2.TextField { id: openRouterRefererField; Kirigami.FormData.label: "OpenRouter referer:"; visible: page.providerEnabled("openrouter"); placeholderText: "https://your-app.example" }
        QQC2.TextField { id: openRouterTitleField; Kirigami.FormData.label: "OpenRouter title:"; visible: page.providerEnabled("openrouter"); placeholderText: "Kai Chat" }
        RowLayout {
            Kirigami.FormData.label: "OpenRouter key:"; visible: page.providerEnabled("openrouter")
            QQC2.TextField { id: openRouterApiKeyField; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "sk-or-..." }
            QQC2.Button { text: "Save"; onClicked: page.kwalletStore("openrouter", openRouterApiKeyField.text) }
            QQC2.Button { text: "Load"; onClicked: page.kwalletLoad("openrouter") }
        }

        QQC2.TextField { id: mistralBaseUrlField; Kirigami.FormData.label: "Mistral URL:"; visible: page.providerEnabled("mistral"); placeholderText: "https://api.mistral.ai/v1" }
        QQC2.TextField { id: mistralModelField; Kirigami.FormData.label: "Mistral model:"; visible: page.providerEnabled("mistral"); placeholderText: "mistral-small-latest" }
        RowLayout {
            Kirigami.FormData.label: "Mistral key:"; visible: page.providerEnabled("mistral")
            QQC2.TextField { id: mistralApiKeyField; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "..." }
            QQC2.Button { text: "Save"; onClicked: page.kwalletStore("mistral", mistralApiKeyField.text) }
            QQC2.Button { text: "Load"; onClicked: page.kwalletLoad("mistral") }
        }

        QQC2.TextField { id: cloudflareBaseUrlField; Kirigami.FormData.label: "Cloudflare URL:"; visible: page.providerEnabled("cloudflare"); placeholderText: "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1" }
        QQC2.TextField { id: cloudflareModelField; Kirigami.FormData.label: "Cloudflare model:"; visible: page.providerEnabled("cloudflare"); placeholderText: "@cf/meta/llama-3.1-8b-instruct" }
        RowLayout {
            Kirigami.FormData.label: "Cloudflare key:"; visible: page.providerEnabled("cloudflare")
            QQC2.TextField { id: cloudflareApiKeyField; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "..." }
            QQC2.Button { text: "Save"; onClicked: page.kwalletStore("cloudflare", cloudflareApiKeyField.text) }
            QQC2.Button { text: "Load"; onClicked: page.kwalletLoad("cloudflare") }
        }

        QQC2.TextField { id: nvidiaBaseUrlField; Kirigami.FormData.label: "NVIDIA URL:"; visible: page.providerEnabled("nvidia"); placeholderText: "https://integrate.api.nvidia.com/v1" }
        QQC2.TextField { id: nvidiaModelField; Kirigami.FormData.label: "NVIDIA model:"; visible: page.providerEnabled("nvidia"); placeholderText: "meta/llama-3.1-70b-instruct" }
        RowLayout {
            Kirigami.FormData.label: "NVIDIA key:"; visible: page.providerEnabled("nvidia")
            QQC2.TextField { id: nvidiaApiKeyField; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "nvapi-..." }
            QQC2.Button { text: "Save"; onClicked: page.kwalletStore("nvidia", nvidiaApiKeyField.text) }
            QQC2.Button { text: "Load"; onClicked: page.kwalletLoad("nvidia") }
        }

        QQC2.TextField { id: huggingFaceBaseUrlField; Kirigami.FormData.label: "HF URL:"; visible: page.providerEnabled("huggingface"); placeholderText: "https://router.huggingface.co/v1" }
        QQC2.TextField { id: huggingFaceModelField; Kirigami.FormData.label: "HF model:"; visible: page.providerEnabled("huggingface"); placeholderText: "openai/gpt-oss-120b:groq" }
        RowLayout {
            Kirigami.FormData.label: "HF token:"; visible: page.providerEnabled("huggingface")
            QQC2.TextField { id: huggingFaceApiKeyField; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "hf_..." }
            QQC2.Button { text: "Save"; onClicked: page.kwalletStore("huggingface", huggingFaceApiKeyField.text) }
            QQC2.Button { text: "Load"; onClicked: page.kwalletLoad("huggingface") }
        }

        QQC2.TextField { id: xaiBaseUrlField; Kirigami.FormData.label: "xAI URL:"; visible: page.providerEnabled("xai"); placeholderText: "https://api.x.ai/v1" }
        QQC2.TextField { id: xaiModelField; Kirigami.FormData.label: "xAI model:"; visible: page.providerEnabled("xai"); placeholderText: "grok-2-latest" }
        RowLayout {
            Kirigami.FormData.label: "xAI key:"; visible: page.providerEnabled("xai")
            QQC2.TextField { id: xaiApiKeyField; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "xai-..." }
            QQC2.Button { text: "Save"; onClicked: page.kwalletStore("xai", xaiApiKeyField.text) }
            QQC2.Button { text: "Load"; onClicked: page.kwalletLoad("xai") }
        }

        QQC2.TextField { id: localBaseUrlField; Kirigami.FormData.label: "Local URL:"; visible: page.providerEnabled("local"); placeholderText: "http://localhost:11434/v1" }
        QQC2.TextField { id: localModelField; Kirigami.FormData.label: "Local model:"; visible: page.providerEnabled("local"); placeholderText: "llama3.2" }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Behavior"
        }

        QQC2.TextArea {
            id: systemPromptArea
            Kirigami.FormData.label: "System prompt:"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            placeholderText: "You are Kai Chat, a precise and helpful assistant."
        }
    }
}
