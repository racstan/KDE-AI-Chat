// A block of selectable monospace text on a faint panel, capped in height
// and scrollable: a command to approve, a tool's output.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: block

    property string text: ""
    property color textColor: Kirigami.Theme.textColor
    property real maxHeight: Kirigami.Units.gridUnit * 10
    readonly property alias view: view
    readonly property string fontFamily: edit.font.family
    // The small font in the fixed-width family.
    readonly property font monoFont: {
        var small = Kirigami.Theme.smallFont;
        var family = Kirigami.Theme.fixedWidthFont.family;
        return small.pixelSize > 0 ? Qt.font({"family": family, "pixelSize": small.pixelSize}) : Qt.font({"family": family, "pointSize": small.pointSize});
    }

    Layout.fillWidth: true
    implicitHeight: Math.min(edit.implicitHeight, maxHeight) + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.cornerRadius
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)
    clip: true

    Flickable {
        id: view
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        contentWidth: width
        contentHeight: edit.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

        TextEdit {
            id: edit
            width: view.width
            text: block.text
            readOnly: true
            selectByMouse: true
            wrapMode: Text.WrapAnywhere
            color: block.textColor
            selectionColor: Kirigami.Theme.highlightColor
            selectedTextColor: Kirigami.Theme.highlightedTextColor
            font: block.monoFont
        }
    }
}
