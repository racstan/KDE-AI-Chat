// The OpenCode row under the header: workspace folder, session, agent
// profile, and refresh/sync buttons. Shown only in OpenCode mode.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../backends/OpenCodeAgents.js" as OpenCodeAgents

RowLayout {
    id: bar

    property var chat: null
    // The history takes the whole view (set by FullRepresentationContent).
    property bool historyFull: chat ? chat.historyOnlyMode : false
    // The agents the selector offers: the server's list plus the chat's own agent.
    readonly property var agentModel: OpenCodeAgents.comboModel(bar.chat.openCodeAgentsList, bar.chat.openCodeAgent)

    signal workspaceRequested()
    signal agentChosen(string value)

    Layout.fillWidth: true
    visible: !bar.historyFull && bar.chat.openCodeMode
    spacing: Kirigami.Units.smallSpacing

    // The agent list belongs to a workspace folder: load it when the open
    // chat's folder isn't the one it was loaded for.
    function refreshAgents() {
        if (bar.chat.openCodeMode && bar.chat.openCodeAgentsDirectory !== String(bar.chat.openCodeWorkspaceCwd || "").trim())
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

    PC3.ToolButton {
        icon.name: "folder"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: bar.chat.openCodeWorkspaceCwd ? ("Workspace: " + bar.chat.openCodeWorkspaceCwd) : "Select OpenCode Workspace Directory"
        Accessible.name: QQC2.ToolTip.text
        onClicked: bar.workspaceRequested()
    }

    PC3.Label {
        text: {
            var folder = "";
            if (bar.chat.openCodeWorkspaceCwd) {
                const p = bar.chat.openCodeWorkspaceCwd;
                folder = p.substring(p.lastIndexOf("/") + 1) || p;
            }
            var sess = bar.chat.currentOpenCodeSessionId();
            var labelStr = folder || "Workspace";
            if (sess) labelStr += " (" + sess.substring(0, 10) + "…)";
            return labelStr;
        }
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        font.bold: true
        opacity: 0.85
        elide: Text.ElideMiddle
        // Takes the spare room and shortens first. (Never size it from
        // bar.width: the bar's own width then feeds back into its layout.)
        Layout.fillWidth: true
        Layout.minimumWidth: 0
    }

    QQC2.ComboBox {
        id: agentSelectorCombo
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
        icon.name: "view-list-details"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Reload the agent list from OpenCode"
        Accessible.name: QQC2.ToolTip.text
        onClicked: bar.chat.fetchOpenCodeAgents()
    }

    PC3.ToolButton {
        icon.name: "view-refresh"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: i18n("Sync session history from OpenCode")
        Accessible.name: QQC2.ToolTip.text
        enabled: !bar.chat.loading && bar.chat.currentOpenCodeSessionId() !== ""
        onClicked: bar.chat.syncOpenCodeSessionHistory()
    }
}
