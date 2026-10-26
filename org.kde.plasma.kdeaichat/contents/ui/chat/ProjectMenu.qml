// "Move to project": a menu (or submenu) that puts a chat in one of the
// projects or in none. The chat's mode never changes (chat/Projects.qml).
// Used by the header's More menu and the history rows' menu.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.Menu {
    id: moveMenu

    // The widget root (main.qml) or a stand-in with `projects`.
    property var chat: null
    // The chat to move ("" = the open chat).
    property string sessionId: ""

    readonly property string _id: sessionId || (chat ? chat.currentSessionId : "")
    readonly property string _projectId: chat ? String(chat.getSessionProperty(_id, "projectId", "") || "") : ""

    title: i18n("Move to project")
    icon.name: "folder-move"

    QQC2.MenuItem {
        objectName: "noProjectItem"
        text: i18n("No project")
        checkable: true
        checked: moveMenu._projectId === ""
        onTriggered: moveMenu.chat.projects.moveChat(moveMenu._id, "")
    }

    QQC2.MenuSeparator {}

    Instantiator {
        model: moveMenu.chat ? moveMenu.chat.projects.list : []
        delegate: QQC2.MenuItem {
            required property var modelData
            objectName: "projectItem"
            text: modelData.name
            checkable: true
            checked: moveMenu._projectId === modelData.id
            onTriggered: moveMenu.chat.projects.moveChat(moveMenu._id, modelData.id)
        }
        onObjectAdded: function(index, object) { moveMenu.insertItem(index + 2, object); }
        onObjectRemoved: function(index, object) { moveMenu.removeItem(object); }
    }

    QQC2.MenuSeparator {}

    QQC2.MenuItem {
        objectName: "newProjectItem"
        text: i18n("New project…")
        icon.name: "list-add"
        // The new project gets this chat once it is saved.
        onTriggered: moveMenu.chat.projects.openEditor("", moveMenu._id)
    }
}
