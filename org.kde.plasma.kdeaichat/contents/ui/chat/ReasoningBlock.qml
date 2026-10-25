// The model's thinking for one reply, collapsed under a "Thinking" header.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Rectangle {
    id: reasoning

    property string text: ""
    property bool streaming: false
    property bool expanded: false

    implicitHeight: column.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.cornerRadius
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        QQC2.AbstractButton {
            Layout.fillWidth: true
            implicitHeight: header.implicitHeight
            Accessible.name: reasoning.expanded ? i18n("Hide thinking") : i18n("Show thinking")
            onClicked: reasoning.expanded = !reasoning.expanded

            contentItem: RowLayout {
                id: header
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: reasoning.expanded ? "arrow-down" : "arrow-right"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                PC3.Label {
                    Layout.fillWidth: true
                    text: reasoning.streaming ? i18n("Thinking…") : i18n("Thought process")
                    opacity: 0.75
                }
            }
        }

        PC3.Label {
            visible: reasoning.expanded
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: reasoning.text
            opacity: 0.8
        }
    }
}
