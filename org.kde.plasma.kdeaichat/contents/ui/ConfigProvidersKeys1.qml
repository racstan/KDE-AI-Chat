// LINKAGE RELATIONSHIPS:
// - ConfigProvidersKeys1.qml: Houses API key input fields and configuration layouts for the first group of providers (OpenAI through Hugging Face).
// - Parent: Instantiated inside ConfigProvidersSection.qml.
// - Linked via properties:
//   - Exposes text field controls via aliases to the parent/grandparent.
//   - Uses the `page` reference to save keys, trigger status checks, and check if a provider is currently active/enabled.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: keys1

    property var page: null

    // OpenAI aliases
    property alias baseUrlField: baseUrlField
    property alias apiKeyField: apiKeyField
    property alias modelField: modelField

    // Anthropic aliases
    property alias anthropicApiKeyField: anthropicApiKeyField
    property alias anthropicModelField: anthropicModelField

    // Groq aliases
    property alias groqBaseUrlField: groqBaseUrlField
    property alias groqApiKeyField: groqApiKeyField
    property alias groqModelField: groqModelField

    // DeepSeek aliases
    property alias deepSeekBaseUrlField: deepSeekBaseUrlField
    property alias deepSeekApiKeyField: deepSeekApiKeyField
    property alias deepSeekModelField: deepSeekModelField

    // MiniMax aliases
    property alias miniMaxBaseUrlField: miniMaxBaseUrlField
    property alias miniMaxApiKeyField: miniMaxApiKeyField
    property alias miniMaxModelField: miniMaxModelField

    // Fireworks aliases
    property alias fireworksBaseUrlField: fireworksBaseUrlField
    property alias fireworksApiKeyField: fireworksApiKeyField
    property alias fireworksModelField: fireworksModelField

    // Google Gemini aliases
    property alias googleBaseUrlField: googleBaseUrlField
    property alias googleApiKeyField: googleApiKeyField
    property alias googleModelField: googleModelField

    // OpenRouter aliases
    property alias openRouterBaseUrlField: openRouterBaseUrlField
    property alias openRouterApiKeyField: openRouterApiKeyField
    property alias openRouterModelField: openRouterModelField

    // Mistral aliases
    property alias mistralBaseUrlField: mistralBaseUrlField
    property alias mistralApiKeyField: mistralApiKeyField
    property alias mistralModelField: mistralModelField

    // Cloudflare aliases
    property alias cloudflareBaseUrlField: cloudflareBaseUrlField
    property alias cloudflareApiKeyField: cloudflareApiKeyField
    property alias cloudflareModelField: cloudflareModelField

    // NVIDIA NIM aliases
    property alias nvidiaBaseUrlField: nvidiaBaseUrlField
    property alias nvidiaApiKeyField: nvidiaApiKeyField
    property alias nvidiaModelField: nvidiaModelField

    // Hugging Face aliases
    property alias huggingFaceBaseUrlField: huggingFaceBaseUrlField
    property alias huggingFaceApiKeyField: huggingFaceApiKeyField
    property alias huggingFaceModelField: huggingFaceModelField

    // ── OpenAI ────────────────────────────────────────────────────────────
    QQC2.TextField {
        id: baseUrlField
        Kirigami.FormData.label: page ? page.translate("OpenAI URL:") : "OpenAI URL:"
        visible: page ? page.providerEnabled("openai") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://api.openai.com/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("OpenAI key:") : "OpenAI key:"
        visible: page ? page.providerEnabled("openai") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: apiKeyField
            Layout.fillWidth: true
            echoMode: apiKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("openai", text);
                    page.refreshIfActiveProvider("openai");
                }
            }
        }

        QQC2.Button {
            id: apiKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("openai") : false
        Kirigami.FormData.label: page ? page.translate("OpenAI model:") : "OpenAI model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the OpenAI API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: modelField
        Kirigami.FormData.label: page ? page.translate("OpenAI model:") : "OpenAI model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "gpt-4o-mini"
    }

    // ── Anthropic ─────────────────────────────────────────────────────────
    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Anthropic key:") : "Anthropic key:"
        visible: page ? page.providerEnabled("anthropic") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: anthropicApiKeyField
            Layout.fillWidth: true
            echoMode: anthropicKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("anthropic", text);
                    page.refreshIfActiveProvider("anthropic");
                }
            }
        }

        QQC2.Button {
            id: anthropicKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("anthropic") : false
        Kirigami.FormData.label: page ? page.translate("Anthropic model:") : "Anthropic model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the Anthropic API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: anthropicModelField
        Kirigami.FormData.label: page ? page.translate("Anthropic model:") : "Anthropic model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "claude-3-5-sonnet-latest"
    }

    // ── Groq ──────────────────────────────────────────────────────────────
    QQC2.TextField {
        id: groqBaseUrlField
        Kirigami.FormData.label: page ? page.translate("Groq URL:") : "Groq URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://api.groq.com/openai/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Groq key:") : "Groq key:"
        visible: page ? page.providerEnabled("groq") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: groqApiKeyField
            Layout.fillWidth: true
            echoMode: groqKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("groq", text);
                    page.refreshIfActiveProvider("groq");
                }
            }
        }

        QQC2.Button {
            id: groqKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("groq") : false
        Kirigami.FormData.label: page ? page.translate("Groq model:") : "Groq model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the Groq API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: groqModelField
        Kirigami.FormData.label: page ? page.translate("Groq model:") : "Groq model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "llama-3.3-70b-versatile"
    }

    // ── DeepSeek ──────────────────────────────────────────────────────────
    QQC2.TextField {
        id: deepSeekBaseUrlField
        Kirigami.FormData.label: page ? page.translate("DeepSeek URL:") : "DeepSeek URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://api.deepseek.com"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("DeepSeek key:") : "DeepSeek key:"
        visible: page ? page.providerEnabled("deepseek") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: deepSeekApiKeyField
            Layout.fillWidth: true
            echoMode: deepSeekKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("deepseek", text);
                    page.refreshIfActiveProvider("deepseek");
                }
            }
        }

        QQC2.Button {
            id: deepSeekKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("deepseek") : false
        Kirigami.FormData.label: page ? page.translate("DeepSeek model:") : "DeepSeek model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the DeepSeek API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: deepSeekModelField
        Kirigami.FormData.label: page ? page.translate("DeepSeek model:") : "DeepSeek model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "deepseek-v4-pro"
    }

    // ── MiniMax ───────────────────────────────────────────────────────────
    QQC2.TextField {
        id: miniMaxBaseUrlField
        Kirigami.FormData.label: page ? page.translate("MiniMax URL:") : "MiniMax URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://api.minimax.io/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("MiniMax key:") : "MiniMax key:"
        visible: page ? page.providerEnabled("minimax") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: miniMaxApiKeyField
            Layout.fillWidth: true
            echoMode: miniMaxKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("minimax", text);
                    page.refreshIfActiveProvider("minimax");
                }
            }
        }

        QQC2.Button {
            id: miniMaxKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("minimax") : false
        Kirigami.FormData.label: page ? page.translate("MiniMax model:") : "MiniMax model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the MiniMax API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: miniMaxModelField
        Kirigami.FormData.label: page ? page.translate("MiniMax model:") : "MiniMax model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "MiniMax-M2.7"
    }

    // ── Fireworks ─────────────────────────────────────────────────────────
    QQC2.TextField {
        id: fireworksBaseUrlField
        Kirigami.FormData.label: page ? page.translate("Fireworks URL:") : "Fireworks URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://api.fireworks.ai/inference/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Fireworks key:") : "Fireworks key:"
        visible: page ? page.providerEnabled("fireworks") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: fireworksApiKeyField
            Layout.fillWidth: true
            echoMode: fireworksKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("fireworks", text);
                    page.refreshIfActiveProvider("fireworks");
                }
            }
        }

        QQC2.Button {
            id: fireworksKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("fireworks") : false
        Kirigami.FormData.label: page ? page.translate("Fireworks model:") : "Fireworks model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the Fireworks API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: fireworksModelField
        Kirigami.FormData.label: page ? page.translate("Fireworks model:") : "Fireworks model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "accounts/fireworks/models/llama-v3p3-70b-instruct"
    }

    // ── Google Gemini ─────────────────────────────────────────────────────
    QQC2.TextField {
        id: googleBaseUrlField
        Kirigami.FormData.label: page ? page.translate("Google URL:") : "Google URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://generativelanguage.googleapis.com/v1beta/openai/"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Google key:") : "Google key:"
        visible: page ? page.providerEnabled("google") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: googleApiKeyField
            Layout.fillWidth: true
            echoMode: googleKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("google", text);
                    page.refreshIfActiveProvider("google");
                }
            }
        }

        QQC2.Button {
            id: googleKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("google") : false
        Kirigami.FormData.label: page ? page.translate("Google model:") : "Google model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the Gemini API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: googleModelField
        Kirigami.FormData.label: page ? page.translate("Google model:") : "Google model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "gemini-3-flash-preview"
    }

    // ── OpenRouter ────────────────────────────────────────────────────────
    QQC2.TextField {
        id: openRouterBaseUrlField
        Kirigami.FormData.label: page ? page.translate("OpenRouter URL:") : "OpenRouter URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://openrouter.ai/api/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("OpenRouter key:") : "OpenRouter key:"
        visible: page ? page.providerEnabled("openrouter") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: openRouterApiKeyField
            Layout.fillWidth: true
            echoMode: openRouterKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("openrouter", text);
                    page.refreshIfActiveProvider("openrouter");
                }
            }
        }

        QQC2.Button {
            id: openRouterKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("openrouter") : false
        Kirigami.FormData.label: page ? page.translate("OpenRouter model:") : "OpenRouter model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the OpenRouter API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: openRouterModelField
        Kirigami.FormData.label: page ? page.translate("OpenRouter model:") : "OpenRouter model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "openai/gpt-4o-mini"
    }

    // ── Mistral ───────────────────────────────────────────────────────────
    QQC2.TextField {
        id: mistralBaseUrlField
        Kirigami.FormData.label: page ? page.translate("Mistral URL:") : "Mistral URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://api.mistral.ai/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Mistral key:") : "Mistral key:"
        visible: page ? page.providerEnabled("mistral") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: mistralApiKeyField
            Layout.fillWidth: true
            echoMode: mistralKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("mistral", text);
                    page.refreshIfActiveProvider("mistral");
                }
            }
        }

        QQC2.Button {
            id: mistralKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("mistral") : false
        Kirigami.FormData.label: page ? page.translate("Mistral model:") : "Mistral model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the Mistral API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: mistralModelField
        Kirigami.FormData.label: page ? page.translate("Mistral model:") : "Mistral model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "mistral-small-latest"
    }

    // ── Cloudflare ────────────────────────────────────────────────────────
    QQC2.TextField {
        id: cloudflareBaseUrlField
        Kirigami.FormData.label: page ? page.translate("Cloudflare URL:") : "Cloudflare URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Cloudflare key:") : "Cloudflare key:"
        visible: page ? page.providerEnabled("cloudflare") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: cloudflareApiKeyField
            Layout.fillWidth: true
            echoMode: cloudflareKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("cloudflare", text);
                    page.refreshIfActiveProvider("cloudflare");
                }
            }
        }

        QQC2.Button {
            id: cloudflareKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("cloudflare") : false
        Kirigami.FormData.label: page ? page.translate("Cloudflare model:") : "Cloudflare model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the Cloudflare API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: cloudflareModelField
        Kirigami.FormData.label: page ? page.translate("Cloudflare model:") : "Cloudflare model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "@cf/meta/llama-3.1-8b-instruct"
    }

    // ── NVIDIA NIM ────────────────────────────────────────────────────────
    QQC2.TextField {
        id: nvidiaBaseUrlField
        Kirigami.FormData.label: page ? page.translate("NVIDIA NIM URL:") : "NVIDIA NIM URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://integrate.api.nvidia.com/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("NVIDIA NIM key:") : "NVIDIA NIM key:"
        visible: page ? page.providerEnabled("nvidia") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: nvidiaApiKeyField
            Layout.fillWidth: true
            echoMode: nvidiaKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("nvidia", text);
                    page.refreshIfActiveProvider("nvidia");
                }
            }
        }

        QQC2.Button {
            id: nvidiaKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("nvidia") : false
        Kirigami.FormData.label: page ? page.translate("NVIDIA NIM model:") : "NVIDIA NIM model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the NVIDIA NIM API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: nvidiaModelField
        Kirigami.FormData.label: page ? page.translate("NVIDIA NIM model:") : "NVIDIA NIM model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "meta/llama-3.1-70b-instruct"
    }

    // ── Hugging Face ──────────────────────────────────────────────────────
    QQC2.TextField {
        id: huggingFaceBaseUrlField
        Kirigami.FormData.label: page ? page.translate("HF URL:") : "HF URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "https://router.huggingface.co/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("HF token:") : "HF token:"
        visible: page ? page.providerEnabled("huggingface") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth

        QQC2.TextField {
            id: huggingFaceApiKeyField
            Layout.fillWidth: true
            echoMode: huggingFaceKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("huggingface", text);
                    page.refreshIfActiveProvider("huggingface");
                }
            }
        }

        QQC2.Button {
            id: huggingFaceKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("huggingface") : false
        Kirigami.FormData.label: page ? page.translate("HF model:") : "HF model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        text: page ? page.translate("Enter the Hugging Face token first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: huggingFaceModelField
        Kirigami.FormData.label: page ? page.translate("HF model:") : "HF model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys1.fieldMaxWidth
        placeholderText: "openai/gpt-oss-120b:groq"
    }

    readonly property real fieldMaxWidth: page ? page.fieldMaxWidth : Kirigami.Units.gridUnit * 28
}
