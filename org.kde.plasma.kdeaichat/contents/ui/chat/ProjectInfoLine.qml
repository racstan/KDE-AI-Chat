// The Chat info panel's lines about the chat's project: which project it is
// in, and which of its settings come from that project (instructions,
// working folder). Hidden for a chat in no project. The model's source is on
// the EffectiveLine above ("From the project …").
import QtQuick
import QtCore
import "DisplayPath.js" as Paths
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: info

    // The widget root (main.qml) or a stand-in with `projects`.
    property var chat: null
    property string sessionId: ""

    readonly property var project: chat && chat.projects ? chat.projects.ofChat(sessionId) : null
    readonly property var workspace: chat && chat.projects ? chat.projects.workspaceFor(sessionId) : ({"path": "", "from": ""})
    readonly property bool hasInstructions: project !== null && String(project.instructions || "").trim() !== ""
    readonly property bool ownInstructions: chat ? String(chat.getSessionProperty(sessionId, "chatSystemPrompt", "") || "").trim() !== ""
                                                   && chat.getSessionProperty(sessionId, "chatSystemPromptEnabled", true) !== false : false

    visible: project !== null
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Rectangle {
            implicitWidth: Kirigami.Units.smallSpacing * 2
            implicitHeight: implicitWidth
            radius: width / 2
            color: info.project ? info.project.color : "transparent"
        }
        PC3.Label {
            objectName: "projectName"
            Layout.fillWidth: true
            text: info.project ? i18n("In the project “%1”", info.project.name) : ""
            elide: Text.ElideRight
        }
    }

    PC3.Label {
        objectName: "projectInstructionsLine"
        visible: info.hasInstructions
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
        text: info.ownInstructions ? i18n("Instructions: the project's, then this chat's own")
                                   : i18n("Instructions: from the project")
    }

    PC3.Label {
        objectName: "projectFolderLine"
        visible: info.workspace.path !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
        text: info.workspace.from === "project" ? i18n("Working folder: %1 (from the project)", Paths.tilde(info.workspace.path, StandardPaths.writableLocation(StandardPaths.HomeLocation)))
            : i18n("Working folder: %1 (this chat's own)", Paths.tilde(info.workspace.path, StandardPaths.writableLocation(StandardPaths.HomeLocation)))
    }
}
