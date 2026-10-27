// Tests for chat/Starters.js, run by tests/test_starters_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/Starters.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.S = {pick, dayPart, allIds, pickTemplates};", ctx);
const S = ctx.S;
const j = (x) => JSON.stringify(x);
const tpl = (n) => Array.from({length: n}, (_, i) => ({name: "T" + i, prompt: "p" + i}));
const base = {mode: "provider", templates: [], seed: "chat-1", hour: 14, sessions: [], currentId: "chat-1"};
const ids = (chips) => chips.filter(c => c.kind === "builtin").map(c => c.id);

// Fills to six from the pool with no templates; no duplicates.
let chips = S.pick(base);
assert.strictEqual(chips.length, 6);
assert.strictEqual(new Set(ids(chips)).size, 6);

// Templates first, capped at three, and the rest filled.
chips = S.pick(Object.assign({}, base, {templates: tpl(2)}));
assert.strictEqual(j(chips.slice(0, 2).map(c => c.name)), j(["T0", "T1"]));
assert.strictEqual(chips.length, 6);
chips = S.pick(Object.assign({}, base, {templates: tpl(10)}));
assert.strictEqual(chips.filter(c => c.kind === "template").length, 3);
assert.strictEqual(chips.slice(0, 3).every(c => c.kind === "template"), true);
assert.strictEqual(chips.length, 6);
// Templates rotate with the seed (three consecutive ones).
const starts = new Set();
for (let i = 0; i < 40; i++)
    starts.add(S.pickTemplates(tpl(10), "id" + i).map(t => t.name)[0]);
assert.ok(starts.size > 3, "rotation reaches many templates");
const w = S.pickTemplates(tpl(5), "x").map(t => Number(t.name.slice(1)));
assert.strictEqual((w[1] - w[0] + 5) % 5, 1);
// Templates without a name are skipped.
assert.strictEqual(S.pickTemplates([{name: "", prompt: "x"}, null], "s").length, 0);

// Stable for one chat id, different across ids.
assert.strictEqual(j(S.pick(base)), j(S.pick(Object.assign({}, base))));
const seen = new Set();
for (let i = 0; i < 20; i++)
    seen.add(j(ids(S.pick(Object.assign({}, base, {seed: "chat-" + i})))));
assert.ok(seen.size >= 10, "chats get different chips: " + seen.size);

// Mode pools: agent modes never get everyday tasks and vice versa.
const agent = new Set(S.allIds("pi"));
const direct = new Set(S.allIds("provider"));
for (const id of agent) assert.ok(!direct.has(id), id);
for (const mode of ["opencode", "pi"])
    for (let i = 0; i < 10; i++)
        for (const id of ids(S.pick(Object.assign({}, base, {mode, seed: "s" + i}))))
            assert.ok(agent.has(id), mode + " " + id);
for (let i = 0; i < 10; i++)
    for (const id of ids(S.pick(Object.assign({}, base, {seed: "s" + i}))))
        assert.ok(direct.has(id), id);
assert.ok(agent.size + direct.size >= 24, "pool of about 24 or more");

// Time of day.
assert.strictEqual(S.dayPart(8), "morning");
assert.strictEqual(S.dayPart(14), "");
assert.strictEqual(S.dayPart(20), "evening");
assert.strictEqual(S.dayPart(2), "");
assert.strictEqual(ids(S.pick(Object.assign({}, base, {hour: 8})))[0], "planday");
assert.strictEqual(ids(S.pick(Object.assign({}, base, {hour: 20})))[0], "reflect");
assert.strictEqual(ids(S.pick(Object.assign({}, base, {hour: 8, mode: "pi"})))[0], "standup");
assert.strictEqual(ids(S.pick(Object.assign({}, base, {hour: 20, mode: "opencode"})))[0], "wrapup");

// Continue chip: latest other, unarchived, titled chat; counts toward six.
const sessions = [
    {value: "chat-1", text: "This one", updatedAt: 99},
    {value: "a", text: "Old", updatedAt: 1},
    {value: "b", text: "Newest", updatedAt: 50},
    {value: "c", text: "Archived", updatedAt: 90, archived: true},
    {value: "d", text: "", updatedAt: 80}
];
chips = S.pick(Object.assign({}, base, {sessions, templates: tpl(1)}));
assert.strictEqual(j(chips[1]), j({kind: "continue", id: "b", title: "Newest"}));
assert.strictEqual(chips.length, 6);
chips = S.pick(Object.assign({}, base, {sessions: [sessions[0]]}));
assert.ok(!chips.some(c => c.kind === "continue"));
console.log("starters ok");
