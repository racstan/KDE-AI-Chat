// Scheduled runs (kdeaichat/schedule_exec.py) happen without the widget: the
// job appends the prompt and reply to the chat file and leaves a copy in
// <chat folder>/inbox/run-*.ini. This watches that folder with a
// FolderListModel (a file-system watcher: nothing runs or polls while no
// schedule fires), merges each run into its chat by run id (merging twice is
// harmless), saves, shows "<name> is ready" (click opens the chat), and once
// the chats are saved removes the inbox files through the helper.
// The open chat is never switched; a run for the open chat waits until a reply
// that is streaming in has finished. On start it also runs `schedules_startup`
// (old scheduler removed, timers in sync). `chat` is the widget root (main.qml).
import QtQuick
import QtCore
import Qt.labs.folderlistmodel

Item {
    id: inbox
    visible: false

    property var chat: null
    property var notifierRef: null      // chat/Notifier.qml
    // The chat folder (store/ChatStore.qml directory) and its readiness.
    property string directory: ""
    property bool ready: false
    // runHelper(command, payload, onDone) and the chat store (saved signal, flush()).
    property var runHelper: null
    property var chatStore: null

    // File name -> true once merged (and notified); removed after the next save.
    property var _merged: ({})
    property var _toRemove: []

    readonly property bool _canMerge: inbox.ready && !!inbox.chat && inbox.chat._initialLoadDone === true

    FolderListModel {
        id: files
        folder: inbox.ready && inbox.directory !== "" ? "file://" + inbox.directory + "/inbox" : ""
        nameFilters: ["run-*.ini"]
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
        onCountChanged: inbox.scan()
        onStatusChanged: inbox.scan()
    }

    Component {
        id: fileComponent
        Settings {}
    }

    function _read(name) {
        var file = fileComponent.createObject(null, {"location": "file://" + inbox.directory + "/inbox/" + name});
        var raw = String(file.value("entry", "") || "");
        file.destroy();
        try {
            var entry = JSON.parse(raw);
            return entry && typeof entry === "object" && Array.isArray(entry.messages) ? entry : null;
        } catch (e) {
            return null;
        }
    }

    // A chat whose messages were not read: the job already appended the run to its file (the widget
    // never writes such a chat), so only the list entry is updated. Returns "added" or "present".
    function mergeUnloaded(idx, session, entry) {
        var count = entry.messages.filter(function(m) { return m && typeof m === "object" && (m.role === "user" || m.role === "assistant"); }).length;
        var newSessionId = String((entry.sessionUpdates || {}).openCodeSessionId || "");
        if (count === 0 && (!newSessionId || session.openCodeSessionId))
            return "present";
        if (count > 0) {
            session.messageCount = (session.messageCount || 0) + count;
            session.updatedAt = Date.now();
        }
        if (newSessionId && !session.openCodeSessionId)
            session.openCodeSessionId = newSessionId;
        var updated = chat.sessions.slice();
        updated[idx] = session;
        chat.sessions = updated;
        return count > 0 ? "added" : "present";
    }

    // Merges one run into its chat. Returns "added", "present", "gone" or "later".
    function merge(entry) {
        var idx = chat.sessionIndexById(String(entry.chatId || ""));
        if (idx < 0)
            return "gone";
        var session = Object.assign({}, chat.sessions[idx]);
        if (session.messagesUnloaded)
            return mergeUnloaded(idx, session, entry);
        var isOpen = session.value === chat.currentSessionId;
        if (isOpen && chat.loading)
            return "later";
        var current = isOpen ? chat.messages : (session.messages || []);
        var present = current.some(function(m) { return m && m.scheduleRunId === entry.runId; });
        var add = present ? [] : entry.messages.filter(function(m) { return m && typeof m === "object" && (m.role === "user" || m.role === "assistant"); });
        var updates = entry.sessionUpdates || {};
        var newSessionId = String(updates.openCodeSessionId || "");
        if (add.length === 0 && (!newSessionId || session.openCodeSessionId))
            return "present";
        if (add.length > 0) {
            var messages = current.concat(add);
            session.messages = messages;
            session.updatedAt = Date.now();
            if (isOpen)
                chat.messages = messages;
        }
        if (newSessionId && !session.openCodeSessionId)
            session.openCodeSessionId = newSessionId;
        var updated = chat.sessions.slice();
        updated[idx] = session;
        chat.sessions = updated;
        return add.length > 0 ? "added" : "present";
    }

    function scan() {
        if (!inbox._canMerge || files.status !== FolderListModel.Ready)
            return;
        var changed = false;
        var merged = Object.assign({}, inbox._merged);
        for (var i = 0; i < files.count; i++) {
            var name = String(files.get(i, "fileName"));
            if (merged[name])
                continue;
            var entry = inbox._read(name);
            var result = entry ? inbox.merge(entry) : "gone";
            if (result === "later")
                continue;
            merged[name] = true;
            inbox._toRemove = inbox._toRemove.concat([name]);
            if (result === "added") {
                changed = true;
                var reply = entry.messages[entry.messages.length - 1] || {};
                if (entry.notify === true && entry.notified !== true && inbox.notifierRef)
                    inbox.notifierRef.scheduledRan(String(entry.chatId), String(entry.scheduleName || ""), String(reply.content || ""));
            }
        }
        inbox._merged = merged;
        if (changed) {
            chat.persistSessions();
            if (inbox.chatStore)
                inbox.chatStore.flush();
        } else {
            inbox._removeMerged();
        }
    }

    // The inbox files whose runs are now in the saved chats.
    function _removeMerged() {
        if (inbox._toRemove.length === 0 || !inbox.runHelper)
            return;
        var names = inbox._toRemove;
        inbox._toRemove = [];
        inbox.runHelper("schedule_inbox_done", {"directory": inbox.directory, "files": names}, function() {
            var merged = Object.assign({}, inbox._merged);
            for (var i = 0; i < names.length; i++)
                delete merged[names[i]];
            inbox._merged = merged;
        });
    }

    Connections {
        target: inbox.chatStore
        ignoreUnknownSignals: true
        function onSaved() { inbox._removeMerged(); }
    }

    Connections {
        target: inbox.chat
        ignoreUnknownSignals: true
        function onLoadingChanged() { if (!inbox.chat.loading) inbox.scan(); }
    }

    on_CanMergeChanged: scan()

    onReadyChanged: {
        if (inbox.ready && inbox.runHelper)
            inbox.runHelper("schedules_startup", {}, null);
    }
}
