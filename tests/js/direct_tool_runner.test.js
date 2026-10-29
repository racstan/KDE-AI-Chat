// Tests for chat/DirectToolRunner.js (run by tests/test_direct_tools.py).
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/DirectToolRunner.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {cutResult, approvalKey, needsApproval, argsLines, RESULT_LIMIT};", ctx);
const R = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));

const mcp = {kind: "mcp", server: "files", realName: "write", risk: "change"};
const mcpRead = {kind: "mcp", server: "files", realName: "read", risk: "read"};
const ws = {kind: "workspace", folder: "/home/me/p", realName: "write_file", risk: "change"};
const wsRead = {kind: "workspace", folder: "/home/me/p", realName: "read_file", risk: "read"};

const tests = {
    short_results_pass_unchanged() {
        assert.strictEqual(R.cutResult("hello"), "hello");
        assert.strictEqual(R.cutResult(undefined), "");
        assert.strictEqual(R.cutResult({a: 1}), '{"a":1}');
        assert.strictEqual(R.cutResult("x".repeat(R.RESULT_LIMIT)).length, R.RESULT_LIMIT);
    },

    long_results_are_cut_with_a_note() {
        const out = R.cutResult("x".repeat(R.RESULT_LIMIT + 500));
        assert.ok(out.startsWith("x".repeat(R.RESULT_LIMIT) + "\n"));
        assert.ok(out.includes("The result was cut"));
        assert.ok(out.includes(String(R.RESULT_LIMIT + 500)));
        assert.strictEqual(R.cutResult("abcdef", 3).indexOf("abc\n"), 0);
    },

    approval_keys() {
        assert.strictEqual(R.approvalKey(mcp), "mcp:files:write");
        assert.strictEqual(R.approvalKey(ws), "workspace:/home/me/p:write_file");
        assert.strictEqual(R.approvalKey({kind: "skill", realName: "load_skill"}), "skill:load_skill");
        assert.strictEqual(R.approvalKey({kind: "workspace", realName: "x"}), "", "no folder, nothing to remember");
        assert.strictEqual(R.approvalKey({kind: "other", realName: "x"}), "");
        assert.strictEqual(R.approvalKey({kind: "other", realName: "x", approvalKey: "skill:y"}), "skill:y");
        assert.strictEqual(R.approvalKey(null), "");
    },

    what_asks_first() {
        assert.strictEqual(R.needsApproval(wsRead, []), false);
        assert.strictEqual(R.needsApproval({kind: "skill", risk: "read", realName: "a"}, []), false);
        assert.strictEqual(R.needsApproval(ws, []), true);
        assert.strictEqual(R.needsApproval(mcp, []), true);
        assert.strictEqual(R.needsApproval(mcpRead, []), true, "every MCP tool asks until always-allowed");
        assert.strictEqual(R.needsApproval(mcpRead, ["mcp:files:read"]), false);
        assert.strictEqual(R.needsApproval(mcp, ["mcp:files:read"]), true, "another tool's approval doesn't count");
        assert.strictEqual(R.needsApproval(ws, ["workspace:/home/me/p:write_file"]), false);
        assert.strictEqual(R.needsApproval(ws, ["workspace:/other:write_file"]), true);
        assert.strictEqual(R.needsApproval({kind: "other", risk: "change", realName: "z"}, ["x"]), true, "a change tool with no key always asks");
    },

    arguments_are_one_line_when_short_and_cut_when_huge() {
        assert.deepStrictEqual(plain(R.argsLines({})), []);
        assert.deepStrictEqual(plain(R.argsLines(null)), []);
        assert.deepStrictEqual(plain(R.argsLines({path: "a.txt"})), ['{"path":"a.txt"}']);
        const mid = plain(R.argsLines({text: "y".repeat(300)}));
        assert.strictEqual(mid.length, 1);
        assert.ok(mid[0].includes("\n"), "indented");
        const big = plain(R.argsLines({text: "z".repeat(9000)}));
        assert.ok(big[0].length < 4100 && big[0].endsWith("..."));
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + (e.stack || e).toString().split("\n").slice(0, 4).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
