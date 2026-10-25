// The chat history: every chat with rename, archive and delete. Clicking a
// title opens that chat.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Rectangle {
    id: sessionList

    property var chat: null
    readonly property alias list: historyList

    radius: Kirigami.Units.cornerRadius
    color: Kirigami.Theme.alternateBackgroundColor

    ListView {
        id: historyList

        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        model: sessionList.chat.sessions
        spacing: Kirigami.Units.smallSpacing
        clip: true
        cacheBuffer: 5000

        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
        }

        delegate: Rectangle {
            id: row

            required property var modelData
            readonly property var chat: sessionList.chat
            readonly property bool editing: chat.editingSessionId === modelData.value
            readonly property real titleWidth: historyCol.width - saveRename.width - archiveChat.width - removeChat.width - (modeBadge.visible ? modeBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - Kirigami.Units.smallSpacing * 3

            width: historyList.width
            height: historyCol.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: Kirigami.Units.cornerRadius
            opacity: modelData.archived ? 0.72 : 1
            // The open chat is tinted with the accent colour, the others faintly.
            color: modelData.value === chat.currentSessionId
                ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)

            Column {
                id: historyCol

                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing / 2

                Row {
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing / 2

                    Rectangle {
                        id: modeBadge

                        visible: row.modelData.source === "opencode"
                        width: modeBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 2
                        height: modeBadgeText.implicitHeight + Kirigami.Units.smallSpacing
                        radius: Kirigami.Units.cornerRadius
                        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)

                        PC3.Label {
                            id: modeBadgeText

                            anchors.centerIn: parent
                            text: "OC"
                            font.bold: true
                            color: Kirigami.Theme.textColor
                        }
                    }

                    PC3.TextField {
                        id: titleField

                        visible: row.editing
                        width: row.titleWidth
                        text: row.chat.editingSessionDraft
                        onTextChanged: row.chat.editingSessionDraft = text
                        onAccepted: row.chat.saveSessionRename(row.modelData.value)
                    }

                    PC3.Label {
                        visible: !row.editing
                        width: row.titleWidth
                        text: row.modelData.text || "New Chat"
                        font.bold: row.modelData.value === row.chat.currentSessionId
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                row.chat.switchSession(row.modelData.value);
                                row.chat.historyOnlyMode = false;
                            }
                        }
                    }

                    PC3.ToolButton {
                        id: saveRename

                        icon.name: row.editing ? "dialog-ok-apply" : "document-edit"
                        display: PC3.AbstractButton.IconOnly
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: row.editing ? "Save title" : "Rename chat"
                        onClicked: {
                            if (row.editing)
                                row.chat.saveSessionRename(row.modelData.value);
                            else
                                row.chat.startSessionRename(row.modelData.value);
                        }
                    }

                    PC3.ToolButton {
                        id: archiveChat

                        icon.name: row.modelData.archived ? "archive-remove" : "archive-insert"
                        display: PC3.AbstractButton.IconOnly
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: row.modelData.archived ? "Unarchive chat" : "Archive chat"
                        onClicked: row.chat.setSessionArchived(row.modelData.value, !row.modelData.archived)
                    }

                    PC3.ToolButton {
                        id: removeChat

                        icon.name: row.editing ? "dialog-cancel" : "trash-empty"
                        display: PC3.AbstractButton.IconOnly
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: row.editing ? "Cancel rename" : "Delete chat"
                        onClicked: {
                            if (row.editing)
                                row.chat.cancelSessionRename();
                            else
                                row.chat.deleteSession(row.modelData.value);
                        }
                    }
                }

                PC3.Label {
                    opacity: 0.7
                    text: row.chat.sessionSubtitle(row.modelData)
                }
            }
        }
    }
}
