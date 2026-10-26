// A short-lived "Undo" notice after clearing a chat, deleting one, deleting a
// project, or saving a memory (chat/Memory.qml's remembered; Undo removes it).
//
// Clearing is seen as the messages of the open chat becoming empty (whoever
// does it); deleting is the widget's `sessionDeleted` signal. The notice
// stays for `timeout` ms, then the undo is gone. Undoing a delete brings the
// chat back with its messages (not its scheduled messages, which are removed
// with the chat).
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Rectangle {
    id: notice

    property var chat: null
    property int timeout: 8000

    // What can be undone: {kind: "clear", messages, count} or
    // {kind: "delete", session, index, wasCurrent} or
    // {kind: "project", project, index, moved, chats, filler} (a deleted
    // project; chats: those deleted with it, see chat/Projects.qml) or
    // {kind: "restore", sessionId, messages} (after regenerating) or
    // {kind: "memory", id} (a saved memory) or {kind: "info"} (nothing to undo).
    property var undoable: null
    property string text: ""

    // The open chat and its messages as last seen, to notice it being emptied.
    property string trackedSession: ""
    property var trackedMessages: []

    function show(what, message) {
        undoable = what;
        text = message;
        timer.restart();
    }

    function dismiss() {
        timer.stop();
        undoable = null;
        text = "";
    }

    function undo() {
        var what = undoable;
        var list = [];
        dismiss();
        if (!what || !chat)
            return;
        if (what.kind === "memory") {
            chat.memory.forget(what.id);
        } else if (what.kind === "info") {
            return;
        } else if (what.kind === "restore") {
            // Regenerate: stop the new answer and bring the old messages back.
            if (chat.currentSessionId === what.sessionId) {
                chat.stopStreaming();
                chat.messages = what.messages;
                if (chat.clearCurrentOpenCodeSessionIfNeeded)
                    chat.clearCurrentOpenCodeSessionIfNeeded();
                chat.saveCurrentSessionState(true);
            }
        } else if (what.kind === "clear") {
            // Only into the same chat, and only if it is still empty.
            if (chat.currentSessionId === what.sessionId && (chat.messages || []).length === 0) {
                chat.messages = what.messages;
                chat.saveCurrentSessionState(true);
            }
        } else if (what.kind === "project") {
            chat.projects.restore(what.project, what.index, what.moved);
            notice._restoreChats(what.chats || [], what.filler || "");
        } else {
            list = (chat.sessions || []).slice();
            list.splice(Math.min(what.index, list.length), 0, what.session);
            chat.sessions = list;
            chat.persistSessions();
            if (what.wasCurrent)
                chat.switchSession(what.session.value);
        }
    }

    // Puts back chats deleted one after another (the last deleted first, each
    // at its index), reopens the one that was open, and drops the empty chat
    // made in their place if it is still empty.
    function _restoreChats(chats, filler) {
        if (chats.length === 0)
            return;
        var list = (chat.sessions || []).slice();
        var reopen = "";
        for (var i = chats.length - 1; i >= 0; i--) {
            list.splice(Math.min(chats[i].index, list.length), 0, chats[i].session);
            if (chats[i].wasCurrent)
                reopen = chats[i].session.value;
        }
        chat.sessions = list;
        if (reopen !== "")
            chat.switchSession(reopen);
        var at = filler !== "" && chat.currentSessionId !== filler ? chat.sessionIndexById(filler) : -1;
        if (at >= 0 && (chat.sessions[at].messages || []).length === 0) {
            list = chat.sessions.slice();
            list.splice(at, 1);
            chat.sessions = list;
        }
        chat.persistSessions();
    }

    visible: undoable !== null
    implicitWidth: row.implicitWidth + Kirigami.Units.largeSpacing * 2
    implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.cornerRadius
    color: Kirigami.Theme.backgroundColor
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)

    Timer {
        id: timer
        interval: notice.timeout
        onTriggered: notice.dismiss()
    }

    Connections {
        target: notice.chat
        function onSessionDeleted(session, index) {
            notice.show({"kind": "delete", "session": session, "index": index, "wasCurrent": notice.chat.currentSessionId === session.value},
                        i18n("Chat “%1” deleted", session.text || i18n("New Chat")));
        }
        function onMessagesDropped(sessionId, messages) {
            var dropped = messages.length - (notice.chat.messages || []).length;
            notice.show({"kind": "restore", "sessionId": sessionId, "messages": messages},
                        i18np("%1 message removed", "%1 messages removed", dropped));
        }
        function onMessagesChanged() {
            var now = notice.chat.messages || [];
            var count = notice.trackedMessages.length;
            if (notice.chat.currentSessionId === notice.trackedSession && now.length === 0 && notice.trackedMessages.length > 0) {
                notice.show({"kind": "clear", "sessionId": notice.trackedSession, "messages": notice.trackedMessages},
                            count === 1 ? i18n("Message deleted") : i18n("Chat cleared"));
            }
            notice.trackedSession = notice.chat.currentSessionId;
            notice.trackedMessages = now;
        }
    }

    Connections {
        target: notice.chat ? notice.chat.memory || null : null
        function onRemembered(id, existed) {
            notice.show(existed ? {"kind": "info"} : {"kind": "memory", "id": id},
                        existed ? i18n("Already in memory") : i18n("Saved to memory"));
        }
        function onRememberFailed(error) {
            notice.show({"kind": "info"}, i18n("Could not save the memory."));
        }
    }

    // A deleted project, with its chats kept (in no project) or deleted; Undo puts it all back.
    Connections {
        target: notice.chat ? notice.chat.projects || null : null
        function onProjectDeleted(project, index, movedChatIds, deletedChats, fillerChatId) {
            var chats = deletedChats || [];
            notice.show({"kind": "project", "project": project, "index": index, "moved": movedChatIds, "chats": chats, "filler": fillerChatId || ""},
                        chats.length > 0 ? i18np("Project “%2” and its chat deleted", "Project “%2” and its %1 chats deleted", chats.length, project.name)
                                         : i18n("Project “%1” deleted; its chats were kept", project.name));
        }
    }

    Component.onCompleted: {
        if (chat) {
            trackedSession = chat.currentSessionId;
            trackedMessages = chat.messages || [];
        }
    }

    // The text wraps when the notice is narrower than it (its parent caps
    // the width); the buttons always keep their room.
    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            objectName: "undoText"
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            text: notice.text
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }

        PC3.Button {
            objectName: "undoButton"
            visible: !!notice.undoable && notice.undoable.kind !== "info"
            text: i18n("Undo")
            icon.name: "edit-undo"
            onClicked: notice.undo()
        }

        PC3.ToolButton {
            objectName: "undoDismiss"
            icon.name: "dialog-close"
            display: PC3.AbstractButton.IconOnly
            Accessible.name: i18n("Dismiss")
            onClicked: notice.dismiss()
        }
    }
}
