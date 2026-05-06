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
    property alias cfg_openCodeApiKey: openCodeApiKeyField.text
    property alias cfg_openCodeModel: openCodeModelField.text

    property alias cfg_kwalletName: walletNameField.text

    property alias cfg_systemPrompt: systemPromptArea.text

    property string keyringStatus: ""
    property var pendingOps: ({})

    function shellEscape(s) {
        return (s || "").replace(/'/g, "'\\''")
    }

    function providerEnabled(providerId) {
        return !openCodeToggle.checked && providerBox.currentValue === providerId
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
        else if (targetId === "opencode")
            openCodeApiKeyField.text = secretValue
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

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Provider"
        }

        QQC2.ComboBox {
            id: providerBox
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

        QQC2.CheckBox {
            id: openCodeToggle
            Kirigami.FormData.label: "OpenCode mode:"
            text: "Enable OpenCode priority mode"
        }

        QQC2.Label {
            visible: openCodeToggle.checked
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "OpenCode mode is ON. The selected provider below is ignored while OpenCode mode remains enabled."
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "KWallet"
        }

        QQC2.TextField {
            id: walletNameField
            Kirigami.FormData.label: "Wallet name:"
            text: "KaiChatWallet"
            placeholderText: "KaiChatWallet"
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Use a dedicated wallet (KaiChatWallet). If save/load fails, create or unlock it in KDE Wallet Manager first."
            opacity: 0.8
        }

        QQC2.Label {
            Kirigami.FormData.label: "Status:"
            text: keyringStatus
            opacity: 0.8
            visible: keyringStatus !== ""
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "OpenCode"
        }

        QQC2.TextField {
            id: openCodeUrlField
            Kirigami.FormData.label: "Base URL:"
            placeholderText: "http://127.0.0.1:4096/v1"
        }

        QQC2.TextField {
            id: openCodeModelField
            Kirigami.FormData.label: "Model:"
            placeholderText: "gpt-4o-mini"
        }

        RowLayout {
            Kirigami.FormData.label: "API key:"
            QQC2.TextField {
                id: openCodeApiKeyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "optional"
            }
            QQC2.Button {
                text: "Save KWallet"
                onClicked: page.kwalletStore("opencode", openCodeApiKeyField.text)
            }
            QQC2.Button {
                text: "Load"
                onClicked: page.kwalletLoad("opencode")
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Provider Settings"
            visible: !openCodeToggle.checked
        }

        QQC2.Label {
            Kirigami.FormData.label: "Active section:"
            visible: !openCodeToggle.checked
            text: providerBox.currentText
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
            QQC2.Button {
                text: "Save KWallet"
                onClicked: page.kwalletStore("openai", apiKeyField.text)
            }
            QQC2.Button {
                text: "Load"
                onClicked: page.kwalletLoad("openai")
            }
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
            QQC2.TextField {
                id: anthropicApiKeyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "sk-ant-..."
            }
            QQC2.Button {
                text: "Save KWallet"
                onClicked: page.kwalletStore("anthropic", anthropicApiKeyField.text)
            }
            QQC2.Button {
                text: "Load"
                onClicked: page.kwalletLoad("anthropic")
            }
        }

        QQC2.TextField {
            id: groqBaseUrlField
            Kirigami.FormData.label: "Groq URL:"
            visible: page.providerEnabled("groq")
            placeholderText: "https://api.groq.com/openai/v1"
        }

        QQC2.TextField {
            id: groqModelField
            Kirigami.FormData.label: "Groq model:"
            visible: page.providerEnabled("groq")
            placeholderText: "llama-3.3-70b-versatile"
        }

        RowLayout {
            Kirigami.FormData.label: "Groq key:"
            visible: page.providerEnabled("groq")
            QQC2.TextField {
                id: groqApiKeyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "gsk_..."
            }
            QQC2.Button {
                text: "Save KWallet"
                onClicked: page.kwalletStore("groq", groqApiKeyField.text)
            }
            QQC2.Button {
                text: "Load"
                onClicked: page.kwalletLoad("groq")
            }
        }

        QQC2.TextField {
            id: openRouterBaseUrlField
            Kirigami.FormData.label: "OpenRouter URL:"
            visible: page.providerEnabled("openrouter")
            placeholderText: "https://openrouter.ai/api/v1"
        }

        QQC2.TextField {
            id: openRouterModelField
            Kirigami.FormData.label: "OpenRouter model:"
            visible: page.providerEnabled("openrouter")
            placeholderText: "openai/gpt-4o-mini"
        }

        QQC2.TextField {
            id: openRouterRefererField
            Kirigami.FormData.label: "OpenRouter referer:"
            visible: page.providerEnabled("openrouter")
            placeholderText: "https://your-app.example"
        }

        QQC2.TextField {
            id: openRouterTitleField
            Kirigami.FormData.label: "OpenRouter title:"
            visible: page.providerEnabled("openrouter")
            placeholderText: "Kai Chat"
        }

        RowLayout {
            Kirigami.FormData.label: "OpenRouter key:"
            visible: page.providerEnabled("openrouter")
            QQC2.TextField {
                id: openRouterApiKeyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "sk-or-..."
            }
            QQC2.Button {
                text: "Save KWallet"
                onClicked: page.kwalletStore("openrouter", openRouterApiKeyField.text)
            }
            QQC2.Button {
                text: "Load"
                onClicked: page.kwalletLoad("openrouter")
            }
        }

        QQC2.TextField {
            id: mistralBaseUrlField
            Kirigami.FormData.label: "Mistral URL:"
            visible: page.providerEnabled("mistral")
            placeholderText: "https://api.mistral.ai/v1"
        }

        QQC2.TextField {
            id: mistralModelField
            Kirigami.FormData.label: "Mistral model:"
            visible: page.providerEnabled("mistral")
            placeholderText: "mistral-small-latest"
        }

        RowLayout {
            Kirigami.FormData.label: "Mistral key:"
            visible: page.providerEnabled("mistral")
            QQC2.TextField {
                id: mistralApiKeyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "..."
            }
            QQC2.Button {
                text: "Save KWallet"
                onClicked: page.kwalletStore("mistral", mistralApiKeyField.text)
            }
            QQC2.Button {
                text: "Load"
                onClicked: page.kwalletLoad("mistral")
            }
        }

        QQC2.TextField {
            id: cloudflareBaseUrlField
            Kirigami.FormData.label: "Cloudflare URL:"
            visible: page.providerEnabled("cloudflare")
            placeholderText: "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1"
        }

        QQC2.TextField {
            id: cloudflareModelField
            Kirigami.FormData.label: "Cloudflare model:"
            visible: page.providerEnabled("cloudflare")
            placeholderText: "@cf/meta/llama-3.1-8b-instruct"
        }

        RowLayout {
            Kirigami.FormData.label: "Cloudflare key:"
            visible: page.providerEnabled("cloudflare")
            QQC2.TextField {
                id: cloudflareApiKeyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "..."
            }
            QQC2.Button {
                text: "Save KWallet"
                onClicked: page.kwalletStore("cloudflare", cloudflareApiKeyField.text)
            }
            QQC2.Button {
                text: "Load"
                onClicked: page.kwalletLoad("cloudflare")
            }
        }

        QQC2.TextField {
            id: nvidiaBaseUrlField
            Kirigami.FormData.label: "NVIDIA URL:"
            visible: page.providerEnabled("nvidia")
            placeholderText: "https://integrate.api.nvidia.com/v1"
        }

        QQC2.TextField {
            id: nvidiaModelField
            Kirigami.FormData.label: "NVIDIA model:"
            visible: page.providerEnabled("nvidia")
            placeholderText: "meta/llama-3.1-70b-instruct"
        }

        RowLayout {
            Kirigami.FormData.label: "NVIDIA key:"
            visible: page.providerEnabled("nvidia")
            QQC2.TextField {
                id: nvidiaApiKeyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "nvapi-..."
            }
            QQC2.Button {
                text: "Save KWallet"
                onClicked: page.kwalletStore("nvidia", nvidiaApiKeyField.text)
            }
            QQC2.Button {
                text: "Load"
                onClicked: page.kwalletLoad("nvidia")
            }
        }

        QQC2.TextField {
            id: huggingFaceBaseUrlField
            Kirigami.FormData.label: "HF URL:"
            visible: page.providerEnabled("huggingface")
            placeholderText: "https://router.huggingface.co/v1"
        }

        QQC2.TextField {
            id: huggingFaceModelField
            Kirigami.FormData.label: "HF model:"
            visible: page.providerEnabled("huggingface")
            placeholderText: "openai/gpt-oss-120b:groq"
        }

        RowLayout {
            Kirigami.FormData.label: "HF token:"
            visible: page.providerEnabled("huggingface")
            QQC2.TextField {
                id: huggingFaceApiKeyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "hf_..."
            }
            QQC2.Button {
                text: "Save KWallet"
                onClicked: page.kwalletStore("huggingface", huggingFaceApiKeyField.text)
            }
            QQC2.Button {
                text: "Load"
                onClicked: page.kwalletLoad("huggingface")
            }
        }

        QQC2.TextField {
            id: xaiBaseUrlField
            Kirigami.FormData.label: "xAI URL:"
            visible: page.providerEnabled("xai")
            placeholderText: "https://api.x.ai/v1"
        }

        QQC2.TextField {
            id: xaiModelField
            Kirigami.FormData.label: "xAI model:"
            visible: page.providerEnabled("xai")
            placeholderText: "grok-2-latest"
        }

        RowLayout {
            Kirigami.FormData.label: "xAI key:"
            visible: page.providerEnabled("xai")
            QQC2.TextField {
                id: xaiApiKeyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: "xai-..."
            }
            QQC2.Button {
                text: "Save KWallet"
                onClicked: page.kwalletStore("xai", xaiApiKeyField.text)
            }
            QQC2.Button {
                text: "Load"
                onClicked: page.kwalletLoad("xai")
            }
        }

        QQC2.TextField {
            id: localBaseUrlField
            Kirigami.FormData.label: "Local URL:"
            visible: page.providerEnabled("local")
            placeholderText: "http://localhost:11434/v1"
        }

        QQC2.TextField {
            id: localModelField
            Kirigami.FormData.label: "Local model:"
            visible: page.providerEnabled("local")
            placeholderText: "llama3.2"
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Behavior"
        }

        QQC2.TextArea {
            id: systemPromptArea
            Kirigami.FormData.label: "System prompt:"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            placeholderText: "You are a helpful assistant."
        }
    }
}
