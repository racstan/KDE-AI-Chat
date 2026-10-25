// Tests for chat/ChatTitle.js (chat names), run by tests/test_chat_title.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/ChatTitle.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {instantTitle, isDefaultTitle, cleanGenerated, parseResponse, buildRequest, request};", ctx);
const T = ctx.exports;

function fakeXhr(status, body, mode) {
    const x = {headers: {}, setRequestHeader(k, v) { x.headers[k] = v; }, open(m, u) { x.url = u; },
        send(b) { x.sent = JSON.parse(b); setTimeout(() => {
            x.status = status; x.responseText = body; x.readyState = 4;
            if (mode === "timeout") x.ontimeout(); else if (mode === "error") x.onerror(); else x.onreadystatechange();
        }, 0); }};
    return x;
}
function run(cfg, xhr) {
    return new Promise(res => T.request(cfg, "hello", () => xhr, (title, err) => res({title, err})));
}
const oa = {type: "openai", baseUrl: "https://x/v1/", apiKey: "SECRET", model: "m", headers: {"X-A": "1"}};
const choice = content => JSON.stringify({choices: [{message: {content}}]});

const tests = {
    short_message_is_kept_whole() {
        assert.strictEqual(T.instantTitle("How do I rotate a PDF?"), "How do I rotate a PDF");
    },
    long_message_is_cut_at_six_words_with_ellipsis() {
        assert.strictEqual(T.instantTitle("please explain how kernel scheduling works on modern CPUs"), "Please explain how kernel scheduling…");
    },
    long_words_are_cut_by_characters() {
        const t = T.instantTitle("Supercalifragilisticexpialidocious Supercalifragilisticexpialidocious");
        assert.ok(t.length <= 41, t);
        assert.ok(t.endsWith("…"));
    },
    single_overlong_word_is_hard_cut() {
        const t = T.instantTitle("a".repeat(100));
        assert.strictEqual(t, "A" + "a".repeat(38) + "…");
    },
    whitespace_collapses_and_trailing_punctuation_goes() {
        assert.strictEqual(T.instantTitle("  hi \n\n  there ,  "), "Hi there");
        assert.strictEqual(T.instantTitle("what is this???"), "What is this");
    },
    markdown_code_and_urls_are_stripped() {
        assert.strictEqual(T.instantTitle("```py\nprint(1)\n```\nwhy does this fail"), "Why does this fail");
        assert.strictEqual(T.instantTitle("see https://example.com/a?b=1 for **bold** idea"), "See for bold idea");
        assert.strictEqual(T.instantTitle("# Heading\n- item one"), "Heading item one");
        assert.strictEqual(T.instantTitle("read [the docs](http://x.y) now"), "Read the docs now");
        assert.strictEqual(T.instantTitle("use `grep -r` here"), "Use grep -r here");
    },
    nothing_usable_gives_empty() {
        assert.strictEqual(T.instantTitle(""), "");
        assert.strictEqual(T.instantTitle("   "), "");
        assert.strictEqual(T.instantTitle("```\ncode only\n```"), "");
        assert.strictEqual(T.instantTitle("https://example.com"), "");
        assert.strictEqual(T.instantTitle(null), "");
    },
    default_titles() {
        assert.ok(T.isDefaultTitle(""));
        assert.ok(T.isDefaultTitle(" new CHAT "));
        assert.ok(!T.isDefaultTitle("Fix my bug"));
    },
    clean_generated_strips_quotes_labels_and_dots() {
        assert.strictEqual(T.cleanGenerated('"Rotating PDF pages."'), "Rotating PDF pages");
        assert.strictEqual(T.cleanGenerated("Title: **Kernel scheduling**\nextra line"), "Kernel scheduling");
        assert.strictEqual(T.cleanGenerated(""), "");
        assert.strictEqual(T.cleanGenerated(undefined), "");
    },
    reasoning_is_ignored() {
        assert.strictEqual(T.cleanGenerated("<think>hmm the user wants</think>Pdf rotation help"), "Pdf rotation help");
        assert.strictEqual(T.cleanGenerated("<think>still thinking about"), "");
        assert.strictEqual(T.cleanGenerated("<think>only thoughts</think>"), "");
    },
    parse_openai_and_anthropic_shapes() {
        assert.strictEqual(T.parseResponse(false, choice("Hello there")), "Hello there");
        assert.strictEqual(T.parseResponse(false, choice([{type: "text", text: "Part"}, {type: "text", text: " two"}])), "Part two");
        assert.strictEqual(T.parseResponse(false, JSON.stringify({choices: [{message: {content: null, reasoning: "long thoughts"}}]})), "");
        assert.strictEqual(T.parseResponse(true, JSON.stringify({content: [{type: "thinking", thinking: "x"}, {type: "text", text: "Claude title"}]})), "Claude title");
        assert.throws(() => T.parseResponse(false, "not json"));
    },
    requests_carry_max_tokens_and_auth() {
        const o = T.buildRequest(oa, "q");
        assert.strictEqual(o.url, "https://x/v1/chat/completions");
        assert.strictEqual(o.body.max_tokens, 40);
        assert.strictEqual(o.body.stream, false);
        assert.strictEqual(o.headers.Authorization, "Bearer SECRET");
        assert.strictEqual(o.headers["X-A"], "1");
        const a = T.buildRequest({type: "anthropic", baseUrl: "https://a/v1", apiKey: "K", model: "c"}, "q");
        assert.strictEqual(a.url, "https://a/v1/messages");
        assert.strictEqual(a.body.max_tokens, 32);
        assert.strictEqual(a.headers["x-api-key"], "K");
    },
    async request_success_uses_20s_timeout() {
        const x = fakeXhr(200, choice('"A fine title"'));
        const r = await run(oa, x);
        assert.strictEqual(r.title, "A fine title");
        assert.strictEqual(x.timeout, 20000);
    },
    async request_failures_report_without_the_key() {
        for (const [x, expect] of [[fakeXhr(401, "{}"), "HTTP 401"], [fakeXhr(0, "", "timeout"), "timed out"],
                                   [fakeXhr(0, "", "error"), "network error"], [fakeXhr(200, choice("")), "no usable"],
                                   [fakeXhr(200, "garbage"), "unreadable"]]) {
            const r = await run(oa, x);
            assert.strictEqual(r.title, "");
            assert.ok(r.err.includes(expect), r.err);
            assert.ok(!r.err.includes("SECRET"));
        }
    },
};

(async () => {
    let failed = 0;
    for (const [name, fn] of Object.entries(tests)) {
        try { await fn(); console.log("PASS " + name); }
        catch (e) { failed++; console.log("FAIL " + name + "\n  " + (e.stack || e).toString().split("\n").slice(0, 3).join("\n  ")); }
    }
    process.exit(failed ? 1 : 0);
})();
