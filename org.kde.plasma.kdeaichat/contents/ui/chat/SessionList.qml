// The chat history: a search across all chats (chat/ChatSearchPanel.qml;
// its results take the place of the rest while it has a query), the projects (chat/ProjectsSidebar.qml: All chats, each
// project, Archived) and, below, the chats of the one chosen, one compact row
// per chat with its title and when it was last used. Rename, archive (restore
// in Archived) and delete appear on the row only while the pointer is over it
// or it has keyboard focus; right-click or the Menu key opens the chat's menu
// (also Move to project). Clicking a row (or Enter on it) opens that chat.
// Dragging a row (mouse) onto a project above moves the chat there, the same
// move as the menu's Move to project.
// Shown beside the chat in a wide popup and in place of it in a narrow one
// (chat/ChatBody.qml).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified
Rectangle {
    id: sessionList

    property var chat: null
    // A narrow popup shows the history instead of the chat: choosing a chat
    // then goes back to it. Beside the chat, the history stays open.
    property bool closeOnSelect: true
    // Room kept free at the bottom for the popup's resize grip (chat/ChatBody.qml).
    property real bottomRoom: 0
    readonly property alias list: historyList

    // "Today", "Yesterday" or the date.
    function dayLabel(ms) {
        if (!(ms > 0))
            return "";
        var now = new Date();
        var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        if (ms >= startOfToday)
            return i18n("Today");
        if (ms >= startOfToday - 86400000)
            return i18n("Yesterday");
        return new Date(ms).toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }

    readonly property var projects: chat.projects
    readonly property bool archivedView: projects.view === "archived"
    readonly property alias sidebar: projectsSidebar
    readonly property alias rowMenu: chatMenu
    // Deletes a chat, or asks first if Settings → Chat says so (returns the question; chat/ChatPrefs.qml).
    function removeChat(s) { return chat.prefs ? chat.prefs.deleteChat(s.value, s.text, sessionList) : chat.deleteSession(s.value); }
    readonly property alias search: searchPanel

    radius: Kirigami.Units.cornerRadius
    color: Kirigami.Theme.alternateBackgroundColor
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)

    // The menu of one chat (right-click or the Menu key on a row).
    ChatRowMenu {
        id: chatMenu
        chat: sessionList.chat
        onDeleteRequested: session => sessionList.removeChat(session)
    }

    function focusSearch() { searchPanel.focusSearch(); }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        anchors.bottomMargin: Kirigami.Units.smallSpacing + sessionList.bottomRoom
        spacing: Kirigami.Units.smallSpacing

        // Search across all chats: while it has a query, its results replace everything below.
        ChatSearchPanel {
            id: searchPanel
            chat: sessionList.chat
            closeOnSelect: sessionList.closeOnSelect
            Layout.fillWidth: true
            Layout.fillHeight: searching
        }

        ProjectsSidebar {
            id: projectsSidebar
            visible: !searchPanel.searching
            chat: sessionList.chat
            Layout.fillWidth: true
        }

        Kirigami.Separator {
            visible: !searchPanel.searching
            Layout.fillWidth: true
        }

        // What the list shows, and New chat in that project.
        RowLayout {
            visible: !searchPanel.searching
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing * 2
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                objectName: "viewTitle"
                Layout.fillWidth: true
                text: sessionList.projects.viewProject ? sessionList.projects.viewProject.name
                    : sessionList.archivedView ? i18n("Archived chats") : i18n("All chats")
                font.bold: true
                elide: Text.ElideRight
            }
            PC3.ToolButton {
                objectName: "newChatInViewButton"
                visible: sessionList.projects.viewProject !== null
                icon.name: "list-add"
                display: PC3.AbstractButton.IconOnly
                enabled: !sessionList.chat.loading
                Accessible.name: i18n("New chat in this project")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: Accessible.name
                onClicked: {
                    sessionList.projects.newChat();
                    if (sessionList.closeOnSelect)
                        sessionList.chat.historyOnlyMode = false;
                }
            }
        }

        PC3.Label {
            objectName: "emptyViewLabel"
            visible: historyList.count === 0 && !searchPanel.searching
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Kirigami.Theme.disabledTextColor
            text: sessionList.archivedView ? i18n("No archived chats. Archive a chat to keep it out of the list without deleting it.")
                : sessionList.projects.viewProject ? i18n("No chats in this project yet. Start one with +, or move a chat here from its menu.")
                : i18n("No chats yet.")
        }

        ListView {
            id: historyList

            visible: !searchPanel.searching
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: sessionList.projects.visibleChats
            spacing: 1
            clip: true
            cacheBuffer: 5000

            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            }

            delegate: Rectangle {
                id: row

                required property var modelData
                readonly property var chat: sessionList.chat
                readonly property bool current: modelData.value === chat.currentSessionId
                readonly property bool editing: chat.editingSessionId === modelData.value
                // One line, as plain text: a title is the start of what was typed, so it
                // can hold markup (rich text ignores elide) or line breaks.
                readonly property string title: String(modelData.text || "").replace(/\s+/g, " ").trim() || i18n("New Chat")
                readonly property bool showActions: hover.hovered || activeFocus || editing || renameButton.activeFocus
                                                    || archiveButton.activeFocus || deleteButton.activeFocus

                function open() {
                    chat.switchSession(modelData.value);
                    if (sessionList.closeOnSelect)
                        chat.historyOnlyMode = false;
                }

                // Beside the scroll bar, not under it.
                width: historyList.width - (historyList.QQC2.ScrollBar.vertical.visible ? historyList.QQC2.ScrollBar.vertical.width : 0)
                clip: true
                height: Kirigami.Units.gridUnit * 2 + Kirigami.Units.smallSpacing
                radius: Kirigami.Units.cornerRadius
                opacity: modelData.archived && !sessionList.archivedView ? 0.72 : 1
                // The open chat is tinted with the accent colour; a hovered one faintly.
                color: current ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
                     : hover.hovered ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)
                     : "transparent"
                border.width: activeFocus ? 1 : 0
                border.color: Kirigami.Theme.highlightColor
                activeFocusOnTab: true

                Accessible.role: Accessible.Button
                Accessible.name: title
                Accessible.description: sessionList.dayLabel(modelData.updatedAt || modelData.createdAt)
                Accessible.onPressAction: open()

                Keys.onReturnPressed: if (!editing) open()
                Keys.onEnterPressed: if (!editing) open()
                Keys.onDownPressed: nextItemInFocusChain(true).forceActiveFocus()
                Keys.onUpPressed: nextItemInFocusChain(false).forceActiveFocus()

                HoverHandler {
                    id: hover
                }

                // Drag onto a project (ProjectsSidebar.qml's drop areas); touch still scrolls.
                DragHandler {
                    id: dragHandler
                    target: null
                    enabled: !row.editing
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onActiveChanged: {
                        if (active) {
                            dragGhost.sessionId = row.modelData.value;
                            dragGhost.title = row.title;
                            dragGhost.Drag.active = true;
                        } else {
                            dragGhost.Drag.drop();
                            dragGhost.Drag.active = false;
                            dragGhost.sessionId = "";
                        }
                    }
                    onCentroidChanged: {
                        if (!active)
                            return;
                        var at = row.mapToItem(sessionList, centroid.position.x, centroid.position.y);
                        dragGhost.x = at.x - dragGhost.Drag.hotSpot.x;
                        dragGhost.y = at.y - dragGhost.Drag.hotSpot.y;
                    }
                }

                TapHandler {
                    enabled: !row.editing
                    onTapped: {
                        row.forceActiveFocus();
                        row.open();
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: !row.editing
                    onTapped: chatMenu.openFor(row.modelData, row)
                }
                Keys.onMenuPressed: chatMenu.openFor(row.modelData, row)

                QQC2.ToolTip.visible: hover.hovered && !row.editing
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.text: chat.sessionSubtitle(modelData)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    // In All chats and Archived, a chat in a project shows the project's colour.
                    Rectangle {
                        readonly property var project: sessionList.projects.viewProject ? null : sessionList.projects.byId(row.modelData.projectId)
                        objectName: "projectDot"
                        visible: project !== null
                        Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                        Layout.preferredHeight: Layout.preferredWidth
                        radius: width / 2
                        color: project ? project.color : "transparent"
                        Accessible.name: project ? i18n("In project %1", project.name) : ""
                    }

                    // Agent chats are marked with a plain tag: OC for OpenCode, PI for Pi.
                    PC3.Label {
                        visible: text !== ""
                        text: row.modelData.source === "opencode" ? "OC" : (row.modelData.source === "pi" ? "PI" : "")
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        font.bold: true
                        opacity: 0.7
                        Accessible.name: row.modelData.source === "pi" ? i18n("Pi chat") : i18n("OpenCode chat")
                    }

                    PC3.Label {
                        objectName: "titleLabel"
                        visible: !row.editing
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: row.title
                        textFormat: Text.PlainText
                        maximumLineCount: 1
                        font.bold: row.current
                        elide: Text.ElideRight
                    }

                    PC3.TextField {
                        Accessible.name: i18n("Chat name")
                        visible: row.editing
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: row.chat.editingSessionDraft
                        onTextChanged: row.chat.editingSessionDraft = text
                        onAccepted: row.chat.saveSessionRename(row.modelData.value)
                        onVisibleChanged: if (visible) forceActiveFocus()
                    }

                    // Always whole: the title is cut instead.
                    PC3.Label {
                        objectName: "dateLabel"
                        visible: !row.showActions
                        text: sessionList.dayLabel(row.modelData.updatedAt || row.modelData.createdAt)
                        color: Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont
                        Layout.minimumWidth: implicitWidth
                    }

                    // Actions: only while hovered or focused (or renaming).
                    PC3.ToolButton {
                        id: renameButton
                        objectName: "renameButton"

                        visible: row.showActions
                        icon.name: row.editing ? "dialog-ok-apply" : "document-edit"
                        display: PC3.AbstractButton.IconOnly
                        Accessible.name: row.editing ? i18n("Save title") : i18n("Rename chat")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: Accessible.name
                        onClicked: {
                            if (row.editing)
                                row.chat.saveSessionRename(row.modelData.value);
                            else
                                row.chat.startSessionRename(row.modelData.value);
                        }
                    }

                    PC3.ToolButton {
                        id: archiveButton
                        objectName: "archiveButton"

                        visible: row.showActions && !row.editing
                        icon.name: row.modelData.archived ? "document-revert" : "archive-insert"
                        display: PC3.AbstractButton.IconOnly
                        Accessible.name: row.modelData.archived ? i18n("Restore chat") : i18n("Archive chat")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: Accessible.name
                        onClicked: row.chat.setSessionArchived(row.modelData.value, !row.modelData.archived)
                    }

                    PC3.ToolButton {
                        id: deleteButton
                        objectName: "deleteButton"

                        visible: row.showActions
                        icon.name: row.editing ? "dialog-cancel" : "trash-empty"
                        display: PC3.AbstractButton.IconOnly
                        Accessible.name: row.editing ? i18n("Cancel rename") : i18n("Delete chat")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: Accessible.name
                        onClicked: {
                            if (row.editing)
                                row.chat.cancelSessionRename();
                            else
                                sessionList.removeChat(row.modelData);
                        }
                    }
                }
            }
        }
    }

    // What a dragged chat row looks like under the pointer; it carries the
    // chat's id to the drop areas of the projects.
    Rectangle {
        id: dragGhost
        objectName: "dragGhost"
        property string sessionId: ""
        property string title: ""
        visible: Drag.active
        z: 10
        width: Math.min(ghostLabel.implicitWidth + Kirigami.Units.largeSpacing * 2, sessionList.width * 0.8)
        height: Kirigami.Units.gridUnit * 1.6
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Kirigami.Theme.highlightColor
        Drag.keys: ["kdeaichat-chat"]
        Drag.hotSpot.x: Kirigami.Units.largeSpacing
        Drag.hotSpot.y: height / 2

        PC3.Label {
            id: ghostLabel
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            verticalAlignment: Text.AlignVCenter
            text: dragGhost.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
    }
}
