// Chat history on disk: one file per chat plus an index, in a private folder.
//
//   <directory>/index.ini        sessions = JSON list of chat metadata (no messages)
//   <directory>/index.ini.bak    the index as last saved, used when index.ini is damaged
//   <directory>/chat-<id>.ini    messages = JSON list of messages
//   <directory>/projects.ini     projects = JSON list of projects (chat/Projects.js)
//
// Files are written in-process with QtCore Settings (atomic, no helper
// process, nothing on a command line). Saves are debounced and only chats
// whose content changed are rewritten. The helper is used only to make the
// folder private, to delete files of removed chats and to keep a copy of a
// file that cannot be read (<name>.damaged-<date>): such a file is never
// overwritten (a damaged chat file is skipped by every save, a damaged index
// blocks saving until the list is rebuilt from the chat files).
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
    // Not "" when index.ini (and index.ini.bak) cannot be read: nothing is saved
    // until rebuildIndex() has run. The text is for the user.
    property string indexProblem: ""
    // The index was damaged and index.ini.bak was used instead (told to the user once).
    property bool recoveredFromBackup: false
    // id -> true for chats whose file cannot be read; they are shown empty and never written.
    property var damagedIds: ({})

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
            if (_pendingProjects !== null) saveProjects(_pendingProjects);
        });
    }

    // Projects (chat/Projects.js) live in <directory>/projects.ini, key
    // "projects" (a JSON list). No file yet: "" (no projects).
    property var _pendingProjects: null
    property string _writtenProjects: ""

    function loadProjects() {
        if (directory === "")
            return "";
        _writtenProjects = _read("projects.ini", "projects");
        return _writtenProjects;
    }

    // Written at once (projects change rarely), or once the folder is ready.
    function saveProjects(projects) {
        var json = JSON.stringify(projects || []);
        if (!ready || directory === "") {
            _pendingProjects = projects || [];
            return;
        }
        _pendingProjects = null;
        if (json === _writtenProjects)
            return;
        var file = _open("projects.ini");
        file.setValue("version", 1);
        file.setValue("projects", json);
        file.sync();
        file.destroy();
        _writtenProjects = json;
        fileWritten("projects.ini");
    }

    // True when an index exists, even a damaged one (or only its backup is left).
    function hasIndex() {
        return directory !== "" && (_read("index.ini", "version") !== "" || _read("index.ini", "sessions") !== ""
                                    || _read("index.ini.bak", "sessions") !== "");
    }

    function _stamp() {
        var d = new Date();
        function two(n) { return (n < 10 ? "0" : "") + n; }
        return d.getFullYear() + two(d.getMonth() + 1) + two(d.getDate()) + "-" + two(d.getHours()) + two(d.getMinutes()) + two(d.getSeconds());
    }

    // Keeps a copy of an unreadable file as <fileName>.damaged-<date> (helper; once).
    function _keepDamaged(fileName) {
        runHelper("keep_damaged_file", {"directory": directory, "file": fileName, "stamp": _stamp()}, null);
    }

    // The list in an index file's "sessions" value, or null when it is not one.
    function _parseIndex(text) {
        try {
            var list = JSON.parse(text);
            return Array.isArray(list) ? list : null;
        } catch (e) {
            return null;
        }
    }

    // Writes index.ini and, after it, the backup index.ini.bak.
    function _writeIndex(json) {
        var names = ["index.ini", "index.ini.bak"];
        for (var i = 0; i < names.length; i++) {
            var index = _open(names[i]);
            index.setValue("version", 1);
            index.setValue("sessions", json);
            index.sync();
            index.destroy();
        }
        _writtenIndex = json;
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
    // folder has no index yet. A damaged index is copied aside and replaced by
    // index.ini.bak when that is readable (recoveredFromBackup); otherwise the
    // result is [] with indexProblem set and nothing will be written.
    function loadAll() {
        if (!hasIndex())
            return null;
        indexProblem = "";
        recoveredFromBackup = false;
        var metas = _parseIndex(_read("index.ini", "sessions") || "[]");
        _writtenIndex = metas === null ? "" : JSON.stringify(metas);
        if (metas === null) {
            lastError = "index unreadable";
            _keepDamaged("index.ini");
            metas = _parseIndex(_read("index.ini.bak", "sessions"));
            if (metas === null) {
                indexProblem = "The chat list is damaged, so nothing is saved. A copy was kept.";  // shown through i18n by chat/HistoryRecovery.qml
                _written = {};
                return [];
            }
            recoveredFromBackup = true;  // index.ini is rewritten by the next save
        }
        var written = {};
        var damaged = {};
        var sessions = [];
        for (var i = 0; i < metas.length; i++) {
            var session = Object.assign({}, metas[i]);
            var raw = _read(fileNameForId(session.value), "messages");
            try {
                session.messages = raw ? JSON.parse(raw) : [];
                written[session.value] = raw;
            } catch (e) {
                session.messages = [];
                damaged[session.value] = true;
                _keepDamaged(fileNameForId(session.value));
                lastError = "chat " + session.value + " unreadable: " + e;
            }
            sessions.push(session);
        }
        _written = written;
        damagedIds = damaged;
        return sessions;
    }

    // Lists the chat files and writes a new index for them (title from the first
    // message, mode left to be inferred from the messages as for any chat without
    // one). A chat file that cannot be read is listed empty and stays as it is.
    // callback(count) when done.
    function rebuildIndex(callback) {
        runHelper("list_chat_files", {"directory": directory}, function(output) {
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
                var raw = _read(files[i], "messages");
                var messages = _parseIndex(raw || "[]");
                if (messages === null) {
                    damaged[id] = true;
                    messages = [];
                    _keepDamaged(files[i]);
                } else {
                    written[id] = raw;
                }
                var first = messages.filter(function(m) { return m && m.role === "user" && typeof m.content === "string"; })[0];
                var last = messages.length > 0 && messages[messages.length - 1] ? messages[messages.length - 1].at : 0;
                metas.push({"value": id, "text": first ? first.content.trim().substring(0, 40) : "Recovered chat",
                            "createdAt": messages.length > 0 && messages[0] && messages[0].at ? messages[0].at : last || Date.now(),
                            "updatedAt": last || Date.now()});
            }
            _written = written;
            damagedIds = damaged;
            _pending = null;
            _writeIndex(JSON.stringify(metas));
            indexProblem = "";
            if (callback) callback(metas.length);
        });
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
        if (_pending === null || !ready || directory === "" || indexProblem !== "")
            return;
        var sessions = _pending;
        _pending = null;

        var metas = [];
        var written = {};
        for (var i = 0; i < sessions.length; i++) {
            var session = sessions[i];
            // An incognito chat (chat/Incognito.qml) is never written.
            if (session.incognito === true)
                continue;
            var meta = Object.assign({}, session);
            delete meta.messages;
            metas.push(meta);
            if (damagedIds[session.value]) {  // unreadable file: kept as it is
                written[session.value] = _written[session.value];
                continue;
            }
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
            _writeIndex(indexJson);
        }
        if (removed.length > 0)
            runHelper("delete_chat_files", {"directory": directory, "files": removed}, null);
        saved();
    }

    Component.onDestruction: flush()
}
