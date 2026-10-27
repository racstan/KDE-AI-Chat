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

    // Projects sit next to the chats in projects.ini; a folder without one has none.
    function test_projects_roundtrip_and_old_folders_have_none() {
        var dir = freshDir();
        var s = makeStore(dir);
        compare(s.loadProjects(), "", "no projects.ini yet: no projects");
        s.save([chat("s-1", "Old chat", ["hi"])], true);
        var projects = [{id: "p-1", name: "Work", color: "#3daee9", instructions: "Answer in French.", folder: "/tmp", provider: "", model: "", createdAt: 1}];
        var written = [];
        s.fileWritten.connect(function(name) { written.push(name); });
        s.saveProjects(projects);
        compare(written, ["projects.ini"]);
        s.saveProjects(projects);
        compare(written.length, 1, "unchanged projects are not rewritten");
        var reader = makeStore(dir);
        compare(JSON.parse(reader.loadProjects()), projects);
        var chats = reader.loadAll();
        compare(chats.length, 1);
        compare(chats[0].projectId, undefined, "a chat from before projects loads unchanged (no project)");
    }

    function test_projects_saved_before_the_folder_is_ready_wait_for_it() {
        var dir = freshDir();
        var s = createTemporaryObject(storeComponent, testCase, {"directory": dir});
        var later = null;
        s.runHelper = function(command, payload, onDone) { later = onDone; };
        s.prepare(null);
        s.saveProjects([{id: "p-2", name: "Later"}]);
        compare(makeStore(dir).loadProjects(), "", "nothing written before the folder is private");
        later("");
        compare(JSON.parse(makeStore(dir).loadProjects())[0].name, "Later");
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

    // A message's quotes (structured, MessageContent.js) are saved with it.
    function test_roundtrip_keeps_the_quotes_of_a_message() {
        var dir = freshDir();
        var s = makeStore(dir);
        var quotes = [{id: "m-1", role: "assistant", text: "Use rsync.\nIt's \"faster\" …"}, {id: "m-0", role: "user", text: "single"}];
        var c = chat("s-q", "Quotes", ["hi"]);
        c.messages = [{role: "assistant", id: "m-1", content: "Use rsync."}, {role: "user", content: "And?", quotes: quotes}];
        s.save([c], true);
        var loaded = makeStore(dir).loadAll();
        compare(JSON.stringify(loaded[0].messages[1].quotes), JSON.stringify(quotes));
        compare(loaded[0].messages[0].id, "m-1", "the id a quote points to is kept");
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

    // 300 chats of ~50 KB: a hinted save serialises and writes only the changed chat.
    function test_hinted_save_of_many_large_chats_writes_one_file_quickly() {
        var s = makeStore(freshDir());
        var filler = new Array(50 * 1024).join("x");
        var chats = [];
        for (var i = 0; i < 300; i++)
            chats.push(chat("c" + i, "Chat " + i, [filler, "m" + i]));
        s.save(chats, true);
        compare(s.loadAll().length, 300);

        var writes = [];
        s.fileWritten.connect(function(name) { writes.push(name); });
        var edited = chat("c7", "Chat 7", [filler, "m7", "new"]);
        chats = chats.slice();
        chats[7] = edited;
        var t0 = Date.now();
        s.save(chats, true, ["c7"]);
        var hinted = Date.now() - t0;
        compare(writes, ["chat-c7.ini"]);

        // Without a hint every chat is compared (still correct, slower).
        writes = [];
        chats = chats.slice();
        chats[9] = chat("c9", "Chat 9", [filler, "m9", "new"]);
        t0 = Date.now();
        s.save(chats, true);
        var full = Date.now() - t0;
        compare(writes, ["chat-c9.ini"]);
        console.info("save timing: hinted " + hinted + " ms, full compare " + full + " ms");
        verify(hinted < 300, "hinted save took " + hinted + " ms");

        // A metadata-only hint writes no chat file; the index changes.
        writes = [];
        chats = chats.slice();
        chats[3] = Object.assign({}, chats[3], {text: "Renamed"});
        s.save(chats, true, []);
        compare(writes.length, 0);
        compare(JSON.parse(s._read("index.ini", "sessions"))[3].text, "Renamed");
    }

    // Hints of several saves before one flush add up; an unhinted save checks everything.
    function test_hints_accumulate_until_the_flush() {
        var s = makeStore(freshDir());
        var a = chat("a", "A", ["1"]), b = chat("b", "B", ["2"]), c = chat("c", "C", ["3"]);
        s.save([a, b, c], true);
        var writes = [];
        s.fileWritten.connect(function(name) { writes.push(name); });
        a = chat("a", "A", ["1", "x"]);
        b = chat("b", "B", ["2", "y"]);
        s.save([a, b, c], false, ["a"]);
        s.save([a, b, c], false, ["b"]);
        s.flush();
        compare(writes.sort(), ["chat-a.ini", "chat-b.ini"]);
        writes = [];
        c = chat("c", "C", ["3", "z"]);
        s.save([a, b, c], true);
        compare(writes, ["chat-c.ini"]);
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

    function keptCopies() {
        return helperCalls.filter(function(c) { return c.command === "keep_damaged_file"; });
    }

    // A chat file that cannot be parsed is kept as it is: a copy is made once and a save never replaces it.
    function test_damaged_chat_file_is_not_overwritten() {
        var dir = freshDir();
        var s = makeStore(dir);
        s.save([chat("a", "A", ["one"]), chat("b", "B", ["two"])], true);
        s._write("chat-a.ini", "messages", "[{\"role\":\"user\",\"content\":\"cut off");

        var reader = makeStore(dir);
        var loaded = reader.loadAll();
        compare(loaded.length, 2);
        compare(loaded[0].messages.length, 0, "the damaged chat is shown empty");
        verify(reader.damagedIds["a"]);
        verify(!reader.damagedIds["b"]);
        compare(loaded[0].source, "provider", "the mode is untouched");
        var copies = keptCopies();
        compare(copies.length, 1);
        compare(copies[0].payload.file, "chat-a.ini");
        verify(/^\d{8}-\d{6}$/.test(copies[0].payload.stamp));

        var writes = [];
        reader.fileWritten.connect(function(name) { writes.push(name); });
        loaded[0].messages = [{role: "user", content: "new"}];
        loaded[1].messages = [{role: "user", content: "two"}, {role: "user", content: "more"}];
        reader.save(loaded, true);
        compare(writes, ["chat-b.ini"], "only the readable chat is written");
        compare(reader._read("chat-a.ini", "messages"), "[{\"role\":\"user\",\"content\":\"cut off");
        compare(helperCalls.filter(function(c) { return c.command === "delete_chat_files"; }).length, 0, "it is not treated as removed");
        compare(makeStore(dir).loadAll().length, 2, "still listed");
    }

    // A damaged index blocks every save; rebuilding lists the chat files again.
    function test_damaged_index_blocks_saves_and_rebuild_restores_chats() {
        var dir = freshDir();
        var s = makeStore(dir);
        var a = chat("a", "A", ["hello there"]);
        a.messages[0].at = 1000;
        s.save([a, chat("b:2", "B", ["two"])], true);
        s._write("index.ini", "sessions", "[{\"value\":\"a\",\"te");
        s._write("index.ini.bak", "sessions", "also {broken");
        var before = s._read("index.ini", "sessions");

        var reader = makeStore(dir);
        reader.runHelper = function(command, payload, onDone) {
            helperCalls.push({command: command, payload: payload});
            if (onDone) onDone(command === "list_chat_files" ? JSON.stringify({files: ["chat-a.ini", "chat-b%3A2.ini"]}) : "");
        };
        compare(reader.loadAll().length, 0, "nothing is listed");
        verify(reader.indexProblem !== "");
        compare(keptCopies()[0].payload.file, "index.ini");

        reader.save([chat("new", "New", ["x"])], true);
        compare(reader._read("index.ini", "sessions"), before, "the damaged index is not replaced");
        compare(reader._read("chat-new.ini", "messages"), "", "no chat file is written either");

        var count = -1;
        reader.rebuildIndex(function(n) { count = n; });
        compare(count, 2);
        compare(reader.indexProblem, "");
        var chats = makeStore(dir).loadAll();
        compare(chats.length, 2);
        compare(chats[0].value, "a");
        compare(chats[0].text, "hello there");
        compare(chats[0].updatedAt, 1000);
        compare(chats[1].value, "b:2");
        compare(chats[1].messages[0].content, "two");
        compare(chats[0].source, undefined, "no mode is invented here");
        reader.save(chats, true);
        compare(makeStore(dir).loadAll().length, 2, "saving works again");
    }

    // index.ini.bak follows each successful index save and stands in for a damaged index.
    function test_backup_index_is_used_when_the_index_is_damaged() {
        var dir = freshDir();
        var s = makeStore(dir);
        s.save([chat("a", "A", ["one"])], true);
        compare(JSON.parse(s._read("index.ini.bak", "sessions"))[0].value, "a");
        s.save([chat("a", "A", ["one"]), chat("b", "B", ["two"])], true);
        compare(JSON.parse(s._read("index.ini.bak", "sessions")).length, 2, "the backup follows the index");
        s._write("index.ini", "sessions", "[{truncated");

        var reader = makeStore(dir);
        var loaded = reader.loadAll();
        compare(loaded.length, 2);
        compare(loaded[1].messages[0].content, "two");
        verify(reader.recoveredFromBackup);
        compare(reader.indexProblem, "");
        compare(keptCopies()[0].payload.file, "index.ini", "the damaged index is kept");
        reader.save(loaded, true);
        compare(JSON.parse(reader._read("index.ini", "sessions")).length, 2, "the next save repairs index.ini");
    }
}
