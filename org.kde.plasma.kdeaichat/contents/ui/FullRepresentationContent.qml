import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "chat" as Chat

Item {
    id: repRoot
    anchors.fill: parent

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

        Chat.ChatHeader {
            chat: root
            historyFull: body.historyFull
            appName: plasmoid.configuration.appDisplayName || "KDE AI Chat"
            onSettingsRequested: Plasmoid.internalAction("configure").trigger()
            onChatControlsRequested: chatSettingsDialog.toggleForSession(root.currentSessionId)
            onExportRequested: function(suggestedFile) {
                exportFileDialog.currentFile = suggestedFile;
                exportFileDialog.open();
            }
        }

        Chat.NoticeBanner {
            isError: true
            text: root.sessionHistoryLoadError
            actionText: "Replace stored history"
            actionIcon: "edit-clear-all"
            onActionTriggered: root.resetUnreadableSessionHistory()
        }

        Chat.NoticeBanner {
            text: root.privacyNotice
            onDismissed: root.privacyNotice = ""
        }

        Chat.OpenCodeBar {
            chat: root
            historyFull: body.historyFull
            onWorkspaceRequested: workspaceFolderDialog.open()
            onAgentChosen: function(value) {
                root.openCodeAgent = value;
                plasmoid.configuration.openCodeAgent = value;
            }
        }

        Chat.RenameRow {
            chat: root
            historyFull: body.historyFull
        }

        Chat.ChatBody {
            id: body
            chat: root
            Layout.fillWidth: true
            Layout.fillHeight: true
            onAttachRequested: fileDialog.open()
        }

    }

    Chat.ChatShortcuts { chat: root } // qmllint disable unqualified

    // In the corner away from the panel, so dragging it grows the popup
    // towards the mouse.
    Chat.ResizeHandle {
        chat: root
        config: plasmoid.configuration
        growsUp: Plasmoid.location === PlasmaCore.Types.BottomEdge
        growsLeft: Plasmoid.location === PlasmaCore.Types.RightEdge
        anchors.right: growsLeft ? undefined : parent.right
        anchors.left: growsLeft ? parent.left : undefined
        anchors.bottom: growsUp ? undefined : parent.bottom
        anchors.top: growsUp ? parent.top : undefined
        z: 10
    }

    ChatSettingsDialog {
        id: chatSettingsDialog
        rootRef: root
        hostItem: repRoot
    }
}
