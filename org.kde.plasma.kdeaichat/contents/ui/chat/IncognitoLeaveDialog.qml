// Asks before leaving an incognito chat that has messages (chat/Incognito.qml
// opens it through leaveRequested): its messages are gone once you leave.
// "Don't ask again" turns the question off (Settings → Chat turns it back on).
// Put it once in the popup; while it exists it is the incognito chat's confirmer.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.Popup {
    id: dialog

    property var chat: null
    readonly property var incognito: chat ? chat.incognito || null : null
    readonly property alias dontAskAgain: dontAsk

    function leave() {
        var target = dialog.incognito;
        var dont = dontAsk.checked;
        if (target)
            target.confirmLeave(dont);
        dialog.close();
    }

    objectName: "incognitoLeaveDialog"
    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(Kirigami.Units.gridUnit * 22, (parent ? parent.width : Kirigami.Units.gridUnit * 24) - Kirigami.Units.largeSpacing * 2)
    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    padding: Kirigami.Units.largeSpacing
    // Closed without leaving: the chat stays open (after leave() this does nothing).
    onClosed: if (dialog.incognito) dialog.incognito.cancelLeave()
    onOpened: stayButton.forceActiveFocus()

    onIncognitoChanged: if (dialog.incognito) dialog.incognito.confirmer = dialog
    Component.onCompleted: if (dialog.incognito) dialog.incognito.confirmer = dialog
    Component.onDestruction: {
        if (dialog.incognito && dialog.incognito.confirmer === dialog)
            dialog.incognito.confirmer = null;
    }

    Connections {
        target: dialog.incognito
        function onLeaveRequested() {
            dontAsk.checked = false;
            dialog.open();
        }
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: "view-private"
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            Kirigami.Heading {
                Layout.fillWidth: true
                level: 3
                wrapMode: Text.Wrap
                text: i18n("Leave the incognito chat?")
            }
        }

        PC3.Label {
            objectName: "incognitoLeaveText"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18n("It isn't saved anywhere: once you leave it, its messages are gone for good.")
        }

        PC3.CheckBox {
            id: dontAsk
            objectName: "incognitoDontAsk"
            text: i18n("Don't ask again")
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing

            PC3.Button {
                id: stayButton
                objectName: "incognitoStayButton"
                text: i18n("Stay")
                icon.name: "dialog-cancel"
                onClicked: dialog.close()
            }
            PC3.Button {
                objectName: "incognitoLeaveButton"
                text: i18n("Leave and discard")
                icon.name: "edit-delete"
                onClicked: dialog.leave()
            }
        }
    }
}
