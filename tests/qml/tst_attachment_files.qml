// Attached files are kept as files (store/AttachmentFiles.qml through store/ChatStore.qml):
// the chat file keeps a reference, the bytes are stored once, old inline chats are moved on
// their next save, incognito chats write no files, and a removed chat's files go (after the undo wait).
// The helper is a stand-in that records what it is asked (kdeaichat/attachments.py is tested in tests/test_attachments.py).
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

TestCase {
    id: testCase
    name: "AttachmentFiles"

    readonly property string root: decodeURIComponent(String(Qt.resolvedUrl("../../build/test-attachments/")).replace(/^file:\/\//, ""))
    property var calls: []
    property bool helperWorks: true
    readonly property string big: new Array(200001).join("QUJD")   // 800,000 characters of base64

    Component {
        id: storeComponent
        Store.ChatStore {
            saveDelay: 10
            attachmentDeleteDelay: 60
        }
    }

    function fakeHash(content) {
        return ("0000000000000000000000000000000000000000000000000000000000000000" + content.length.toString(16)).slice(-64);
    }

    function makeStore(dir) {
        var s = createTemporaryObject(storeComponent, testCase, {"directory": dir});
        s.runHelper = function(command, payload, onDone) {
            calls.push({command: command, payload: payload});
            var out = "";
            if (command === "attachment_store") {
                out = JSON.stringify({items: payload.items.map(function(item) {
                    if (!helperWorks)
                        return {ok: false, error: "disk full"};
                    var h = fakeHash(item.content);
                    return {ok: true, hash: h, file: "attachments/" + payload.chat + "/" + h + (item.kind === "text" ? ".txt" : ".png"), bytes: item.content.length};
                })});
            }
            if (onDone) onDone(out, 0, "");
        };
        s.prepare(null);
        return s;
    }

    function freshDir() {
        return root + "applet-" + Date.now() + "-" + Math.floor(Math.random() * 1e6);
    }

    function attachment(content, name) {
        return {name: name || "photo.png", type: "image", mimeType: "image/png", size: 600000, path: "/home/u/" + (name || "photo.png"), content: content, loading: false, error: "", warning: ""};
    }

    function chatWith(id, attachments, extra) {
        return Object.assign({value: id, text: id, updatedAt: 1, source: "provider",
                              messages: [{role: "user", content: "see this", attachments: attachments}, {role: "assistant", content: "ok"}]}, extra || {});
    }

    function chatFileSize(store, id) {
        return store._read(store.fileNameForId(id), "messages").length;
    }

    function storeCalls() {
        return calls.filter(function(c) { return c.command === "attachment_store"; });
    }

    function init() {
        calls = [];
        helperWorks = true;
    }

    function test_attachment_is_stored_once_and_the_chat_file_stays_small() {
        var dir = freshDir();
        var s = makeStore(dir);
        // The same file attached to two messages.
        var chat = chatWith("s-1", [attachment(big)]);
        chat.messages.push({role: "user", content: "again", attachments: [attachment(big)]});
        s.save([chat], true);
        tryVerify(function() { return chatFileSize(s, "s-1") < 5000; }, 2000, "the chat file keeps only references");
        compare(storeCalls().length, 1, "one helper call");
        compare(storeCalls()[0].payload.items.length, 1, "the same bytes are stored once");
        compare(storeCalls()[0].payload.items[0].kind, "base64");
        compare(storeCalls()[0].payload.directory, dir);
        compare(storeCalls()[0].payload.chat, "s-1");

        var loaded = makeStore(dir).loadAll();
        var att = loaded[0].messages[0].attachments[0];
        compare(att.content, undefined, "no bytes in the chat file");
        compare(att.name, "photo.png");
        compare(att.mimeType, "image/png");
        compare(att.size, 600000);
        compare(att.hash, fakeHash(big));
        verify(/^attachments\/s-1\/0+[0-9a-f]+\.png$/.test(att.file));
        compare(loaded[0].messages[2].attachments[0].file, att.file);
        compare(chat.messages[0].attachments[0].content, big, "the open chat keeps its bytes in memory");
    }

    function test_text_attachment_is_stored_as_text() {
        var s = makeStore(freshDir());
        var doc = {name: "notes.txt", type: "text", mimeType: "text/plain", size: 9, path: "/home/u/notes.txt", content: "some text"};
        s.save([chatWith("s-t", [doc])], true);
        tryVerify(function() { return storeCalls().length === 1; });
        compare(storeCalls()[0].payload.items[0].kind, "text");
        compare(storeCalls()[0].payload.items[0].content, "some text");
    }

    function test_attachment_stays_inline_when_the_helper_fails() {
        var dir = freshDir();
        helperWorks = false;
        var s = makeStore(dir);
        s.save([chatWith("s-f", [attachment(big)])], true);
        wait(100);
        verify(chatFileSize(s, "s-f") > 700000, "nothing is dropped from the chat file without a verified copy");
        compare(storeCalls().length, 1, "not tried again and again");
        s.save([chatWith("s-f", [attachment(big)])], true);
        wait(50);
        compare(storeCalls().length, 1);
    }

    function test_old_chat_with_inline_attachments_is_moved_on_its_next_save() {
        var dir = freshDir();
        helperWorks = false;
        var old = makeStore(dir);
        old.save([chatWith("s-old", [attachment(big)])], true);
        wait(50);
        verify(chatFileSize(old, "s-old") > 700000, "an old chat file with the bytes inside");

        helperWorks = true;
        calls = [];
        var s = makeStore(dir);
        var sessions = s.loadAll();
        compare(sessions[0].messages[0].attachments[0].content, big);
        s.save(sessions, true, ["s-old"]);
        tryVerify(function() { return chatFileSize(s, "s-old") < 5000; }, 2000);
        compare(storeCalls().length, 1);
        var again = makeStore(dir).loadAll();
        compare(again[0].messages[0].attachments[0].hash, fakeHash(big));
        compare(again[0].messages[1].content, "ok", "the rest of the chat is unchanged");
    }

    function test_incognito_chat_writes_no_files() {
        var dir = freshDir();
        var s = makeStore(dir);
        s.save([chatWith("s-incognito-1", [attachment(big)], {incognito: true}), chatWith("s-keep", [])], true);
        wait(100);
        compare(storeCalls().length, 0, "no attachment file for an incognito chat");
        compare(s._read(s.fileNameForId("s-incognito-1"), "messages"), "", "and no chat file");
    }

    function test_removed_chat_loses_its_attachments_after_the_wait() {
        var dir = freshDir();
        var s = makeStore(dir);
        s.save([chatWith("a", [attachment(big)]), chatWith("b", [attachment(big, "b.png")])], true);
        wait(50);
        s.save([chatWith("a", [attachment(big)])], true);
        compare(calls.filter(function(c) { return c.command === "attachment_delete"; }).length, 0, "not at once: the undo notice may bring the chat back");
        tryVerify(function() { return calls.filter(function(c) { return c.command === "attachment_delete"; }).length === 1; }, 2000);
        var del = calls.filter(function(c) { return c.command === "attachment_delete"; })[0];
        compare(del.payload.chats, ["b"]);
        compare(del.payload.directory, dir);
    }

    function test_a_chat_that_comes_back_keeps_its_attachments() {
        var s = makeStore(freshDir());
        var a = chatWith("a", [attachment(big)]);
        var b = chatWith("b", [attachment(big, "b.png")]);
        s.save([a, b], true);
        wait(50);
        s.save([a], true);
        s.save([a, b], true);   // undo
        wait(250);
        compare(calls.filter(function(c) { return c.command === "attachment_delete"; }).length, 0);
        tryVerify(function() { return chatFileSize(s, "b") < 5000; }, 2000, "and its file still holds the reference");
    }
}
