// The "rename current chat" row, shown under the header while renaming.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

RowLayout {
    id: row

    property var chat: null

    function save() {
        row.chat.renameCurrentSession(row.chat.currentChatRenameDraft);
        row.chat.renamingCurrentChat = false;
    }

    visible: !row.chat.historyOnlyMode && row.chat.renamingCurrentChat
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    QQC2.TextField {
        id: field
        Layout.fillWidth: true
        text: row.chat.currentChatRenameDraft
        color: Kirigami.Theme.textColor
        background: Rectangle {
            color: Kirigami.Theme.backgroundColor
            radius: Kirigami.Units.smallSpacing
            border.color: field.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
            border.width: 1
        }
        onTextChanged: row.chat.currentChatRenameDraft = text
        onAccepted: row.save()
    }

    PC3.ToolButton {
        icon.name: "dialog-ok-apply"
        onClicked: row.save()
    }

    PC3.ToolButton {
        icon.name: "dialog-cancel"
        onClicked: row.chat.renamingCurrentChat = false
    }
}
