// Attached files kept as files, not inside the chat file (the chat store, ChatStore.qml, owns one).
//
//   <chat folder>/attachments/<chatId>/<sha256>.<ext>      written by the helper (kdeaichat/attachments.py)
//
// A message's attachment arrives with its bytes in `content` (base64 for an image,
// the extracted text for a document). When a chat is saved, strip() returns its
// messages with a reference ({name, type, mimeType, size, path, file, hash})
// in place of `content` for every attachment whose file is stored and verified;
// schedule() hands the others to the helper, which writes them (atomically, once
// per hash) and reads them back before answering. Until then the chat file keeps
// the inline copy, so nothing is ever lost. Old chats with inline attachments
// are moved the same way the next time they are saved. Incognito chats are never
// passed here. Files of removed chats are deleted after a short wait (the undo
// notice), unless the chat came back.
import QtQuick

Item {
    id: files
    visible: false

    property string directory: ""
    property var runHelper: function(command, payload, onDone) { if (onDone) onDone("", 1, ""); }
    // The chat ids that still exist (a chat that came back must keep its files).
    property var isPresent: function(chatId) { return false; }
    property int deleteDelay: 12000

    // fingerprint -> {hash, file, bytes}: stored and read back this session.
    property var _known: ({})
    property var _inflight: ({})
    property var _failed: ({})
    property var _doomed: []

    // A chat's attachments are all stored (their message lists can be saved without bytes).
    signal stored(string chatId)

    function _kind(att) {
        return att && typeof att.content === "string" && att.content !== "" && (att.type === "image" || att.type === "text")
            ? (att.type === "image" ? "base64" : "text") : "";
    }

    function fingerprint(chatId, att) {
        var c = att.content;
        return [chatId, att.name || "", att.mimeType || "", c.length, c.substring(0, 32), c.substring(c.length - 32)].join("|");
    }

    // `messages` with the stored attachments reduced to references. The same array when there is nothing to reduce.
    function strip(chatId, messages) {
        var out = null;
        for (var i = 0; i < messages.length; i++) {
            var list = messages[i] && messages[i].attachments;
            if (!Array.isArray(list))
                continue;
            var reduced = null;
            for (var j = 0; j < list.length; j++) {
                if (files._kind(list[j]) === "")
                    continue;
                var known = files._known[files.fingerprint(chatId, list[j])];
                if (!known)
                    continue;
                if (reduced === null)
                    reduced = list.slice();
                var ref = Object.assign({}, list[j], {"file": known.file, "hash": known.hash});
                delete ref.content;
                reduced[j] = ref;
            }
            if (reduced !== null) {
                if (out === null)
                    out = messages.slice();
                out[i] = Object.assign({}, messages[i], {"attachments": reduced});
            }
        }
        return out === null ? messages : out;
    }

    // Stores the attachments of `messages` that are not stored yet; stored(chatId) when done.
    function schedule(chatId, messages) {
        var items = [];
        var keys = [];
        for (var i = 0; i < messages.length; i++) {
            var list = messages[i] && messages[i].attachments;
            if (!Array.isArray(list))
                continue;
            for (var j = 0; j < list.length; j++) {
                var kind = files._kind(list[j]);
                if (kind === "")
                    continue;
                var key = files.fingerprint(chatId, list[j]);
                if (files._known[key] || files._inflight[key] || files._failed[key] || keys.indexOf(key) >= 0)
                    continue;
                keys.push(key);
                items.push({"kind": kind, "content": list[j].content, "mime": list[j].mimeType || ""});
            }
        }
        if (items.length === 0 || directory === "")
            return;
        for (var k = 0; k < keys.length; k++)
            files._inflight[keys[k]] = true;
        files.runHelper("attachment_store", {"directory": directory, "chat": chatId, "items": items}, function(out) {
            var results = [];
            try { results = JSON.parse(String(out).trim().split("\n").pop()).items || []; } catch (e) { results = []; }
            var any = false;
            for (var n = 0; n < keys.length; n++) {
                delete files._inflight[keys[n]];
                var r = results[n];
                if (r && r.ok && r.hash && r.file) {
                    files._known[keys[n]] = {"hash": r.hash, "file": r.file, "bytes": r.bytes};
                    any = true;
                } else {
                    files._failed[keys[n]] = true;  // stays inline; tried again next start
                }
            }
            if (any)
                files.stored(chatId);
        });
    }

    // A removed chat: its fingerprints go and its folder is deleted after the wait (unless it is back).
    function chatRemoved(chatId) {
        var prefix = chatId + "|";
        for (var key in files._known) {
            if (key.indexOf(prefix) === 0)
                delete files._known[key];
        }
        files._doomed = files._doomed.concat([chatId]);
        sweepTimer.restart();
    }

    Timer {
        id: sweepTimer
        interval: files.deleteDelay
        repeat: false
        onTriggered: {
            var gone = files._doomed.filter(function(id) { return !files.isPresent(id); });
            files._doomed = [];
            if (gone.length > 0 && files.directory !== "")
                files.runHelper("attachment_delete", {"directory": files.directory, "chats": gone}, null);
        }
    }
}
