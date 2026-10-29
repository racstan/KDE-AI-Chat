// Chats are loaded when opened: at start only the index is read (store/ChatStore.qml loadAll(true)),
// a chat's messages are read when it is opened or something needs its text (chat/SessionMessages.qml),
// and a chat that was never read is never rewritten. Also: a request is built with the content of
// attachments that were saved as files (hydrate/resolve), and search still finds text in an unopened chat.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/chat/ChatSearch.js" as ChatSearch
import "../../org.kde.plasma.kdeaichat/contents/ui/chat/MessageContent.js" as MessageContent

Item {
    id: root
    width: 100
    height: 100

    function i18n(text) { return text; }

    readonly property string dirRoot: decodeURIComponent(String(Qt.resolvedUrl("../../build/test-lazy/")).replace(/^file:\/\//, ""))

    Component {
        id: storeComponent
        Store.ChatStore { saveDelay: 10 }
    }

    QtObject {
        id: chat
        property var sessions: []
        property var chatStore: null
        property string currentSessionId: ""
        property string privacyNotice: ""
        readonly property int maxMessageChars: 2000000
        function sessionIndexById(id) {
            for (var i = 0; i < sessions.length; i++)
                if (sessions[i].value === id) return i;
            return -1;
        }
        readonly property var loader: Chat.SessionMessages { chat: chat }
    }

    TestCase {
        id: testCase
        name: "LazyChats"
        when: windowShown

        property var helperCalls: []
        property var files: ({})     // attachment file -> content, for the stand-in "attachment_read"

        function makeStore(dir) {
            var s = createTemporaryObject(storeComponent, testCase, {"directory": dir});
            s.runHelper = function(command, payload, onDone) {
                helperCalls.push({command: command, payload: payload});
                var out = "";
                if (command === "attachment_read")
                    out = JSON.stringify({items: payload.items.map(function(i) {
                        return i.file in files ? {file: i.file, ok: true, content: files[i.file]} : {file: i.file, ok: false, error: "missing"};
                    })});
                if (onDone) onDone(out, 0, "");
            };
            s.prepare(null);
            return s;
        }

        function freshDir() {
            return dirRoot + "applet-" + Date.now() + "-" + Math.floor(Math.random() * 1e6);
        }

        function chatOf(id, words, extra) {
            var messages = [];
            for (var i = 0; i < 4; i++)
                messages.push({role: i % 2 === 0 ? "user" : "assistant", content: "message " + i + " about " + words, at: 1000 + i, time: "10:00"});
            return Object.assign({value: id, text: "Chat " + id, createdAt: 1, updatedAt: 5, source: "provider", messages: messages}, extra || {});
        }

        // Three saved chats; returns the folder.
        function saved() {
            var dir = freshDir();
            var s = makeStore(dir);
            s.save([chatOf("a", "apples"), chatOf("b", "bananas"), chatOf("c", "cherries")], true);
            return dir;
        }

        function init() {
            helperCalls = [];
            files = ({});
            chat.sessions = [];
            chat.currentSessionId = "";
        }

        function test_start_reads_the_index_only() {
            var dir = saved();
            var s = makeStore(dir);
            // Chat b's file is unreadable: a start that read it would call it damaged.
            s._write(s.fileNameForId("b"), "messages", "{this is not json");
            var list = s.loadAll(true);
            compare(list.length, 3);
            for (var i = 0; i < list.length; i++) {
                compare(list[i].messages.length, 0, "no messages read");
                compare(list[i].messagesUnloaded, true);
                compare(list[i].messageCount, 4, "the count comes from the index");
                compare(list[i].text, "Chat " + list[i].value);
                compare(list[i].source, "provider");
            }
            compare(Object.keys(s.damagedIds).length, 0, "no chat file was parsed");
            compare(helperCalls.filter(function(c) { return c.command === "keep_damaged_file"; }).length, 0);
        }

        function test_messages_are_read_when_a_chat_is_opened() {
            var s = makeStore(saved());
            chat.chatStore = s;
            chat.sessions = s.loadAll(true);
            verify(chat.sessions[0].messagesUnloaded);
            verify(chat.loader.ensure("a"));
            var a = chat.sessions[chat.sessionIndexById("a")];
            compare(a.messagesUnloaded, undefined);
            compare(a.messages.length, 4);
            compare(a.messages[0].content, "message 0 about apples");
            compare(chat.sessions[chat.sessionIndexById("b")].messages.length, 0, "other chats stay unread");
        }

        function test_a_chat_that_was_not_read_is_never_rewritten() {
            var dir = saved();
            var s = makeStore(dir);
            chat.chatStore = s;
            chat.sessions = s.loadAll(true);
            var written = [];
            s.fileWritten.connect(function(name) { written.push(name); });
            chat.loader.ensure("a");
            chat.sessions[chat.sessionIndexById("a")].messages.push({role: "user", content: "one more", at: 2000, time: "10:01"});
            s.save(chat.sessions, true);   // no hint: every chat is compared
            compare(written, ["chat-a.ini"], "only the chat that was read");
            var index = JSON.parse(s.indexJson());
            compare(index.map(function(m) { return m.messageCount; }).sort(), [4, 4, 5], "counts stay right for all");
            for (var i = 0; i < index.length; i++)
                compare(index[i].messagesUnloaded, undefined, "the flag is not stored");
            var reread = makeStore(dir).loadAll();
            compare(reread[chat.sessionIndexById("b")].messages.length, 4, "chat b is as it was");
            compare(reread[chat.sessionIndexById("a")].messages.length, 5);
        }

        function test_a_chat_without_a_mode_is_read_at_start() {
            var dir = freshDir();
            var s = makeStore(dir);
            s.save([chatOf("old", "oranges", {source: ""})], true);
            var list = makeStore(dir).loadAll(true);
            compare(list[0].messages.length, 4, "its mode is inferred from its messages");
            compare(list[0].messagesUnloaded, undefined);
        }

        function test_an_unreadable_chat_file_is_kept_aside_when_opened() {
            var dir = saved();
            var s = makeStore(dir);
            chat.chatStore = s;
            chat.sessions = s.loadAll(true);
            s._write(s.fileNameForId("b"), "messages", "{broken");
            chat.loader.ensure("b");
            compare(chat.sessions[chat.sessionIndexById("b")].messages.length, 0);
            compare(s.damagedIds["b"], true);
            compare(helperCalls.filter(function(c) { return c.command === "keep_damaged_file"; }).length, 1);
            s.save(chat.sessions, true);
            compare(s._read(s.fileNameForId("b"), "messages"), "{broken", "never overwritten");
        }

        function test_search_finds_text_in_a_chat_that_was_not_opened() {
            var s = makeStore(saved());
            chat.chatStore = s;
            chat.sessions = s.loadAll(true);
            chat.currentSessionId = "a";
            chat.loader.ensure("a");
            chat.loader.ensureAll();   // what the search panel does before it searches
            var found = ChatSearch.search(chat.sessions, ChatSearch.normalizeQuery("bananas"));
            verify(found.results.length > 0, "found");
            compare(found.results[0].sessionId || found.results[0].value || found.results[0].chatId, "b");
        }

        function test_request_is_built_with_the_attachments_content() {
            var s = makeStore(freshDir());
            chat.chatStore = s;
            var png = "iVBORw0KGgo=";
            var ref = {name: "pic.png", type: "image", mimeType: "image/png", size: 8, file: "attachments/a/" + new Array(65).join("1") + ".png", hash: new Array(65).join("1")};
            var doc = {name: "n.txt", type: "text", mimeType: "text/plain", size: 5, file: "attachments/a/" + new Array(65).join("2") + ".txt", hash: new Array(65).join("2")};
            files[ref.file] = png;
            files[doc.file] = "hello";
            var messages = [{role: "user", content: "look", attachments: [ref, doc]}, {role: "assistant", content: "ok"}];
            var done = false;
            chat.loader.hydrate(messages, function() { done = true; });
            verify(done);
            var reads = helperCalls.filter(function(c) { return c.command === "attachment_read"; });
            compare(reads.length, 1);
            compare(reads[0].payload.items.map(function(i) { return i.kind; }), ["base64", "text"]);
            var content = MessageContent.build("look", chat.loader.resolve(messages[0].attachments), "openai", []);
            compare(content[0].text.indexOf("hello") >= 0, true, "the document's text is in the request");
            compare(content[1].image_url.url, "data:image/png;base64," + png, "the image is in the request");
            // Read once: the next request uses the cache.
            helperCalls = [];
            chat.loader.hydrate(messages, function() {});
            compare(helperCalls.length, 0);
        }

        function test_a_file_that_cannot_be_read_becomes_a_note_not_an_empty_image() {
            var ref = {name: "gone.png", type: "image", mimeType: "image/png", size: 8, file: "attachments/a/" + new Array(65).join("3") + ".png"};
            chat.chatStore = makeStore(freshDir());
            var done = false;
            chat.loader.hydrate([{role: "user", content: "x", attachments: [ref]}], function() { done = true; });
            verify(done);
            var content = MessageContent.build("x", chat.loader.resolve([ref]), "openai", []);
            compare(typeof content, "string");
            verify(content.indexOf("could not be read") >= 0);
        }

        // How long start takes with a large store: all chats read (before) against the index only (after).
        function test_start_time_with_a_large_store() {
            var dir = freshDir();
            var s = makeStore(dir);
            var sessions = [];
            var text = new Array(40).join("Lorem ipsum dolor sit amet, consectetur adipiscing elit. ");   // about 2 KB
            for (var i = 0; i < 80; i++) {
                var messages = [];
                for (var m = 0; m < 200; m++)
                    messages.push({id: "m" + m, role: m % 2 === 0 ? "user" : "assistant", content: text + i + ":" + m, at: 1000 + m, time: "10:00"});
                sessions.push({value: "s-" + i, text: "Chat " + i, createdAt: 1, updatedAt: i, source: "provider", messages: messages});
            }
            s.save(sessions, true);
            var reader = makeStore(dir);
            var t0 = Date.now();
            var eager = reader.loadAll();
            var tEager = Date.now() - t0;
            compare(eager.length, 80);
            t0 = Date.now();
            var lazy = makeStore(dir).loadAll(true);
            var tLazy = Date.now() - t0;
            compare(lazy.length, 80);
            console.log("start, 80 chats x 200 messages (" + Math.round(s._read(s.fileNameForId("s-0"), "messages").length * 80 / 1e6) + " MB): all chats read " + tEager + " ms, index only " + tLazy + " ms");
            verify(tLazy < tEager, "reading the index only is faster than reading every chat");
        }
    }
}
