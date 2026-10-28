// Tests for chat/Activity.js, run by tests/test_activity.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/Activity.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.A = {thinkingChars, closeThinking, record, hasContent, items, summary, seconds};", ctx);
const A = ctx.A;
const plain = x => JSON.parse(JSON.stringify(x));

// Thinking, a tool, more thinking, a notice, built the way ReplyEvents.qml does.
let act = [];
act = A.closeThinking(act, "plan the work", 1000, 4000);
assert.deepStrictEqual(plain(act), [{kind: "thinking", text: "plan the work", ms: 3000}]);
assert.strictEqual(A.closeThinking(act, "plan the work", 0, 0), act, "nothing new: same list");
act = A.record(act, {type: "tool_start", callId: "c1", name: "read"}, {});
act = A.record(act, {type: "tool_start", callId: "c1", name: "read"}, {});
act = A.record(act, {type: "tool_end", callId: "c1"}, {});
assert.strictEqual(act.length, 2, "one entry per call, none for updates and ends");
act = A.closeThinking(act, "plan the workthen check", 5000, 5500);
act = A.record(act, {type: "notice", level: "warn", message: "slow"}, {notices: ["⚠ slow"]});
act = A.record(act, {type: "file_changed", path: "a.txt"}, {});
act = A.record(act, {type: "file_changed", path: "a.txt"}, {});
assert.deepStrictEqual(plain(act.map(e => e.kind)), ["thinking", "tool", "thinking", "notice", "file"]);
assert.strictEqual(act[2].text, "then check", "only the new thinking");
assert.strictEqual(act[2].ms, 500);
assert.strictEqual(A.thinkingChars(act), "plan the work".length + "then check".length);

const message = {activity: act, reasoning: "plan the workthen check", tools: {c1: {name: "read", status: "done"}}};
const list = plain(A.items(message));
assert.deepStrictEqual(list.map(i => i.kind), ["thinking", "tool", "thinking", "notice", "file"], "order kept");
assert.strictEqual(list[1].tool.name, "read");
assert.deepStrictEqual(plain(A.summary(list)), {ms: 3500, steps: 3, failed: 0, running: ""});

// Thinking in the message but not yet in the list (a cut-off reply) comes last.
const cut = A.items({activity: [], reasoning: "half a thought"});
assert.deepStrictEqual(plain(cut), [{kind: "thinking", text: "half a thought", ms: 0}]);

// A running and a failed tool.
const s = A.summary(A.items({activity: [{kind: "tool", id: "a"}, {kind: "tool", id: "b"}],
    tools: {a: {name: "bash", status: "error"}, b: {name: "grep", status: "running"}}}));
assert.deepStrictEqual(plain(s), {ms: 0, steps: 2, failed: 1, running: "grep"});

// Old messages (no activity): thinking, then notices, tools, files; or the summary lines.
const old = plain(A.items({reasoning: "hmm", tools: {t: {name: "read", status: "done"}}, notices: ["ℹ hi"], filesChanged: ["f.py"]}));
assert.deepStrictEqual(old.map(i => i.kind), ["thinking", "notice", "tool", "file"]);
const lines = plain(A.items({contextItems: ["✓ read", "📝 f.py"]}));
assert.deepStrictEqual(lines.map(i => i.kind + ":" + i.text), ["line:✓ read", "line:📝 f.py"]);
assert.deepStrictEqual(plain(A.items({content: "plain"})), []);

assert.strictEqual(A.hasContent({content: "x"}), false);
assert.strictEqual(A.hasContent({reasoning: "x"}), true);
assert.strictEqual(A.hasContent({activity: [{kind: "tool", id: "a"}]}), true);
assert.strictEqual(A.hasContent({contextItems: ["x"]}), true);
assert.strictEqual(A.seconds(200), 1);
assert.strictEqual(A.seconds(12400), 12);
console.log("PASS activity");
