// Memories in chats: which ones go with a request (chat/MemoryRecall.js) and
// keeping the list tidy when chats and projects go. The memories themselves
// are store/MemoryStore.qml (chat.memoryStore). `chat` is the widget root
// (main.qml) or a stand-in.
//
// A request gets nothing when memory is off in the settings (memoryEnabled)
// or for the chat (its session property memoryOff is true). Otherwise the
// chosen memories go into the system prompt (direct, OpenCode) or Pi's
// instructions as one block, and their ids are kept on the chat as the
// session property memoryUsedIds (the memories of its latest request), for
// Chat info to show.
//
// Deleting a chat or a project deletes the memories scoped to it. They are
// kept here until the widget closes, so Undo of the delete brings them back.
import QtQuick
import "MemoryRecall.js" as MemoryRecall

QtObject {
    id: memory

    property var chat: null
    readonly property var store: chat ? chat.memoryStore || null : null
    property int budget: MemoryRecall.DEFAULT_BUDGET

    // Memories removed with a chat or project: {"chat:<id>" | "project:<id>": [memories]}.
    property var _removed: ({})

    function _session(sessionId) {
        var idx = chat.sessionIndexById(sessionId || chat.currentSessionId);
        return idx < 0 ? null : chat.sessions[idx];
    }

    function _messages(sessionId) {
        if (!sessionId || sessionId === chat.currentSessionId)
            return chat.messages || [];
        var session = _session(sessionId);
        return session ? session.messages || [] : [];
    }

    // Whether memories go with this chat's requests at all.
    function activeFor(sessionId) {
        if (!store || !store.enabled)
            return false;
        var session = _session(sessionId);
        return !!session && session.memoryOff !== true;
    }

    // The memories this chat may use (enabled; every chat, its project, itself).
    function applicableFor(sessionId) {
        var session = _session(sessionId);
        if (!store || !session)
            return [];
        return MemoryRecall.applicable(store.list, {"id": session.value, "projectId": session.projectId || ""});
    }

    // What a request is sent with: {block, ids}. Records the ids on the chat
    // (memoryUsedIds) when they changed.
    function forRequest(sessionId) {
        var id = sessionId || (chat ? chat.currentSessionId : "");
        var chosen = activeFor(id)
            ? MemoryRecall.recall(applicableFor(id), MemoryRecall.queryFor(_messages(id)), budget)
            : {"block": "", "ids": []};
        var previous = chat && _session(id) ? chat.getSessionProperty(id, "memoryUsedIds", []) : [];
        if (_session(id) && JSON.stringify(previous || []) !== JSON.stringify(chosen.ids))
            chat.setSessionProperty(id, "memoryUsedIds", chosen.ids);
        return chosen;
    }

    // The prompt block for a request ("" = none); see forRequest.
    function blockFor(sessionId) {
        return forRequest(sessionId).block;
    }

    function _forget(kind, id) {
        if (!store || !id)
            return;
        store.removeScoped(kind === "chat" ? [id] : [], kind === "project" ? [id] : [], function(ok, result) {
            var deleted = ok && result ? result.deleted || [] : [];
            if (deleted.length > 0) {
                var removed = Object.assign({}, memory._removed);
                removed[kind + ":" + id] = deleted;
                memory._removed = removed;
                memory._restoreReturned();  // Undo may have been quicker than the helper
            }
        });
    }

    // A chat or project that came back (Undo) gets its memories back.
    function _restoreReturned() {
        var keys = Object.keys(_removed);
        if (keys.length === 0 || !store)
            return;
        var remaining = Object.assign({}, _removed);
        var back = [];
        for (var i = 0; i < keys.length; i++) {
            var kind = keys[i].substring(0, keys[i].indexOf(":"));
            var id = keys[i].substring(kind.length + 1);
            var present = kind === "chat" ? chat.sessionIndexById(id) >= 0 : !!(chat.projects && chat.projects.byId(id));
            if (present) {
                back = back.concat(remaining[keys[i]]);
                delete remaining[keys[i]];
            }
        }
        if (back.length > 0) {
            _removed = remaining;
            store.restore(back, null);
        }
    }

    readonly property Connections _chatEvents: Connections {
        target: memory.chat
        function onSessionDeleted(session, index) { memory._forget("chat", session ? session.value : ""); }
        function onSessionsChanged() { memory._restoreReturned(); }
    }

    readonly property Connections _projectEvents: Connections {
        target: memory.chat ? memory.chat.projects || null : null
        function onProjectDeleted(project, index, movedChatIds) { memory._forget("project", project ? project.id : ""); }
        function onListChanged() { memory._restoreReturned(); }
    }
}
