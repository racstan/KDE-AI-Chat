// LINKAGE RELATIONSHIPS:
// - ConfigProvidersSection.qml: Manages the provider selection UI, model discovery process, and encapsulates both keys1 and keys2 sub-components.
// - Parent: Instantiated inside ConfigGeneral.qml (the main KCM settings page).
// - Children: ConfigProvidersKeys1.qml (keys1) and ConfigProvidersKeys2.qml (keys2).
// - Linked via properties:
//   - Passes `page` down to children.
//   - Exposes child aliases to the grandparent (ConfigGeneral.qml) for configuration bindings.
//   - Accesses parent helper functions (e.g. page.refreshCurrentProviderModels, page.updateFilteredProviderModels) and status strings via the `page` reference.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: providersSection

    property var page: null

    // Expose provider combo for config mapping
    property alias providerBox: providerBox

    // Expose keys1 aliases
    property alias keys1: keys1
    property alias baseUrlField: keys1.baseUrlField
    property alias apiKeyField: keys1.apiKeyField
    property alias modelField: keys1.modelField
    property alias anthropicApiKeyField: keys1.anthropicApiKeyField
    property alias anthropicModelField: keys1.anthropicModelField
    property alias groqBaseUrlField: keys1.groqBaseUrlField
    property alias groqApiKeyField: keys1.groqApiKeyField
    property alias groqModelField: keys1.groqModelField
    property alias deepSeekBaseUrlField: keys1.deepSeekBaseUrlField
    property alias deepSeekApiKeyField: keys1.deepSeekApiKeyField
    property alias deepSeekModelField: keys1.deepSeekModelField
    property alias miniMaxBaseUrlField: keys1.miniMaxBaseUrlField
    property alias miniMaxApiKeyField: keys1.miniMaxApiKeyField
    property alias miniMaxModelField: keys1.miniMaxModelField
    property alias fireworksBaseUrlField: keys1.fireworksBaseUrlField
    property alias fireworksApiKeyField: keys1.fireworksApiKeyField
    property alias fireworksModelField: keys1.fireworksModelField
    property alias googleBaseUrlField: keys1.googleBaseUrlField
    property alias googleApiKeyField: keys1.googleApiKeyField
    property alias googleModelField: keys1.googleModelField
    property alias openRouterBaseUrlField: keys1.openRouterBaseUrlField
    property alias openRouterApiKeyField: keys1.openRouterApiKeyField
    property alias openRouterModelField: keys1.openRouterModelField
    property alias mistralBaseUrlField: keys1.mistralBaseUrlField
    property alias mistralApiKeyField: keys1.mistralApiKeyField
    property alias mistralModelField: keys1.mistralModelField
    property alias cloudflareBaseUrlField: keys1.cloudflareBaseUrlField
    property alias cloudflareApiKeyField: keys1.cloudflareApiKeyField
    property alias cloudflareModelField: keys1.cloudflareModelField
    property alias nvidiaBaseUrlField: keys1.nvidiaBaseUrlField
    property alias nvidiaApiKeyField: keys1.nvidiaApiKeyField
    property alias nvidiaModelField: keys1.nvidiaModelField
    property alias huggingFaceBaseUrlField: keys1.huggingFaceBaseUrlField
    property alias huggingFaceApiKeyField: keys1.huggingFaceApiKeyField
    property alias huggingFaceModelField: keys1.huggingFaceModelField

    // Expose keys2 aliases
    property alias keys2: keys2
    property alias xaiBaseUrlField: keys2.xaiBaseUrlField
    property alias xaiApiKeyField: keys2.xaiApiKeyField
    property alias xaiModelField: keys2.xaiModelField
    property alias lmStudioBaseUrlField: keys2.lmStudioBaseUrlField
    property alias lmStudioModelField: keys2.lmStudioModelField
    property alias localBaseUrlField: keys2.localBaseUrlField
    property alias localModelField: keys2.localModelField
    property alias ollamaBaseUrlField: keys2.ollamaBaseUrlField
    property alias ollamaModelField: keys2.ollamaModelField
    property alias litellmBaseUrlField: keys2.litellmBaseUrlField
    property alias litellmApiKeyField: keys2.litellmApiKeyField
    property alias litellmModelField: keys2.litellmModelField
    property alias qwenBaseUrlField: keys2.qwenBaseUrlField
    property alias qwenApiKeyField: keys2.qwenApiKeyField
    property alias qwenModelField: keys2.qwenModelField
    property alias moonshotBaseUrlField: keys2.moonshotBaseUrlField
    property alias moonshotApiKeyField: keys2.moonshotApiKeyField
    property alias moonshotModelField: keys2.moonshotModelField
    property alias mimoBaseUrlField: keys2.mimoBaseUrlField
    property alias mimoApiKeyField: keys2.mimoApiKeyField
    property alias mimoModelField: keys2.mimoModelField
    property alias maritacaBaseUrlField: keys2.maritacaBaseUrlField
    property alias maritacaApiKeyField: keys2.maritacaApiKeyField
    property alias maritacaModelField: keys2.maritacaModelField

    QQC2.ComboBox {
        id: providerBox
        visible: page ? !page.cfg_useOpenCode : true
        Kirigami.FormData.label: page ? page.translate("Default provider:") : "Default provider:"
        Layout.fillWidth: true
        Layout.maximumWidth: providersSection.fieldMaxWidth
        textRole: "text"
        valueRole: "value"
        model: [{
            "value": "openai",
            "text": "OpenAI"
        }, {
            "value": "anthropic",
            "text": "Anthropic"
        }, {
            "value": "groq",
            "text": "Groq"
        }, {
            "value": "deepseek",
            "text": "DeepSeek"
        }, {
            "value": "minimax",
            "text": "MiniMax"
        }, {
            "value": "fireworks",
            "text": "Fireworks"
        }, {
            "value": "google",
            "text": "Google Gemini"
        }, {
            "value": "openrouter",
            "text": "OpenRouter"
        }, {
            "value": "mistral",
            "text": "Mistral"
        }, {
            "value": "cloudflare",
            "text": "Cloudflare Workers AI"
        }, {
            "value": "nvidia",
            "text": "NVIDIA NIM"
        }, {
            "value": "huggingface",
            "text": "Hugging Face"
        }, {
            "value": "xai",
            "text": "xAI Grok"
        }, {
            "value": "lmstudio",
            "text": "LM Studio"
        }, {
            "value": "local",
            "text": "Local / OpenAI-compatible"
        }, {
            "value": "ollama",
            "text": "Ollama"
        }, {
            "value": "litellm",
            "text": "LiteLLM"
        }, {
            "value": "qwen",
            "text": "Alibaba Qwen"
        }, {
            "value": "moonshot",
            "text": "Moonshot AI"
        }, {
            "value": "mimo",
            "text": "Xiaomi MiMo"
        }, {
            "value": "maritaca",
            "text": "Maritaca AI"
        }]
        currentIndex: {
            if (!page) return 0;
            for (let i = 0; i < model.length; i++) {
                if (model[i].value === page.cfg_provider)
                    return i;
            }
            return 0;
        }
        onActivated: {
            if (page) {
                page.cfg_provider = currentValue;
                page.providerModelCandidates = [];
                page.discoveryStatus = "";
            }
        }
    }

    QQC2.Label {
        visible: page ? !page.cfg_useOpenCode : true
        Layout.fillWidth: true
        Layout.maximumWidth: providersSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("Select the AI backend provider that you want to use for standard chat modes.") : ""
    }

    QQC2.Button {
        visible: page ? !page.cfg_useOpenCode : true
        Kirigami.FormData.label: page ? page.translate("Model discovery:") : "Model discovery:"
        Layout.fillWidth: true
        Layout.maximumWidth: providersSection.fieldMaxWidth
        text: page ? page.translate("Refresh") : "Refresh"
        enabled: page ? (!page.providerNeedsApiKey(providerBox.currentValue || "openai") || page.providerHasConfiguredKey(providerBox.currentValue || "openai")) : false
        onClicked: { if (page) page.refreshCurrentProviderModels(); }
    }

    QQC2.Label {
        visible: page ? !page.cfg_useOpenCode : true
        Layout.fillWidth: true
        Layout.maximumWidth: providersSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("Queries the selected provider API to dynamically fetch and populate the list of available model names.") : ""
    }

    QQC2.BusyIndicator {
        visible: page ? (!page.cfg_useOpenCode && page.openCodeBusy) : false
        running: visible
        Kirigami.FormData.label: page ? page.translate("Loading:") : "Loading:"
    }

    QQC2.TextField {
        id: providerModelTextField
        visible: page ? (!page.cfg_useOpenCode && page.providerModelVisible(providerBox.currentValue || "openai")) : false
        Kirigami.FormData.label: page ? page.translate("Model:") : "Model:"
        Layout.fillWidth: true
        Layout.maximumWidth: providersSection.fieldMaxWidth
        placeholderText: page ? page.translate("Enter or search model...") : "Enter or search model..."
        rightPadding: dropdownButton.width + Kirigami.Units.smallSpacing

        Binding {
            target: providerModelTextField
            property: "text"
            value: page ? page.activeProviderModelValue() : ""
            when: page ? (!providerModelTextField.activeFocus && !providerModelPopup.visible) : false
        }

        onTextChanged: {
            if (activeFocus && page) {
                page.applyDetectedModelToActiveProvider(text);
                page.updateFilteredProviderModels(text);
                if (page.filteredProviderModels.length > 0) {
                    if (!providerModelPopup.visible) {
                        providerModelPopup.open();
                    }
                } else {
                    providerModelPopup.close();
                }
            }
        }

        onActiveFocusChanged: {
            if (!activeFocus) {
                providerModelPopup.close();
            }
        }

        onAccepted: {
            providerModelPopup.close();
        }

        QQC2.ToolButton {
            id: dropdownButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon.name: "go-down"
            flat: true
            onClicked: {
                if (providerModelPopup.visible) {
                    providerModelPopup.close();
                } else {
                    if (page) page.updateFilteredProviderModels("");
                    providerModelPopup.open();
                }
            }
        }

        QQC2.Popup {
            id: providerModelPopup
            x: 0
            y: parent.height + Kirigami.Units.smallSpacing / 2
            width: parent.width
            height: Math.min(250, providerModelListView.contentHeight + Kirigami.Units.smallSpacing * 2)
            padding: 0
            closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

            background: Rectangle {
                color: Kirigami.Theme.backgroundColor
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                border.width: 1
                radius: 4
            }

            contentItem: QQC2.ScrollView {
                clip: true
                ListView {
                    id: providerModelListView
                    model: page ? page.filteredProviderModels : []
                    delegate: QQC2.ItemDelegate {
                        width: providerModelListView.width
                        text: modelData
                        highlighted: ListView.isCurrentItem
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize
                        onClicked: {
                            providerModelTextField.text = modelData;
                            if (page) {
                                page.applyDetectedModelToActiveProvider(modelData);
                                page.updateFilteredProviderModels("");
                            }
                            providerModelPopup.close();
                        }
                    }
                }
            }
        }
    }

    QQC2.Label {
        visible: page ? (page.discoveryStatus !== "" && !page.cfg_useOpenCode) : false
        Kirigami.FormData.label: page ? page.translate("Status:") : "Status:"
        Layout.fillWidth: true
        Layout.maximumWidth: providersSection.fieldMaxWidth
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        text: {
            if (!page) return "";
            if (page.discoveryStatus.indexOf("check failed") >= 0 || page.discoveryStatus.indexOf("error") >= 0 || page.discoveryStatus.indexOf("Network error") >= 0)
                return page.discoveryStatus + (page.cfg_useOpenCode ? " → Click \"Start server\" or \"Refresh\" to retry." : "");

            return page.discoveryStatus;
        }
        wrapMode: Text.Wrap
        opacity: 0.8
        color: page ? ((page.discoveryStatus.indexOf("check failed") >= 0 || page.discoveryStatus.indexOf("error") >= 0 || page.discoveryStatus.indexOf("Network error") >= 0) ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor) : Kirigami.Theme.textColor
    }

    // ── Keys1 and Keys2 are now sibling FormLayouts in ConfigGeneral.qml ──
    // They are NOT nested here because nesting Kirigami.FormLayouts breaks
    // the Kirigami.FormData label propagation. Instead they are separate
    // Kirigami.FormLayout instances stacked vertically in zoomHost and
    // linked back via twinFormLayouts.

    readonly property real fieldMaxWidth: page ? page.fieldMaxWidth : Kirigami.Units.gridUnit * 28
}
