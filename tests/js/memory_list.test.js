// Tests for config/MemoryList.js (Settings → Memory's list), run by tests/test_memory_list.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/config/MemoryList.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {visible, sorted, disabledIds, chatTitles, projectNames, FILTERS};", ctx);
const L = ctx.exports;
const ids = list => Array.from(list, m => m.id);

const list = [
    {id: "a", text: "Prefers metric units", scope: "all", pinned: false, enabled: true, created: 1},
    {id: "b", text: "Project uses Qt 6", scope: "project", projectId: "p1", pinned: false, enabled: false, created: 3},
    {id: "c", text: "Call me Sam", scope: "chat", chatId: "c1", pinned: true, enabled: true, created: 2},
    {id: "d", text: "Likes tea", scope: "all", pinned: false, enabled: false, created: 4}
];

// Pinned first, then newest.
assert.deepStrictEqual(ids(L.visible(list, "", "any")), ["c", "d", "b", "a"]);
// Filters.
assert.deepStrictEqual(ids(L.visible(list, "", "all")), ["d", "a"]);
assert.deepStrictEqual(ids(L.visible(list, "", "project")), ["b"]);
assert.deepStrictEqual(ids(L.visible(list, "", "chat")), ["c"]);
assert.deepStrictEqual(ids(L.visible(list, "", "off")), ["d", "b"]);
// Search, case-insensitive, also in the names given.
assert.deepStrictEqual(ids(L.visible(list, "METRIC", "any")), ["a"]);
assert.deepStrictEqual(ids(L.visible(list, "trip", "any", m => m.chatId === "c1" ? "Chat “Trip”" : "")), ["c"]);
assert.deepStrictEqual(ids(L.visible(list, "tea", "chat")), []);
assert.deepStrictEqual(ids(L.visible(null, "", "any")), []);
// Turned-off ids.
assert.deepStrictEqual(Array.from(L.disabledIds(list)), ["b", "d"]);
// Names from the chats index and projects.ini.
assert.deepStrictEqual(JSON.parse(JSON.stringify(L.chatTitles(JSON.stringify([{value: "c1", text: "Trip"}, {text: "no id"}])))), {c1: "Trip"});
assert.deepStrictEqual(JSON.parse(JSON.stringify(L.chatTitles("not json"))), {});
assert.deepStrictEqual(JSON.parse(JSON.stringify(L.projectNames(JSON.stringify([{id: "p1", name: "Widget"}])))), {p1: "Widget"});
assert.deepStrictEqual(JSON.parse(JSON.stringify(L.projectNames(""))), {});
console.log("memory_list: ok");
