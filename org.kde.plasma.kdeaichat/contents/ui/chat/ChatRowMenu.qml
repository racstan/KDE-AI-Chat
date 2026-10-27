// The menu of one chat in the history (chat/SessionList.qml): right-click or
// the Menu key on a row. Rename, move to a project, archive or restore, delete.
import QtQuick
import QtQuick.Controls as QQC2

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.Menu {
    id: chatMenu

    property var chat: null
    // Delete was chosen (the history asks first when Settings → Chat says so).
    signal deleteRequested(var session)
    property var session: ({})
    readonly property bool archived: session.archived === true

    function openFor(session, item) {
        chatMenu.session = session;
        moveMenu.sessionId = session.value;
        chatMenu.popup(item, 0, item.height);
    }

    QQC2.MenuItem {
        text: i18n("Rename chat")
        icon.name: "document-edit"
        onTriggered: chatMenu.chat.startSessionRename(chatMenu.session.value)
    }
    ProjectMenu {
        id: moveMenu
        chat: chatMenu.chat
    }
    QQC2.MenuItem {
        objectName: "archiveItem"
        text: chatMenu.archived ? i18n("Restore chat") : i18n("Archive chat")
        icon.name: chatMenu.archived ? "document-revert" : "archive-insert"
        onTriggered: chatMenu.chat.setSessionArchived(chatMenu.session.value, !chatMenu.archived)
    }
    QQC2.MenuSeparator {}
    QQC2.MenuItem {
        text: i18n("Delete chat")
        icon.name: "trash-empty"
        onTriggered: chatMenu.deleteRequested(chatMenu.session)
    }
}
