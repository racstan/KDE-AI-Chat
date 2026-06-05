/**
 * SessionSidebar — list of chat sessions with rename / archive / delete actions.
 *
 * Renders the ListView used by the "History" view in main.qml. The
 * component is decoupled from the rest of the UI by exposing all
 * callbacks and read-only helpers through the `root` property.
 *
 * Required caller bindings (via `root`):
 *   - root.sessions                 model array
 *   - root.currentSessionId        string
 *   - root.editingSessionId        string
 *   - root.editingSessionDraft     string
 *   - root.popupIsDark             bool
 *   - root.sessionHasSchedules(id) -> bool
 *   - root.sessionSubtitle(s)      -> string
 *   - root.historySessionTint(s)   -> color
 *   - root.translate(s)            -> string
 *   - root.switchSession(id)
 *   - root.startSessionRename(id)
 *   - root.saveSessionRename(id)
 *   - root.cancelSessionRename()
 *   - root.setSessionArchived(id, bool)
 *   - root.deleteSession(id)
 */
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Rectangle {
    id: sidebarRoot

    property var root

    radius: 8
    color: Kirigami.Theme.alternateBackgroundColor

    ListView {
        id: historyList

        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        model: sidebarRoot.root ? sidebarRoot.root.sessions : []
        spacing: Kirigami.Units.smallSpacing
        clip: true
        cacheBuffer: 5000

        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

        delegate: Rectangle {
            required property var modelData

            width: historyList.width
            height: historyCol.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: 8
            opacity: modelData.archived ? 0.72 : 1
            color: sidebarRoot.root.historySessionTint(modelData)

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

                        visible: modelData.source === "opencode"
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

                    Rectangle {
                        id: schedBadge

                        visible: sidebarRoot.root.sessionHasSchedules(modelData.value)
                        width: schedBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 2
                        height: schedBadgeText.implicitHeight + Kirigami.Units.smallSpacing
                        radius: 999
                        color: Qt.rgba(0.92, 0.48, 0.2, 0.18)

                        PC3.Label {
                            id: schedBadgeText

                            anchors.centerIn: parent
                            text: "SC"
                            font.bold: true
                            color: Qt.rgba(0.78, 0.35, 0.12, 1)
                        }
                    }

                    Rectangle {
                        id: forkBadge

                        visible: modelData.value && modelData.value.indexOf("fork-") === 0
                        width: forkBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 2
                        height: forkBadgeText.implicitHeight + Kirigami.Units.smallSpacing
                        radius: 999
                        color: Qt.rgba(0.48, 0.2, 0.92, 0.18)

                        PC3.Label {
                            id: forkBadgeText

                            anchors.centerIn: parent
                            text: "FK"
                            font.bold: true
                            color: Qt.rgba(0.35, 0.12, 0.78, 1)
                        }
                    }

                    QQC2.TextField {
                        visible: sidebarRoot.root.editingSessionId === modelData.value
                        width: parent.width - saveRename.width - archiveChat.width - removeChat.width
                            - (modeBadge.visible ? modeBadge.width + Kirigami.Units.smallSpacing / 2 : 0)
                            - (schedBadge.visible ? schedBadge.width + Kirigami.Units.smallSpacing / 2 : 0)
                            - (forkBadge.visible ? forkBadge.width + Kirigami.Units.smallSpacing / 2 : 0)
                            - (countBadge.visible ? countBadge.width + Kirigami.Units.smallSpacing / 2 : 0)
                            - Kirigami.Units.smallSpacing * 4
                        text: sidebarRoot.root.editingSessionDraft
                        onTextChanged: sidebarRoot.root.editingSessionDraft = text
                        onAccepted: sidebarRoot.root.saveSessionRename(modelData.value)
                    }

                    PC3.Label {
                        id: sessionTitleLabel

                        visible: sidebarRoot.root.editingSessionId !== modelData.value
                        width: parent.width - saveRename.width - archiveChat.width - removeChat.width
                            - (modeBadge.visible ? modeBadge.width + Kirigami.Units.smallSpacing / 2 : 0)
                            - (schedBadge.visible ? schedBadge.width + Kirigami.Units.smallSpacing / 2 : 0)
                            - (forkBadge.visible ? forkBadge.width + Kirigami.Units.smallSpacing / 2 : 0)
                            - (countBadge.visible ? countBadge.width + Kirigami.Units.smallSpacing / 2 : 0)
                            - Kirigami.Units.smallSpacing * 4
                        text: {
                            var rawText = modelData.text || "New Chat";
                            if (rawText.indexOf("[FK] ") === 0)
                                rawText = rawText.substring(5);
                            return sidebarRoot.root.translate(rawText);
                        }
                        font.bold: modelData.value === sidebarRoot.root.currentSessionId
                        color: sidebarRoot.root.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                sidebarRoot.root.switchSession(modelData.value);
                                sidebarRoot.root.historyOnlyMode = false;
                            }
                        }
                    }

                    Rectangle {
                        id: countBadge

                        property int totalCount: (modelData.messages || []).length
                        property int readCount: modelData.readCount !== undefined ? modelData.readCount : totalCount
                        property int unreadCount: Math.max(0, totalCount - readCount)

                        visible: unreadCount > 0
                        width: countBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 1.5
                        height: countBadgeText.implicitHeight + Kirigami.Units.smallSpacing * 0.5
                        radius: 10
                        color: Kirigami.Theme.highlightColor

                        PC3.Label {
                            id: countBadgeText

                            anchors.centerIn: parent
                            text: parent.unreadCount > 99 ? "99+" : parent.unreadCount
                            font.bold: true
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.75
                            color: Kirigami.Theme.highlightedTextColor
                        }
                    }

                    PC3.ToolButton {
                        id: saveRename

                        icon.name: sidebarRoot.root.editingSessionId === modelData.value ? "dialog-ok-apply" : "document-edit"
                        display: PC3.AbstractButton.IconOnly
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: sidebarRoot.root.editingSessionId === modelData.value ? "Save title" : "Rename chat"
                        onClicked: {
                            if (sidebarRoot.root.editingSessionId === modelData.value)
                                sidebarRoot.root.saveSessionRename(modelData.value);
                            else
                                sidebarRoot.root.startSessionRename(modelData.value);
                        }
                    }

                    PC3.ToolButton {
                        id: archiveChat

                        icon.name: modelData.archived ? "archive-remove" : "archive-insert"
                        display: PC3.AbstractButton.IconOnly
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: modelData.archived ? "Unarchive chat" : "Archive chat"
                        onClicked: sidebarRoot.root.setSessionArchived(modelData.value, !modelData.archived)
                    }

                    PC3.ToolButton {
                        id: removeChat

                        icon.name: sidebarRoot.root.editingSessionId === modelData.value ? "dialog-cancel" : "edit-delete"
                        display: PC3.AbstractButton.IconOnly
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: sidebarRoot.root.editingSessionId === modelData.value ? "Cancel rename" : "Delete chat"
                        onClicked: {
                            if (sidebarRoot.root.editingSessionId === modelData.value)
                                sidebarRoot.root.cancelSessionRename();
                            else
                                sidebarRoot.root.deleteSession(modelData.value);
                        }
                    }
                }

                PC3.Label {
                    opacity: sidebarRoot.root.popupIsDark ? 1 : 0.7
                    color: sidebarRoot.root.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                    text: sidebarRoot.root.sessionSubtitle(modelData)
                }
            }
        }
    }
}
