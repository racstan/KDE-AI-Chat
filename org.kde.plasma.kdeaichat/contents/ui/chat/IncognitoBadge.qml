// The header's mark of an incognito chat (chat/Incognito.qml): an icon,
// "Incognito — not saved", and a button that closes the chat (asking first
// when it has messages). In chat/ChatHeader.qml, shown while one is open.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Rectangle {
    id: badge

    property var chat: null
    // Only the icon and the button (a very narrow header); the text is the tooltip then.
    property bool compact: false
    readonly property string label: i18n("Incognito — not saved")

    objectName: "incognitoBadge"
    implicitWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    implicitHeight: row.implicitHeight
    radius: height / 2
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)

    Accessible.role: Accessible.StaticText
    Accessible.name: label

    HoverHandler {
        id: hover
    }
    QQC2.ToolTip.visible: hover.hovered && !closeButton.hovered
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    QQC2.ToolTip.text: i18n("This chat is never written to disk, uses no memories and adds none. It is gone when you leave it.")

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing * 2
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: "view-private"
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
        PC3.Label {
            objectName: "incognitoLabel"
            visible: !badge.compact
            text: badge.label
            font.bold: true
            textFormat: Text.PlainText
        }
        PC3.ToolButton {
            id: closeButton
            objectName: "incognitoCloseButton"
            icon.name: "window-close"
            display: PC3.AbstractButton.IconOnly
            Accessible.name: i18n("Close incognito chat")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: Accessible.name
            onClicked: badge.chat.incognito.close()
        }
    }
}
