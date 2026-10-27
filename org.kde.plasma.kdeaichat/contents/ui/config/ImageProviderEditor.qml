// The form for one image service (AI Horde, Pollinations), shown by ImageProvidersPanel.qml.
// It holds no state of its own: the panel gives it the draft and every edit or button goes
// out as a signal. A service is off until you tick "Use ..." after reading what it sends where.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../backends/HordeBackend.js" as Horde
import "../backends/PollinationsBackend.js" as Pollinations
import "../components" as Components

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: editor

    property var draft: ({})
    property string draftKey: ""
    // [{id, name}] from config/ImageModels.qml.
    property var models: []
    property bool listing: false
    // "" | "unreachable" | "failed"
    property string listError: ""
    property string message: ""
    property string messageKind: "info"

    readonly property string service: draft.service || ""
    readonly property bool isHorde: service === "horde"
    readonly property bool isLegacy: service === "pollinations-legacy"
    readonly property bool hasKey: draftKey.trim() !== ""
    readonly property var options: draft.options || ({})
    readonly property string serviceName: isHorde ? "AI Horde" : "Pollinations"
    // AI Horde allows 576 px without an account (more needs kudos); the others take up to 1024.
    readonly property int maxSize: isHorde ? (hasKey ? Horde.KEY_MAX_SIZE : Horde.ANON_MAX_SIZE) : Pollinations.MAX_SIZE
    readonly property var sizes: {
        var out = [];
        var step = isHorde ? 64 : 128;
        for (var s = 256; s <= maxSize; s += step)
            out.push(s);
        return out;
    }

    signal fieldEdited(string field, var value)
    signal refreshClicked()
    signal saveClicked()
    signal cancelClicked()

    function sizeIndex(value, fallback) {
        var n = Number(value) > 0 ? Math.min(Number(value), maxSize) : fallback;
        var best = 0;
        for (var i = 0; i < sizes.length; i++) {
            if (Math.abs(sizes[i] - n) < Math.abs(sizes[best] - n))
                best = i;
        }
        return best;
    }

    QQC2.TextField {
        Accessible.name: Kirigami.FormData.label
        objectName: "image_nameField"
        Kirigami.FormData.label: i18n("Name:")
        text: editor.draft.name || ""
        onTextEdited: editor.fieldEdited("name", text)
    }
    SettingHelp {
        text: i18n("Any name you like; it is how this picture service shows in lists.")
    }

    // What this service does with a prompt, and where its rules are.
    ColumnLayout {
        Kirigami.FormData.label: i18n("Before you use it:")
        Layout.fillWidth: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            objectName: "privacyNote"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: editor.isHorde
                ? i18n("Your prompt is sent to AI Horde and made into a picture on a volunteer's computer, so the volunteer can see it. Pictures made without an account are shared with LAION, a research dataset. Anonymous requests wait behind others, so a picture can take a minute or more. Don't put personal details or secrets in a prompt. Only your prompt is sent, never the chat.")
                : editor.isLegacy
                ? i18n("Your prompt is sent to Pollinations. This is their older free service: it may stop working, it makes one picture every 45 seconds, and it adds a Pollinations logo to the picture. Don't put personal details or secrets in a prompt. Only your prompt is sent, never the chat.")
                : i18n("Your prompt is sent to Pollinations, with your own key. Don't put personal details or secrets in a prompt. Only your prompt is sent, never the chat.")
        }
        Kirigami.UrlButton {
            Accessible.name: text
            objectName: "termsLink"
            url: editor.isHorde ? "https://aihorde.net/terms" : "https://pollinations.ai"
            text: editor.isHorde ? i18n("AI Horde terms of use") : i18n("pollinations.ai")
        }
        Kirigami.UrlButton {
            Accessible.name: text
            visible: editor.service === "pollinations"
            url: "https://enter.pollinations.ai"
            text: i18n("Get a Pollinations key")
        }
        QQC2.CheckBox {
            objectName: "acceptCheck"
            text: i18n("Use %1 for pictures", editor.serviceName)
            checked: editor.draft.accepted === true
            onToggled: editor.fieldEdited("accepted", checked)
        }
        SettingHelp {
            text: i18n("No picture is made with this service until you have read the note above and ticked this box.")
        }
    }

    Kirigami.PasswordField {
        Accessible.name: Kirigami.FormData.label
        objectName: "image_keyField"
        visible: !editor.isLegacy
        Kirigami.FormData.label: i18n("API key:")
        Layout.fillWidth: true
        text: editor.draftKey
        placeholderText: editor.isHorde ? i18n("Optional: empty uses AI Horde without an account") : i18n("Your Pollinations key, stored in KWallet")
        onTextEdited: editor.fieldEdited("key", text)
    }
    SettingHelp {
        visible: !editor.isLegacy
        text: editor.isHorde
            ? i18n("The password-like code of your AI Horde account. Without one you can still make pictures, but they are smaller and wait longer. It is kept in KDE Wallet, your computer's password safe.")
            : i18n("The password-like code Pollinations gives you on its website. It is kept in KDE Wallet, your computer's password safe, never in the settings file.")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Model:")
        Layout.fillWidth: true
        Components.ModelPicker {
            objectName: "image_modelPicker"
            Layout.fillWidth: true
            enabled: !editor.isLegacy
            allowCustom: !editor.isHorde   // AI Horde: only the safe list (HordeBackend.parseModels)
            model: editor.models
            value: editor.draft.model || ""
            placeholderText: editor.isHorde ? i18n("Chosen for you when empty") : ""
            onPicked: function(id) { editor.fieldEdited("model", id); }
        }
        QQC2.Button {
            objectName: "image_refreshButton"
            visible: !editor.isLegacy
            text: i18n("Refresh")
            icon.name: "view-refresh"
            enabled: !editor.listing
            onClicked: editor.refreshClicked()
        }
    }
    SettingHelp {
        text: i18n("The picture model: each draws in its own style. Refresh asks the service which ones it has.")
    }
    RowLayout {
        visible: editor.listing || editor.listError !== ""
        Layout.fillWidth: true
        QQC2.BusyIndicator {
            running: editor.listing
            visible: editor.listing
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }
        QQC2.Label {
            objectName: "listNote"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.8
            text: editor.listing ? i18n("Fetching models…")
                : editor.isHorde ? i18n("Could not get AI Horde's model list. Leave the model empty to use a common one, or try Refresh later.")
                : editor.listError === "unreachable" ? i18n("Could not reach %1 to list its models. You can still type a model name.", editor.serviceName)
                : i18n("%1 sent no usable model list. You can still type a model name.", editor.serviceName)
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Picture size:")
        QQC2.ComboBox {
            objectName: "widthBox"
            model: editor.sizes
            currentIndex: editor.sizeIndex(editor.options.width, 512)
            onActivated: editor.fieldEdited("option.width", editor.sizes[currentIndex])
            Accessible.name: i18n("Width")
        }
        QQC2.Label { text: "×" }
        QQC2.ComboBox {
            objectName: "heightBox"
            model: editor.sizes
            currentIndex: editor.sizeIndex(editor.options.height, 512)
            onActivated: editor.fieldEdited("option.height", editor.sizes[currentIndex])
            Accessible.name: i18n("Height")
        }
        QQC2.Label { text: i18n("pixels") }
    }
    SettingHelp {
        text: i18n("Width × height of new pictures. Bigger pictures show more detail but take longer.")
    }
    QQC2.Label {
        objectName: "sizeNote"
        visible: editor.isHorde && !editor.hasKey
        Layout.fillWidth: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        wrapMode: Text.Wrap
        opacity: 0.75
        text: i18n("Without an account AI Horde makes one picture at a time, up to %1 pixels wide or high and %2 steps. More needs an account with kudos.", Horde.ANON_MAX_SIZE, Horde.ANON_MAX_STEPS)
    }
    QQC2.SpinBox {
        Accessible.name: Kirigami.FormData.label
        objectName: "stepsBox"
        visible: editor.isHorde
        Kirigami.FormData.label: i18n("Steps:")
        from: 10
        to: editor.hasKey ? Horde.MAX_STEPS : Horde.ANON_MAX_STEPS
        value: Math.min(editor.options.steps || Horde.DEFAULT_STEPS, to)
        onValueModified: editor.fieldEdited("option.steps", value)
    }
    SettingHelp {
        visible: editor.isHorde
        text: i18n("How many times the picture is refined. More steps can look better but take longer.")
    }
    QQC2.SpinBox {
        Accessible.name: Kirigami.FormData.label
        objectName: "countBox"
        visible: editor.isHorde && editor.hasKey
        Kirigami.FormData.label: i18n("Pictures per message:")
        from: 1
        to: 4
        value: Math.min(editor.options.n || 1, to)
        onValueModified: editor.fieldEdited("option.n", value)
    }
    SettingHelp {
        visible: editor.isHorde && editor.hasKey
        text: i18n("How many different pictures each /image message asks for.")
    }
    QQC2.TextField {
        Accessible.name: Kirigami.FormData.label
        objectName: "seedField"
        Kirigami.FormData.label: i18n("Seed:")
        Layout.maximumWidth: Kirigami.Units.gridUnit * 10
        text: editor.options.seed !== undefined ? String(editor.options.seed) : ""
        placeholderText: i18n("Empty: a new one each time")
        validator: IntValidator { bottom: 0; top: 2147483647 }
        onTextEdited: editor.fieldEdited("option.seed", text === "" ? null : Number(text))
    }
    SettingHelp {
        text: i18n("A number that fixes the randomness: the same prompt with the same seed gives the same picture again. Leave empty for a different picture every time.")
    }

    QQC2.Label {
        objectName: "image_statusLabel"
        visible: editor.message !== ""
        text: editor.message
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        color: editor.messageKind === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
    }
    RowLayout {
        QQC2.Button {
            objectName: "image_saveButton"
            text: i18n("Save")
            icon.name: "document-save"
            onClicked: editor.saveClicked()
        }
        QQC2.Button {
            objectName: "image_cancelButton"
            text: i18n("Cancel")
            onClicked: editor.cancelClicked()
        }
    }
}
