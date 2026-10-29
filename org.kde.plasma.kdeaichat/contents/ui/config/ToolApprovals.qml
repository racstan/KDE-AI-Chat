// Settings → Tools → Remembered approvals: the tools the user chose "Always allow" for on a permission card
// (kdeaichat/tool_approvals.py keeps them in tool-approvals.json). Forget makes a tool ask again.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "McpForm.js" as Form

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified
ColumnLayout {
    id: approvals

    // function(command, payload, onDone(stdout, exitCode, stderr)).
    property var runHelper: null
    property var keys: []
    property bool loaded: false
    property string problem: ""

    spacing: Kirigami.Units.smallSpacing

    function _apply(stdout, exitCode) {
        try {
            const list = exitCode === 0 ? JSON.parse(stdout).keys : null;
            if (Array.isArray(list)) {
                approvals.keys = list.map(String);
                approvals.loaded = true;
                approvals.problem = "";
                return;
            }
        } catch (e) {
            // falls through
        }
        approvals.problem = i18n("Couldn't read the remembered approvals.");
    }

    function load() {
        if (approvals.runHelper)
            approvals.runHelper("tool_approvals_list", {}, approvals._apply);
    }

    function forget(key) {
        if (approvals.runHelper)
            approvals.runHelper("tool_approvals_remove", {"key": key}, approvals._apply);
    }

    Component.onCompleted: load()

    QQC2.Label {
        objectName: "approvalsEmpty"
        Layout.fillWidth: true
        visible: approvals.loaded && approvals.keys.length === 0
        opacity: 0.7
        wrapMode: Text.Wrap
        text: i18n("Nothing is remembered. Tools ask before they run, until you choose “Always” on the question.")
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: approvals.problem !== ""
        color: Kirigami.Theme.negativeTextColor
        wrapMode: Text.Wrap
        text: approvals.problem
    }

    Repeater {
        model: approvals.keys

        delegate: RowLayout {
            id: item
            required property string modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                objectName: "approvalLabel"
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
                text: Form.approvalLabel(item.modelData)
            }
            QQC2.Button {
                objectName: "approvalForget"
                text: i18n("Forget")
                icon.name: "edit-undo"
                onClicked: approvals.forget(item.modelData)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Ask again before this tool runs")
            }
        }
    }
}
