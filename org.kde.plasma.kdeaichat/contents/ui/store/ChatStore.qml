// Chat history on disk: one file per chat plus an index, in a private folder.
//
//   <directory>/index.ini        sessions = JSON list of chat metadata (no messages)
//   <directory>/index.ini.bak    the index as last saved, used when index.ini is damaged
//   <directory>/chat-<id>.ini    messages = JSON list of messages
//   <directory>/projects.ini     projects = JSON list of projects (chat/Projects.js)
//   <directory>/attachments/<chat>/<sha256>.<ext>   attached files (AttachmentFiles.qml); the chat file keeps references
//
// The chat list is read from the index alone (loadAll(true)); a chat's messages
// are read when it is first needed (loadMessages). A chat whose messages are
// not loaded is never written, so its file stays as it is.
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
    // How long the attachment files of a removed chat are kept (the undo notice).
    property int attachmentDeleteDelay: 12000
    readonly property alias attachmentFiles: attachments

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
    property var _lastSessions: null
    // id -> true for chats whose messages are still on disk only (loadAll(true)).
    property var _unloaded: ({})

    signal saved()
    signal fileWritten(string fileName)

    Component {
        id: fileComponent
        Settings {}
    }

    AttachmentFiles {
        id: attachments
        directory: store.directory
        runHelper: store.runHelper
        deleteDelay: store.attachmentDeleteDelay
        isPresent: function(chatId) { return chatId in store._written; }
        // The bytes are on disk now: the chat is saved again, without them.
        onStored: function(chatId) {
            store._dirty[chatId] = true;
            if (store._pending === null && store._lastSessions !== null)
                store._pending = store._lastSessions;
            saveTimer.restart();
        }
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

    property var _dirty: ({})        // ids named by save() hints since the last flush
    property bool _fullCompare: false  // a save came without a hint

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

    // Forgets the index (and its backup), so hasIndex() is false again and the
    // old history is migrated on the next start. Used when a migration failed.
    function discardIndex() {
        var names = ["index.ini", "index.ini.bak"];
        for (var i = 0; i < names.length; i++) {
            var index = _open(names[i]);
            index.setValue("version", "");
            index.setValue("sessions", "");
            index.sync();
            index.destroy();
        }
        _writtenIndex = "";
        _written = {};
        _pending = null;
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
    // folder has no index yet. With `lazy`, the messages of chats that have a
    // mode stay on disk: such a chat has messages [] and messagesUnloaded true
    // until loadMessages(id); its messageCount comes from the index. A damaged index is copied aside and replaced by
    // index.ini.bak when that is readable (recoveredFromBackup); otherwise the
    // result is [] with indexProblem set and nothing will be written.
    function loadAll(lazy) {
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
        var unloaded = {};
        var sessions = [];
        for (var i = 0; i < metas.length; i++) {
            var session = Object.assign({}, metas[i]);
            // A chat without a mode (or a count) is read now: its mode is inferred from its messages (chat/EffectiveConfig.js).
            if (lazy === true && /^(provider|opencode|pi)$/.test(String(session.source || "")) && typeof session.messageCount === "number") {
                session.messages = [];
                session.messagesUnloaded = true;
                written[session.value] = null;
                unloaded[session.value] = true;
                sessions.push(session);
                continue;
            }
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
        _unloaded = unloaded;
        damagedIds = damaged;
        return sessions;
    }

    // Reads the messages of a chat loaded without them. Returns the list, or
    // null when the chat's file cannot be read (it is kept aside and never written).
    function loadMessages(id) {
        var raw = _read(fileNameForId(id), "messages");
        var messages = null;
        try {
            messages = raw ? JSON.parse(raw) : [];
        } catch (e) {
            var damaged = Object.assign({}, damagedIds);
            damaged[id] = true;
            damagedIds = damaged;
            _keepDamaged(fileNameForId(id));
            lastError = "chat " + id + " unreadable: " + e;
        }
        var rest = Object.assign({}, _unloaded);
        delete rest[id];
        _unloaded = rest;
        if (messages !== null)
            _written[id] = raw;
        return Array.isArray(messages) ? messages : null;
    }

    // Writes a new index from the chat files (IndexRebuild.qml). callback(count) when done.
    function rebuildIndex(callback) { rebuilder.run(callback); }

    IndexRebuild { id: rebuilder; chatStore: store }

    // Schedules a save of `sessions`; immediate writes now (if ready).
    // `changed` (optional) lists the ids of the chats whose messages may have
    // changed ([] when only metadata did). Without it every chat is compared
    // with what was last written. Hints of saves that wait for one flush add up.
    function save(sessions, immediate, changed) {
        _pending = sessions;
        if (Array.isArray(changed)) {
            for (var i = 0; i < changed.length; i++)
                _dirty[changed[i]] = true;
        } else {
            _fullCompare = true;
        }
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
        var dirty = _dirty;
        var full = _fullCompare;
        _pending = null;
        _lastSessions = sessions;
        _dirty = {};
        _fullCompare = false;

        var metas = [];
        var written = {};
        for (var i = 0; i < sessions.length; i++) {
            var session = sessions[i];
            // An incognito chat (chat/Incognito.qml) is never written.
            if (session.incognito === true)
                continue;
            var meta = Object.assign({}, session);
            delete meta.messages;
            delete meta.messagesUnloaded;
            if (_unloaded[session.value]) {  // messages still on disk: not touched
                metas.push(meta);
                written[session.value] = _written[session.value];
                continue;
            }
            meta.messageCount = (session.messages || []).length;
            metas.push(meta);
            if (damagedIds[session.value]) {  // unreadable file: kept as it is
                written[session.value] = _written[session.value];
                continue;
            }
            // Not hinted as changed and already on disk: no need to serialise it again.
            if (!full && !dirty[session.value] && session.value in _written) {
                written[session.value] = _written[session.value];
                continue;
            }
            // Attached files are kept as files: the chat file holds references once they are stored.
            var messages = session.messages || [];
            var json = JSON.stringify(attachments.strip(session.value, messages));
            attachments.schedule(session.value, messages);
            if (_written[session.value] !== json)
                _write(fileNameForId(session.value), "messages", json);
            written[session.value] = json;
        }

        var removed = [];
        for (var id in _written) {
            if (!(id in written)) {
                removed.push(fileNameForId(id));
                attachments.chatRemoved(id);
            }
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
