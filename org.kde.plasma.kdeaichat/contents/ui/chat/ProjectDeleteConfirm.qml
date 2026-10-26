// Asks before deleting a project together with its chats (chat/ProjectsSidebar.qml
// opens it; chat/Projects.qml removeWithChats does it). Says how many chats
// go and what Undo brings back. Destroys itself when closed.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.Popup {
    id: confirm

    // chat/Projects.qml
    property var projects: null
    property string projectId: ""
    readonly property var project: projects ? projects.byId(projectId) : null
    readonly property int count: projects ? projects.chatsIn(projectId).length : 0

    objectName: "projectDeleteConfirm"
    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    padding: Kirigami.Units.largeSpacing
    onClosed: destroy()

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        PC3.Label {
            objectName: "projectDeleteText"
            Layout.maximumWidth: Math.min(Kirigami.Units.gridUnit * 20, (confirm.parent ? confirm.parent.width : 400) - Kirigami.Units.largeSpacing * 4)
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: i18np("Delete the project “%2” and its chat?", "Delete the project “%2” and its %1 chats?", confirm.count, confirm.project ? confirm.project.name : "")
                + "\n\n" + i18n("For a few seconds afterwards, Undo brings back the project and its chats, but not their scheduled messages.")
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing

            PC3.Button {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onClicked: confirm.close()
            }

            PC3.Button {
                objectName: "projectDeleteConfirmButton"
                text: i18n("Delete project and chats")
                icon.name: "edit-delete"
                onClicked: {
                    var id = confirm.projectId;
                    var target = confirm.projects;
                    confirm.close();
                    target.removeWithChats(id);
                }
            }
        }
    }
}
