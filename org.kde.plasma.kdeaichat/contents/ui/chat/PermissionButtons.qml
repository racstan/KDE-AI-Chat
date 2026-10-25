// Answer buttons for an agent's permission request (a permission_request
// message), or its answer once given.
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Row {
    id: buttons

    property var message: ({})

    // always: allow it from now on too (only offered when message.canAlways).
    signal answered(bool approved, bool always)

    spacing: Kirigami.Units.largeSpacing

    PC3.Button {
        visible: buttons.message.status === "pending"
        text: "Allow"
        icon.name: "dialog-ok-apply"
        onClicked: buttons.answered(true, false)
    }

    PC3.Button {
        visible: buttons.message.status === "pending" && buttons.message.canAlways === true
        text: "Always allow"
        icon.name: "dialog-ok-apply"
        onClicked: buttons.answered(true, true)
    }

    PC3.Button {
        visible: buttons.message.status === "pending"
        text: "Reject"
        icon.name: "dialog-cancel"
        onClicked: buttons.answered(false, false)
    }

    // The answer: a Breeze icon and a word.
    Row {
        readonly property alias text: answerLabel.text
        readonly property alias iconSource: answerIcon.source

        visible: buttons.message.status !== "pending"
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            id: answerIcon
            visible: buttons.message.status === "allowed" || buttons.message.status === "denied"
            source: buttons.message.status === "allowed" ? "dialog-ok-apply" : "dialog-cancel"
            width: Kirigami.Units.iconSizes.small
            height: Kirigami.Units.iconSizes.small
            anchors.verticalCenter: parent.verticalCenter
        }

        PC3.Label {
            id: answerLabel
            text: buttons.message.status === "allowed" ? "Approved" : buttons.message.status === "denied" ? "Rejected" : "Answering…"
            font.bold: true
            color: buttons.message.status === "allowed" ? Kirigami.Theme.positiveTextColor
                 : buttons.message.status === "denied" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }
    }
}
