// Tests for config/ScheduleDescribe.js ("Describe when") and the shared
// one-shot request in chat/ChatTitle.js, run by tests/test_schedule_ui_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

function load(rel) {
    const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/", rel), "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/m, "");
    const ctx = {};
    vm.runInNewContext(src + "\nthis.M = this;", ctx);
    return ctx.M;
}
const S = load("config/ScheduleDescribe.js");
const T = load("chat/ChatTitle.js");
const plain = v => JSON.parse(JSON.stringify(v));
const NOW = new Date(2026, 9, 26, 8, 20);

function fakeXhr(status, body) {
    const x = {headers: {}, setRequestHeader(k, v) { x.headers[k] = v; }, open(m, u) { x.url = u; },
        send(b) { x.sent = JSON.parse(b); setTimeout(() => {
            x.status = status; x.responseText = body; x.readyState = 4; x.onreadystatechange();
        }, 0); }};
    return x;
}

const tests = {
    prompt_has_today_and_the_owner_example() {
        const p = S.systemPrompt(NOW);
        assert.ok(p.includes("Today is Monday 2026-10-26, the time is 08:20."), p);
        assert.ok(p.includes("every other day"));
        assert.ok(p.includes("\"question\""));
    },
    messages_keep_the_conversation() {
        const m = S.buildMessages([{role: "user", content: "every other day"}, {role: "assistant", content: "{}"},
                                   {role: "user", content: "alternate days"}, {role: "tool", content: "x"}], NOW);
        assert.deepStrictEqual(plain(m.map(x => x.role)), ["system", "user", "assistant", "user"]);
    },
    turns_wrap_the_description_and_answers() {
        assert.ok(S.describeTurn(" weekdays at 9 ").startsWith('Describe as schedule rules: "weekdays at 9"\n'));
        assert.strictEqual(S.answerTurn("Which?", "Every 2 days"), 'To your question "Which?": Every 2 days\nNow reply with the rules as JSON.');
    },
    every_other_day_is_always_asked() {
        const a = S.ambiguity("Mondays at 4 pm and every other day at 3 pm");
        assert.strictEqual(a.question, '"every other day" can be read two ways. Which one do you mean?');
        assert.deepStrictEqual(plain(a.options), ["The remaining days of the week at 3 pm", "Every 2 days (alternate days) at 3 pm"]);
        assert.deepStrictEqual(plain(S.ambiguity("Every second day").options), ["The remaining days of the week", "Every 2 days (alternate days)"]);
        assert.strictEqual(S.ambiguity("weekdays at 9 and Sunday at noon"), null);
    },
    rules_reply_is_parsed_and_tidied() {
        const r = S.parseReply('```json\n{"rules":[{"kind":"weekly","days":[1,2,3,4,5],"times":["9:00"],"note":"x"},' +
                               '{"kind":"weekly","days":[7],"times":"12:00"}]}\n```');
        assert.deepStrictEqual(plain(r), {rules: [{kind: "weekly", days: [1, 2, 3, 4, 5], times: ["09:00"]},
                                                   {kind: "weekly", days: [0], times: ["12:00"]}]});
    },
    reasoning_and_prose_around_json_are_ignored() {
        const r = S.parseReply('<think>maybe {"rules": []}</think>Sure! Here it is: {"rules":[{"kind":"daily","times":["15:00"],"everyDays":2}]} hope it helps');
        assert.deepStrictEqual(plain(r.rules), [{kind: "daily", times: ["15:00"], everyDays: 2}]);
    },
    question_reply_has_options() {
        const r = S.parseReply('{"question":"Every other day: which one?","options":["Tue–Sun","Every 2 days",{"label":"Odd dates"},""]}');
        assert.strictEqual(r.question, "Every other day: which one?");
        assert.deepStrictEqual(plain(r.options), ["Tue–Sun", "Every 2 days", "Odd dates"]);
    },
    bad_replies_are_errors() {
        assert.strictEqual(S.parseReply("").error, "empty");
        assert.strictEqual(S.parseReply("I can't do that").error, "no-json");
        assert.strictEqual(S.parseReply('{"rules": [{"kind": "fortnightly"}]}').error, "no-rules");
        assert.strictEqual(S.parseReply('{"rules": [ {"kind": "daily", ').error, "no-json");
        assert.strictEqual(S.parseReply("<think>unfinished").error, "no-json");
    },
    a_once_rule_drops_seconds() {
        assert.strictEqual(S.parseReply('{"rules":[{"kind":"once","at":"2026-11-03T14:30:00"}]}').rules[0].at, "2026-11-03T14:30");
    },
    chat_request_for_openai_and_anthropic() {
        const msgs = [{role: "system", content: "S"}, {role: "user", content: "U"}];
        const oa = T.buildChatRequest({type: "openai-compat", baseUrl: "https://x/v1/", apiKey: "K", model: "m"}, msgs, 900);
        assert.strictEqual(oa.url, "https://x/v1/chat/completions");
        assert.strictEqual(oa.body.max_tokens, 900);
        assert.strictEqual(oa.body.messages.length, 2);
        const an = T.buildChatRequest({type: "anthropic", baseUrl: "https://a/v1", apiKey: "K", model: "c"}, msgs, 900);
        assert.strictEqual(an.url, "https://a/v1/messages");
        assert.strictEqual(an.body.system, "S");
        assert.deepStrictEqual(plain(an.body.messages), [{role: "user", content: "U"}]);
    },
    async send_returns_the_raw_text() {
        const req = T.buildChatRequest({type: "openai-compat", baseUrl: "https://x/v1", apiKey: "K", model: "m"},
                                       [{role: "user", content: "U"}], 50);
        const body = JSON.stringify({choices: [{message: {content: '{"rules":[]}'}}]});
        const got = await new Promise(res => T.send(req, 1000, () => fakeXhr(200, body), (text, err) => res({text, err})));
        assert.deepStrictEqual(got, {text: '{"rules":[]}', err: ""});
        const bad = await new Promise(res => T.send(req, 1000, () => fakeXhr(401, "no"), (text, err) => res({text, err})));
        assert.deepStrictEqual(bad, {text: "", err: "HTTP 401"});
    },
};

(async () => {
    let failed = 0;
    for (const [name, fn] of Object.entries(tests)) {
        try {
            await fn();
            console.log("ok   " + name);
        } catch (e) {
            failed++;
            console.log("FAIL " + name + "\n" + e.stack);
        }
    }
    process.exit(failed ? 1 : 0);
})();
