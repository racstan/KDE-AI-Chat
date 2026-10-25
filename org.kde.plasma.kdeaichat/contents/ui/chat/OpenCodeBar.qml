// The OpenCode row under the header: workspace folder, session, agent
// profile, and refresh/sync buttons. Shown only in OpenCode mode.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

RowLayout {
    id: bar

    property var chat: null
    // The history takes the whole view (set by FullRepresentationContent).
    property bool historyFull: chat ? chat.historyOnlyMode : false

    signal workspaceRequested()
    signal agentChosen(string value)

    Layout.fillWidth: true
    visible: !bar.historyFull && bar.chat.openCodeMode
    spacing: Kirigami.Units.smallSpacing

    Component.onCompleted: {
        if (bar.chat.openCodeMode && bar.chat.openCodeAgentsList.length === 0)
            bar.chat.fetchOpenCodeAgents();
    }
    onVisibleChanged: {
        if (visible && bar.chat.openCodeAgentsList.length === 0)
            bar.chat.fetchOpenCodeAgents();
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
                var p = bar.chat.openCodeWorkspaceCwd;
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
        // The list is populated from OpenCode's API/configuration.
        // Never invent agent names locally: an empty list means that
        // OpenCode has not reported any agents yet.
        model: bar.chat.openCodeAgentsList
        textRole: "text"
        valueRole: "value"
        enabled: model.length > 0
        currentIndex: {
            var cur = bar.chat.openCodeAgent || "";
            for (var i = 0; i < model.length; i++) {
                if (model[i].value === cur) return i;
            }
            return 0;
        }
        onActivated: {
            if (!model[currentIndex]) return;
            bar.agentChosen(model[currentIndex].value);
        }
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Agent profile — uses model from opencode.json\nCurrently: " + (bar.chat.openCodeAgent || "(default)")
        Accessible.name: i18n("Agent profile")
    }

    PC3.ToolButton {
        icon.name: "view-list-details"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Refresh agent list from opencode.json"
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
