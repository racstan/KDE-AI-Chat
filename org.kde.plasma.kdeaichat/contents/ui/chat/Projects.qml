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
    signal projectDeleted(var project, int index, var movedChatIds)
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

    // Deletes the project; its chats stay and move to no project.
    function remove(id) {
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
        projectDeleted(project, index, released.moved);
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
