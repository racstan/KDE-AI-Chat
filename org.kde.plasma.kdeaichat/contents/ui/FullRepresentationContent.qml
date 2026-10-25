import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasmoid
import "chat" as Chat

Item {
    id: repRoot
    anchors.fill: parent

    Kirigami.Theme.inherit: false
    Kirigami.Theme.backgroundColor: root.popupIsDark ? "#121212" : "#ffffff"
    Kirigami.Theme.alternateBackgroundColor: root.popupIsDark ? "#1a1a1a" : "#f5f7fa"
    Kirigami.Theme.textColor: root.popupIsDark ? "#f7fafc" : "#1a202c"
    Kirigami.Theme.highlightColor: "#3182ce"

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
            radius: 8
            visible: parent.containsDrag
            z: 999

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "mail-attachment"
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 48
                    implicitHeight: 48
                    color: Kirigami.Theme.highlightColor
                }

                PC3.Label {
                    text: "Drop files here to attach"
                    font.bold: true
                    font.pointSize: 14
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
            onWorkspaceRequested: workspaceFolderDialog.open()
            onAgentChosen: function(value) {
                root.openCodeAgent = value;
                plasmoid.configuration.openCodeAgent = value;
            }
        }

        Chat.RenameRow {
            chat: root
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.historyOnlyMode ? 1 : 0

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: Kirigami.Theme.alternateBackgroundColor
                        clip: true

                        Chat.ChatView {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            visible: !root.historyOnlyMode
                            chat: root
                        }
                    }

                    Chat.Composer {
                        chat: root
                        onAttachRequested: fileDialog.open()
                    }
                }
            }

            Loader {
                id: historyLoader

                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.historyOnlyMode
                visible: status === Loader.Ready

                sourceComponent: Component {
                    Chat.SessionList {
                        chat: root
                    }
                }
            }
        }

    }

    MouseArea {
        property real startX: 0
        property real startY: 0
        property real startW: 0
        property real startH: 0

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Kirigami.Units.gridUnit
        height: Kirigami.Units.gridUnit
        cursorShape: Qt.SizeFDiagCursor
        onPressed: function(mouse) {
            startX = mouse.x;
            startY = mouse.y;
            startW = parent.implicitWidth;
            startH = parent.implicitHeight;
        }
        onPositionChanged: function(mouse) {
            if (pressed) {
                var dx = mouse.x - startX;
                var dy = mouse.y - startY;
                var newW = Math.max(500, startW + dx);
                var newH = Math.max(620, startH + dy);
                parent.implicitWidth = newW;
                parent.implicitHeight = newH;
                plasmoid.configuration.customPopupWidth = newW;
                plasmoid.configuration.customPopupHeight = newH;
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"

            Canvas {
                anchors.fill: parent
                anchors.margins: 4
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.strokeStyle = Kirigami.Theme.textColor;
                    ctx.lineWidth = 1;
                    ctx.globalAlpha = 0.5;
                    ctx.beginPath();
                    ctx.moveTo(width - 4, height);
                    ctx.lineTo(width, height - 4);
                    ctx.moveTo(width - 8, height);
                    ctx.lineTo(width, height - 8);
                    ctx.moveTo(width - 12, height);
                    ctx.lineTo(width, height - 12);
                    ctx.stroke();
                }
            }

        }

    } // MouseArea

    ChatSettingsDialog {
        id: chatSettingsDialog
        rootRef: root
        hostItem: repRoot
    }
}
