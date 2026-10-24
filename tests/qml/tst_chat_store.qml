// store/ChatStore.qml: per-chat files, only changed chats rewritten.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

TestCase {
    id: testCase
    name: "ChatStore"

    readonly property string root: decodeURIComponent(String(Qt.resolvedUrl("../../build/test-chats/")).replace(/^file:\/\//, ""))
    property var helperCalls: []

    Component {
        id: storeComponent
        Store.ChatStore {
            saveDelay: 10
        }
    }

    function makeStore(dir) {
        var s = createTemporaryObject(storeComponent, testCase, {"directory": dir});
        s.runHelper = function(command, payload, onDone) {
            helperCalls.push({command: command, payload: payload});
            if (onDone) onDone("");
        };
        var prepared = false;
        s.prepare(function() { prepared = true; });
        verify(prepared);
        return s;
    }

    function freshDir() {
        return root + "applet-" + Date.now() + "-" + Math.floor(Math.random() * 1e6);
    }

    function chat(id, title, contents) {
        return {value: id, text: title, updatedAt: 1, source: "provider",
                messages: contents.map(function(c) { return {role: "user", content: c}; })};
    }

    function init() {
        helperCalls = [];
    }

    function test_empty_folder_has_no_index() {
        var s = makeStore(freshDir());
        verify(!s.hasIndex());
        compare(s.loadAll(), null);
    }

    function test_roundtrip_keeps_metadata_and_messages() {
        var dir = freshDir();
        var s = makeStore(dir);
        var big = new Array(5000).join("long text \"quoted\" ünï 🎉 ");
        s.save([chat("s-1", "First", ["hi", big]), chat("s:2", "Second", [])], true);

        var reader = makeStore(dir);
        var loaded = reader.loadAll();
        compare(loaded.length, 2);
        compare(loaded[0].text, "First");
        compare(loaded[0].messages[1].content, big);
        compare(loaded[1].value, "s:2");
        compare(loaded[1].messages.length, 0);
    }

    function test_only_changed_chats_are_rewritten_and_removed_chats_deleted() {
        var dir = freshDir();
        var s = makeStore(dir);
        var a = chat("a", "A", ["one"]);
        var b = chat("b", "B", ["two"]);
        s.save([a, b], true);

        var writes = [];
        s.fileWritten.connect(function(fileName) { writes.push(fileName); });

        b = chat("b", "B", ["two", "three"]);
        s.save([a, b], true);
        compare(writes, ["chat-b.ini"]);

        s.save([b], true);
        var deletes = helperCalls.filter(function(c) { return c.command === "delete_chat_files"; });
        compare(deletes.length, 1);
        compare(deletes[0].payload.files, ["chat-a.ini"]);
        compare(makeStore(dir).loadAll().length, 1);
    }

    function test_save_waits_until_prepared() {
        var dir = freshDir();
        var s = createTemporaryObject(storeComponent, testCase, {"directory": dir});
        var later = null;
        s.runHelper = function(command, payload, onDone) { if (command === "prepare_chat_dir") later = onDone; };
        s.prepare(null);
        s.save([chat("x", "X", ["m"])], true);
        verify(!s.hasIndex(), "wrote before the folder was made private");
        later("");
        verify(s.hasIndex());
    }

    function test_file_names_are_safe() {
        var s = makeStore(freshDir());
        compare(s.fileNameForId("s-1.2_x"), "chat-s-1.2_x.ini");
        compare(s.fileNameForId("a:b/c"), "chat-a%3Ab%2Fc.ini");
    }
}
