// Rows of name and value for a server's environment variables or headers. A row can be marked "Secret":
// its value is hidden while typing and goes to KWallet, never into mcp.json (config/McpStore.qml).
// `rows()` gives [{name, value, secret}] for config/McpForm.js.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified
ColumnLayout {
    id: editor

    property string addText: i18n("Add")
    property string nameHint: i18n("Name")
    property string prefix: "pair"
    // Names typed here are suggested as secret when they look like one.
    readonly property var secretish: /key|token|secret|password|auth/i

    spacing: Kirigami.Units.smallSpacing

    function rows() {
        const out = [];
        for (let i = 0; i < pairs.count; i++)
            out.push({"name": pairs.get(i).name, "value": pairs.get(i).value, "secret": pairs.get(i).secret});
        return out;
    }

    function clear() {
        pairs.clear();
    }

    function addRow(name, value, secret) {
        pairs.append({"name": name || "", "value": value || "", "secret": secret === true});
    }

    ListModel {
        id: pairs
    }

    Repeater {
        model: pairs

        delegate: RowLayout {
            id: row
            required property int index
            required property string name
            required property string value
            required property bool secret
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                objectName: editor.prefix + "Name" + row.index
                Accessible.name: editor.nameHint
                Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                Layout.minimumWidth: 0
                placeholderText: editor.nameHint
                text: row.name
                onTextEdited: {
                    pairs.setProperty(row.index, "name", text);
                    if (!row.secret && editor.secretish.test(text))
                        pairs.setProperty(row.index, "secret", true);
                }
            }
            QQC2.TextField {
                objectName: editor.prefix + "Value" + row.index
                Accessible.name: i18n("Value")
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                placeholderText: i18n("Value")
                echoMode: row.secret ? TextInput.Password : TextInput.Normal
                text: row.value
                onTextEdited: pairs.setProperty(row.index, "value", text)
            }
            QQC2.CheckBox {
                objectName: editor.prefix + "Secret" + row.index
                text: i18n("Secret")
                checked: row.secret
                onToggled: pairs.setProperty(row.index, "secret", checked)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Keep the value in KWallet instead of the settings file.")
            }
            QQC2.ToolButton {
                icon.name: "list-remove"
                Accessible.name: i18n("Remove")
                onClicked: pairs.remove(row.index)
            }
        }
    }

    QQC2.Button {
        objectName: editor.prefix + "Add"
        icon.name: "list-add"
        text: editor.addText
        onClicked: editor.addRow("", "", false)
    }
}
