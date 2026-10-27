import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "chat" as Chat

// The accent colour from Settings → Appearance; none: the Plasma theme as is.
Chat.AccentArea {
    id: repRoot
    anchors.fill: parent
    accent: root.prefs ? root.prefs.accent : ""

    Connections {
        target: root.voiceManagerRef || null
        function onIsPlayingChanged() {
            if (root.voiceManagerRef && !root.voiceManagerRef.isPlaying) {
                root.playingMessageIndex = -1;
            }
        }
    }


    DropArea {
        id: dropArea

        anchors.fill: parent
        onEntered: function(drag) {
            if (drag.hasUrls)
                drag.accept(Qt.CopyAction);

        }
        onDropped: function(drop) {
            if (drop.hasUrls) {
                for (var i = 0; i < drop.urls.length; i++) {
                    root.attachFile(drop.urls[i]);
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
            border.color: Kirigami.Theme.highlightColor
            border.width: 2
            radius: Kirigami.Units.cornerRadius
            visible: parent.containsDrag
            z: 999

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "mail-attachment"
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Kirigami.Units.iconSizes.large
                    implicitHeight: Kirigami.Units.iconSizes.large
                    color: Kirigami.Theme.highlightColor
                }

                Kirigami.Heading {
                    text: "Drop files here to attach"
                    level: 3
                    color: Kirigami.Theme.highlightColor
                    Layout.alignment: Qt.AlignHCenter
                }

            }

        }

    }

    ColumnLayout {
        id: mainContentColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        anchors.rightMargin: chatSettingsDialog.visible ? chatSettingsDialog.width + Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // The grip (below) may sit in a corner of this row: its last button keeps clear of it.
        Chat.ChatHeader {
            Layout.leftMargin: grip.roomTopLeft
            Layout.rightMargin: chatSettingsDialog.visible ? 0 : grip.roomTopRight
            chat: root
            historyFull: body.historyFull
            appName: plasmoid.configuration.appDisplayName || "KDE AI Chat"
            onSettingsRequested: Plasmoid.internalAction("configure").trigger()
            onChatControlsRequested: chatSettingsDialog.toggleForSession(root.currentSessionId)
            onExportRequested: function(suggestedFile) {
                exportDialog.openWith(suggestedFile);
            }
            onScheduleRequested: scheduleOverlay.openForChat(root.currentSessionId) // qmllint disable unqualified
        }

        Chat.NoticeBanner {
            isError: true
            text: root.sessionHistoryLoadError
            actionText: root.chatStore && root.chatStore.indexProblem ? i18n("Rebuild the chat list from chat files") : "Replace stored history" // qmllint disable unqualified
            actionIcon: "edit-clear-all"
            onActionTriggered: root.resetUnreadableSessionHistory()
        }

        Chat.NoticeBanner {
            isError: true
            text: root.chatStore && root.chatStore.damagedIds[root.currentSessionId] ? i18n("This chat's file could not be read. A copy was kept and this chat is not saved, so nothing you add here is kept.") : "" // qmllint disable unqualified
        }

        Chat.NoticeBanner {
            text: root.privacyNotice
            onDismissed: root.privacyNotice = ""
        }

        Chat.WorkspaceBar {
            chat: root
            historyFull: body.historyFull
            onAgentChosen: function(value) { root.chooseOpenCodeAgent(value); }
        }

        Chat.RenameRow {
            chat: root
            historyFull: body.historyFull
        }

        Chat.ChatBody {
            id: body
            chat: root
            roomBottomLeft: grip.roomBottomLeft
            roomBottomRight: chatSettingsDialog.visible ? 0 : grip.roomBottomRight
            Layout.fillWidth: true
            Layout.fillHeight: true
            onAttachRequested: fileDialog.show()
            onChatInfoRequested: chatSettingsDialog.openForSession(body.chat.currentSessionId)
        }

    }

    // qmllint disable unqualified
    Chat.ChatShortcuts {
        chat: root
        onChatInfoRequested: chatSettingsDialog.toggleForSession(root.currentSessionId)
        onSearchRequested: body.openSearch()
    }
    // qmllint enable unqualified

    // Asks before leaving an incognito chat that has messages (chat/Incognito.qml).
    Chat.IncognitoLeaveDialog {
        chat: root // qmllint disable unqualified
    }

    // In the corner away from the panel, so dragging it grows the popup
    // towards the mouse. Above the chat info panel too; the rows in its
    // corner (header, composer, history, the panel's own top and bottom
    // rows) leave it room, so it never covers a button.
    Chat.ResizeHandle {
        id: grip
        chat: root
        config: plasmoid.configuration
        growsUp: Plasmoid.location === PlasmaCore.Types.BottomEdge
        growsLeft: Plasmoid.location === PlasmaCore.Types.RightEdge
        z: 1001
    }

    // "Schedule a message…": the schedule editor over the chat.
    // qmllint disable unqualified
    Chat.ScheduleOverlay {
        id: scheduleOverlay
        anchors.fill: parent
        chat: root
        z: 1002
    }
    // qmllint enable unqualified

    Chat.ExportDialog {
        id: exportDialog
        chat: root
    }

    ChatSettingsDialog {
        id: chatSettingsDialog
        rootRef: root
        hostItem: repRoot
        roomTop: grip.roomTopRight
        roomBottom: grip.roomBottomRight
    }
}
