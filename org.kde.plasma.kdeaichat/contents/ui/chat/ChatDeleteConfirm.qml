// Asks before a chat is deleted, when "Ask before deleting a chat" is on
// (Settings → Chat; chat/ChatPrefs.qml deleteChat opens it). Says what Undo
// brings back. Destroys itself when closed.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.Popup {
    id: confirm

    // The widget root (main.qml): deleteSession(id).
    property var chat: null
    property string sessionId: ""
    property string title: ""

    objectName: "chatDeleteConfirm"
    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    padding: Kirigami.Units.largeSpacing
    onClosed: destroy()

    function accept() {
        var target = confirm.chat;
        var id = confirm.sessionId;
        confirm.close();
        if (target)
            target.deleteSession(id);
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        PC3.Label {
            objectName: "chatDeleteText"
            Layout.maximumWidth: Math.min(Kirigami.Units.gridUnit * 20, (confirm.parent ? confirm.parent.width : 400) - Kirigami.Units.largeSpacing * 4)
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: (confirm.title ? i18n("Delete the chat “%1”?", confirm.title) : i18n("Delete this chat?"))
                + "\n\n" + i18n("For a few seconds afterwards, Undo brings it back, but not its scheduled messages.")
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing

            PC3.Button {
                objectName: "chatDeleteCancel"
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onClicked: confirm.close()
            }

            PC3.Button {
                objectName: "chatDeleteConfirmButton"
                text: i18n("Delete chat")
                icon.name: "edit-delete"
                focus: true
                onClicked: confirm.accept()
                Keys.onReturnPressed: confirm.accept()
                Keys.onEnterPressed: confirm.accept()
            }
        }
    }
}
