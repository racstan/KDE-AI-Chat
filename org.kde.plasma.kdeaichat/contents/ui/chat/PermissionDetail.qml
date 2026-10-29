// What an agent asks permission for (a permission_request message): the
// tool, and the command or paths it wants to use in monospace. Older chats
// and some agents only have the message text, which is shown the same way.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: detail

    property var message: ({})

    readonly property string tool: message.tool || ""
    readonly property string command: {
        var args = message.arguments;
        if (args && args.length > 0)
            return args.join("\n");
        return tool === "" ? String(message.content || "") : "";
    }

    spacing: Kirigami.Units.smallSpacing

    PC3.Label {
        textFormat: Text.PlainText
        objectName: "permissionTool"
        visible: detail.tool !== ""
        Layout.fillWidth: true
        text: i18n("Wants to use %1", detail.tool)
        elide: Text.ElideRight
    }

    MonoBlock {
        objectName: "permissionCommand"
        visible: detail.command !== ""
        text: detail.command
        maxHeight: Kirigami.Units.gridUnit * 6
    }
}
