// Tests for chat/ChatStats.js (the Chat info panel's totals), run by tests/test_chat_stats.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/ChatStats.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {summarize, formatCount, formatCost};", ctx);
const S = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));

const tests = {
    empty_chat_has_zero_totals_and_no_usage() {
        const s = plain(S.summarize([], {}));
        assert.strictEqual(s.messages, 0);
        assert.strictEqual(s.hasTokens, false);
        assert.strictEqual(s.hasCost, false);
        assert.deepStrictEqual(s.models, []);
        assert.strictEqual(s.createdAt, 0);
        assert.deepStrictEqual(plain(S.summarize(null, null)), s);
    },

    sums_cache_tokens_and_hides_them_when_never_reported() {
        const s = plain(S.summarize([
            {role: "assistant", content: "a", tokens: {input: 100, output: 5, cache: {read: 64, write: 0}}},
            {role: "assistant", content: "b", tokens: {input: 200, output: 5, cache: {read: 150, write: 30}}},
            {role: "assistant", content: "c", tokens: {input: 7, output: 1}},
        ], {}));
        assert.strictEqual(s.hasCache, true);
        assert.strictEqual(s.cacheRead, 214);
        assert.strictEqual(s.cacheWrite, 30);
        assert.strictEqual(plain(S.summarize([{role: "assistant", content: "a", tokens: {input: 1, output: 1}}], {})).hasCache, false);
    },

    sums_tokens_and_cost_from_the_replies() {
        const s = plain(S.summarize([
            {role: "user", content: "a", at: 1000},
            {role: "assistant", model: "gpt-4o", content: "b", at: 2000, tokens: {input: 30, output: 212}, cost: 0.001},
            {role: "user", content: "c", at: 3000},
            {role: "assistant", model: "gpt-4o", content: "d", at: 4000, tokens: {input: 260, output: 14}, cost: 0.0005},
            {role: "assistant", model: "claude", content: "e", at: 5000, tokens: {input: 5, output: 1}},
        ], {}));
        assert.strictEqual(s.messages, 5);
        assert.strictEqual(s.replies, 3);
        assert.strictEqual(s.repliesWithUsage, 3);
        assert.strictEqual(s.inputTokens, 295);
        assert.strictEqual(s.outputTokens, 227);
        assert.ok(s.hasCost);
        assert.ok(Math.abs(s.cost - 0.0015) < 1e-12);
        assert.deepStrictEqual(s.models, ["gpt-4o", "claude"]);
    },

    replies_without_usage_add_nothing_and_are_not_estimated() {
        const s = plain(S.summarize([
            {role: "assistant", model: "local", content: "x", at: 1},
            {role: "assistant", model: "local", content: "y", at: 2, tokens: {input: 10, output: 4}},
        ], {}));
        assert.strictEqual(s.replies, 2);
        assert.strictEqual(s.repliesWithUsage, 1);
        assert.strictEqual(s.inputTokens, 10);
        assert.strictEqual(s.outputTokens, 4);
        assert.strictEqual(s.hasCost, false);
        const none = plain(S.summarize([{role: "assistant", content: "x"}], {}));
        assert.strictEqual(none.hasTokens, false);
    },

    only_user_and_assistant_messages_count() {
        const s = plain(S.summarize([
            {role: "user", content: "a"}, {role: "error", content: "boom"},
            {role: "permission_request", status: "pending"}, {role: "assistant", content: "b"}, null,
        ], {}));
        assert.strictEqual(s.messages, 2);
    },

    cost_zero_or_junk_is_not_a_cost() {
        const s = plain(S.summarize([
            {role: "assistant", content: "a", cost: 0}, {role: "assistant", content: "b", cost: "n/a"},
        ], {}));
        assert.strictEqual(s.hasCost, false);
    },

    opencode_style_tokens_with_extra_fields() {
        const s = plain(S.summarize([
            {role: "assistant", model: "OpenCode", content: "a", tokens: {input: 100, output: 20, reasoning: 5, cache: {read: 1, write: 2}}, cost: 0.02},
        ], {}));
        assert.strictEqual(s.inputTokens, 100);
        assert.strictEqual(s.outputTokens, 20);
        assert.strictEqual(s.cost, 0.02);
    },

    times_come_from_the_session_then_the_messages() {
        const msgs = [{role: "user", content: "a", at: 5000}, {role: "assistant", content: "b", at: 9000}];
        const fromSession = plain(S.summarize(msgs, {createdAt: 1000, updatedAt: 20000}));
        assert.strictEqual(fromSession.createdAt, 1000);
        assert.strictEqual(fromSession.lastActive, 20000);
        const fromMessages = plain(S.summarize(msgs, {}));
        assert.strictEqual(fromMessages.createdAt, 5000);
        assert.strictEqual(fromMessages.lastActive, 9000);
    },

    formatting() {
        assert.strictEqual(S.formatCount(0), "0");
        assert.strictEqual(S.formatCount(1234567), "1,234,567");
        assert.strictEqual(S.formatCount(undefined), "0");
        assert.strictEqual(S.formatCost(0.000321), "$0.00032");
        assert.strictEqual(S.formatCost(0.0456), "$0.046");
        assert.strictEqual(S.formatCost(12.3456), "$12.35");
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + (e.stack || e).toString().split("\n").slice(0, 3).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
