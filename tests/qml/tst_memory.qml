// Memories: store/MemoryStore.qml against a stand-in for the helper's memory
// commands (kdeaichat/memory.py), chat/Memory.qml choosing what goes with a
// request in each mode, memories leaving with their chat or project (and
// coming back on Undo), and store/MemoryMigration.qml moving old memory.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

Item {
    id: root

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    // The helper's memory commands, in memory. dropAdds: answers as if the
    // write had not happened (for the migration's check).
    QtObject {
        id: helper
        property var memories: []
        property var calls: []
        property int counter: 0
        property bool dropAdds: false
        property bool fail: false

        function key(m) {
            return [String(m.text).split(/\s+/).join(" ").trim().toLowerCase(), m.scope || "all", m.projectId || "", m.chatId || ""].join("|");
        }

        function run(command, payload, onDone) {
            calls = calls.concat([{command: command, payload: payload}]);
            if (fail) { onDone("Error executing " + command, 1, ""); return; }
            var list = memories.slice();
            var out = {};
            if (command === "memory_add") {
                var added = [], existing = [];
                payload.items.forEach(function(item) {
                    var m = {id: item.id || ("m-" + String(++helper.counter).padStart(16, "0")), text: String(item.text).trim(),
                             scope: item.scope || "all", projectId: item.scope === "project" ? item.projectId : "",
                             chatId: item.scope === "chat" ? item.chatId : "", pinned: item.pinned === true,
                             enabled: item.enabled !== false, created: item.created || helper.counter, sourceChatId: item.sourceChatId || ""};
                    var same = list.filter(function(x) { return helper.key(x) === helper.key(m); })[0];
                    if (same) { existing.push(same.id); return; }
                    list.push(m);
                    added.push(m.id);
                });
                out = {added: added, existing: existing};
                if (!dropAdds)
                    memories = list;
            } else if (command === "memory_update") {
                memories = list.map(function(m) { return m.id === payload.id ? Object.assign({}, m, payload) : m; });
            } else if (command === "memory_delete") {
                var gone = function(m) {
                    return (payload.ids || []).indexOf(m.id) >= 0 || (m.scope === "chat" && (payload.chatIds || []).indexOf(m.chatId) >= 0)
                        || (m.scope === "project" && (payload.projectIds || []).indexOf(m.projectId) >= 0);
                };
                out = {deleted: list.filter(gone)};
                memories = list.filter(function(m) { return !gone(m); });
            }
            out.memories = command === "memory_add" && dropAdds ? memories : memories;
            var text = JSON.stringify(out);
            Qt.callLater(function() { onDone(text, 0, ""); });
        }
    }

    QtObject {
        id: config
        property bool memoryEnabled: true
        property int memoryBudget: 2000
        property bool enableSystemPrompt: true
        property string provider: "openai"
        property string providersJson: "[]"
        property bool perChatModelSettings: false
        property string userMemory: ""
        property bool enableMemory: false
    }

    FakeChat {
        id: chat
        plasmoid: ({configuration: config})
        property string compiledSystemPrompt: "Main instructions."
        function buildEffectiveSystemPrompt(id) { return direct.buildEffectiveSystemPrompt(id); }
        function buildMessageContent(text) { return text; }
    }

    Store.MemoryStore {
        id: store
        configuration: config
        runHelper: helper.run
    }

    Store.MemoryMigration {
        id: migration
        configuration: config
        memoryStore: store
    }

    Chat.DirectRequest { id: direct; chat: chat }
    Chat.PiMode { id: pi; chat: chat }

    TestCase {
        name: "Memory"
        when: windowShown

        function waitIdle() {
            tryVerify(function() { return !store._busy && store._queue.length === 0; });
        }

        function addAll(items) {
            var done = false;
            store.addMany(items, function() { done = true; });
            tryVerify(function() { return done; });
        }

        function init() {
            config.memoryBudget = 2000;
            helper.memories = [];
            helper.calls = [];
            helper.dropAdds = false;
            helper.fail = false;
            config.memoryEnabled = true;
            config.userMemory = "";
            config.enableMemory = false;
            chat.memoryStore = store;
            chat.projects.list = [{id: "p-work", name: "Work", color: "#1cdc9a", instructions: "", folder: "", provider: "", model: ""}];
            chat.currentSessionId = "a";
            chat.messages = [{role: "user", content: "What should I feed my dog?"}];
            chat.sessions = [
                {value: "a", text: "Pets", source: "provider", projectId: "p-work"},
                {value: "b", text: "Other", source: "provider", projectId: ""},
                {value: "p", text: "Pi chat", source: "pi", projectId: "", messages: [{role: "user", content: "dog food"}]}
            ];
            store.load();
            waitIdle();
        }

        function test_store_adds_updates_and_removes() {
            addAll([{text: "My dog is called Rex", scope: "all"}, {text: "Use metric units", scope: "all"}]);
            compare(store.list.length, 2);
            var id = store.list[0].id;
            store.setPinned(id, true);
            store.setEnabled(id, false);
            waitIdle();
            compare(store.byId(id).pinned, true);
            compare(store.byId(id).enabled, false);
            store.update(id, {text: "My dog is Rex"});
            waitIdle();
            compare(store.byId(id).text, "My dog is Rex");
            store.remove(id);
            waitIdle();
            compare(store.list.length, 1);
            // One command at a time, in order.
            compare(helper.calls.map(function(c) { return c.command; }).join(","),
                    "memory_list,memory_add,memory_update,memory_update,memory_update,memory_delete");
        }

        function test_large_imports_go_in_batches() {
            var items = [];
            for (var i = 0; i < 120; i++)
                items.push({text: "note " + i + " " + "x".repeat(900), scope: "all"});
            addAll(items);
            compare(store.list.length, 120);
            var adds = helper.calls.filter(function(c) { return c.command === "memory_add"; });
            verify(adds.length >= 3, "batches: " + adds.length);
            adds.forEach(function(c) { verify(JSON.stringify(c.payload).length <= 45000); });
        }

        function test_a_failed_command_keeps_the_list() {
            addAll([{text: "kept", scope: "all"}]);
            helper.fail = true;
            store.remove(store.list[0].id);
            waitIdle();
            compare(store.list.length, 1);
            verify(store.lastError !== "");
        }

        function test_direct_and_opencode_get_matching_memories_in_the_system_prompt() {
            addAll([{text: "My dog is called Rex", scope: "all"}, {text: "Answer in British English", scope: "all", pinned: true},
                    {text: "Rex eats dog kibble", scope: "project", projectId: "p-work"},
                    {text: "The dog is a husky", scope: "chat", chatId: "b"},
                    {text: "dog walking schedule", scope: "all", enabled: false},
                    {text: "Tea is nice", scope: "all"}]);
            var prompt = direct.buildEffectiveSystemPrompt("a");
            var block = "## Things the user asked you to remember\n- Answer in British English\n";
            verify(prompt.indexOf("Main instructions.") === 0, prompt);
            verify(prompt.indexOf(block) > 0, prompt);
            verify(prompt.indexOf("Rex eats dog kibble") > 0, "the project's memory");
            verify(prompt.indexOf("My dog is called Rex") > 0);
            verify(prompt.indexOf("husky") < 0, "another chat's memory");
            verify(prompt.indexOf("walking") < 0, "a memory that is off");
            verify(prompt.indexOf("Tea") < 0, "not relevant");
            // The ids sent are kept on the chat.
            var used = chat.getSessionProperty("a", "memoryUsedIds", []);
            compare(used.length, 3);
            compare(used[0], store.list[1].id, "pinned first");
        }

        function test_pi_gets_memories_in_its_instructions() {
            addAll([{text: "My dog is called Rex", scope: "all"}]);
            var body = pi.promptBody("p", {content: "dog food"});
            compare(body.instructions, "## Things the user asked you to remember\n- My dog is called Rex");
            compare(chat.getSessionProperty("p", "memoryUsedIds", []).length, 1);
        }

        function test_off_switches_send_nothing() {
            addAll([{text: "My dog is called Rex", scope: "all", pinned: true}]);
            verify(direct.buildEffectiveSystemPrompt("a").indexOf("Rex") > 0);
            chat.setSessionProperty("a", "memoryOff", true);
            compare(direct.buildEffectiveSystemPrompt("a"), "Main instructions.", "this chat has memory off");
            compare(chat.getSessionProperty("a", "memoryUsedIds", null).length, 0, "nothing recorded as used");
            verify(direct.buildEffectiveSystemPrompt("b").indexOf("Rex") > 0, "other chats still get it");
            store.setGlobalEnabled(false);
            compare(config.memoryEnabled, false);
            compare(direct.buildEffectiveSystemPrompt("b"), "Main instructions.", "memory off everywhere");
            compare(pi.promptBody("p", {content: "dog"}).instructions, "");
        }

        function test_the_size_per_message_follows_the_setting() {
            var long = "dog " + "x".repeat(2500);
            addAll([{text: long, scope: "all"}]);
            verify(direct.buildEffectiveSystemPrompt("a").indexOf(long) < 0, "too big for 2000");
            config.memoryBudget = 0;
            verify(direct.buildEffectiveSystemPrompt("a").indexOf(long) > 0, "no limit");
            config.memoryBudget = 5000;
            verify(direct.buildEffectiveSystemPrompt("a").indexOf(long) > 0, "fits in 5000");
            config.memoryBudget = 2000;
        }

        function test_memories_go_with_their_chat_and_project_and_come_back_on_undo() {
            addAll([{text: "all", scope: "all"}, {text: "chat b", scope: "chat", chatId: "b"},
                    {text: "project", scope: "project", projectId: "p-work"}]);
            var session = chat.sessions[1];
            chat.deleteSession("b");
            tryVerify(function() { return store.list.length === 2; });
            // Undo: the chat is back, so are its memories.
            chat.sessions = chat.sessions.concat([session]);
            tryVerify(function() { return store.list.length === 3; });
            verify(store.list.some(function(m) { return m.text === "chat b"; }));

            chat.projects.remove("p-work");
            tryVerify(function() { return store.list.length === 2; });
            verify(!store.list.some(function(m) { return m.scope === "project"; }));
        }

        function test_migration_moves_old_memory_once() {
            config.userMemory = "- I live in Pune\n\n* Prefer short answers\n1. Use metric units\n   ";
            config.enableMemory = false;
            var sessions = [{value: "a", chatMemory: "The project is due Friday", chatMemoryEnabled: false},
                            {value: "b", chatMemory: "• Call me Ana"},
                            {value: "c", chatMemoryEnabled: true},
                            {value: "d"}];
            var result = null;
            migration.migrate(sessions, function(changed, moved) { result = {changed: changed, moved: moved}; });
            tryVerify(function() { return result !== null; });
            compare(result.moved, 5);
            compare(result.changed, true);
            compare(store.list.map(function(m) { return m.text; }).join("|"),
                    "I live in Pune|Prefer short answers|Use metric units|The project is due Friday|Call me Ana");
            verify(store.list.slice(0, 3).every(function(m) { return m.scope === "all" && m.enabled === false; }), "memory was off");
            compare(store.list[3].scope, "chat");
            compare(store.list[3].chatId, "a");
            compare(store.list[3].enabled, false);
            compare(store.list[4].enabled, true);
            compare(store.list[4].sourceChatId, "b");
            compare(config.userMemory, "");
            verify(sessions.every(function(s) { return s.chatMemory === undefined && s.chatMemoryEnabled === undefined; }));
            compare(migration.notice, "Moved 5 remembered notes into the new memory list.");

            // Again (say the old copies had come back): nothing is added twice.
            config.userMemory = "I live in Pune";
            result = null;
            migration.migrate([{value: "b", chatMemory: "Call me Ana"}], function(changed, moved) { result = {changed: changed, moved: moved}; });
            tryVerify(function() { return result !== null; });
            compare(result.moved, 0);
            compare(store.list.length, 5);
            compare(config.userMemory, "");
        }

        function test_migration_keeps_old_memory_when_the_write_is_not_verified() {
            config.userMemory = "I live in Pune";
            config.enableMemory = true;
            var sessions = [{value: "a", chatMemory: "Due Friday"}];
            helper.dropAdds = true;
            var result = null;
            migration.migrate(sessions, function(changed, moved) { result = {changed: changed, moved: moved}; });
            tryVerify(function() { return result !== null; });
            compare(result.changed, false);
            compare(config.userMemory, "I live in Pune");
            compare(sessions[0].chatMemory, "Due Friday");
            helper.dropAdds = false;
            helper.fail = true;
            result = null;
            migration.migrate(sessions, function(changed, moved) { result = {changed: changed, moved: moved}; });
            tryVerify(function() { return result !== null; });
            compare(config.userMemory, "I live in Pune", "the helper failed");
            helper.fail = false;
            result = null;
            migration.migrate(sessions, function(changed, moved) { result = {changed: changed, moved: moved}; });
            tryVerify(function() { return result !== null; });
            compare(result.moved, 2);
            verify(store.list.every(function(m) { return m.enabled; }), "memory was on");
        }

        function test_migration_with_nothing_to_move_only_tidies() {
            var sessions = [{value: "a", chatMemory: "  ", chatMemoryEnabled: true}, {value: "b"}];
            var result = null;
            migration.migrate(sessions, function(changed, moved) { result = {changed: changed, moved: moved}; });
            tryVerify(function() { return result !== null; });
            compare(result.changed, true);
            compare(sessions[0].chatMemory, undefined);
            compare(helper.calls.filter(function(c) { return c.command === "memory_add"; }).length, 0);
        }
    }
}
