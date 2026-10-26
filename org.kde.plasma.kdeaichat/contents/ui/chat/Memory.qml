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
// remember() saves a memory the user asked for (the Remember action under a
// message, /remember); `remembered` tells chat/UndoNotice.qml, whose Undo
// calls forget(). Only the user saves memories: nothing here suggests any.
//
// Deleting a chat or a project deletes the memories scoped to it. They are
// kept here until the widget closes, so Undo of the delete brings them back.
import QtQuick
import "MemoryRecall.js" as MemoryRecall

QtObject {
    id: memory

    property var chat: null
    readonly property var store: chat ? chat.memoryStore || null : null
    // Characters of memories per message, from the settings (0 = no limit).
    property int budget: chat && chat.plasmoid && chat.plasmoid.configuration.memoryBudget !== undefined
        ? chat.plasmoid.configuration.memoryBudget : MemoryRecall.DEFAULT_BUDGET

    // The helper's limit on a memory's text (kdeaichat/memory.py).
    readonly property int maxChars: 4000

    // A memory was saved (existed: the same one was there already, so there
    // is nothing to undo).
    signal remembered(string id, bool existed)
    // Saving failed (the helper's error, if any).
    signal rememberFailed(string error)

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

    // The text a memory is saved with: trimmed and cut to maxChars.
    function clip(text) {
        var t = String(text === undefined || text === null ? "" : text).trim();
        return t.length > maxChars ? t.substring(0, maxChars).trim() : t;
    }

    // The chat's project ({id, name, ...}) or null.
    function projectOf(sessionId) {
        var session = chat ? _session(sessionId) : null;
        return session && session.projectId && chat.projects ? chat.projects.byId(session.projectId) || null : null;
    }

    // Saves `text` for scope "all" | "project" | "chat" (of chat `sessionId`,
    // else the open one). A project scope without a project saves for every
    // chat. callback(ok, id, existed). Returns false when nothing is sent.
    function remember(text, scope, sessionId, callback) {
        var session = chat ? _session(sessionId) : null;
        var body = clip(text);
        if (!store || body === "") {
            if (callback) callback(false, "", false);
            return false;
        }
        var fields = {"text": body, "scope": "all", "sourceChatId": session ? session.value : ""};
        var project = projectOf(sessionId);
        if (scope === "chat" && session) {
            fields.scope = "chat";
            fields.chatId = session.value;
        } else if (scope === "project" && project) {
            fields.scope = "project";
            fields.projectId = project.id;
        }
        store.add(fields, function(ok, result) {
            var added = ok && result ? result.added || [] : [];
            var id = added[0] || (ok && result ? (result.existing || [])[0] || "" : "");
            var existed = added.length === 0;
            // Saved again on purpose: an old memory that was off is turned on.
            var old = existed && id ? store.byId(id) : null;
            if (old && old.enabled === false)
                store.setEnabled(id, true, null);
            if (id)
                memory.remembered(id, existed);
            else
                memory.rememberFailed(store.lastError);
            if (callback) callback(id !== "", id, existed);
        });
        return true;
    }

    // Removes a memory saved by remember() (Undo).
    function forget(id) {
        if (store && id)
            store.remove(id, null);
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
