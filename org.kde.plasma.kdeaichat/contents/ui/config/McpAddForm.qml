// Settings → Tools → Add server: a program on this computer (command, arguments, environment) or a web
// address (URL, headers). Any environment value or header can be marked "Secret": it is kept in KWallet.
// Saving goes through config/McpStore.qml (`save` is given the form's values).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified
ColumnLayout {
    id: form

    property bool saving: false
    property string error: ""

    signal saveRequested(var values)
    signal cancelled()

    readonly property bool isUrl: urlRadio.checked

    function reset() {
        nameField.text = "";
        commandRadio.checked = true;
        commandField.text = "";
        argsField.text = "";
        cwdField.text = "";
        urlField.text = "";
        envEditor.clear();
        headerEditor.clear();
        form.error = "";
    }

    function values() {
        return {"name": nameField.text, "kind": form.isUrl ? "url" : "command", "command": commandField.text, "args": argsField.text,
                "cwd": cwdField.text, "url": urlField.text, "env": envEditor.rows(), "headers": headerEditor.rows()};
    }

    spacing: Kirigami.Units.largeSpacing

    Kirigami.Heading {
        level: 3
        text: i18n("Add an MCP server")
        Layout.fillWidth: true
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.TextField {
            id: nameField
            objectName: "mcpNameField"
            Kirigami.FormData.label: i18n("Name:")
            Layout.fillWidth: true
            placeholderText: i18n("For example: files")
        }
        SettingHelp {
            text: i18n("A short name. It is also how the tools of this server are named for the AI.")
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Kind:")
            Kirigami.FormData.buddyFor: commandRadio
            spacing: 0
            QQC2.RadioButton {
                id: commandRadio
                objectName: "mcpKindCommand"
                checked: true
                text: i18n("A program on this computer")
            }
            QQC2.RadioButton {
                id: urlRadio
                objectName: "mcpKindUrl"
                text: i18n("A web address (URL)")
            }
        }
        SettingHelp {
            text: i18n("Most servers are programs the widget starts for you (for example with npx or uvx). Others run elsewhere and are reached by a web address.")
        }

        QQC2.TextField {
            id: commandField
            objectName: "mcpCommandField"
            visible: !form.isUrl
            Kirigami.FormData.label: i18n("Command:")
            Layout.fillWidth: true
            placeholderText: "npx"
        }
        SettingHelp {
            visible: !form.isUrl
            text: i18n("The program to start.")
        }

        QQC2.TextArea {
            id: argsField
            objectName: "mcpArgsField"
            visible: !form.isUrl
            Kirigami.FormData.label: i18n("Arguments:")
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4
            placeholderText: i18n("One per line")
        }
        SettingHelp {
            visible: !form.isUrl
            text: i18n("What follows the command, one item per line.")
        }

        QQC2.TextField {
            id: cwdField
            objectName: "mcpCwdField"
            visible: !form.isUrl
            Kirigami.FormData.label: i18n("Folder:")
            Layout.fillWidth: true
            placeholderText: i18n("Optional")
        }
        SettingHelp {
            visible: !form.isUrl
            text: i18n("The folder the program starts in. Leave empty for your home folder.")
        }

        QQC2.TextField {
            id: urlField
            objectName: "mcpUrlField"
            visible: form.isUrl
            Kirigami.FormData.label: i18n("Address:")
            Layout.fillWidth: true
            placeholderText: "https://example.com/mcp"
        }
        SettingHelp {
            visible: form.isUrl
            text: i18n("The server's address, starting with https:// (or http://).")
        }

        McpPairsEditor {
            id: envEditor
            prefix: "mcpEnv"
            visible: !form.isUrl
            Kirigami.FormData.label: i18n("Environment:")
            Layout.fillWidth: true
            addText: i18n("Add a variable")
            nameHint: i18n("Name")
        }
        SettingHelp {
            visible: !form.isUrl
            text: i18n("Settings handed to the program, such as an API key. Mark keys and tokens as secret.")
        }

        McpPairsEditor {
            id: headerEditor
            prefix: "mcpHeader"
            visible: form.isUrl
            Kirigami.FormData.label: i18n("Headers:")
            Layout.fillWidth: true
            addText: i18n("Add a header")
            nameHint: i18n("Header")
        }
        SettingHelp {
            visible: form.isUrl
            text: i18n("Sent with every request, for example Authorization with your token. Mark tokens as secret.")
        }
    }

    QQC2.Label {
        objectName: "mcpAddError"
        Layout.fillWidth: true
        visible: form.error !== ""
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: Kirigami.Theme.negativeTextColor
        text: form.error
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        QQC2.Button {
            objectName: "mcpSaveButton"
            highlighted: true
            icon.name: "dialog-ok-apply"
            text: i18n("Add server")
            enabled: !form.saving
            onClicked: form.saveRequested(form.values())
        }
        QQC2.Button {
            objectName: "mcpCancelButton"
            text: i18n("Cancel")
            onClicked: form.cancelled()
        }
    }
}
