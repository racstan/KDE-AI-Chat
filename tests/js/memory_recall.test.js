// Tests for chat/MemoryRecall.js, run by tests/test_memory_recall.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/MemoryRecall.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {tokenize, applicable, queryFor, scores, recall, block, line, DEFAULT_BUDGET, HEADING};", ctx);
const R = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));

let n = 0;
const mem = (text, extra) => Object.assign({id: "m-" + String(++n).padStart(16, "0"), text, scope: "all", projectId: "", chatId: "",
                                            pinned: false, enabled: true, created: 1000 + n}, extra || {});

const tests = {
    tokenize_lowercases_drops_stopwords_and_plurals() {
        assert.deepStrictEqual(plain(R.tokenize("I'm using the Projects, and my DOG's name is Rex!")),
                               ["project", "dog", "name", "rex"]);
        assert.deepStrictEqual(plain(R.tokenize("")), []);
        assert.deepStrictEqual(plain(R.tokenize(null)), []);
        assert.deepStrictEqual(plain(R.tokenize("glass über-café")), ["glass", "über", "café"]);
    },

    applicable_follows_scope_and_enabled() {
        const all = mem("all"), off = mem("off", {enabled: false});
        const proj = mem("proj", {scope: "project", projectId: "p-1"}), other = mem("other", {scope: "project", projectId: "p-2"});
        const mine = mem("mine", {scope: "chat", chatId: "s-1"}), theirs = mem("theirs", {scope: "chat", chatId: "s-2"});
        const list = [all, off, proj, other, mine, theirs, mem("  ", {}), null, mem("odd", {scope: "galaxy"})];
        assert.deepStrictEqual(R.applicable(list, {id: "s-1", projectId: "p-1"}).map(m => m.text), ["all", "proj", "mine"]);
        assert.deepStrictEqual(R.applicable(list, {id: "s-3", projectId: ""}).map(m => m.text), ["all"]);
        assert.deepStrictEqual(R.applicable(list, null).map(m => m.text), ["all"]);
    },

    query_is_the_last_three_messages() {
        const messages = [{content: "one"}, {content: "two"}, {content: [{type: "image"}]}, {content: "four"}, {content: "five"}];
        assert.strictEqual(R.queryFor(messages), "four\nfive");
        assert.strictEqual(R.queryFor(messages, 5), "one\ntwo\nfour\nfive");
        assert.strictEqual(R.queryFor([]), "");
        assert.strictEqual(R.queryFor([{content: "x".repeat(5000)}]).length, 2000);
    },

    bm25_prefers_rare_terms_and_shorter_memories() {
        const list = [mem("I like python and rust"), mem("python python everywhere"), mem("my cat is called Tom"),
                      mem("python is used at work, a long note about many unrelated things like gardening and cooking")];
        const s = R.scores(list, "Which python version for rust?");
        assert.ok(s[0] > s[1], "two query terms beat one");
        assert.strictEqual(s[2], 0);
        assert.ok(s[1] > s[3], "the shorter note scores higher");
    },

    recall_sends_pinned_first_then_best_matches() {
        const pinned = mem("Answer in British English", {pinned: true});
        const dog = mem("My dog is called Rex");
        const tea = mem("I drink green tea");
        const both = mem("Rex the dog likes green tea");
        const r = R.recall([dog, tea, pinned, both], "What should I feed my dog Rex?");
        assert.deepStrictEqual(plain(r.ids), [pinned.id, dog.id, both.id]);
        assert.strictEqual(r.block, R.HEADING + "\n- Answer in British English\n- My dog is called Rex\n- Rex the dog likes green tea");
        const none = R.recall([dog, tea], "hello there");
        assert.deepStrictEqual(plain(none.ids), []);
        assert.strictEqual(none.block, "");
        assert.strictEqual(R.recall([], "x").block, "");
    },

    recall_is_deterministic() {
        const list = [mem("alpha beta"), mem("beta alpha"), mem("alpha"), mem("beta gamma", {pinned: true})];
        const first = plain(R.recall(list, "alpha beta"));
        for (let i = 0; i < 5; i++)
            assert.deepStrictEqual(plain(R.recall(list.slice().reverse(), "alpha beta")), first);
        // Equal scores: the older one first.
        assert.deepStrictEqual(first.ids.slice(0, 3), [list[3].id, list[0].id, list[1].id]);
    },

    recall_keeps_within_the_budget_dropping_lowest_scores() {
        const long = mem("rust " + "x".repeat(300));
        const best = mem("rust rust cargo");
        const pinned = mem("p".repeat(100), {pinned: true});
        const r = R.recall([long, best, pinned], "rust cargo", 200);
        assert.deepStrictEqual(plain(r.ids), [pinned.id, best.id]);
        assert.ok(r.block.length <= 200);
        // A memory too big for what is left is skipped, smaller ones still go.
        const r2 = R.recall([mem("rust " + "y".repeat(3000)), mem("rust small")], "rust");
        assert.deepStrictEqual(plain(r2.memories.map(m => m.text)), ["rust small"]);
        assert.ok(R.recall([pinned], "", 0).ids.length === 0);
        const big = R.recall(Array.from({length: 60}, (_, i) => mem("rust note number " + i + " " + "z".repeat(40))), "rust");
        assert.ok(big.block.length <= R.DEFAULT_BUDGET, "default budget " + big.block.length);
        assert.ok(big.ids.length > 10);
    },

    multi_line_memories_stay_one_item() {
        assert.strictEqual(R.line({text: " first\nsecond "}), "- first\n  second");
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
