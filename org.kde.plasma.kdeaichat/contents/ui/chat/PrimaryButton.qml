// The main choice in a card: a button filled with the theme's accent colour.
// Plasma's own button has no "highlighted" look, so the card's other buttons
// (plain PC3.Button) stay quiet beside it.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.Button {
    id: control

    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color onAccent: Kirigami.Theme.highlightedTextColor

    leftPadding: Kirigami.Units.largeSpacing
    rightPadding: Kirigami.Units.largeSpacing
    topPadding: Kirigami.Units.smallSpacing + 1
    bottomPadding: Kirigami.Units.smallSpacing + 1
    hoverEnabled: true
    highlighted: true
    Accessible.name: text

    background: Rectangle {
        radius: Kirigami.Units.cornerRadius
        color: control.down ? Qt.darker(control.accent, 1.2) : control.hovered ? Qt.lighter(control.accent, 1.12) : control.accent
        opacity: control.enabled ? 1 : 0.4
        border.width: control.visualFocus ? 2 : 0
        border.color: Kirigami.Theme.textColor
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing
        opacity: control.enabled ? 1 : 0.6

        Kirigami.Icon {
            visible: control.icon.name !== ""
            source: control.icon.name
            color: control.onAccent
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        Text {
            text: control.text
            color: control.onAccent
            font: control.font
            elide: Text.ElideRight
        }
    }
}
