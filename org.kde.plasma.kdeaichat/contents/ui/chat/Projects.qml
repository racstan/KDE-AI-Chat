// Projects: the list (stored by store/ChatStore.qml in projects.ini), which
// view the history shows (all chats, one project or the archived ones), and
// the actions on them: create, edit, delete (with Undo), move a chat into a
// project, start a chat in one. The rules for what a project gives its chats
// are in chat/Projects.js. `chat` is the widget root (main.qml) or a stand-in.
import QtQuick
import "Projects.js" as ProjectsJs

QtObject {
    id: projects

    property var chat: null
    property var list: []
    // "all", "archived" or a project id.
    property string view: "all"

    // The chats the history shows for `view`, and how many each view has.
    readonly property var visibleChats: ProjectsJs.filterChats(chat ? chat.sessions : [], view)
    readonly property var counts: ProjectsJs.counts(chat ? chat.sessions : [])
    // The project shown, or null (All chats, Archived).
    readonly property var viewProject: ProjectsJs.byId(list, view)

    readonly property var colors: ProjectsJs.COLORS

    // A project was deleted: what Undo needs (chat/UndoNotice.qml).
    // movedChatIds: its chats that stayed (now in no project). deletedChats:
    // with removeWithChats(), the chats deleted with it, [{session, index,
    // wasCurrent}] in the order deleted; fillerChatId: the empty chat made
    // because none would have been left ("" = none).
    signal projectDeleted(var project, int index, var movedChatIds, var deletedChats, string fillerChatId)
    // The project editor (chat/ProjectEditor.qml, in chat/ChatBody.qml) should
    // open: projectId "" = a new project; moveChatId: a chat to put in it once saved.
    signal editorRequested(string projectId, string moveChatId)

    function openEditor(projectId, moveChatId) {
        editorRequested(projectId || "", moveChatId || "");
    }

    function load() {
        var store = chat ? chat.chatStore : null;
        list = ProjectsJs.normalize(store && store.loadProjects ? store.loadProjects() : "");
        if (view !== "all" && view !== "archived" && !byId(view))
            view = "all";
    }

    function persist() {
        var store = chat ? chat.chatStore : null;
        if (store && store.saveProjects)
            store.saveProjects(list);
    }

    function byId(id) {
        return ProjectsJs.byId(list, id);
    }

    function _session(sessionId) {
        var idx = chat.sessionIndexById(sessionId || chat.currentSessionId);
        return idx < 0 ? null : chat.sessions[idx];
    }

    // The project of a chat (the open one by default), or null.
    function ofChat(sessionId) {
        return ProjectsJs.ofChat(list, _session(sessionId));
    }

    // The folder the chat runs in: {path, from: "chat" | "project" | ""}.
    function workspaceFor(sessionId) {
        var session = _session(sessionId);
        return ProjectsJs.workspaceFor(session, ProjectsJs.ofChat(list, session));
    }

    // The project's instructions block for the chat's system prompt ("" = none).
    function instructionsBlock(sessionId) {
        return ProjectsJs.instructionsBlock(ofChat(sessionId));
    }

    // Everything an agent (Pi) is told for this chat: the project's, then the chat's own.
    function instructionsFor(sessionId) {
        var session = _session(sessionId);
        return ProjectsJs.instructionsFor(session, ProjectsJs.ofChat(list, session));
    }

    // fields: {name, color, instructions, folder, provider, model}. Returns the new id.
    function create(fields) {
        var p = ProjectsJs.normalizeOne(Object.assign({}, fields || {}, {"id": ProjectsJs.makeId(), "createdAt": Date.now()}));
        list = list.concat([p]);
        persist();
        return p.id;
    }

    function update(id, fields) {
        var updated = list.slice();
        for (var i = 0; i < updated.length; i++) {
            if (updated[i].id === id) {
                updated[i] = ProjectsJs.normalizeOne(Object.assign({}, updated[i], fields || {}, {"id": id}));
                list = updated;
                persist();
                _reapplyOpenChat();
                return true;
            }
        }
        return false;
    }

    // The chats in project `id`, archived ones too.
    function chatsIn(id) {
        var all = chat ? chat.sessions || [] : [];
        return all.filter(function(s) { return !!s && String(s.projectId || "") === String(id || ""); });
    }

    // Deletes the project; its chats stay and move to no project.
    function remove(id) {
        _remove(id, [], "");
    }

    // Deletes the project and its chats. Each chat goes the way a single
    // chat is deleted (chat.deleteSession: a reply being written into it is
    // stopped; its schedules, memories and images go too), the open one last.
    // There is always one chat, so when the project has all of them a new
    // empty chat is made first. Undo (chat/UndoNotice.qml) brings back the
    // project and its chats, not their scheduled messages.
    function removeWithChats(id) {
        if (!byId(id))
            return;
        var open = chat.currentSessionId;
        var ids = chatsIn(id).map(function(s) { return s.value; });
        ids.sort(function(a, b) { return (a === open) - (b === open); });
        var filler = "";
        if (ids.length > 0 && ids.length >= chat.sessions.length) {
            var before = chat.sessions.map(function(s) { return s.value; });
            chat.createSession(false, "");
            var made = chat.sessions.filter(function(s) { return before.indexOf(s.value) < 0; });
            filler = made.length > 0 ? made[0].value : "";
        }
        var deleted = [];
        for (var i = 0; i < ids.length; i++) {
            var index = chat.sessionIndexById(ids[i]);
            if (index < 0)
                continue;
            var session = chat.sessions[index];
            chat.deleteSession(ids[i]);
            if (chat.sessionIndexById(ids[i]) < 0)
                deleted.push({"session": session, "index": index, "wasCurrent": ids[i] === open});
        }
        _remove(id, deleted, filler);
    }

    // Any chat still in the project (one that could not be deleted) stays, in no project.
    function _remove(id, deleted, filler) {
        var index = -1;
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id)
                index = i;
        }
        if (index < 0)
            return;
        var project = list[index];
        var rest = list.slice();
        rest.splice(index, 1);
        var released = ProjectsJs.releaseChats(chat.sessions, id);
        list = rest;
        if (view === id)
            view = "all";
        persist();
        if (released.moved.length > 0) {
            chat.sessions = released.chats;
            chat.persistSessions();
        }
        _reapplyOpenChat();
        projectDeleted(project, index, released.moved, deleted, filler);
    }

    // Undo of remove(): the project comes back with the chats it had.
    function restore(project, index, movedChatIds) {
        if (!project || byId(project.id))
            return;
        var updated = list.slice();
        updated.splice(Math.min(Math.max(index, 0), updated.length), 0, project);
        list = updated;
        persist();
        if (movedChatIds && movedChatIds.length > 0) {
            chat.sessions = ProjectsJs.returnChats(chat.sessions, project.id, movedChatIds);
            chat.persistSessions();
        }
        _reapplyOpenChat();
    }

    // Puts a chat in a project ("" = none). Its mode never changes. An agent
    // chat (OpenCode, Pi) that already has history and no folder of its own
    // keeps working where it did (keepOwnFolder) instead of moving to the
    // project's folder, where its agent session would not be found.
    function moveChat(sessionId, projectId) {
        var session = _session(sessionId);
        if (!session || (projectId && !byId(projectId)) || String(session.projectId || "") === String(projectId || ""))
            return;
        var change = {"projectId": String(projectId || "")};
        var messages = session.value === chat.currentSessionId ? chat.messages : session.messages;
        var agentWithHistory = (session.source === "opencode" || session.source === "pi")
            && (messages || []).length > 0 && String(session.openCodeWorkspaceCwd || "").trim() === "";
        if (agentWithHistory && session.keepOwnFolder === undefined)
            change.keepOwnFolder = true;
        chat.setSessionOverrides(session.value, change);
    }

    // A new chat in the project shown (or in none), and the history shows it.
    function newChat() {
        var projectId = viewProject ? viewProject.id : "";
        if (view === "archived")
            view = "all";
        chat.createSession(true, projectId);
    }

    function _reapplyOpenChat() {
        if (chat && typeof chat.applySessionSource === "function")
            chat.applySessionSource(_session(chat.currentSessionId));
    }
}
