// Tests for chat/Spending.js (budgets, helper replies, provider lines, day bars), run by tests/test_spending_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/Spending.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {parseBudgets, serializeBudgets, parseReply, percentUsed, monthOf, monthList, providerRows, dayRows};", ctx);
const plain = x => JSON.parse(JSON.stringify(x));
// Results are built inside the vm context; a JSON copy makes them plain objects of this realm for deepStrictEqual.
const S = Object.fromEntries(Object.entries(ctx.exports).map(([name, fn]) => [name, (...args) => plain(fn(...args))]));

const tests = {
    budgets_keep_only_usable_positive_numbers() {
        assert.deepStrictEqual(plain(S.parseBudgets('{"openrouter": 10, "ollama": 0, "openai": -1, "anthropic": "5", "x": null, "": 3, "y": 2.5}')),
                               {openrouter: 10, y: 2.5});
        assert.deepStrictEqual(S.parseBudgets("not json"), {});
        assert.deepStrictEqual(S.parseBudgets("[1, 2]"), {});
        assert.deepStrictEqual(S.parseBudgets(""), {});
        assert.deepStrictEqual(S.parseBudgets(undefined), {});
        assert.deepStrictEqual(S.parseBudgets('{"big": 1e13}'), {});
    },

    budgets_serialize_back_to_the_setting() {
        assert.strictEqual(S.serializeBudgets({openrouter: 10, nope: 0, neg: -2}), '{"openrouter":10}');
        assert.strictEqual(S.serializeBudgets({}), "{}");
    },

    helper_replies_are_read_from_the_last_line() {
        assert.deepStrictEqual(plain(S.parseReply('noise\n{"type": "usage_added", "alerts": []}\n')), {type: "usage_added", alerts: []});
        assert.strictEqual(S.parseReply("Error executing usage_add: nope"), null);
        assert.strictEqual(S.parseReply(""), null);
        assert.strictEqual(S.parseReply("[1]"), null);
    },

    percent_of_a_budget_in_whole_numbers() {
        assert.strictEqual(S.percentUsed(2.5, 10), 25);
        assert.strictEqual(S.percentUsed(8, 10), 80);
        assert.strictEqual(S.percentUsed(12, 10), 120);
        assert.strictEqual(S.percentUsed(3, 0), 0);
        assert.strictEqual(S.percentUsed(3, undefined), 0);
    },

    months_are_local_year_and_month() {
        assert.strictEqual(S.monthOf(new Date(2026, 9, 3)), "2026-10");
        assert.strictEqual(S.monthOf(new Date(2026, 0, 31)), "2026-01");
        assert.deepStrictEqual(S.monthList(["2026-08", "2026-10", "bad", "2026-13"], "2026-09"), ["2026-10", "2026-09", "2026-08"]);
        assert.deepStrictEqual(S.monthList([], "2026-10"), ["2026-10"]);
        assert.deepStrictEqual(S.monthList(["2026-10", "2026-10"], "2026-10"), ["2026-10"]);
    },

    provider_lines_follow_the_configured_order_then_the_others() {
        const rows = S.providerRows(["openrouter", "ollama"],
                                    {"anthropic": {count: 2, input: 5, output: 1, cacheRead: 0, cost: 0.5, costCount: 2}, "ollama": {count: 1, input: 9, output: 2, cacheRead: 0, cost: 0, costCount: 0}},
                                    {"openrouter": 10, "deepseek": 4});
        assert.deepStrictEqual(rows.map(r => r.id), ["openrouter", "ollama", "anthropic", "deepseek"]);
        assert.deepStrictEqual(plain(rows[0]), {id: "openrouter", count: 0, input: 0, output: 0, cacheRead: 0, cost: 0, costCount: 0, budget: 10});
        assert.deepStrictEqual(plain(rows[1]), {id: "ollama", count: 1, input: 9, output: 2, cacheRead: 0, cost: 0, costCount: 0, budget: 0});
        assert.strictEqual(rows[2].costCount, 2);
        assert.strictEqual(rows[3].budget, 4);
    },

    day_bars_are_scaled_to_the_busiest_day() {
        const rows = S.dayRows({
            "2026-10-03": {count: 1, input: 100, output: 100, cacheRead: 0, cost: 0.2, costCount: 1},
            "2026-10-01": {count: 2, input: 300, output: 100, cacheRead: 0, cost: 0, costCount: 0},
            "2026-10-12": {count: 1, input: 0, output: 0, cacheRead: 0, cost: 0, costCount: 0},
        });
        assert.deepStrictEqual(rows.map(r => r.key), ["2026-10-01", "2026-10-03", "2026-10-12"]);
        assert.deepStrictEqual(rows.map(r => r.label), ["1", "3", "12"]);
        assert.deepStrictEqual(rows.map(r => r.fraction), [1, 0.5, 0]);
        assert.deepStrictEqual(rows.map(r => r.tokens), [400, 200, 0]);
        assert.deepStrictEqual(S.dayRows({}), []);
        assert.strictEqual(S.dayRows({"2026-10-02": {count: 1}})[0].fraction, 0);
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + (e.stack || e).toString().split("\n").slice(0, 3).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
