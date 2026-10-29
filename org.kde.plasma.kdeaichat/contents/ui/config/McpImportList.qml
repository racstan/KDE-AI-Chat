// Settings → Tools → Import: the MCP servers found in Claude Desktop's and OpenCode's settings, each with a
// check box. Nothing is added unless ticked. A key or token found there is put in KWallet (config/McpStore.qml),
// never in the settings file. Servers already added, and entries that can't be used, are shown but not offered.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() and i18np() are provided by Plasma at runtime.
// qmllint disable unqualified
ColumnLayout {
    id: list

    property var candidates: []
    property bool loaded: false
    property string result: ""
    property var ticked: ({})

    signal importRequested(var ids)
    signal cancelled()

    function usable(c) {
        return !c.exists && !c.problem;
    }

    function reset() {
        list.ticked = ({});
        list.result = "";
    }

    spacing: Kirigami.Units.largeSpacing

    Kirigami.Heading {
        level: 3
        text: i18n("Import MCP servers")
        Layout.fillWidth: true
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: i18n("Servers found in Claude Desktop and OpenCode. Tick the ones to add; keys and tokens go to KWallet.")
    }

    QQC2.Label {
        objectName: "mcpImportEmpty"
        Layout.fillWidth: true
        visible: list.loaded && list.candidates.length === 0
        opacity: 0.7
        wrapMode: Text.Wrap
        text: i18n("No MCP servers were found in those apps.")
    }

    Repeater {
        model: list.candidates

        delegate: QQC2.CheckBox {
            id: box
            required property var modelData
            objectName: "mcpImport-" + modelData.id
            Layout.fillWidth: true
            enabled: list.usable(modelData)
            checked: list.ticked[modelData.id] === true
            text: modelData.id + "  ·  " + modelData.source
                + (modelData.exists ? "  ·  " + i18n("already added") : "")
                + (modelData.problem ? "  ·  " + i18n("can't be used: %1", modelData.problem) : "")
                + "\n" + (modelData.url ? modelData.url : [modelData.command].concat(modelData.args || []).join(" "))
            contentItem: QQC2.Label {
                leftPadding: box.indicator.width + box.spacing
                text: box.text
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                opacity: box.enabled ? 1 : 0.6
                verticalAlignment: Text.AlignVCenter
            }
            onToggled: {
                const next = Object.assign({}, list.ticked);
                next[modelData.id] = checked;
                list.ticked = next;
            }
        }
    }

    QQC2.Label {
        objectName: "mcpImportResult"
        Layout.fillWidth: true
        visible: list.result !== ""
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: list.result
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        QQC2.Button {
            objectName: "mcpImportButton"
            highlighted: true
            icon.name: "document-import"
            text: i18n("Import selected")
            enabled: Object.keys(list.ticked).some(function(id) { return list.ticked[id] === true; })
            onClicked: list.importRequested(Object.keys(list.ticked).filter(function(id) { return list.ticked[id] === true; }))
        }
        QQC2.Button {
            objectName: "mcpImportClose"
            text: i18n("Close")
            onClicked: list.cancelled()
        }
    }
}
