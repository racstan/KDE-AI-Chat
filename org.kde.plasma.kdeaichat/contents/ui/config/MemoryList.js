.pragma library

// The memory list of Settings → Memory (ConfigMemory.qml): which memories
// show for a search and a filter, and in what order. Plain functions, so
// tests run them in node.

// Filters: "any" (every memory), "all" (for every chat), "project", "chat",
// "off" (turned off).
var FILTERS = ["any", "all", "project", "chat", "off"];

function matchesFilter(memory, filter) {
    if (filter === "off")
        return memory.enabled === false;
    if (filter === "all" || filter === "project" || filter === "chat")
        return (memory.scope || "all") === filter;
    return true;
}

// `names(memory)` gives extra text to search (the chat or project name).
function matchesQuery(memory, query, names) {
    var q = String(query || "").trim().toLowerCase();
    if (q === "")
        return true;
    var text = String(memory.text || "") + " " + (names ? names(memory) : "");
    return text.toLowerCase().indexOf(q) >= 0;
}

// Pinned first, then the newest.
function sorted(list) {
    return (list || []).slice().sort(function(a, b) {
        if ((a.pinned === true) !== (b.pinned === true))
            return a.pinned === true ? -1 : 1;
        return (Number(b.created) || 0) - (Number(a.created) || 0);
    });
}

function visible(list, query, filter, names) {
    return sorted((list || []).filter(function(m) {
        return m && matchesFilter(m, filter) && matchesQuery(m, query, names);
    }));
}

function disabledIds(list) {
    return (list || []).filter(function(m) { return m && m.enabled === false; }).map(function(m) { return m.id; });
}

// {chatId: title} from the chats index (a JSON list of {value, text}).
function chatTitles(indexJson) {
    var result = {};
    try {
        var list = JSON.parse(indexJson || "[]");
        for (var i = 0; Array.isArray(list) && i < list.length; i++) {
            if (list[i] && list[i].value)
                result[list[i].value] = String(list[i].text || "");
        }
    } catch (e) {
        return {};
    }
    return result;
}

// {projectId: name} from projects.ini's JSON list of {id, name}.
function projectNames(projectsJson) {
    var result = {};
    try {
        var list = JSON.parse(projectsJson || "[]");
        for (var i = 0; Array.isArray(list) && i < list.length; i++) {
            if (list[i] && list[i].id)
                result[list[i].id] = String(list[i].name || "");
        }
    } catch (e) {
        return {};
    }
    return result;
}
