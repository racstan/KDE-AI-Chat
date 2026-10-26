// The helper's memory commands (kdeaichat/memory.py), in memory, for the
// tests of the memory UI. run() has HelperRunner's signature and answers
// asynchronously, like the real helper. fail: every command fails.
import QtQuick

QtObject {
    id: helper

    property var memories: []
    property var calls: []
    property int counter: 0
    property bool fail: false

    function reset() {
        memories = [];
        calls = [];
        counter = 0;
        fail = false;
    }

    function key(m) {
        return [String(m.text).split(/\s+/).join(" ").trim().toLowerCase(), m.scope || "all", m.projectId || "", m.chatId || ""].join("|");
    }

    function run(command, payload, onDone) {
        calls = calls.concat([{command: command, payload: payload}]);
        if (fail) {
            Qt.callLater(function() { onDone("Error executing " + command, 1, ""); });
            return;
        }
        var list = memories.slice();
        var out = {};
        if (command === "memory_add") {
            var added = [], existing = [];
            payload.items.forEach(function(item) {
                var m = {id: item.id || ("m-" + String(++helper.counter).padStart(16, "0")), text: String(item.text).trim(),
                         scope: item.scope || "all", projectId: item.scope === "project" ? item.projectId : "",
                         chatId: item.scope === "chat" ? item.chatId : "", pinned: item.pinned === true,
                         enabled: item.enabled !== false, created: item.created || helper.counter, sourceChatId: item.sourceChatId || ""};
                var same = list.filter(function(x) { return helper.key(x) === helper.key(m); })[0];
                if (same) { existing.push(same.id); return; }
                list.push(m);
                added.push(m.id);
            });
            out = {added: added, existing: existing};
            memories = list;
        } else if (command === "memory_update") {
            memories = list.map(function(m) { return m.id === payload.id ? Object.assign({}, m, payload) : m; });
        } else if (command === "memory_delete") {
            var gone = function(m) { return (payload.ids || []).indexOf(m.id) >= 0; };
            out = {deleted: list.filter(gone)};
            memories = list.filter(function(m) { return !gone(m); });
        }
        out.memories = memories;
        var text = JSON.stringify(out);
        Qt.callLater(function() { onDone(text, 0, ""); });
    }
}
