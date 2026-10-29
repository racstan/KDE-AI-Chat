// Images in chats: saving what a model or an image service made as files in
// the chat's folder, attaching them to the message, and removing them again.
//
// An image is stored on disk by the helper (kdeaichat/images.py), which checks
// it by its first bytes and caps its size. A message keeps only
//   images: [{path, mime, bytes, source, prompt?, service?, model?, provider?, width?, height?, seed?, alt?}]
// with `path` relative to the chat folder (images/<chatId>/<messageId>-<n>.<ext>):
// never the picture's data and never a signed link. Base64 data is too big for a
// command line, so it goes to the helper through a staging file written
// in-process (like the chat files, see store/ChatStore.qml); links are fetched
// by the helper itself.
//
// Files of removed messages and chats are deleted after a short wait, so
// "Undo" can bring them back: a file goes only if no chat still has the message.
// `chat` is the widget root (main.qml).
import QtQuick
import "../Security.js" as Sec
import "ImageExtract.js" as ImageExtract

QtObject {
    id: store

    property var chat: null
    // Runs a helper command: run(command, payload, onDone(stdout, exitCode, stderr)).
    property var runHelper: function(command, payload, onDone) { chat.store.runHelper(command, payload, onDone); }
    // Writes the base64 text of an image to a staging file: stage(fileName, text).
    property var stage: function(fileName, text) { chat.chatStore.writeBackup(fileName, text); }
    // The chat folder, chats/applet-<id> (a test can set it).
    property string directory: chat && chat.chatStore ? chat.chatStore.directory : ""
    // How long the files of a removed message or chat are kept (the undo notice lasts 8 s).
    property int deleteDelay: 12000
    property int sweepInterval: 1000
    // Making new images with an image service: its jobs and progress (chat/ImageJobs.qml).
    readonly property var jobs: ImageJobs { chat: store.chat; imageStore: store }

    // Messages being saved right now (id -> count) and the numbers used so far.
    property var _pending: ({})
    property var _used: ({})
    property var _seen: ({})
    property int _counter: 0
    property var _doomed: []
    // Messages with images, per chat, as last seen (see _reconcile).
    property var _known: ({})
    property string _trackedSession: ""

    signal saved(string messageId, var entries)

    // file:// address of a saved image, for Image { source }.
    function urlFor(path) {
        return directory === "" || !path ? "" : "file://" + encodeURI(directory + "/" + path);
    }

    function hasPending(messageId) {
        return (_pending[messageId] || 0) > 0;
    }

    function hasImages(message) {
        return !!message && ((message.images || []).length > 0 || hasPending(message.id));
    }

    function _adjust(messageId, by) {
        var next = Object.assign({}, _pending);
        next[messageId] = (next[messageId] || 0) + by;
        if (next[messageId] <= 0)
            delete next[messageId];
        _pending = next;
    }

    // Saves one item ({kind: "data", b64} or {kind: "url", url}) as image number n of a message.
    // done({ok, path, mime, bytes} or {ok: false, code, error}).
    function saveItem(sessionId, messageId, n, item, done) {
        var payload = {"directory": directory, "chat": sessionId, "message": messageId, "n": n};
        if (item.kind === "data") {
            var name = "staging-" + Date.now().toString(36) + "-" + (++_counter) + ".ini";
            stage(name, item.b64);
            payload.staging = name;
        } else if (Sec.validateImageUrl(item.url) !== "") {
            payload.url = item.url;
        } else {
            done({"ok": false, "code": "bad_url", "error": "This image link is not allowed."});
            return;
        }
        runHelper("image_save", payload, function(out, code, err) {
            var result = null;
            try { result = JSON.parse(String(out).trim().split("\n").pop()); } catch (e) { result = null; }
            if (result && result.path)
                done(Object.assign({"ok": true}, result));
            else
                done({"ok": false, "code": result && result.code ? result.code : "failed", "error": result && result.error ? result.error : (err || "The image could not be saved.")});
        });
    }

    function _nextNumber(messageId) {
        var next = Object.assign({}, _used);
        var n = next[messageId] || 0;
        next[messageId] = n + 1;
        _used = next;
        return n;
    }

    // Saves a list of items for a message and attaches the ones that worked.
    // meta: fields added to every entry (source, prompt, service, model, ...).
    // done(entries, errors) is optional; errors are the helper's messages.
    function saveItems(sessionId, messageId, items, meta, done) {
        var entries = [];
        var errors = [];
        var queue = items.slice();
        _adjust(messageId, queue.length);
        function next() {
            if (queue.length === 0) {
                if (entries.length > 0)
                    store.attach(sessionId, messageId, entries);
                if (done)
                    done(entries, errors);
                return;
            }
            var item = queue.shift();
            saveItem(sessionId, messageId, _nextNumber(messageId), item, function(result) {
                _adjust(messageId, -1);
                if (result.ok) {
                    var entry = Object.assign({}, meta || {}, {"path": result.path, "mime": result.mime, "bytes": result.bytes});
                    // What the service reports about this picture (the model that made it, its size and seed).
                    var facts = ["model", "width", "height", "seed"];
                    for (var f = 0; f < facts.length; f++) {
                        if (item[facts[f]] !== undefined && item[facts[f]] !== "")
                            entry[facts[f]] = item[facts[f]];
                    }
                    entries.push(entry);
                } else {
                    errors.push(result);
                }
                next();
            });
        }
        next();
    }

    // Images a model sent with its reply (event "images" of DirectBackend). Repeats are dropped.
    function addFromReply(sessionId, messageId, items, meta) {
        var seen = Object.assign({}, _seen);
        var fresh = [];
        for (var i = 0; i < items.length; i++) {
            var key = messageId + "|" + ImageExtract.itemKey(items[i]);
            if (!seen[key]) {
                seen[key] = true;
                fresh.push(items[i]);
            }
        }
        _seen = seen;
        if (fresh.length > 0)
            saveItems(sessionId, messageId, fresh, Object.assign({"source": "model"}, meta || {}), function(entries, errors) {
                if (errors.length > 0 && entries.length === 0)
                    store._reportFailure(errors[0]);
            });
    }

    function _reportFailure(error) {
        chat.pushErrorMessage(error.code === "too_large" ? i18n("An image in the reply was too large to keep.") // qmllint disable unqualified
            : error.code === "not_image" ? i18n("The reply had an image in a format the widget can't show (it shows PNG, JPEG, WebP and GIF).") // qmllint disable unqualified
            : i18n("An image in the reply could not be saved: %1", error.error || "")); // qmllint disable unqualified
    }

    // Moves images written as Markdown data links out of a finished reply's text into files.
    // Returns the message to keep (its content without those links).
    function takeInlineImages(sessionId, reply) {
        var found = ImageExtract.extractMarkdown(reply.content, Sec.validateImageUrl);
        if (found.data.length === 0)
            return reply;
        var copy = Object.assign({}, reply);
        copy.content = found.text;
        saveItems(sessionId, reply.id, found.data, {"source": "model"}, null);
        return copy;
    }

    // The message with the entries added to its images. Works on any chat, not only the open one.
    function attach(sessionId, messageId, entries) {
        var current = sessionId === chat.currentSessionId;
        var at0 = current ? -1 : chat.sessionIndexById(sessionId);
        if (at0 >= 0 && chat.sessions[at0].messagesUnloaded)
            chat.messageLoader.ensure(sessionId);
        var list = current ? chat.messages : ((chat.sessions[chat.sessionIndexById(sessionId)] || {}).messages || []);
        var at = -1;
        for (var i = list.length - 1; i >= 0 && at < 0; i--) {
            if (list[i] && list[i].id === messageId)
                at = i;
        }
        if (at < 0) {
            // The message is gone (deleted, or the chat was cleared) before its image arrived.
            for (var k = 0; k < entries.length; k++)
                _doom(sessionId, messageId);
            return false;
        }
        var copy = list.slice();
        var message = Object.assign({}, copy[at]);
        message.images = (message.images || []).concat(entries);
        copy[at] = message;
        if (current) {
            chat.messages = copy;
            chat.saveCurrentSessionState(true);
        } else {
            var updated = chat.sessions.slice();
            var idx = chat.sessionIndexById(sessionId);
            updated[idx] = Object.assign({}, updated[idx], {"messages": copy});
            chat.sessions = updated;
            chat.persistSessions();
        }
        saved(messageId, entries);
        return true;
    }

    // --- Using a saved image ------------------------------------------------------

    // Makes another image from the same prompt (a new seed) as image `index` of a message.
    function regenerate(messageId, index) {
        if (jobs)
            jobs.regenerate(messageId, index);
    }

    // Puts the image on the clipboard (the helper uses wl-copy on Wayland, xclip on X11).
    // done(ok, text): text is the tool used, or a plain-words reason.
    function copyImage(path, done) {
        runHelper("image_copy", {"directory": directory, "path": path}, function(out, code) {
            var result = {};
            try { result = JSON.parse(String(out).trim().split("\n").pop()); } catch (e) { result = {}; }
            if (code === 0 && result.tool)
                done(true, result.tool);
            else
                done(false, result.code === "no_tool" ? i18n("Copying an image needs wl-clipboard (Wayland) or xclip (X11). Install one of them, or use Download.") // qmllint disable unqualified
                                                      : i18n("The image could not be copied.")); // qmllint disable unqualified
        });
    }

    // Saves a copy of the image to `dest` (an absolute path from the Save dialog).
    function exportImage(path, dest, done) {
        runHelper("image_export", {"directory": directory, "path": path, "dest": dest}, function(out, code, err) {
            done(code === 0, code === 0 ? dest : i18n("The image could not be saved there.")); // qmllint disable unqualified
        });
    }

    // Loads the image behind a Markdown link of a message (after the user asked) and attaches it.
    // linkIndex is the link's place in the message's links (ImageExtract.extractMarkdown).
    function loadLink(sessionId, messageId, linkIndex, link, done) {
        saveItems(sessionId, messageId, [{"kind": "url", "url": link.url}],
                  {"source": "link", "linkIndex": linkIndex, "alt": link.alt || ""}, function(entries, errors) {
            if (done)
                done(entries.length > 0, errors.length > 0 ? store._linkError(errors[0]) : "");
        });
    }

    function _linkError(error) {
        return error.code === "too_large" ? i18n("That image is too large to load.") // qmllint disable unqualified
            : error.code === "not_image" ? i18n("That link is not a PNG, JPEG, WebP or GIF image.") // qmllint disable unqualified
            : error.code === "bad_url" ? i18n("This image link is not allowed.") // qmllint disable unqualified
            : i18n("The image could not be loaded."); // qmllint disable unqualified
    }

    // --- Removing files -------------------------------------------------------------

    function _doom(sessionId, messageId) {
        _doomed = _doomed.concat([{"chat": sessionId, "message": messageId || "", "due": Date.now() + deleteDelay}]);
        sweeper.start();
    }

    function _exists(sessionId, messageId) {
        var idx = chat.sessionIndexById(sessionId);
        if (idx < 0)
            return false;
        if (!messageId)
            return true;
        if (chat.sessions[idx].messagesUnloaded)
            chat.messageLoader.ensure(sessionId);
        var list = sessionId === chat.currentSessionId ? chat.messages : (chat.sessions[idx].messages || []);
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === messageId && (list[i].images || []).length > 0)
                return true;
        }
        return false;
    }

    // Deletes what is due and not wanted any more.
    function sweep() {
        var now = Date.now();
        var keep = [];
        for (var i = 0; i < _doomed.length; i++) {
            var item = _doomed[i];
            if (item.due > now) {
                keep.push(item);
            } else if (!_exists(item.chat, item.message)) {
                var payload = {"directory": directory, "chat": item.chat};
                if (item.message)
                    payload.message = item.message;
                runHelper("image_delete", payload, function() {});
            }
        }
        _doomed = keep;
        if (keep.length === 0)
            sweeper.stop();
    }

    // Looks for messages whose images are gone from the open chat (deleted, cut off by an edit, cleared).
    function _reconcile() {
        var sid = chat.currentSessionId;
        var now = {};
        var messages = chat.messages || [];
        for (var i = 0; i < messages.length; i++) {
            if (messages[i] && (messages[i].images || []).length > 0)
                now[messages[i].id] = true;
        }
        if (_trackedSession === sid) {
            for (var id in (_known[sid] || {})) {
                if (!now[id])
                    _doom(sid, id);
            }
        }
        var known = Object.assign({}, _known);
        known[sid] = now;
        _known = known;
        _trackedSession = sid;
    }

    property Timer sweeper: Timer {
        interval: store.sweepInterval
        repeat: true
        onTriggered: store.sweep()
    }

    property Connections watcher: Connections {
        target: store.chat
        ignoreUnknownSignals: true
        function onMessagesChanged() { store._reconcile(); }
        function onSessionDeleted(session, index) { store._doom(session.value, ""); }
    }
}
