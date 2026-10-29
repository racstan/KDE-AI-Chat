// One MCP server in Settings → Tools: an on/off switch, its name, what it runs or where it is, Test (lists
// its tools through the bridge and shows the count or the error) and Delete (asks first, in the row).
// Everything that comes from the server or its definition is shown as plain text.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../mcp/McpDefs.js" as Defs

// i18n() and i18np() are provided by Plasma at runtime.
// qmllint disable unqualified
QQC2.Frame {
    id: row
    objectName: "mcpRow-" + (server.id || "")

    property var server: ({})
    // config/McpStore.qml tests[id]: {state, count, names, text} or undefined.
    property var testResult: undefined
    property bool confirming: false

    signal enabledToggled(bool enabled)
    signal testRequested()
    signal deleteRequested()

    readonly property bool remote: Defs.isRemote(row.server)
    readonly property int secretCount: Defs.secretNames(row.server).length
    readonly property string what: row.remote ? row.server.url
        : [row.server.command].concat(row.server.args || []).join(" ")

    Layout.fillWidth: true

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Switch {
                objectName: "mcpEnabled"
                Accessible.name: i18n("Server turned on")
                checked: row.server.enabled !== false
                onToggled: row.enabledToggled(checked)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: checked ? i18n("On: chats can use its tools") : i18n("Off: chats don't use it")
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Kirigami.Heading {
                    level: 4
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row.server.id || ""
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                    opacity: 0.7
                    text: (row.remote ? i18n("Web address: %1", row.what) : i18n("Program: %1", row.what))
                        + (row.secretCount > 0 ? "  ·  " + i18np("1 secret in KWallet", "%1 secrets in KWallet", row.secretCount) : "")
                }
            }
            QQC2.Button {
                objectName: "mcpTest"
                text: i18n("Test")
                icon.name: "system-run"
                enabled: !(row.testResult && row.testResult.state === "testing")
                onClicked: row.testRequested()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Start the server and list its tools")
            }
            QQC2.ToolButton {
                objectName: "mcpDelete"
                icon.name: "edit-delete"
                Accessible.name: i18n("Delete server")
                visible: !row.confirming
                onClicked: row.confirming = true
            }
        }

        QQC2.Label {
            objectName: "mcpTestResult"
            Layout.fillWidth: true
            visible: row.testResult !== undefined
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            color: row.testResult && row.testResult.state === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            text: !row.testResult ? ""
                : row.testResult.state === "testing" ? i18n("Starting the server…")
                : row.testResult.state === "error" ? i18n("Couldn't use this server: %1", row.testResult.text)
                : row.testResult.count === 0 ? i18n("The server works but has no tools.")
                : i18np("Works: 1 tool (%2)", "Works: %1 tools (%2)", row.testResult.count, row.testResult.names)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: row.confirming
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: i18n("Delete this server? Its secrets are removed from KWallet.")
            }
            QQC2.Button {
                objectName: "mcpDeleteConfirm"
                text: i18n("Delete")
                icon.name: "edit-delete"
                onClicked: {
                    row.confirming = false;
                    row.deleteRequested();
                }
            }
            QQC2.Button {
                text: i18n("Keep")
                onClicked: row.confirming = false
            }
        }
    }
}
