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
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Rectangle {
    id: sidebarRoot

    property var chatRoot
    property string sortBy: "date_desc"

    radius: 8
    color: Kirigami.Theme.alternateBackgroundColor

    function focusSearch() {
        searchInput.forceActiveFocus();
    }

    function getFilteredSessions(isArchived) {
        if (!sidebarRoot.chatRoot || !sidebarRoot.chatRoot.sessions) return [];
        let rawList = sidebarRoot.chatRoot.sessions;
        let filtered = [];
        let query = searchInput.text.trim().toLowerCase();
        for (let i = 0; i < rawList.length; i++) {
            let s = rawList[i];
            let isArch = s.archived || false;
            if (isArch !== isArchived) continue;
            if (query !== "") {
                let title = (s.text || "New Chat").toLowerCase();
                let subtitle = (sidebarRoot.chatRoot ? sidebarRoot.chatRoot.sessionSubtitle(s) : "").toLowerCase();
                if (title.indexOf(query) === -1 && subtitle.indexOf(query) === -1) {
                    continue;
                }
            }
            filtered.push(s);
        }
        // Sort
        filtered.sort(function(a, b) {
            if (sortBy === "date_desc") {
                let tA = a.updatedAt || a.createdAt || 0;
                let tB = b.updatedAt || b.createdAt || 0;
                return tB - tA;
            } else if (sortBy === "date_asc") {
                let tA = a.updatedAt || a.createdAt || 0;
                let tB = b.updatedAt || b.createdAt || 0;
                return tA - tB;
            } else if (sortBy === "name_asc") {
                let nA = (a.text || "New Chat").toLowerCase();
                let nB = (b.text || "New Chat").toLowerCase();
                return nA.localeCompare(nB);
            } else if (sortBy === "name_desc") {
                let nA = (a.text || "New Chat").toLowerCase();
                let nB = (b.text || "New Chat").toLowerCase();
                return nB.localeCompare(nA);
            }
            return 0;
        });
        return filtered;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // Search & Sort bar
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: searchInput
                Layout.fillWidth: true
                placeholderText: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.translate("Search chats...") : "Search chats..."
                rightPadding: clearSearchButton.visible ? clearSearchButton.width : Kirigami.Units.smallSpacing
                
                PC3.ToolButton {
                    id: clearSearchButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.text !== ""
                    icon.name: "edit-clear"
                    display: PC3.AbstractButton.IconOnly
                    onClicked: {
                        parent.text = "";
                    }
                }
            }

            PC3.ToolButton {
                id: sortButton
                icon.name: "view-sort"
                display: PC3.AbstractButton.IconOnly
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.translate("Sort order") : "Sort order"
                onClicked: sortMenu.open()

                QQC2.Menu {
                    id: sortMenu
                    y: parent.height

                    QQC2.MenuItem {
                        text: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.translate("Newest first") : "Newest first"
                        checkable: true
                        checked: sortBy === "date_desc"
                        onTriggered: sortBy = "date_desc"
                    }
                    QQC2.MenuItem {
                        text: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.translate("Oldest first") : "Oldest first"
                        checkable: true
                        checked: sortBy === "date_asc"
                        onTriggered: sortBy = "date_asc"
                    }
                    QQC2.MenuItem {
                        text: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.translate("Name (A-Z)") : "Name (A-Z)"
                        checkable: true
                        checked: sortBy === "name_asc"
                        onTriggered: sortBy = "name_asc"
                    }
                    QQC2.MenuItem {
                        text: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.translate("Name (Z-A)") : "Name (Z-A)"
                        checkable: true
                        checked: sortBy === "name_desc"
                        onTriggered: sortBy = "name_desc"
                    }
                }
            }
        }

        // Sessions list in ScrollView
        QQC2.ScrollView {
            id: historyScrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AsNeeded

            ColumnLayout {
                x: Kirigami.Units.smallSpacing
                width: historyScrollView.availableWidth - Kirigami.Units.smallSpacing * 2
                spacing: Kirigami.Units.smallSpacing

                // Active Chats Header
                RowLayout {
                    Layout.fillWidth: true
                    visible: activeRepeater.count > 0
                    
                    PC3.Label {
                        text: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.translate("Active Chats") : "Active Chats"
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    
                    PC3.Label {
                        text: activeRepeater.count
                        opacity: 0.6
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }

                Repeater {
                    id: activeRepeater
                    model: sidebarRoot.getFilteredSessions(false)
                    delegate: sessionDelegateComponent
                }

                // Separator between Active and Archived if both exist
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                    visible: activeRepeater.count > 0 && archivedRepeater.count > 0
                }

                // Archived Chats Header
                RowLayout {
                    Layout.fillWidth: true
                    visible: archivedRepeater.count > 0
                    
                    PC3.Label {
                        text: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.translate("Archived Chats") : "Archived Chats"
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    
                    PC3.Label {
                        text: archivedRepeater.count
                        opacity: 0.6
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }

                Repeater {
                    id: archivedRepeater
                    model: sidebarRoot.getFilteredSessions(true)
                    delegate: sessionDelegateComponent
                }
            }
        }
    }

    Component {
        id: sessionDelegateComponent

        Rectangle {
            id: delegateBg
            required property var modelData

            Layout.fillWidth: true
            implicitHeight: delegateLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: 8
            opacity: modelData.archived ? 0.72 : 1
            color: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.historySessionTint(modelData) : "transparent"

            MouseArea {
                id: delegateMouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (sidebarRoot.chatRoot) {
                        sidebarRoot.chatRoot.switchSession(modelData.value);
                        sidebarRoot.chatRoot.historyOnlyMode = false;
                    }
                }
            }

            RowLayout {
                id: delegateLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                // Left side: Badges and Text (Title + Subtitle)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    // Badges layout (horizontal)
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing / 2
                        visible: modeBadge.visible || schedBadge.visible || forkBadge.visible
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            id: modeBadge
                            visible: modelData.source === "opencode"
                            width: modeBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 1.5
                            height: modeBadgeText.implicitHeight + Kirigami.Units.smallSpacing * 0.5
                            radius: 4
                            color: Qt.rgba(0.2, 0.48, 0.92, 0.15)

                            PC3.Label {
                                id: modeBadgeText
                                anchors.centerIn: parent
                                text: "OC"
                                font.bold: true
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.8
                                color: Qt.rgba(0.12, 0.35, 0.78, 1)
                            }
                        }

                        Rectangle {
                            id: schedBadge
                            visible: sidebarRoot.chatRoot && sidebarRoot.chatRoot.sessionHasSchedules(modelData.value)
                            width: schedBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 1.5
                            height: schedBadgeText.implicitHeight + Kirigami.Units.smallSpacing * 0.5
                            radius: 4
                            color: Qt.rgba(0.92, 0.48, 0.2, 0.15)

                            PC3.Label {
                                id: schedBadgeText
                                anchors.centerIn: parent
                                text: "SC"
                                font.bold: true
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.8
                                color: Qt.rgba(0.78, 0.35, 0.12, 1)
                            }
                        }

                        Rectangle {
                            id: forkBadge
                            visible: modelData.value && modelData.value.indexOf("fork-") === 0
                            width: forkBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 1.5
                            height: forkBadgeText.implicitHeight + Kirigami.Units.smallSpacing * 0.5
                            radius: 4
                            color: Qt.rgba(0.48, 0.2, 0.92, 0.15)

                            PC3.Label {
                                id: forkBadgeText
                                anchors.centerIn: parent
                                text: "FK"
                                font.bold: true
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.8
                                color: Qt.rgba(0.35, 0.12, 0.78, 1)
                            }
                        }
                    }

                    // Title and Subtitle stacked vertically
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        // Rename field (if editing)
                        QQC2.TextField {
                            id: renameField
                            visible: sidebarRoot.chatRoot && sidebarRoot.chatRoot.editingSessionId === modelData.value
                            Layout.fillWidth: true
                            text: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.editingSessionDraft : ""
                            onTextChanged: if (sidebarRoot.chatRoot) sidebarRoot.chatRoot.editingSessionDraft = text
                            onAccepted: if (sidebarRoot.chatRoot) sidebarRoot.chatRoot.saveSessionRename(modelData.value)
                            Component.onCompleted: {
                                if (visible) forceActiveFocus();
                            }
                        }

                        // Chat Title
                        PC3.Label {
                            id: sessionTitleLabel
                            visible: sidebarRoot.chatRoot && sidebarRoot.chatRoot.editingSessionId !== modelData.value
                            Layout.fillWidth: true
                            text: {
                                let rawText = modelData.text || "New Chat";
                                if (rawText.indexOf("[FK] ") === 0)
                                    rawText = rawText.substring(5);
                                return sidebarRoot.chatRoot ? sidebarRoot.chatRoot.translate(rawText) : rawText;
                            }
                            font.bold: sidebarRoot.chatRoot && modelData.value === sidebarRoot.chatRoot.currentSessionId
                            color: sidebarRoot.chatRoot && sidebarRoot.chatRoot.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                            elide: Text.ElideRight
                        }

                        // Chat Subtitle (Updated Date / Time / etc)
                        PC3.Label {
                            Layout.fillWidth: true
                            opacity: sidebarRoot.chatRoot && sidebarRoot.chatRoot.popupIsDark ? 0.8 : 0.6
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                            color: sidebarRoot.chatRoot && sidebarRoot.chatRoot.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                            text: sidebarRoot.chatRoot ? sidebarRoot.chatRoot.sessionSubtitle(modelData) : ""
                            elide: Text.ElideRight
                        }
                    }
                }

                // Right side: Message Count Badge (Actions are now an overlay)
                RowLayout {
                    id: actionsRow
                    spacing: Kirigami.Units.smallSpacing / 2
                    Layout.alignment: Qt.AlignVCenter

                    // Message Count Badge
                    Rectangle {
                        id: countBadge
                        property int totalCount: (modelData.messages || []).length
                        property int readCount: modelData.readCount !== undefined ? modelData.readCount : totalCount
                        property int unreadCount: Math.max(0, totalCount - readCount)

                        visible: unreadCount > 0 && !actionsContainer.visible
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
                }
            }

            // Actions Container Overlay
            // Positioned as an overlay to prevent layout reflows (flickering)
            // anchored with a larger margin to clear the scrollbar.
            Rectangle {
                id: actionsContainer
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Kirigami.Units.gridUnit * 0.8
                radius: 6
                color: {
                    let bg = delegateBg.color;
                    if (bg === "transparent" || bg === "#00000000" || bg === "rgba(0,0,0,0)")
                        return Kirigami.Theme.alternateBackgroundColor;
                    return bg;
                }
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                
                // Visibility logic: include button hover states to prevent flickering when
                // the mouse enters the overlay (which might cause the main MouseArea to lose hover).
                visible: delegateMouseArea.containsMouse || 
                         saveRename.hovered || 
                         archiveChat.hovered || 
                         removeChat.hovered ||
                         (sidebarRoot.chatRoot && (modelData.value === sidebarRoot.chatRoot.currentSessionId || 
                                                    sidebarRoot.chatRoot.editingSessionId === modelData.value))
                
                width: actionsRowInner.implicitWidth + Kirigami.Units.smallSpacing
                height: actionsRowInner.implicitHeight + Kirigami.Units.smallSpacing

                RowLayout {
                    id: actionsRowInner
                    anchors.centerIn: parent
                    spacing: 2

                    PC3.ToolButton {
                        id: saveRename
                        icon.name: sidebarRoot.chatRoot && sidebarRoot.chatRoot.editingSessionId === modelData.value ? "dialog-ok-apply" : "document-edit"
                        display: PC3.AbstractButton.IconOnly
                        implicitWidth: Kirigami.Units.gridUnit * 1.5
                        implicitHeight: Kirigami.Units.gridUnit * 1.5
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: sidebarRoot.chatRoot && sidebarRoot.chatRoot.editingSessionId === modelData.value ? "Save title" : "Rename chat"
                        onClicked: {
                            if (sidebarRoot.chatRoot) {
                                if (sidebarRoot.chatRoot.editingSessionId === modelData.value)
                                    sidebarRoot.chatRoot.saveSessionRename(modelData.value);
                                else
                                    sidebarRoot.chatRoot.startSessionRename(modelData.value);
                            }
                        }
                    }

                    PC3.ToolButton {
                        id: archiveChat
                        icon.name: modelData.archived ? "archive-remove" : "archive-insert"
                        display: PC3.AbstractButton.IconOnly
                        implicitWidth: Kirigami.Units.gridUnit * 1.5
                        implicitHeight: Kirigami.Units.gridUnit * 1.5
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: modelData.archived ? "Unarchive chat" : "Archive chat"
                        onClicked: if (sidebarRoot.chatRoot) sidebarRoot.chatRoot.setSessionArchived(modelData.value, !modelData.archived)
                    }

                    PC3.ToolButton {
                        id: removeChat
                        icon.name: sidebarRoot.chatRoot && sidebarRoot.chatRoot.editingSessionId === modelData.value ? "dialog-cancel" : "edit-delete"
                        display: PC3.AbstractButton.IconOnly
                        implicitWidth: Kirigami.Units.gridUnit * 1.5
                        implicitHeight: Kirigami.Units.gridUnit * 1.5
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: sidebarRoot.chatRoot && sidebarRoot.chatRoot.editingSessionId === modelData.value ? "Cancel rename" : "Delete chat"
                        onClicked: {
                            if (sidebarRoot.chatRoot) {
                                if (sidebarRoot.chatRoot.editingSessionId === modelData.value)
                                    sidebarRoot.chatRoot.cancelSessionRename();
                                else
                                    sidebarRoot.chatRoot.requestDeleteSession(modelData.value);
                            }
                        }
                    }
                }
            }
        }
    }
}