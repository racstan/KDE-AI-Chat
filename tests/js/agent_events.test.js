// Tests for backends/AgentEvents.js, run by tests/test_agent_events.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/backends/AgentEvents.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {isReplyEvent, applyToReply, contextItems, permissionMessage, questionMessage};", ctx);
const AE = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));

const tests = {
    tools_files_and_notices_build_the_reply() {
        const reply = {};
        for (const e of [
            {type: "tool_start", callId: "c1", name: "write", input: {path: "hello.txt", content: "x".repeat(9000)}},
            {type: "notice", message: "Retrying", level: "warning"},
            {type: "tool_end", callId: "c1", title: "", output: "Wrote it", isError: false},
            {type: "file_changed", path: "hello.txt"},
            {type: "file_changed", path: "hello.txt"},
            {type: "tool_start", callId: "c2", name: "bash", input: {command: "rm -rf x"}},
            {type: "tool_end", callId: "c2", title: "", output: "Blocked", isError: true},
        ]) {
            assert.ok(AE.isReplyEvent(e.type));
            AE.applyToReply(reply, e);
        }
        const r = plain(reply);
        assert.deepStrictEqual(r.contextItems, ["⚠ Retrying", "✓ write: hello.txt", "✗ bash: rm -rf x", "📝 hello.txt"]);
        assert.strictEqual(r.tools.c1.output, "Wrote it");
        assert.strictEqual(r.tools.c1.input.length, 4000, "tool input is capped");
        assert.strictEqual(r.tools.c2.status, "error");
        assert.deepStrictEqual(r.filesChanged, ["hello.txt"]);
        assert.ok(!AE.isReplyEvent("text_delta"));
    },

    permission_cards_name_the_agent() {
        const oc = plain(AE.permissionMessage({id: "per_1", permission: "edit", patterns: ["a.txt"]}, {directory: "/w"}, 5));
        assert.deepStrictEqual(oc, {role: "permission_request", status: "pending", at: 5, model: "OpenCode", harness: "opencode",
                                    openCodeDirectory: "/w", harnessChatId: "", permissionId: "per_1", id: "perm-per_1", tool: "edit",
                                    arguments: ["a.txt"], canAlways: true,
                                    content: "OpenCode asks for permission: **edit**\n\n```\na.txt\n```"});
        const pi = plain(AE.permissionMessage({id: "d1", permission: "Clear?", patterns: []}, {harness: "pi", chatId: "s-1"}, 5));
        assert.strictEqual(pi.model, "Pi");
        assert.strictEqual(pi.canAlways, false);
        assert.strictEqual(pi.harnessChatId, "s-1");
        assert.strictEqual(pi.content, "Pi asks for permission: **Clear?**");
    },

    question_cards() {
        const q = plain(AE.questionMessage({id: "q1", questions: [
            {header: "Pick", question: "Which?", options: [{label: "A", description: "first"}, {label: "B"}], custom: false},
        ]}, {harness: "pi", chatId: "s-1"}, 7));
        assert.strictEqual(q.id, "question-q1");
        assert.strictEqual(q.questionId, "q1");
        assert.strictEqual(q.allowCustom, false);
        assert.deepStrictEqual(q.questions[0].options, [{label: "A", description: "first"}, {label: "B", description: ""}]);
        assert.strictEqual(q.content, "Pi is asking:\n\n**Pick**: Which?");
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + String(e.stack || e).split("\n").slice(0, 4).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
