import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "chat" as Chat

// The Chat info panel: a non-modal right-side drawer, opened from the chat
// header with toggleForSession(). It shows what this chat has used
// (Chat.ChatInfoSummary), its memories (Chat.ChatMemoryInfo) and its own
// settings (Chat.ChatOverridesForm), and keeps the settings as a draft
// (Chat.ChatSettingsDraft) until Apply. It stays attached to the chat
// instead of covering it.
Rectangle {
    id: page

    property var rootRef: null
    property Item hostItem: null
    // Room its top and bottom rows leave at the right for the popup's resize
    // grip (chat/ResizeHandle.qml) when it is in that corner.
    property real roomTop: 0
    property real roomBottom: 0
    property bool sidebarOpen: false
    readonly property alias draft: settingsDraft

    // The chat shown, from the chat's list so totals and dates stay current.
    readonly property var _session: {
        var list = rootRef ? (rootRef.sessions || []) : [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].value === settingsDraft.sessionId)
                return list[i];
        }
        return ({});
    }

    // What this chat really uses, and where that comes from (main.qml's
    // effectiveConfig, which follows the "per chat" settings).
    readonly property var _effective: rootRef && typeof rootRef.effectiveConfig === "function"
        ? rootRef.effectiveConfig(settingsDraft.sessionId) : ({"mode": "provider", "provider": "", "model": "", "source": "main"})
    readonly property bool _perChat: rootRef && rootRef.plasmoid ? rootRef.plasmoid.configuration.perChatModelSettings === true : false
    readonly property bool _mainWins: rootRef && rootRef.plasmoid ? rootRef.plasmoid.configuration.perChatPriority === "main" : false

    function openForSession(sessionId) {
        if (!rootRef)
            return;
        sidebarOpen = true;
        settingsDraft.load(sessionId);
    }

    function open() { sidebarOpen = true; }
    function close() { sidebarOpen = false; }

    function toggleForSession(sessionId) {
        if (visible && settingsDraft.sessionId === sessionId) {
            close();
            return;
        }
        openForSession(sessionId);
    }

    function _save() {
        settingsDraft.save();
        mcpChoice.save();
        close();
    }

    visible: sidebarOpen
    z: 1000
    anchors.top: parent ? parent.top : undefined
    anchors.right: parent ? parent.right : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    width: Math.min(Kirigami.Units.gridUnit * 24, Math.max(Kirigami.Units.gridUnit * 19, (parent ? parent.width : 760) * 0.44))
    color: Kirigami.Theme.backgroundColor
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
    border.width: 1
    focus: sidebarOpen
    Keys.onEscapePressed: page.close()
    onSidebarOpenChanged: if (!sidebarOpen) settingsDraft.invalidate()

    Chat.ChatSettingsDraft {
        id: settingsDraft
        rootRef: page.rootRef
        active: page.visible
    }

    Connections {
        target: page.rootRef
        function onCurrentSessionIdChanged() {
            if (page.visible && page.rootRef && page.rootRef.currentSessionId !== settingsDraft.sessionId)
                settingsDraft.load(page.rootRef.currentSessionId);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing + page.roomTop
            spacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Kirigami.Heading {
                    level: 3
                    text: i18n("Chat info")
                    Layout.fillWidth: true
                }
                PC3.Label {
                    textFormat: Text.PlainText
                    text: settingsDraft.sessionTitle
                    elide: Text.ElideRight
                    opacity: 0.7
                    Layout.fillWidth: true
                }
            }
            PC3.ToolButton {
                icon.name: "window-close"
                Accessible.name: i18n("Close chat info")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Close chat info")
                onClicked: page.close()
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        QQC2.ScrollView {
            id: scroll

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Heading {
                    level: 4
                    font.bold: true
                    text: i18n("This chat")
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                }

                // Which settings this chat sends with, and why.
                Chat.EffectiveLine {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    chat: page.rootRef
                    onModelChanged: {
                        // The picker saved straight to the chat: take that over, unless edits wait.
                        if (page.visible && !settingsDraft.dirty)
                            settingsDraft.load(settingsDraft.sessionId);
                    }
                    effective: page._effective
                    perChat: page._perChat
                    mainWins: page._mainWins
                    projectName: projectInfo.project ? projectInfo.project.name : ""
                    providerName: function(id) { return page.rootRef ? page.rootRef.providerDisplayName(id) : id; }
                }

                // The chat's project and what comes from it.
                Chat.ProjectInfoLine {
                    id: projectInfo
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    chat: page.rootRef
                    sessionId: settingsDraft.sessionId
                }

                Chat.ChatInfoSummary {
                    id: summary
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    messages: page.rootRef ? page.rootRef.messages : []
                    createdAt: page._session.createdAt || 0
                    updatedAt: page._session.updatedAt || 0
                }

                // Memories: on or off for this chat, and those its latest message used.
                Chat.ChatMemoryInfo {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    chat: page.rootRef
                    sessionId: settingsDraft.sessionId
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                Kirigami.Heading {
                    level: 4
                    font.bold: true
                    text: i18n("Settings for this chat")
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                }

                Chat.ChatOverridesForm {
                    id: form
                    draft: settingsDraft
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.bottomMargin: mcpChoice.visible ? 0 : Kirigami.Units.largeSpacing
                }

                // Direct chats: which MCP servers it may use.
                Chat.ChatMcpChoice {
                    id: mcpChoice
                    draft: settingsDraft
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.bottomMargin: Kirigami.Units.largeSpacing
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing + page.roomBottom
            spacing: Kirigami.Units.smallSpacing

            PC3.Button {
                text: i18n("Reset")
                icon.name: "edit-undo"
                onClicked: settingsDraft.reset()
            }
            Item {
                Layout.fillWidth: true
            }
            PC3.Label {
                visible: settingsDraft.dirty
                text: i18n("Unsaved changes")
                opacity: 0.7
            }
            PC3.Button {
                text: i18n("Apply")
                icon.name: "dialog-ok-apply"
                highlighted: true
                enabled: !settingsDraft.busy
                onClicked: page._save()
            }
        }
    }
}
