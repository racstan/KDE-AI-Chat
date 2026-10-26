// The top of the history: All chats, each project, and Archived, with how
// many chats each has. Choosing one filters the history below it
// (chat.projects.view). Projects can be created here; each project row edits
// (pencil on hover, or its menu) and deletes, keeping its chats or with
// them after a confirmation (its menu; Undo brings it all back). A chat row
// of the history dropped on a project moves the chat there.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: sidebar

    property var chat: null
    readonly property var projects: chat ? chat.projects : null
    // The rows: {view, name, color | icon}.
    readonly property var rows: {
        var out = [{"view": "all", "name": i18n("All chats"), "icon": "view-list-details"}];
        var list = projects ? projects.list : [];
        for (var i = 0; i < list.length; i++)
            out.push({"view": list[i].id, "name": list[i].name, "color": list[i].color});
        out.push({"view": "archived", "name": i18n("Archived"), "icon": "archive-insert"});
        return out;
    }
    readonly property alias list: viewList

    // Asks first (chat/ProjectDeleteConfirm.qml); returns the question.
    function confirmDeleteWithChats(projectId) {
        var popup = deleteConfirm.createObject(sidebar, {"projects": sidebar.projects, "projectId": projectId}) as ProjectDeleteConfirm;
        popup.open();
        return popup;
    }

    Component {
        id: deleteConfirm
        ProjectDeleteConfirm {}
    }

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing * 2
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            Layout.fillWidth: true
            text: i18n("Projects")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }
        PC3.ToolButton {
            objectName: "newProjectButton"
            icon.name: "folder-new"
            display: PC3.AbstractButton.IconOnly
            Accessible.name: i18n("New project")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: Accessible.name
            onClicked: sidebar.projects.openEditor("", "")
        }
    }

    ListView {
        id: viewList

        Layout.fillWidth: true
        // Grows with the projects, up to a third of the history's height.
        Layout.preferredHeight: Math.min(contentHeight, Math.max(Kirigami.Units.gridUnit * 5, (sidebar.parent ? sidebar.parent.height : 600) / 3))
        model: sidebar.rows
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

        delegate: Rectangle {
            id: row

            required property var modelData
            readonly property bool current: sidebar.projects && sidebar.projects.view === modelData.view
            readonly property bool isProject: modelData.color !== undefined
            readonly property int count: sidebar.projects ? (sidebar.projects.counts[modelData.view] || 0) : 0

            function choose() { sidebar.projects.view = row.modelData.view; }

            objectName: "viewRow"
            width: viewList.width - (viewList.QQC2.ScrollBar.vertical.visible ? viewList.QQC2.ScrollBar.vertical.width : 0)
            height: Kirigami.Units.gridUnit * 1.6
            radius: Kirigami.Units.cornerRadius
            color: current || dropArea.containsDrag ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, dropArea.containsDrag ? 0.35 : 0.18)
                 : hover.hovered ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)
                 : "transparent"
            border.width: activeFocus ? 1 : 0
            border.color: Kirigami.Theme.highlightColor
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.name
            Accessible.checked: current
            Accessible.onPressAction: choose()
            Keys.onReturnPressed: choose()
            Keys.onSpacePressed: choose()
            Keys.onMenuPressed: if (isProject) projectMenu.popup(row, 0, row.height)

            HoverHandler { id: hover }
            TapHandler { onTapped: row.choose() }
            // A chat dragged from the history (chat/SessionList.qml) moves here.
            DropArea {
                id: dropArea
                objectName: "projectDropArea"
                anchors.fill: parent
                enabled: row.isProject
                keys: ["kdeaichat-chat"]
                onDropped: function(drop) {
                    var sessionId = drop.source ? String(drop.source.sessionId || "") : "";
                    if (sessionId === "")
                        return;
                    sidebar.projects.moveChat(sessionId, row.modelData.view);
                    drop.accept();
                }
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                enabled: row.isProject
                onTapped: projectMenu.popup()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                anchors.rightMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    visible: row.isProject
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small * 0.75
                    Layout.preferredHeight: Layout.preferredWidth
                    Layout.leftMargin: Kirigami.Units.iconSizes.small * 0.125
                    Layout.rightMargin: Kirigami.Units.iconSizes.small * 0.125
                    radius: width / 2
                    color: row.modelData.color || "transparent"
                }
                Kirigami.Icon {
                    visible: !row.isProject
                    source: row.modelData.icon || ""
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                PC3.Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: row.modelData.name
                    textFormat: Text.PlainText
                    font.bold: row.current
                    elide: Text.ElideRight
                }
                PC3.Label {
                    objectName: "viewCount"
                    visible: !editButton.visible
                    text: row.count > 0 ? String(row.count) : ""
                    color: Kirigami.Theme.disabledTextColor
                    font: Kirigami.Theme.smallFont
                    Layout.minimumWidth: implicitWidth
                }
                PC3.ToolButton {
                    id: editButton
                    objectName: "editProjectButton"
                    visible: row.isProject && (hover.hovered || row.activeFocus || activeFocus)
                    Layout.preferredHeight: row.height
                    Layout.preferredWidth: row.height
                    icon.name: "document-edit"
                    display: PC3.AbstractButton.IconOnly
                    Accessible.name: i18n("Edit project")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: Accessible.name
                    onClicked: sidebar.projects.openEditor(row.modelData.view, "")
                }
            }

            QQC2.Menu {
                id: projectMenu
                QQC2.MenuItem {
                    text: i18n("Edit project…")
                    icon.name: "document-edit"
                    onTriggered: sidebar.projects.openEditor(row.modelData.view, "")
                }
                QQC2.MenuItem {
                    text: i18n("New chat in this project")
                    icon.name: "list-add"
                    onTriggered: {
                        row.choose();
                        sidebar.projects.newChat();
                    }
                }
                QQC2.MenuSeparator {}
                QQC2.MenuItem {
                    objectName: "deleteProjectItem"
                    text: i18n("Delete project (keeps its chats)")
                    icon.name: "edit-delete"
                    onTriggered: sidebar.projects.remove(row.modelData.view)
                }
                QQC2.MenuItem {
                    objectName: "deleteProjectWithChatsItem"
                    text: i18n("Delete project and its chats…")
                    icon.name: "edit-delete"
                    enabled: sidebar.projects.chatsIn(row.modelData.view).length > 0
                    onTriggered: sidebar.confirmDeleteWithChats(row.modelData.view)
                }
            }
        }
    }
}
