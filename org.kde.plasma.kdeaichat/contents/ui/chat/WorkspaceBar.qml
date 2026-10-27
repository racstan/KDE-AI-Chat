// The row under the header, in every mode: the chat's workspace folder
// (a folder button, its name or "No workspace", and a button to clear it).
// In OpenCode mode it also shows the session, the agent profile and the
// refresh/sync buttons.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../backends/OpenCodeAgents.js" as OpenCodeAgents

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

RowLayout {
    id: bar

    property var chat: null
    // The history takes the whole view (set by FullRepresentationContent).
    property bool historyFull: chat ? chat.historyOnlyMode : false
    // The agents the selector offers: the server's list plus the chat's own agent.
    readonly property var agentModel: OpenCodeAgents.comboModel(bar.chat.openCodeAgentsList, bar.chat.openCodeAgent)
    // The chat's workspace folder ("" = none).
    readonly property string workspace: String(bar.chat.openCodeWorkspaceCwd || "").trim()
    // The open chat's project (or null), and whether the folder is the project's.
    readonly property var project: bar.chat.projects ? bar.chat.projects.ofChat(bar.chat.currentSessionId) : null
    readonly property bool fromProject: bar.chat.projects ? bar.chat.projects.workspaceFor(bar.chat.currentSessionId).from === "project" : false

    signal agentChosen(string value)

    Layout.fillWidth: true
    // Settings → Appearance can hide it; OpenCode chats keep it for the agent profile.
    visible: !bar.historyFull && (!bar.chat.prefs || bar.chat.prefs.showWorkspaceBar || bar.chat.openCodeMode)
    spacing: Kirigami.Units.smallSpacing

    // Sets (or, with "", clears) the open chat's workspace.
    function choose(path) {
        bar.chat.chooseWorkspace(path);
    }

    // The agent list belongs to a workspace folder: load it when the open
    // chat's folder isn't the one it was loaded for.
    function refreshAgents() {
        if (bar.chat.openCodeMode && bar.chat.openCodeAgentsDirectory !== bar.workspace)
            bar.chat.fetchOpenCodeAgents();
    }
    Component.onCompleted: bar.refreshAgents()
    onVisibleChanged: {
        if (visible)
            bar.refreshAgents();
    }
    Connections {
        target: bar.chat
        function onOpenCodeWorkspaceCwdChanged() { bar.refreshAgents(); }
    }

    FolderDialog {
        id: folderDialog
        title: i18n("Select the chat's workspace folder")
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));
            bar.choose(path);
        }
    }

    PC3.ToolButton {
        objectName: "workspaceButton"
        icon.name: "folder"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: bar.workspace ? i18n("Workspace: %1", bar.workspace) : i18n("Choose a workspace folder")
        Accessible.name: QQC2.ToolTip.text
        onClicked: {
            if (bar.workspace)
                folderDialog.currentFolder = "file://" + encodeURI(bar.workspace);
            folderDialog.open();
        }
    }

    PC3.Label {
        objectName: "workspaceLabel"
        text: {
            var folder = "";
            if (bar.workspace) {
                const p = bar.workspace;
                folder = p.substring(p.lastIndexOf("/") + 1) || p;
            }
            var labelStr = folder || i18n("No workspace");
            var sess = bar.chat.openCodeMode ? bar.chat.currentOpenCodeSessionId() : "";
            if (sess) labelStr += " (" + sess.substring(0, 10) + "…)";
            return labelStr;
        }
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        font.bold: bar.workspace !== ""
        opacity: bar.workspace ? 0.85 : 0.6
        elide: Text.ElideMiddle
        // Takes the spare room and shortens first. (Never size it from
        // bar.width: the bar's own width then feeds back into its layout.)
        Layout.fillWidth: true
        Layout.minimumWidth: 0
    }

    // The chat's project, with its colour; the folder may come from it.
    Rectangle {
        visible: bar.project !== null
        implicitWidth: Kirigami.Units.smallSpacing * 2
        implicitHeight: implicitWidth
        radius: width / 2
        color: bar.project ? bar.project.color : "transparent"
    }
    PC3.Label {
        objectName: "workspaceProject"
        visible: bar.project !== null
        text: bar.project ? (bar.fromProject ? i18n("%1 (folder from the project)", bar.project.name) : bar.project.name) : ""
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        opacity: 0.75
        elide: Text.ElideRight
        Layout.maximumWidth: Kirigami.Units.gridUnit * 12
    }

    // Clears the chat's own folder (a project's folder is changed in the project).
    PC3.ToolButton {
        objectName: "workspaceClear"
        visible: bar.workspace !== "" && !bar.fromProject
        icon.name: "edit-clear"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: i18n("Clear the workspace (No workspace)")
        Accessible.name: QQC2.ToolTip.text
        onClicked: bar.choose("")
    }

    QQC2.ComboBox {
        id: agentSelectorCombo
        visible: bar.chat.openCodeMode
        implicitWidth: Kirigami.Units.gridUnit * 7
        implicitHeight: Kirigami.Units.gridUnit * 1.8
        // The agents OpenCode reports for the chat's folder (GET /agent),
        // and always the agent the chat really sends with.
        model: bar.agentModel
        textRole: "text"
        valueRole: "value"
        enabled: bar.chat.openCodeAgentsList.length > 0
        currentIndex: OpenCodeAgents.indexOf(bar.agentModel, bar.chat.openCodeAgent)
        onActivated: function(index) {
            if (bar.agentModel[index] && bar.agentModel[index].value !== (bar.chat.openCodeAgent || ""))
                bar.agentChosen(bar.agentModel[index].value);
            // Always show the agent the chat really has (picking may not change it).
            agentSelectorCombo.currentIndex = Qt.binding(function() { return OpenCodeAgents.indexOf(bar.agentModel, bar.chat.openCodeAgent); });
        }
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Agent profile — uses model from opencode.json\nCurrently: " + (bar.chat.openCodeAgent || "(default)")
        Accessible.name: i18n("Agent profile")
    }

    PC3.ToolButton {
        visible: bar.chat.openCodeMode
        icon.name: "view-list-details"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Reload the agent list from OpenCode"
        Accessible.name: QQC2.ToolTip.text
        onClicked: bar.chat.fetchOpenCodeAgents()
    }

    PC3.ToolButton {
        visible: bar.chat.openCodeMode
        icon.name: "view-refresh"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: i18n("Sync session history from OpenCode")
        Accessible.name: QQC2.ToolTip.text
        enabled: !bar.chat.loading && bar.chat.currentOpenCodeSessionId() !== ""
        onClicked: bar.chat.syncOpenCodeSessionHistory()
    }
}
