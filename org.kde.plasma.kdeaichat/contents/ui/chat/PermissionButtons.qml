// Answer buttons for an agent's permission request (a permission_request
// message), or its answer once given. Allow is the highlighted choice.
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Flow {
    id: buttons

    property var message: ({})

    // always: allow it from now on too (only offered when message.canAlways).
    signal answered(bool approved, bool always)

    spacing: Kirigami.Units.largeSpacing

    PrimaryButton {
        objectName: "allowButton"
        visible: buttons.message.status === "pending"
        text: i18n("Allow")
        icon.name: "dialog-ok-apply"
        onClicked: buttons.answered(true, false)
    }

    PC3.Button {
        objectName: "alwaysAllowButton"
        visible: buttons.message.status === "pending" && buttons.message.canAlways === true
        text: i18n("Always allow")
        icon.name: "dialog-ok-apply"
        onClicked: buttons.answered(true, true)
    }

    PC3.Button {
        objectName: "rejectButton"
        visible: buttons.message.status === "pending"
        text: i18n("Reject")
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
            text: buttons.message.status === "allowed" ? i18n("Approved") : buttons.message.status === "denied" ? i18n("Rejected") : i18n("Answering…")
            font.bold: true
            color: buttons.message.status === "allowed" ? Kirigami.Theme.positiveTextColor
                 : buttons.message.status === "denied" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }
    }
}
