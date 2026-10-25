// A one-line notice above the chat: an error with an optional action, or
// an informational message the user can dismiss.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Rectangle {
    id: banner

    property string text: ""
    property bool isError: false
    property string actionText: ""
    property string actionIcon: ""
    property bool dismissible: !isError

    signal actionTriggered()
    signal dismissed()

    readonly property color tone: isError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor

    visible: text !== ""
    Layout.fillWidth: true
    color: Qt.rgba(tone.r, tone.g, tone.b, 0.10)
    border.color: tone
    border.width: 1
    radius: Kirigami.Units.cornerRadius
    implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing * 2

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: banner.text
            color: Kirigami.Theme.textColor
        }
        PC3.Button {
            visible: banner.actionText !== ""
            text: banner.actionText
            icon.name: banner.actionIcon
            onClicked: banner.actionTriggered()
        }
        PC3.ToolButton {
            visible: banner.dismissible
            icon.name: "dialog-close"
            onClicked: banner.dismissed()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Dismiss") // qmllint disable unqualified
        }
    }
}
