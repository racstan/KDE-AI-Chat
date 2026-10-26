// The short, everyday-words explanation under a setting: what it does and
// when to change it, for someone with no technical background. `details`
// is a longer explanation shown when the pointer rests on the line.
//
// Every setting on a settings page has one (tests/test_setting_help.py
// checks this): put it right after the control, inside the same FormLayout.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.Label {
    id: help

    // A longer explanation, shown on hover ("" = none).
    property string details: ""
    // For tests and tools that look for the explanations on a page.
    readonly property bool isSettingHelp: true

    Layout.fillWidth: true
    Layout.maximumWidth: Kirigami.Units.gridUnit * 28
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    font: Kirigami.Theme.smallFont
    color: Kirigami.Theme.disabledTextColor
    Accessible.role: Accessible.StaticText
    Accessible.description: details

    HoverHandler {
        id: hover
        enabled: help.details !== ""
    }

    QQC2.ToolTip.visible: hover.hovered && help.details !== ""
    QQC2.ToolTip.text: help.details
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
}
