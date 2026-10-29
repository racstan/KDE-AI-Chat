// One memory in Settings → Memory (ConfigMemory.qml): on/off, its text
// (edited in place), where it applies, pin and delete. The page does the
// changes; this row only asks for them.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: row

    property var memory: ({})
    // Where it applies, readable ("All chats", "Chat “Trip”", …).
    property string scopeText: ""
    property int maxChars: 4000
    property bool editing: false

    signal toggleEnabled(bool on)
    signal togglePinned(bool on)
    signal saveText(string text)
    signal remove()

    readonly property bool on: memory.enabled !== false

    function startEdit() {
        editor.text = memory.text || "";
        editing = true;
        editor.forceActiveFocus();
        editor.cursorPosition = editor.length;
    }

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.CheckBox {
            objectName: "memoryOnBox"
            Layout.alignment: Qt.AlignTop
            checked: row.on
            onToggled: row.toggleEnabled(checked)
            Accessible.name: i18n("Use this memory")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: row.on ? i18n("On: can go with messages") : i18n("Off: never sent")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: !row.editing

            QQC2.Label {
                textFormat: Text.PlainText
                objectName: "memoryText"
                Layout.fillWidth: true
                text: row.memory.text || ""
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                opacity: row.on ? 1 : 0.7
            }
            QQC2.Label {
                objectName: "memoryScope"
                Layout.fillWidth: true
                text: row.scopeText + (row.memory.pinned ? " · " + i18n("pinned") : "") + (row.on ? "" : " · " + i18n("off"))
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                elide: Text.ElideRight
            }
        }

        QQC2.TextArea {
            Keys.onTabPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)
            Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
            Accessible.name: i18n("Edit memory")
            id: editor
            objectName: "memoryEditor"
            visible: row.editing
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 3
            wrapMode: TextEdit.Wrap
            Keys.onEscapePressed: row.editing = false
        }

        QQC2.ToolButton {
            objectName: "memoryPinButton"
            visible: !row.editing
            Layout.alignment: Qt.AlignTop
            icon.name: "pin"
            checkable: true
            checked: row.memory.pinned === true
            onToggled: row.togglePinned(checked)
            Accessible.name: checked ? i18n("Unpin") : i18n("Pin")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: checked ? i18n("Unpin") : i18n("Pin: send it with every message, first")
        }
        QQC2.ToolButton {
            objectName: "memoryEditButton"
            visible: !row.editing
            Layout.alignment: Qt.AlignTop
            icon.name: "document-edit"
            onClicked: row.startEdit()
            Accessible.name: i18n("Edit")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Edit")
        }
        QQC2.ToolButton {
            objectName: "memoryDeleteButton"
            visible: !row.editing
            Layout.alignment: Qt.AlignTop
            icon.name: "edit-delete"
            onClicked: row.remove()
            Accessible.name: i18n("Delete")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Delete")
        }
    }

    RowLayout {
        visible: row.editing
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("%1 / %2", editor.length, row.maxChars)
            font: Kirigami.Theme.smallFont
            color: editor.length > row.maxChars ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
        }
        QQC2.Button {
            text: i18n("Cancel")
            icon.name: "dialog-cancel"
            onClicked: row.editing = false
        }
        QQC2.Button {
            objectName: "memorySaveButton"
            text: i18n("Save")
            icon.name: "document-save"
            enabled: editor.text.trim() !== "" && editor.length <= row.maxChars
            onClicked: {
                row.editing = false;
                if (editor.text.trim() !== String(row.memory.text || "").trim())
                    row.saveText(editor.text.trim());
            }
        }
    }
}
