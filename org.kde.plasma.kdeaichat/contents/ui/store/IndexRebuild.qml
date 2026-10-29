// Rebuilds a lost or damaged chat index from the chat files (used by ChatStore.rebuildIndex).
import QtQuick

QtObject {
    id: rebuilder

    property var store: null

    // Lists the chat files and writes a new index for them (title from the first
    // message, mode left to be inferred from the messages as for any chat without
    // one). A chat file that cannot be read is listed empty and stays as it is.
    // callback(count) when done.
    function run(callback) {
        var s = rebuilder.store;
        s.runHelper("list_chat_files", {"directory": s.directory}, function(output) {
            var files = [];
            try { files = JSON.parse(output).files || []; } catch (e) { }
            var metas = [];
            var written = {};
            var damaged = {};
            for (var i = 0; i < files.length; i++) {
                var id;
                try { id = decodeURIComponent(files[i].slice(5, -4)); } catch (e) { continue; }
                if (/^s-incognito-/.test(id))
                    continue;
                var raw = s._read(files[i], "messages");
                var messages = s._parseIndex(raw || "[]");
                if (messages === null) {
                    damaged[id] = true;
                    messages = [];
                    s._keepDamaged(files[i]);
                } else {
                    written[id] = raw;
                }
                var first = messages.filter(function(m) { return m && m.role === "user" && typeof m.content === "string"; })[0];
                var last = messages.length > 0 && messages[messages.length - 1] ? messages[messages.length - 1].at : 0;
                metas.push({"value": id, "text": first ? first.content.trim().substring(0, 40) : "Recovered chat",
                            "createdAt": messages.length > 0 && messages[0] && messages[0].at ? messages[0].at : last || Date.now(),
                            "updatedAt": last || Date.now()});
            }
            s._written = written;
            s._unloaded = {};
            s.damagedIds = damaged;
            s._pending = null;
            s._writeIndex(JSON.stringify(metas));
            s.indexProblem = "";
            if (callback) callback(metas.length);
        });
    }
}
