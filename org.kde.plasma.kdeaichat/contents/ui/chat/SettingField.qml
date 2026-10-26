// One setting of a chat's own settings (chat/ChatOverridesForm.qml,
// chat/PiChatSettings.qml): a small grey label above its input(s) and, under
// them, `help`: what it does in everyday words (tests/test_setting_help.py
// checks every SettingField has one). `details` is a longer hover text.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../config" as Config

ColumnLayout {
    id: field

    property string label
    property string help
    property string details
    default property alias content: slot.data

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    PC3.Label {
        text: field.label
        color: Kirigami.Theme.disabledTextColor
        Layout.fillWidth: true
    }
    ColumnLayout {
        id: slot
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
    }
    Config.SettingHelp {
        visible: text !== ""
        text: field.help
        details: field.details
    }
}
