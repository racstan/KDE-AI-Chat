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

    radius: 8
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
            radius: 8
            opacity: modelData.archived ? 0.72 : 1
            color: chat.historySessionTint(modelData)

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
                        radius: 999
                        color: Qt.rgba(0.2, 0.48, 0.92, 0.18)

                        PC3.Label {
                            id: modeBadgeText

                            anchors.centerIn: parent
                            text: "OC"
                            font.bold: true
                            color: Qt.rgba(0.12, 0.35, 0.78, 1)
                        }
                    }

                    QQC2.TextField {
                        id: titleField

                        visible: row.editing
                        width: row.titleWidth
                        text: row.chat.editingSessionDraft
                        color: Kirigami.Theme.textColor
                        background: Rectangle {
                            color: Kirigami.Theme.backgroundColor
                            radius: Kirigami.Units.smallSpacing
                            border.color: titleField.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
                            border.width: 1
                        }
                        onTextChanged: row.chat.editingSessionDraft = text
                        onAccepted: row.chat.saveSessionRename(row.modelData.value)
                    }

                    PC3.Label {
                        visible: !row.editing
                        width: row.titleWidth
                        text: row.modelData.text || "New Chat"
                        font.bold: row.modelData.value === row.chat.currentSessionId
                        color: row.chat.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
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

                        icon.name: row.editing ? "dialog-cancel" : "edit-delete"
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
                    opacity: row.chat.popupIsDark ? 1 : 0.7
                    color: row.chat.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                    text: row.chat.sessionSubtitle(row.modelData)
                }
            }
        }
    }
}
