// LINKAGE RELATIONSHIPS:
// - ConfigProvidersKeys2.qml: Houses API key input fields and configurations for the second group of providers (xAI through Maritaca AI).
// - Parent: Instantiated inside ConfigProvidersSection.qml.
// - Linked via properties:
//   - Exposes text field controls via aliases to the parent/grandparent.
//   - Uses the `page` reference to save keys, trigger status checks, and check if a provider is currently active/enabled.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: keys2

    property var page: null

    // xAI aliases
    property alias xaiBaseUrlField: xaiBaseUrlField
    property alias xaiApiKeyField: xaiApiKeyField
    property alias xaiModelField: xaiModelField

    // LM Studio aliases
    property alias lmStudioBaseUrlField: lmStudioBaseUrlField
    property alias lmStudioModelField: lmStudioModelField

    // Local aliases
    property alias localBaseUrlField: localBaseUrlField
    property alias localModelField: localModelField

    // Ollama aliases
    property alias ollamaBaseUrlField: ollamaBaseUrlField
    property alias ollamaModelField: ollamaModelField

    // LiteLLM aliases
    property alias litellmBaseUrlField: litellmBaseUrlField
    property alias litellmApiKeyField: litellmApiKeyField
    property alias litellmModelField: litellmModelField

    // Alibaba Qwen aliases
    property alias qwenBaseUrlField: qwenBaseUrlField
    property alias qwenApiKeyField: qwenApiKeyField
    property alias qwenModelField: qwenModelField

    // Moonshot aliases
    property alias moonshotBaseUrlField: moonshotBaseUrlField
    property alias moonshotApiKeyField: moonshotApiKeyField
    property alias moonshotModelField: moonshotModelField

    // Xiaomi MiMo aliases
    property alias mimoBaseUrlField: mimoBaseUrlField
    property alias mimoApiKeyField: mimoApiKeyField
    property alias mimoModelField: mimoModelField

    // Maritaca aliases
    property alias maritacaBaseUrlField: maritacaBaseUrlField
    property alias maritacaApiKeyField: maritacaApiKeyField
    property alias maritacaModelField: maritacaModelField

    // ── xAI Grok ──────────────────────────────────────────────────────────
    QQC2.TextField {
        id: xaiBaseUrlField
        Kirigami.FormData.label: page ? page.translate("xAI URL:") : "xAI URL:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "https://api.x.ai/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("xAI key:") : "xAI key:"
        visible: page ? page.providerEnabled("xai") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth

        QQC2.TextField {
            id: xaiApiKeyField
            Layout.fillWidth: true
            echoMode: xaiKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("xai", text);
                    page.refreshIfActiveProvider("xai");
                }
            }
        }

        QQC2.Button {
            id: xaiKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("xai") : false
        Kirigami.FormData.label: page ? page.translate("xAI model:") : "xAI model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        text: page ? page.translate("Enter the xAI API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: xaiModelField
        Kirigami.FormData.label: page ? page.translate("xAI model:") : "xAI model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "grok-2-latest"
    }

    // ── LM Studio ─────────────────────────────────────────────────────────
    QQC2.TextField {
        id: lmStudioBaseUrlField
        Kirigami.FormData.label: page ? page.translate("LM Studio URL:") : "LM Studio URL:"
        visible: page ? page.providerEnabled("lmstudio") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "http://localhost:1234/v1"
    }

    QQC2.TextField {
        id: lmStudioModelField
        Kirigami.FormData.label: page ? page.translate("LM Studio model:") : "LM Studio model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: page ? page.translate("Load a model in LM Studio, then refresh models") : "Load a model in LM Studio, then refresh models"
    }

    // ── Local / OpenAI-compatible ─────────────────────────────────────────
    QQC2.TextField {
        id: localBaseUrlField
        Kirigami.FormData.label: page ? page.translate("Local URL:") : "Local URL:"
        visible: page ? page.providerEnabled("local") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "http://localhost:11434/v1"
    }

    QQC2.TextField {
        id: localModelField
        Kirigami.FormData.label: page ? page.translate("Local model:") : "Local model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "llama3.2"
    }

    // ── Ollama ────────────────────────────────────────────────────────────
    QQC2.TextField {
        id: ollamaBaseUrlField
        Kirigami.FormData.label: page ? page.translate("Ollama URL:") : "Ollama URL:"
        visible: page ? page.providerEnabled("ollama") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "http://localhost:11434/v1"
    }

    QQC2.TextField {
        id: ollamaModelField
        Kirigami.FormData.label: page ? page.translate("Ollama model:") : "Ollama model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "llama3.2"
    }

    // ── LiteLLM ───────────────────────────────────────────────────────────
    QQC2.TextField {
        id: litellmBaseUrlField
        Kirigami.FormData.label: page ? page.translate("LiteLLM URL:") : "LiteLLM URL:"
        visible: page ? page.providerEnabled("litellm") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "http://localhost:4000/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("LiteLLM key:") : "LiteLLM key:"
        visible: page ? page.providerEnabled("litellm") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth

        QQC2.TextField {
            id: litellmApiKeyField
            Layout.fillWidth: true
            echoMode: litellmKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("litellm", text);
                    page.refreshIfActiveProvider("litellm");
                }
            }
        }

        QQC2.Button {
            id: litellmKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("litellm") : false
        Kirigami.FormData.label: page ? page.translate("LiteLLM model:") : "LiteLLM model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        text: page ? page.translate("Enter the LiteLLM API key first if required, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: litellmModelField
        Kirigami.FormData.label: page ? page.translate("LiteLLM model:") : "LiteLLM model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "gpt-4o-mini"
    }

    // ── Alibaba Qwen ──────────────────────────────────────────────────────
    QQC2.TextField {
        id: qwenBaseUrlField
        visible: false
        Kirigami.FormData.label: page ? page.translate("Qwen URL:") : "Qwen URL:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Qwen key:") : "Qwen key:"
        visible: page ? page.providerEnabled("qwen") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth

        QQC2.TextField {
            id: qwenApiKeyField
            Layout.fillWidth: true
            echoMode: qwenKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("qwen", text);
                    page.refreshIfActiveProvider("qwen");
                }
            }
        }

        QQC2.Button {
            id: qwenKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerEnabled("qwen") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: "Get your API key at dashscope.aliyuncs.com. Supports qwen-max, qwen-plus, qwen-turbo."
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("qwen") : false
        Kirigami.FormData.label: page ? page.translate("Qwen model:") : "Qwen model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        text: page ? page.translate("Enter the Qwen API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: qwenModelField
        Kirigami.FormData.label: page ? page.translate("Qwen model:") : "Qwen model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "qwen-max"
    }

    // ── Moonshot AI ───────────────────────────────────────────────────────
    QQC2.TextField {
        id: moonshotBaseUrlField
        visible: false
        Kirigami.FormData.label: page ? page.translate("Moonshot URL:") : "Moonshot URL:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "https://api.moonshot.ai/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Moonshot key:") : "Moonshot key:"
        visible: page ? page.providerEnabled("moonshot") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth

        QQC2.TextField {
            id: moonshotApiKeyField
            Layout.fillWidth: true
            echoMode: moonshotKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("moonshot", text);
                    page.refreshIfActiveProvider("moonshot");
                }
            }
        }

        QQC2.Button {
            id: moonshotKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerEnabled("moonshot") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: "Get your API key at platform.moonshot.ai. Supports moonshot-v1-8k, moonshot-v1-32k."
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("moonshot") : false
        Kirigami.FormData.label: page ? page.translate("Moonshot model:") : "Moonshot model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        text: page ? page.translate("Enter the Moonshot API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: moonshotModelField
        Kirigami.FormData.label: page ? page.translate("Moonshot model:") : "Moonshot model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "moonshot-v1-8k"
    }

    // ── Xiaomi MiMo ───────────────────────────────────────────────────────
    QQC2.TextField {
        id: mimoBaseUrlField
        visible: false
        Kirigami.FormData.label: page ? page.translate("MiMo URL:") : "MiMo URL:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "https://api.xiaomimimo.com/v1"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("MiMo key:") : "MiMo key:"
        visible: page ? page.providerEnabled("mimo") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth

        QQC2.TextField {
            id: mimoApiKeyField
            Layout.fillWidth: true
            echoMode: mimoKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("mimo", text);
                    page.refreshIfActiveProvider("mimo");
                }
            }
        }

        QQC2.Button {
            id: mimoKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerEnabled("mimo") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: "Get your API key at xiaomimimo.com. Supports mimo-v2-pro and other MiMo models."
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("mimo") : false
        Kirigami.FormData.label: page ? page.translate("MiMo model:") : "MiMo model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        text: page ? page.translate("Enter the MiMo API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: mimoModelField
        Kirigami.FormData.label: page ? page.translate("MiMo model:") : "MiMo model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "mimo-v2-pro"
    }

    // ── Maritaca AI ───────────────────────────────────────────────────────
    QQC2.TextField {
        id: maritacaBaseUrlField
        visible: false
        Kirigami.FormData.label: page ? page.translate("Maritaca URL:") : "Maritaca URL:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "https://chat.maritaca.ai/api"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Maritaca key:") : "Maritaca key:"
        visible: page ? page.providerEnabled("maritaca") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth

        QQC2.TextField {
            id: maritacaApiKeyField
            Layout.fillWidth: true
            echoMode: maritacaKeyShowHide.checked ? TextInput.Normal : TextInput.Password
            onEditingFinished: {
                if (page) {
                    page.saveKey("maritaca", text);
                    page.refreshIfActiveProvider("maritaca");
                }
            }
        }

        QQC2.Button {
            id: maritacaKeyShowHide
            checkable: true
            text: checked ? (page ? page.translate("Hide") : "Hide") : (page ? page.translate("Show") : "Show")
        }
    }

    QQC2.Label {
        visible: page ? page.providerEnabled("maritaca") : false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: "Get your API key at chat.maritaca.ai. Default model: sabia-4 (Portuguese-optimised)."
    }

    QQC2.Label {
        visible: page ? page.providerNeedsKeyHintVisible("maritaca") : false
        Kirigami.FormData.label: page ? page.translate("Maritaca model:") : "Maritaca model:"
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        text: page ? page.translate("Enter the Maritaca API key first, then refresh models or type a model name.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.TextField {
        id: maritacaModelField
        Kirigami.FormData.label: page ? page.translate("Maritaca model:") : "Maritaca model:"
        visible: false
        Layout.fillWidth: true
        Layout.maximumWidth: keys2.fieldMaxWidth
        placeholderText: "sabia-4"
    }

    readonly property real fieldMaxWidth: page ? page.fieldMaxWidth : Kirigami.Units.gridUnit * 28
}
