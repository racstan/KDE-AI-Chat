// The messages of the chats in chat.sessions. At start only the chat list is read
// (store/ChatStore.qml loadAll(true)): a chat whose messages are still on disk has
// messages [] and messagesUnloaded true. ensure() reads them when the chat is
// opened or something needs its text (search, a scheduled run, a request in it);
// ensureAll() does so for every chat (search). `chat` is the widget root (main.qml).
import QtQuick
import "ReplyState.js" as ReplyState
import "TimeFormat.js" as TimeFormat
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QtObject {
    id: store

    property var chat: null

    // Tidies a chat's messages as they come from disk: only objects, text content,
    // interrupted replies marked, a time on each.
    function normalise(session) {
        if (!Array.isArray(session.messages))
            session.messages = [];
        session.messages = session.messages.filter(function(message) {
            return message && typeof message === "object";
        });
        for (var j = 0; j < session.messages.length; j++) {
            var message = session.messages[j];
            if (message.content === undefined || message.content === null)
                message.content = "";
            else if (typeof message.content !== "string")
                message.content = String(message.content);
            // A long message keeps its full text; the view cuts it (ReplyState.displayContent).
            // A plain notice: the error banner's action would replace the history.
            if (message.content.length > chat.maxMessageChars)
                chat.privacyNotice = i18n("Some messages are too long to show in full and are shown shortened. The full text is kept.");
            ReplyState.markInterrupted(message);
            if (!message.at) message.at = session.updatedAt || session.createdAt || Date.now();
            if (!message.time) message.time = TimeFormat.nowTime(message.at);
        }
    }

    // Reads the messages of chat `sessionId` if they are still on disk. True when they are in memory.
    function ensure(sessionId) {
        var idx = chat.sessionIndexById(sessionId);
        if (idx < 0)
            return false;
        var session = chat.sessions[idx];
        if (!session.messagesUnloaded)
            return true;
        var list = chat.chatStore.loadMessages(session.value);
        session.messages = list === null ? [] : list;  // an unreadable file is kept aside and never written
        delete session.messagesUnloaded;
        store.normalise(session);
        return true;
    }

    function ensureAll() {
        for (var i = 0; i < chat.sessions.length; i++) {
            if (chat.sessions[i].messagesUnloaded)
                store.ensure(chat.sessions[i].value);
        }
    }

    // --- Attached files -------------------------------------------------------------
    // A saved message keeps a reference ({file, hash, ...}) instead of the attachment's
    // bytes (store/AttachmentFiles.qml). A request needs the bytes: hydrate() reads the
    // files of a chat's messages through the helper into a small cache, and resolve()
    // puts the cached content back into the attachments a request is built from.

    property var _cache: ({})       // file -> content (base64 text for an image, text for a document)
    property var _cached: []        // files in the order they were read
    property int cacheChars: 80000000

    function _wanted(att) {
        return !!att && !!att.file && !att.content && (att.type === "image" || att.type === "text");
    }

    // Reads the files of the attachments in `messages` that are not cached; done() when they are (or could not be read).
    function hydrate(messages, done) {
        var need = [];
        var seen = {};
        for (var i = 0; i < messages.length; i++) {
            var list = messages[i] && messages[i].role !== "assistant" ? messages[i].attachments : null;
            for (var j = 0; list && j < list.length; j++) {
                if (store._wanted(list[j]) && !(list[j].file in store._cache) && !seen[list[j].file]) {
                    seen[list[j].file] = true;
                    need.push({"file": list[j].file, "kind": list[j].type === "image" ? "base64" : "text"});
                }
            }
        }
        if (need.length === 0 || !chat.chatStore) {
            done();
            return;
        }
        chat.chatStore.runHelper("attachment_read", {"directory": chat.chatStore.directory, "items": need}, function(out) {
            var results = [];
            try { results = JSON.parse(String(out).trim().split("\n").pop()).items || []; } catch (e) { results = []; }
            for (var n = 0; n < results.length; n++) {
                if (results[n] && results[n].ok)
                    store._remember(results[n].file, String(results[n].content));
            }
            done();
        });
    }

    function _remember(file, content) {
        store._cache[file] = content;
        store._cached.push(file);
        var total = 0;
        for (var k = store._cached.length - 1; k >= 0; k--) {
            total += (store._cache[store._cached[k]] || "").length;
            if (total > store.cacheChars && k < store._cached.length - 1) {  // the newest file always stays
                delete store._cache[store._cached[k]];
                store._cached.splice(k, 1);
            }
        }
    }

    // `attachments` with the bytes of stored files put back; a file that cannot be read becomes a short note.
    function resolve(attachments) {
        if (!attachments)
            return attachments;
        return attachments.map(function(att) {
            if (!store._wanted(att))
                return att;
            if (att.file in store._cache)
                return Object.assign({}, att, {"content": store._cache[att.file]});
            return Object.assign({}, att, {"type": "text", "content": "[The attached file " + String(att.name || "") + " could not be read from its stored copy.]"});
        });
    }
}
