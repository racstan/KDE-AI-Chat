// What an agent did for a reply (tools, changed files, notices), collapsed
// to one line until opened. Fed by backends/AgentEvents.js.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

ColumnLayout {
    id: context

    property var items: []
    property bool expanded: false

    spacing: 2

    QQC2.AbstractButton {
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight
        Accessible.name: context.expanded ? i18n("Hide activity") : i18n("Show activity")
        onClicked: context.expanded = !context.expanded

        contentItem: RowLayout {
            id: header
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: context.expanded ? "arrow-down" : "arrow-right"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            PC3.Label {
                Layout.fillWidth: true
                text: i18np("1 step", "%1 steps", context.items.length)
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }
    }

    Repeater {
        model: context.expanded ? context.items : []

        delegate: PC3.Label {
            required property string modelData
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
            text: modelData
            font: Kirigami.Theme.smallFont
            elide: Text.ElideMiddle
            opacity: 0.75
        }
    }
}
