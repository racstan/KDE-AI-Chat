// LINKAGE RELATIONSHIPS:
// - ConfigGeneralSection.qml: Contains the UI for basic general settings (Appearance, Language, Sound, Guides, Key Storage, and KWallet configuration).
// - Parent: Instantiated inside ConfigGeneral.qml (the main KCM settings page).
// - Linked via properties:
//   - Exposes child control elements via aliases (e.g., appearanceModeCombo, storageModeCombo) to the parent for configuration binding (cfg_).
//   - Accesses parent properties and helper methods (e.g., page.cfg_language, page.detectWallets, page.keyringBusy) via the `page` reference.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: generalSection

    property var page: null

    // Aliases to let parent link to settings backend bindings (cfg_ aliases)
    property alias appearanceModeCombo: appearanceModeCombo
    property alias playSoundToggle: playSoundToggle
    property alias showGuidesToggle: showGuidesToggle
    property alias openCodeToggle: openCodeToggle
    property alias storageModeCombo: storageModeCombo
    property alias walletNameField: walletNameField

    // Value aliases for config bindings to avoid double-nested aliases in parent
    property alias appearanceMode: appearanceModeCombo.currentIndex
    property alias playSound: playSoundToggle.checked
    property alias showGuides: showGuidesToggle.checked
    property alias openCode: openCodeToggle.checked
    property alias storageMode: storageModeCombo.currentIndex
    property alias walletName: walletNameField.text
    property alias kwalletAutoPrompt: kwalletAutoPromptCheck.checked

    QQC2.TextField {
        id: walletNameField
        visible: false
        text: "kdeaichatwallet"
    }

    RowLayout {
        visible: page ? page.cfg_showInteractiveGuides : false
        Layout.fillWidth: true
        Layout.maximumWidth: generalSection.fieldMaxWidth
        spacing: Kirigami.Units.gridUnit
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("General Guide") : "General Guide"

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: guideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: guideLayout
                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "help-hint"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                    Layout.alignment: Qt.AlignTop
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: generalSection.guideText
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }

    ColumnLayout {
        Kirigami.FormData.label: page ? page.translate("Appearance:") : "Appearance:"
        Layout.fillWidth: true
        Layout.maximumWidth: generalSection.fieldMaxWidth
        spacing: Kirigami.Units.smallSpacing

        QQC2.ComboBox {
            id: appearanceModeCombo
            Layout.fillWidth: true
            Layout.maximumWidth: generalSection.fieldMaxWidth
            model: page ? [page.translate("Follow system"), page.translate("Light mode"), page.translate("Dark mode")] : ["Follow system", "Light mode", "Dark mode"]
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: generalSection.fieldMaxWidth
            wrapMode: Text.Wrap
            opacity: 0.72
            font: Kirigami.Theme.smallFont
            text: page ? page.translate("Choose whether the chat widget follows your system theme or is pinned to light/dark mode.") : ""
        }
    }

    ColumnLayout {
        Kirigami.FormData.label: page ? page.translate("Language:") : "Language:"
        Layout.fillWidth: true
        Layout.maximumWidth: generalSection.fieldMaxWidth
        spacing: Kirigami.Units.smallSpacing

        QQC2.ComboBox {
            id: languageCombo
            Layout.fillWidth: true
            Layout.maximumWidth: generalSection.fieldMaxWidth
            textRole: "text"
            valueRole: "value"
            model: [{
                "value": "",
                "text": page ? page.translate("Choose system language") : "Choose system language"
            }, {
                "value": "en",
                "text": "English"
            }, {
                "value": "ar",
                "text": "Arabic (عربي)"
            }, {
                "value": "zh",
                "text": "Chinese (中文)"
            }, {
                "value": "fr",
                "text": "French (Français)"
            }, {
                "value": "de",
                "text": "German (Deutsch)"
            }, {
                "value": "hi",
                "text": "Hindi (हिंदी)"
            }, {
                "value": "it",
                "text": "Italian (Italiano)"
            }, {
                "value": "ja",
                "text": "Japanese (日本語)"
            }, {
                "value": "pt",
                "text": "Portuguese (Português)"
            }, {
                "value": "ru",
                "text": "Russian (Русский)"
            }, {
                "value": "es",
                "text": "Spanish (Español)"
            }]
            currentIndex: {
                if (!page) return 0;
                for (let i = 0; i < model.length; i++) {
                    if (model[i].value === page.cfg_language)
                        return i;
                }
                return 0;
            }
            onActivated: {
                if (page) page.cfg_language = currentValue;
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: generalSection.fieldMaxWidth
            wrapMode: Text.Wrap
            opacity: 0.72
            font: Kirigami.Theme.smallFont
            text: page ? page.translate("Choose the display language for the widget interface.") : ""
        }

        QQC2.Label {
            visible: page ? !page.isLanguageEnglish : false
            Layout.fillWidth: true
            Layout.maximumWidth: generalSection.fieldMaxWidth
            wrapMode: Text.Wrap
            color: Kirigami.Theme.neutralColor
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
            text: page ? page.translate("This plasmoid is being built in English so there maybe errors in translation. Switch to English language if any problem arises.") : ""
        }
    }

    QQC2.CheckBox {
        id: playSoundToggle
        Kirigami.FormData.label: page ? page.translate("Notification sound:") : "Notification sound:"
        Layout.maximumWidth: generalSection.fieldMaxWidth
        text: page ? page.translate("Play sound when AI finishes a response") : ""
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: generalSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("Plays a sound notification when the AI assistant completes its response.") : ""
    }

    QQC2.CheckBox {
        id: showGuidesToggle
        Kirigami.FormData.label: page ? page.translate("Interactive Guides:") : "Interactive Guides:"
        Layout.maximumWidth: generalSection.fieldMaxWidth
        text: page ? page.translate("Turn on interactive guides (Recommended)") : ""
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: generalSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("Displays detailed setup and configuration guides at the top of the settings page.") : ""
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("Provider & Mode") : "Provider & Mode"
    }

    RowLayout {
        visible: page ? page.cfg_showInteractiveGuides : false
        Layout.fillWidth: true
        Layout.maximumWidth: generalSection.fieldMaxWidth
        spacing: Kirigami.Units.gridUnit
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: (page && page.cfg_useOpenCode) ? page.translate("OpenCode Guide") : (page ? page.translate("Provider Guide") : "Provider Guide")

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: providerGuideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: providerGuideLayout
                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "help-hint"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                    Layout.alignment: Qt.AlignTop
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: generalSection.providerGuideText
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }

    QQC2.CheckBox {
        id: normalModeToggle
        Kirigami.FormData.label: page ? page.translate("Operating mode:") : "Operating mode:"
        Layout.maximumWidth: generalSection.fieldMaxWidth
        text: page ? page.translate("Normal Mode (Cloud & Local API Providers)") : ""
        checked: page ? !page.cfg_useOpenCode : true
        onClicked: {
            if (checked) {
                openCodeToggle.checked = false;
            } else {
                checked = true;
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: generalSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("Use cloud-based (OpenAI, Anthropic, Gemini, Groq, DeepSeek, etc.) or local API providers (Ollama, LM Studio, LiteLLM) to power your chat. Select your provider and configure API keys below.") : ""
    }

    QQC2.CheckBox {
        id: openCodeToggle
        Kirigami.FormData.label: ""
        Layout.maximumWidth: generalSection.fieldMaxWidth
        text: page ? page.translate("OpenCode Mode (Uses Opencode)") : ""
        onClicked: {
            if (checked) {
                normalModeToggle.checked = false;
            } else {
                checked = true;
            }
        }
        onCheckedChanged: {
            if (checked) {
                normalModeToggle.checked = false;
                if (page) page.checkAndAutoStartOpenCodeServer();
            } else {
                normalModeToggle.checked = true;
                if (page) {
                    if (page.cfg_keyStorageMode === 2 && page.availableWalletNames.length === 0)
                        page.detectWallets();
                }
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: generalSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("Use your local offline OpenCode agent server for secure, private developer assistance and system scripting without sending data to the cloud.") : ""
    }

    // Internal read-only helpers referencing page properties
    readonly property real boundedWidth: page ? page.boundedWidth : Kirigami.Units.gridUnit * 28
    readonly property real fieldMaxWidth: page ? page.fieldMaxWidth : Kirigami.Units.gridUnit * 28
    readonly property string guideText: page ? page.guideText : ""
    readonly property string providerGuideText: page ? page.providerGuideText : ""
    readonly property string apiGuideText: page ? page.apiGuideText : ""
}
