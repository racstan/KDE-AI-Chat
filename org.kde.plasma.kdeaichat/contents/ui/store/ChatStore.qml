// Chat history on disk: one file per chat plus an index, in a private folder.
//
//   <directory>/index.ini        sessions = JSON list of chat metadata (no messages)
//   <directory>/chat-<id>.ini    messages = JSON list of messages
//
// Files are written in-process with QtCore Settings (atomic, no helper
// process, nothing on a command line). Saves are debounced and only chats
// whose content changed are rewritten. The helper is used only to make the
// folder private and to delete files of removed chats.
import QtQuick
import QtCore

Item {
    id: store
    visible: false

    // Absolute folder path, e.g. ~/.local/share/kdeaichat/chats/applet-40.
    property string directory: ""
    // Runs a helper command; calls onDone(output) when it finishes (if given).
    property var runHelper: function(command, payload, onDone) { if (onDone) onDone(""); }
    property int saveDelay: 400

    // Set once prepare() has made the folder private.
    property bool ready: false
    property string lastError: ""

    // id -> JSON written last, so unchanged chats are skipped.
    property var _written: ({})
    property string _writtenIndex: ""
    property var _pending: null

    signal saved()
    signal fileWritten(string fileName)

    Component {
        id: fileComponent
        Settings {}
    }

    Timer {
        id: saveTimer
        interval: store.saveDelay
        repeat: false
        onTriggered: store.flush()
    }

    function fileNameForId(id) {
        return "chat-" + String(id).replace(/[^A-Za-z0-9._-]/g, function(c) {
            return "%" + c.charCodeAt(0).toString(16).toUpperCase();
        }) + ".ini";
    }

    function _open(fileName) {
        return fileComponent.createObject(null, {"location": "file://" + directory + "/" + fileName});
    }

    function _read(fileName, key) {
        var file = _open(fileName);
        var value = String(file.value(key, "") || "");
        file.destroy();
        return value;
    }

    function _write(fileName, key, value) {
        var file = _open(fileName);
        file.setValue(key, value);
        file.sync();
        file.destroy();
        fileWritten(fileName);
    }

    // Makes the folder (0700) before anything is written. callback().
    function prepare(callback) {
        runHelper("prepare_chat_dir", {"directory": directory}, function() {
            ready = true;
            if (callback) callback();
            if (_pending !== null) flush();
        });
    }

    function hasIndex() {
        return directory !== "" && _read("index.ini", "version") !== "";
    }

    // Stores `json` under the key "data" in <directory>/<fileName>.
    function writeBackup(fileName, json) {
        _write(fileName, "data", json);
    }

    // Chat metadata (no messages) as JSON, for lists such as the schedule
    // dialog's chat picker. "" when there is no index yet.
    function indexJson() {
        return directory === "" ? "" : _read("index.ini", "sessions");
    }

    // Returns the stored chats (metadata with messages), or null when this
    // folder has no index yet.
    function loadAll() {
        if (!hasIndex())
            return null;
        var metas;
        try {
            metas = JSON.parse(_read("index.ini", "sessions") || "[]");
        } catch (e) {
            lastError = "index unreadable: " + e;
            return null;
        }
        _writtenIndex = JSON.stringify(metas);
        var written = {};
        var sessions = [];
        for (var i = 0; i < metas.length; i++) {
            var session = Object.assign({}, metas[i]);
            var raw = _read(fileNameForId(session.value), "messages");
            try {
                session.messages = raw ? JSON.parse(raw) : [];
                written[session.value] = raw;
            } catch (e) {
                session.messages = [];
                lastError = "chat " + session.value + " unreadable: " + e;
            }
            sessions.push(session);
        }
        _written = written;
        return sessions;
    }

    // Schedules a save of `sessions`; immediate writes now (if ready).
    function save(sessions, immediate) {
        _pending = sessions;
        if (immediate)
            flush();
        else
            saveTimer.restart();
    }

    function flush() {
        saveTimer.stop();
        if (_pending === null || !ready || directory === "")
            return;
        var sessions = _pending;
        _pending = null;

        var metas = [];
        var written = {};
        for (var i = 0; i < sessions.length; i++) {
            var session = sessions[i];
            var meta = Object.assign({}, session);
            delete meta.messages;
            metas.push(meta);
            var json = JSON.stringify(session.messages || []);
            if (_written[session.value] !== json)
                _write(fileNameForId(session.value), "messages", json);
            written[session.value] = json;
        }

        var removed = [];
        for (var id in _written) {
            if (!(id in written))
                removed.push(fileNameForId(id));
        }
        _written = written;

        var indexJson = JSON.stringify(metas);
        if (indexJson !== _writtenIndex) {
            var index = _open("index.ini");
            index.setValue("version", 1);
            index.setValue("sessions", indexJson);
            index.sync();
            index.destroy();
            _writtenIndex = indexJson;
        }
        if (removed.length > 0)
            runHelper("delete_chat_files", {"directory": directory, "files": removed}, null);
        saved();
    }

    Component.onDestruction: flush()
}
