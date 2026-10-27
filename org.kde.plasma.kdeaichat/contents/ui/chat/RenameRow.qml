// The "rename current chat" row, shown under the header while renaming.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

RowLayout {
    id: row

    property var chat: null
    // The history takes the whole view (set by FullRepresentationContent).
    property bool historyFull: chat ? chat.historyOnlyMode : false

    function save() {
        row.chat.renameCurrentSession(row.chat.currentChatRenameDraft);
        row.chat.renamingCurrentChat = false;
    }

    visible: !row.historyFull && row.chat.renamingCurrentChat
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    PC3.TextField {
        Accessible.name: i18n("Chat name") // qmllint disable unqualified
        id: field
        Layout.fillWidth: true
        text: row.chat.currentChatRenameDraft
        onTextChanged: row.chat.currentChatRenameDraft = text
        onAccepted: row.save()
    }

    PC3.ToolButton {
        icon.name: "dialog-ok-apply"
        Accessible.name: i18n("Save title") // qmllint disable unqualified
        onClicked: row.save()
    }

    PC3.ToolButton {
        icon.name: "dialog-cancel"
        Accessible.name: i18n("Cancel rename") // qmllint disable unqualified
        onClicked: row.chat.renamingCurrentChat = false
    }
}
