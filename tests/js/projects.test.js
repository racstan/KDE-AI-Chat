// Tests for chat/Projects.js and the project layer of chat/EffectiveConfig.js,
// run by tests/test_projects.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

function load(file, names) {
    const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat", file), "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/m, "");
    const ctx = {};
    vm.runInNewContext(src + "\nthis.exports = {" + names.join(", ") + "};", ctx);
    return ctx.exports;
}

const P = load("Projects.js", ["COLORS", "makeId", "normalize", "normalizeOne", "byId", "ofChat", "inView", "filterChats",
                               "counts", "workspaceFor", "instructionsBlock", "instructionsFor", "releaseChats", "returnChats"]);
const E = load("EffectiveConfig.js", ["resolve", "forSession"]);
const plain = x => JSON.parse(JSON.stringify(x));

const models = {openai: "gpt-main", nvidia: "nemotron-main"};
const main = {provider: "openai", openCodeProvider: "opencode", openCodeModel: "zen-x", piProvider: "ollama", piModel: "qwen",
              modelFor: id => models[id] || "", variantFor: () => ""};
const project = {id: "p-1", name: "Work", provider: "nvidia", model: "nemotron-proj"};
const on = priority => ({perChat: true, priority});

const tests = {
    normalize_fills_every_field_and_drops_bad_entries() {
        const list = P.normalize(JSON.stringify([
            {id: "p-1", name: "  Work   stuff ", color: "#ABCDEF", instructions: "Be brief", folder: " /tmp/x ", provider: "nvidia", model: "m", extra: 1},
            {id: "p-1", name: "duplicate"},
            {id: "../evil", name: "bad id"},
            null, "x",
            {id: "p-2", color: "red", model: "orphan model"}
        ]));
        assert.deepStrictEqual(plain(list), [
            {id: "p-1", name: "Work stuff", color: "#abcdef", instructions: "Be brief", folder: "/tmp/x", provider: "nvidia", model: "m", createdAt: 0},
            {id: "p-2", name: "Project", color: P.COLORS[0], instructions: "", folder: "", provider: "", model: "", createdAt: 0}
        ]);
        assert.deepStrictEqual(plain(P.normalize("not json")), []);
        assert.deepStrictEqual(plain(P.normalize("")), []);
        assert.deepStrictEqual(plain(P.normalize({})), []);
        assert.ok(/^p-\d+-\d+$/.test(P.makeId()));
        assert.strictEqual(P.makeId(5, 7), "p-5-7");
    },

    chats_without_a_project_load_unchanged_in_no_project() {
        const old = {value: "s-1", text: "Old chat", archived: false};
        assert.strictEqual(P.ofChat([project], old), null);
        assert.strictEqual(P.ofChat([project], {projectId: "p-gone"}), null, "a deleted project counts as none");
        assert.strictEqual(P.ofChat([project], {projectId: "p-1"}).name, "Work");
        assert.ok(P.inView(old, "all"));
        assert.ok(!P.inView(old, "p-1"));
        assert.ok(!P.inView(old, "archived"));
    },

    views_filter_the_history() {
        const chats = [
            {value: "a", projectId: "p-1"},
            {value: "b"},
            {value: "c", projectId: "p-1", archived: true},
            {value: "d", archived: true},
            {value: "e", projectId: "p-2"}
        ];
        const ids = view => P.filterChats(chats, view).map(c => c.value).join(",");
        assert.strictEqual(ids("all"), "a,b,e", "All chats: everything that isn't archived");
        assert.strictEqual(ids(""), "a,b,e");
        assert.strictEqual(ids("p-1"), "a", "a project: its chats that aren't archived");
        assert.strictEqual(ids("archived"), "c,d", "Archived: every archived chat, in a project or not");
        assert.deepStrictEqual(plain(P.counts(chats)), {all: 3, archived: 2, "p-1": 1, "p-2": 1});
    },

    the_chats_own_folder_wins_then_the_project() {
        const proj = {folder: "/home/u/proj"};
        assert.deepStrictEqual(plain(P.workspaceFor({openCodeWorkspaceCwd: "/own"}, proj)), {path: "/own", from: "chat"});
        assert.deepStrictEqual(plain(P.workspaceFor({openCodeWorkspaceCwd: ""}, proj)), {path: "/home/u/proj", from: "project"});
        assert.deepStrictEqual(plain(P.workspaceFor({openCodeWorkspaceCwd: "", keepOwnFolder: true}, proj)), {path: "", from: ""},
                               "an agent chat moved in with history keeps its own folder");
        assert.deepStrictEqual(plain(P.workspaceFor({}, null)), {path: "", from: ""});
        assert.deepStrictEqual(plain(P.workspaceFor({}, {folder: ""})), {path: "", from: ""});
    },

    instructions_come_from_the_project_then_the_chat() {
        const proj = {name: "Work", instructions: "Answer in French."};
        assert.strictEqual(P.instructionsBlock(proj), "--- Project instructions (Work) ---\nAnswer in French.\n--- End project instructions ---");
        assert.strictEqual(P.instructionsBlock({name: "x", instructions: "  "}), "");
        assert.strictEqual(P.instructionsBlock(null), "");
        const both = P.instructionsFor({chatSystemPrompt: "Be short."}, proj);
        assert.ok(both.indexOf("Answer in French.") < both.indexOf("Be short."));
        assert.strictEqual(P.instructionsFor({chatSystemPrompt: "Be short.", chatSystemPromptEnabled: false}, proj), P.instructionsBlock(proj));
        assert.strictEqual(P.instructionsFor({}, null), "");
    },

    deleting_a_project_moves_its_chats_to_no_project_and_undo_brings_them_back() {
        const chats = [{value: "a", projectId: "p-1"}, {value: "b"}, {value: "c", projectId: "p-1", archived: true}];
        const r = P.releaseChats(chats, "p-1");
        assert.deepStrictEqual(plain(r.moved), ["a", "c"]);
        assert.ok(r.chats.every(c => !c.projectId));
        assert.strictEqual(chats[0].projectId, "p-1", "the old list is not changed");
        const back = P.returnChats(r.chats, "p-1", r.moved);
        assert.deepStrictEqual(plain(back.map(c => c.projectId || "")), ["p-1", "", "p-1"]);
        // A chat moved elsewhere meanwhile stays where it is.
        const moved = r.chats.map(c => c.value === "a" ? Object.assign({}, c, {projectId: "p-9"}) : c);
        assert.strictEqual(P.returnChats(moved, "p-1", r.moved)[0].projectId, "p-9");
    },

    project_model_stands_in_for_the_main_settings_in_direct_chats() {
        const chat = {value: "s", source: "provider", projectId: "p-1"};
        const r = E.resolve(main, chat, {perChat: false}, project);
        assert.strictEqual(r.provider, "nvidia");
        assert.strictEqual(r.model, "nemotron-proj");
        assert.strictEqual(r.source, "project");
        assert.strictEqual(r.direct.provider, "nvidia");
        // Without a model, the project's provider uses that provider's configured model.
        const r2 = E.resolve(main, chat, {perChat: false}, {provider: "nvidia", model: ""});
        assert.strictEqual(r2.model, "nemotron-main");
        assert.strictEqual(r2.source, "project");
        // A project without provider changes nothing.
        const r3 = E.resolve(main, chat, {perChat: false}, {provider: "", model: "ignored"});
        assert.strictEqual(r3.provider, "openai");
        assert.strictEqual(r3.model, "gpt-main");
        assert.strictEqual(r3.source, "main");
    },

    the_chats_own_settings_beat_the_project() {
        const chat = {value: "s", source: "provider", ownModel: true, chatProvider: "openai", chatModel: "gpt-own"};
        const r = E.resolve(main, chat, on("chat"), project);
        assert.strictEqual(r.provider, "openai");
        assert.strictEqual(r.model, "gpt-own");
        assert.strictEqual(r.source, "chat");
        // "Main settings win": the project is the main side for its chats.
        const m = E.resolve(main, chat, on("main"), project);
        assert.strictEqual(m.provider, "nvidia");
        assert.strictEqual(m.model, "nemotron-proj");
        assert.strictEqual(m.source, "project");
        // A chat model with no provider of its own fills the project provider's empty model.
        const partial = {value: "s", source: "provider", ownModel: true, chatModel: "only-model"};
        const p = E.resolve(main, partial, on("chat"), {provider: "nvidia", model: ""});
        assert.strictEqual(p.provider, "nvidia");
        assert.strictEqual(p.model, "only-model");
    },

    a_project_never_changes_a_chats_mode() {
        for (const source of ["provider", "opencode", "pi"]) {
            const chat = {value: "s", source, projectId: "p-1"};
            for (const m of [main, Object.assign({}, main, {useOpenCode: true}), Object.assign({}, main, {usePi: true})])
                assert.strictEqual(E.resolve(m, chat, {perChat: true, priority: "chat"}, project).mode, source);
        }
        // OpenCode and Pi chats keep their own provider lists.
        const oc = E.resolve(main, {source: "opencode"}, {perChat: false}, project);
        assert.strictEqual(oc.provider, "opencode");
        assert.strictEqual(oc.model, "zen-x");
        assert.strictEqual(oc.source, "main");
        const pi = E.resolve(main, {source: "pi"}, {perChat: false}, project);
        assert.strictEqual(pi.provider, "ollama");
        assert.strictEqual(pi.source, "main");
    },

    for_session_passes_the_project_through() {
        const config = {provider: "openai", perChatModelSettings: false};
        const r = E.forSession(config, {value: "s", source: "provider"}, id => models[id] || "", () => "", project);
        assert.strictEqual(r.provider, "nvidia");
        assert.strictEqual(r.model, "nemotron-proj");
        const none = E.forSession(config, {value: "s", source: "provider"}, id => models[id] || "", () => "");
        assert.strictEqual(none.provider, "openai");
        assert.strictEqual(none.source, "main");
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try {
        fn();
        console.log("ok   " + name);
    } catch (e) {
        failed++;
        console.log("FAIL " + name + "\n" + e.stack);
    }
}
process.exit(failed ? 1 : 0);
