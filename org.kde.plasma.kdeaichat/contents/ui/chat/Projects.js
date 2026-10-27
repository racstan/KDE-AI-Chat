.pragma library

// Projects: named groups of chats with shared settings. Plain JavaScript on
// purpose (tested with node): no QML globals.
//
// A project is {id, name, color, instructions, folder, provider, model,
// createdAt}. A chat belongs to no project (projectId "" or missing) or to one
// (projectId = the project's id). Projects are stored next to the chats
// (store/ChatStore.qml, projects.ini); chats saved before projects existed
// have no projectId and load unchanged, in no project.
//
// What a project gives its chats follows the usual order, the chat's own
// settings first, then the project, then the main settings:
//   instructions  sent after the main instructions and before the chat's own
//                 (instructionsFor below); every mode.
//   folder        the working folder when the chat has none of its own
//                 (workspaceFor below); OpenCode and Pi run in it.
//   provider and model  stand in for the main settings' provider and model in
//                 direct chats (chat/EffectiveConfig.js).
// A project never changes a chat's mode (direct, OpenCode or Pi).

// The colours offered for a project (the first is the default).
var COLORS = ["#3daee9", "#1cdc9a", "#c9ce3b", "#f67400", "#da4453", "#8e44ad", "#7f8c8d", "#e91e63"];

var MAX_NAME = 80;
var MAX_INSTRUCTIONS = 20000;

function _s(value) {
    return value === undefined || value === null ? "" : String(value);
}

function _validId(id) {
    return /^p-[A-Za-z0-9_-]{1,64}$/.test(_s(id));
}

function makeId(now, random) {
    var n = now === undefined ? Date.now() : now;
    var r = random === undefined ? Math.floor(Math.random() * 100000) : random;
    return "p-" + n + "-" + r;
}

function _color(value) {
    var c = _s(value).trim();
    return /^#[0-9a-fA-F]{6}$/.test(c) ? c.toLowerCase() : COLORS[0];
}

// One project with every field present and of the right type, or null when
// it has no valid id. Unknown fields are dropped.
function normalizeOne(raw) {
    if (!raw || typeof raw !== "object" || !_validId(raw.id))
        return null;
    var name = _s(raw.name).replace(/\s+/g, " ").trim().substring(0, MAX_NAME);
    var provider = _s(raw.provider).trim();
    return {
        "id": _s(raw.id),
        "name": name || "Project",
        "color": _color(raw.color),
        "instructions": _s(raw.instructions).substring(0, MAX_INSTRUCTIONS),
        "folder": _s(raw.folder).trim(),
        "provider": provider,
        // A model only means something with the provider it was chosen for.
        "model": provider ? _s(raw.model).trim() : "",
        "createdAt": Number(raw.createdAt) > 0 ? Number(raw.createdAt) : 0
    };
}

// The stored list (an array, or its JSON) as clean projects, without duplicates.
function normalize(stored) {
    var list = stored;
    if (typeof stored === "string") {
        try {
            list = stored.trim() ? JSON.parse(stored) : [];
        } catch (e) {
            return [];
        }
    }
    if (!Array.isArray(list))
        return [];
    var seen = {};
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var p = normalizeOne(list[i]);
        if (p && !seen[p.id]) {
            seen[p.id] = true;
            out.push(p);
        }
    }
    return out;
}

function byId(projects, id) {
    if (!id || !Array.isArray(projects))
        return null;
    for (var i = 0; i < projects.length; i++) {
        if (projects[i] && projects[i].id === id)
            return projects[i];
    }
    return null;
}

// The project a chat belongs to, or null (none, or its project was deleted).
function ofChat(projects, chat) {
    return chat ? byId(projects, _s(chat.projectId)) : null;
}

// The views of the history: "all" (every chat that isn't archived),
// "archived", or a project id (that project's chats that aren't archived).
// An incognito chat (chat/Incognito.qml) is in none of them.
function inView(chat, view) {
    if (!chat || chat.incognito === true)
        return false;
    if (view === "archived")
        return chat.archived === true;
    if (chat.archived === true)
        return false;
    if (!view || view === "all")
        return true;
    return _s(chat.projectId) === view;
}

function filterChats(chats, view) {
    var out = [];
    for (var i = 0; i < (chats || []).length; i++) {
        if (inView(chats[i], view))
            out.push(chats[i]);
    }
    return out;
}

// How many chats each view has: {all, archived, <projectId>: n}.
function counts(chats) {
    var c = {"all": 0, "archived": 0};
    for (var i = 0; i < (chats || []).length; i++) {
        var chat = chats[i];
        if (!chat || chat.incognito === true)
            continue;
        if (chat.archived === true) {
            c.archived++;
            continue;
        }
        c.all++;
        var pid = _s(chat.projectId);
        if (pid)
            c[pid] = (c[pid] || 0) + 1;
    }
    return c;
}

// The working folder a chat runs in: {path, from: "chat" | "project" | ""}.
// The chat's own folder wins; a chat that keeps its own (empty) folder
// (keepOwnFolder, see Projects.qml moveChat) ignores the project's.
function workspaceFor(chat, project) {
    var own = chat ? _s(chat.openCodeWorkspaceCwd).trim() : "";
    if (own)
        return {"path": own, "from": "chat"};
    if (project && !(chat && chat.keepOwnFolder === true) && _s(project.folder).trim())
        return {"path": _s(project.folder).trim(), "from": "project"};
    return {"path": "", "from": ""};
}

// The project's instructions as a block for the system prompt, or "".
function instructionsBlock(project) {
    var text = project ? _s(project.instructions).trim() : "";
    if (!text)
        return "";
    return "--- Project instructions (" + project.name + ") ---\n" + text + "\n--- End project instructions ---";
}

// The instructions an agent (Pi) gets for a chat: the project's, then the
// chat's own when they are switched on.
function instructionsFor(chat, project) {
    var parts = [];
    var block = instructionsBlock(project);
    if (block)
        parts.push(block);
    var own = chat ? _s(chat.chatSystemPrompt).trim() : "";
    if (own && chat.chatSystemPromptEnabled !== false)
        parts.push("--- Chat-specific instructions ---\n" + own + "\n--- End chat-specific instructions ---");
    return parts.join("\n\n");
}

// The chats after deleting project `id`: its chats move to no project.
// Returns {chats, moved: [chat ids]}.
function releaseChats(chats, id) {
    var moved = [];
    var out = [];
    for (var i = 0; i < (chats || []).length; i++) {
        var chat = chats[i];
        if (chat && _s(chat.projectId) === id) {
            var copy = Object.assign({}, chat);
            copy.projectId = "";
            out.push(copy);
            moved.push(chat.value);
        } else {
            out.push(chat);
        }
    }
    return {"chats": out, "moved": moved};
}

// The chats after an Undo of a project deletion: these chats go back in.
function returnChats(chats, id, chatIds) {
    var wanted = {};
    for (var i = 0; i < (chatIds || []).length; i++)
        wanted[chatIds[i]] = true;
    return (chats || []).map(function(chat) {
        if (!chat || !wanted[chat.value] || _s(chat.projectId) !== "")
            return chat;
        var copy = Object.assign({}, chat);
        copy.projectId = id;
        return copy;
    });
}
