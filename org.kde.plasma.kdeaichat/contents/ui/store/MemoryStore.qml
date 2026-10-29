// Memories (things the user asked the assistant to remember), kept by the
// helper in a private ~/.local/share/kdeaichat/memory.json (kdeaichat/memory.py,
// which documents a memory's fields). Never in the widget's config.
//
// The list is held here once loaded; every change goes through the helper,
// one command at a time, and the helper answers with the whole list, which
// replaces `list`. Callbacks get (ok, result) with the helper's JSON answer.
// Which memories go with a request is chat/MemoryRecall.js (via chat/Memory.qml).
import QtQuick

QtObject {
    id: store

    property var configuration: null   // plasmoid.configuration: memoryEnabled
    property var runHelper: function(command, payload, onDone) { if (onDone) onDone("{\"memories\": []}", 0, ""); }

    property var list: []
    property bool loaded: false
    property string lastError: ""
    // Memory on or off for every chat (a normal setting: it is not secret).
    readonly property bool enabled: !configuration || configuration.memoryEnabled !== false

    // Emitted after each load.
    signal listLoaded()

    // Items go to the helper in batches small enough for its command line.
    readonly property int maxBatchItems: 50
    readonly property int maxBatchChars: 40000

    property var _queue: []
    property bool _busy: false

    function _run(command, payload, callback) {
        _queue.push({"command": command, "payload": payload, "callback": callback});
        _next();
    }

    function _next() {
        if (_busy || _queue.length === 0)
            return;
        _busy = true;
        var job = _queue.shift();
        runHelper(job.command, job.payload, function(stdout, exitCode, stderr) {
            var result = null;
            try { result = exitCode === 0 ? JSON.parse(stdout) : null; } catch (e) { result = null; }
            if (result && Array.isArray(result.memories)) {
                list = result.memories;
                lastError = "";
            } else {
                lastError = String(stdout || stderr || "memory helper failed").trim().substring(0, 300);
                console.warn("KDE AI Chat: memory command failed:", job.command, lastError);
            }
            _busy = false;
            if (job.callback)
                job.callback(result !== null, result);
            _next();
        });
    }

    function setGlobalEnabled(on) {
        if (configuration)
            configuration.memoryEnabled = on === true;
    }

    function load(callback) {
        _run("memory_list", {}, function(ok, result) {
            loaded = ok || loaded;
            listLoaded();
            if (callback) callback(ok, result);
        });
    }

    function byId(id) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id)
                return list[i];
        }
        return null;
    }

    // fields: {text, scope, projectId?, chatId?, pinned?, enabled?, sourceChatId?}
    function add(fields, callback) {
        addMany([fields], callback);
    }

    // Adds items in batches; callback(ok, {added, existing}) once all are in
    // (ok false and nothing more sent after a batch fails). With
    // options.skipInvalid a malformed item is skipped instead of failing its
    // batch; result.skipped counts them.
    function addMany(items, callback, options) {
        var batches = [];
        var batch = [], size = 0;
        (items || []).forEach(function(item) {
            var itemSize = JSON.stringify(item).length;
            if (batch.length > 0 && (batch.length >= maxBatchItems || size + itemSize > maxBatchChars)) {
                batches.push(batch);
                batch = [];
                size = 0;
            }
            batch.push(item);
            size += itemSize;
        });
        if (batch.length > 0)
            batches.push(batch);
        var added = [], existing = [], skipped = 0;
        var skipInvalid = options && options.skipInvalid === true;
        function step(i) {
            if (i >= batches.length) {
                if (callback) callback(true, {"added": added, "existing": existing, "skipped": skipped});
                return;
            }
            _run("memory_add", skipInvalid ? {"items": batches[i], "skipInvalid": true} : {"items": batches[i]}, function(ok, result) {
                if (!ok) {
                    if (callback) callback(false, {"added": added, "existing": existing});
                    return;
                }
                added = added.concat(result.added || []);
                existing = existing.concat(result.existing || []);
                skipped += Number(result.skipped || 0);
                step(i + 1);
            });
        }
        step(0);
    }

    // fields: any of {text, pinned, enabled, scope, projectId, chatId}.
    function update(id, fields, callback) {
        _run("memory_update", Object.assign({}, fields || {}, {"id": id}), callback);
    }

    function setPinned(id, pinned, callback) {
        update(id, {"pinned": pinned === true}, callback);
    }

    function setEnabled(id, on, callback) {
        update(id, {"enabled": on === true}, callback);
    }

    function remove(id, callback) {
        _run("memory_delete", {"ids": [id]}, callback);
    }

    // Removes the memories of these chats and projects. callback(ok, {deleted}).
    function removeScoped(chatIds, projectIds, callback) {
        _run("memory_delete", {"chatIds": chatIds || [], "projectIds": projectIds || []}, callback);
    }

    // Puts removed memories back as they were (same ids), e.g. on Undo.
    function restore(memories, callback) {
        if (!memories || memories.length === 0) {
            if (callback) callback(true, {"added": [], "existing": []});
            return;
        }
        addMany(memories, callback);
    }
}
