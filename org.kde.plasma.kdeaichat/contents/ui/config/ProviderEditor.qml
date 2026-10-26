// The form for editing one provider (name, type, URL, key, model), shown by
// ProvidersPanel.qml. It holds no state of its own: the panel gives it the
// draft and tells it what to show, and every edit or button goes out as a
// signal.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components" as Components

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: editor

    property var draft: ({})
    property string draftKey: ""
    property bool local: false
    // The models offered: ids or {id, name}.
    property var models: []
    // Models hidden by the "chat models only" filter, and whether they are shown.
    property int hiddenCount: 0
    property bool showAll: false
    property bool listing: false
    property bool checking: false
    // A message under the form; kind is "info", "ok", "warn" or "error".
    property string message: ""
    property string messageKind: "info"
    // Set when the user may go on anyway: "Use anyway" / "Save anyway".
    property string overrideText: ""
    // Why the chosen model is flagged ("" when it is not).
    property string modelWarning: ""
    // The chosen model's variants (reasoning levels) when its provider reports
    // any: [{id, label}]. Empty: no picker.
    property var variants: []

    signal fieldEdited(string field, var value)
    signal refreshClicked()
    signal showAllToggled(bool on)
    signal saveClicked()
    signal overrideClicked()
    signal cancelClicked()

    QQC2.TextField {
        Kirigami.FormData.label: i18n("Name:")
        text: editor.draft.name || ""
        onTextEdited: editor.fieldEdited("name", text)
    }
    SettingHelp {
        text: i18n("Any name you like; it is how this provider shows in lists.")
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("API type:")
        model: [i18n("OpenAI-compatible"), i18n("Anthropic")]
        currentIndex: editor.draft.type === "anthropic" ? 1 : 0
        onActivated: editor.fieldEdited("type", currentIndex === 1 ? "anthropic" : "openai-compat")
    }
    SettingHelp {
        text: i18n("The \"language\" the provider's server speaks. Almost all services, and local programs like Ollama, use \"OpenAI-compatible\"; choose \"Anthropic\" only for Anthropic's own server.")
    }
    QQC2.TextField {
        objectName: "urlField"
        Kirigami.FormData.label: i18n("Server URL:")
        Layout.fillWidth: true
        text: editor.draft.baseUrl || ""
        placeholderText: "https://api.example.com/v1"
        onTextEdited: editor.fieldEdited("baseUrl", text)
    }
    SettingHelp {
        text: i18n("The web address of the provider's server, as given in its documentation (often ending in /v1). For a model on your own computer it starts with http://localhost.")
    }
    Kirigami.PasswordField {
        objectName: "keyField"
        Kirigami.FormData.label: i18n("API key:")
        Layout.fillWidth: true
        text: editor.draftKey
        placeholderText: editor.local ? i18n("Optional for local servers") : i18n("Stored in KWallet")
        onTextEdited: editor.fieldEdited("key", text)
    }
    SettingHelp {
        text: i18n("The password-like code your AI provider gives you (on its website, usually under \"API keys\"). It proves the requests are yours and is kept in KDE Wallet, your computer's password safe.")
        details: i18n("Anyone with this key can use your account, so it is never written into the settings file. Local servers usually need no key.")
    }
    RowLayout {
        Kirigami.FormData.label: i18n("Model:")
        Layout.fillWidth: true
        Components.ModelPicker {
            objectName: "modelPicker"
            Layout.fillWidth: true
            model: editor.models
            value: editor.draft.model || ""
            onPicked: function(id) { editor.fieldEdited("model", id); }
        }
        QQC2.Button {
            objectName: "refreshButton"
            text: i18n("Refresh")
            icon.name: "view-refresh"
            enabled: !editor.listing && !editor.checking
            onClicked: editor.refreshClicked()
        }
    }
    SettingHelp {
        text: i18n("The AI model to use with this provider. Refresh asks the provider which models it has.")
    }
    Components.VariantPicker {
        objectName: "variantPicker"
        Kirigami.FormData.label: i18n("Variant:")
        Layout.fillWidth: true
        variants: editor.variants
        value: editor.draft.variant || ""
        onPicked: function(id) { editor.fieldEdited("variant", id); }
    }
    SettingHelp {
        visible: editor.variants.length > 0
        text: i18n("Some models can think longer before answering. More thinking gives better answers to hard questions, but is slower and costs more.")
    }
    QQC2.Label {
        objectName: "modelWarning"
        visible: editor.modelWarning !== ""
        text: editor.modelWarning
        wrapMode: Text.Wrap
        color: Kirigami.Theme.neutralTextColor
        Layout.fillWidth: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20   // wraps instead of widening the form
    }
    QQC2.CheckBox {
        objectName: "showAllCheck"
        visible: editor.hiddenCount > 0 || editor.showAll
        text: i18n("Show all models (%1 hidden)", editor.hiddenCount)
        checked: editor.showAll
        onToggled: editor.showAllToggled(checked)
    }
    SettingHelp {
        visible: editor.hiddenCount > 0 || editor.showAll
        text: i18n("Only models you can chat with are listed. Turn this on to also see the others (for search, safety checks, speech or pictures).")
    }
    RowLayout {
        visible: editor.listing || editor.checking
        Layout.fillWidth: true
        QQC2.BusyIndicator {
            objectName: "busy"
            running: editor.listing || editor.checking
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }
        QQC2.Label {
            text: editor.checking ? i18n("Checking the key with the provider…") : i18n("Fetching models…")
            opacity: 0.8
        }
    }
    QQC2.Label {
        objectName: "statusLabel"
        visible: editor.message !== ""
        text: editor.message
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        color: editor.messageKind === "error" ? Kirigami.Theme.negativeTextColor
             : editor.messageKind === "warn" ? Kirigami.Theme.neutralTextColor
             : editor.messageKind === "ok" ? Kirigami.Theme.positiveTextColor
             : Kirigami.Theme.textColor
        opacity: editor.messageKind === "info" ? 0.8 : 1
    }
    RowLayout {
        QQC2.Button {
            objectName: "saveButton"
            text: i18n("Save")
            icon.name: "document-save"
            enabled: !editor.checking
            onClicked: editor.saveClicked()
        }
        QQC2.Button {
            objectName: "overrideButton"
            visible: editor.overrideText !== ""
            text: editor.overrideText
            enabled: !editor.checking
            onClicked: editor.overrideClicked()
        }
        QQC2.Button {
            objectName: "cancelButton"
            text: i18n("Cancel")
            onClicked: editor.cancelClicked()
        }
    }
}
