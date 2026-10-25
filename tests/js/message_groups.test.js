// Tests for chat/MessageGroups.js, run by tests/test_message_groups.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/MessageGroups.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {startsRun, senderKey};", ctx);
const G = ctx.exports;
const starts = messages => messages.map((m, i) => G.startsRun(messages, i));

const tests = {
    one_ai_turn_with_tools_and_a_question_has_one_header() {
        const m = [{role: "user"}, {role: "assistant", model: "m"}, {role: "question_request", model: "m"}, {role: "assistant", model: "m"}];
        assert.deepStrictEqual(starts(m), [true, true, false, false]);
    },
    agent_cards_join_the_turn_whatever_name_they_carry() {
        const m = [{role: "user"}, {role: "assistant", model: "claude"}, {role: "permission_request", model: "OpenCode"},
                   {role: "question_request", model: "OpenCode"}, {role: "assistant", model: "claude"}];
        assert.deepStrictEqual(starts(m), [true, true, false, false, false]);
    },
    a_card_that_opens_the_turn_has_a_header() {
        const m = [{role: "user"}, {role: "question_request", model: "Pi"}, {role: "assistant", model: "x"}];
        assert.deepStrictEqual(starts(m), [true, true, true]);
    },
    your_messages_group_but_a_queued_one_and_an_error_keep_their_heading() {
        const m = [{role: "user"}, {role: "user"}, {role: "queued"}, {role: "error"}, {role: "error"}, {role: "assistant", model: "m"}];
        assert.deepStrictEqual(starts(m), [true, false, true, true, true, true]);
    },
    a_message_from_you_or_another_model_starts_a_new_run() {
        const m = [{role: "assistant", model: "a"}, {role: "assistant", model: "a"}, {role: "assistant", model: "b"},
                   {role: "user"}, {role: "assistant", model: "b"}];
        assert.deepStrictEqual(starts(m), [true, false, true, true, true]);
    },
    the_first_message_always_has_a_header() {
        assert.strictEqual(G.startsRun([{role: "assistant", model: "m"}], 0), true);
        assert.strictEqual(G.startsRun([{role: "question_request"}], 0), true);
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + (e.stack || e).toString().split("\n").slice(0, 4).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
