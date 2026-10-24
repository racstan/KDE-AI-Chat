// Tests for backends/DirectBackend.js, run by tests/test_direct_backend.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const source = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/backends/DirectBackend.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const DB = {};
vm.runInNewContext(source + "\nthis.exports = {createSseParser, createThinkSplitter, buildRequest, errorMessage, send, DEFAULT_MAX_TOKENS};", DB);
const B = DB.exports;
// Objects from the vm context have another realm's prototypes; compare plain copies.
const plain = x => JSON.parse(JSON.stringify(x));

// Fake XHR that delivers `chunks` as LOADING (3) updates, then DONE (4).
function fakeXhr(status, chunks) {
    const xhr = {
        readyState: 0, status: 0, responseText: "", sent: null, headers: {}, aborted: false,
        open(method, url) { this.method = method; this.url = url; },
        setRequestHeader(k, v) { this.headers[k] = v; },
        send(body) { this.sent = JSON.parse(body); },
        abort() { this.aborted = true; },
        play() {
            this.status = status;
            for (const c of chunks) { this.responseText += c; this.readyState = 3; this.onreadystatechange(); }
            this.readyState = 4; this.onreadystatechange();
        },
    };
    return xhr;
}

function run(options, status, chunks) {
    const xhr = fakeXhr(status, chunks);
    const events = [];
    const handle = B.send(Object.assign({xhrFactory: () => xhr, onEvent: e => events.push(e)}, options));
    return {xhr, events, handle};
}

function collect(events, type) {
    return events.filter(e => e.type === type).map(e => e.delta).join("");
}

const tests = {
    sse_handles_split_lines_crlf_comments_and_multiline_data() {
        const got = [];
        const p = B.createSseParser(m => got.push(m));
        p.push("data: {\"a\"");
        p.push(":1}\r\n\r\n: keepalive\n\nevent: ping\ndata:x\ndata: y\n\n");
        p.push("data:no-trailing-newline");
        p.end();
        assert.deepStrictEqual(plain(got.map(m => [m.event, m.data])), [["message", "{\"a\":1}"], ["ping", "x\ny"], ["message", "no-trailing-newline"]]);
    },

    think_tags_split_across_chunks() {
        const out = [];
        const t = B.createThinkSplitter((k, s) => out.push([k, s]));
        for (const c of ["Hi <th", "ink>pla", "n</thi", "nk> done <", "3"]) t.push(c);
        t.end();
        const text = out.filter(o => o[0] === "text").map(o => o[1]).join("");
        const reasoning = out.filter(o => o[0] === "reasoning").map(o => o[1]).join("");
        assert.strictEqual(text, "Hi  done <3");
        assert.strictEqual(reasoning, "plan");
    },

    openai_request_has_default_max_tokens_and_system_first() {
        const r = B.buildRequest({type: "openai", baseUrl: "https://x.test/v1/", apiKey: "k", model: "m",
                                  system: "be brief", messages: [{role: "user", content: "hi"}]});
        assert.strictEqual(r.url, "https://x.test/v1/chat/completions");
        assert.strictEqual(r.headers.Authorization, "Bearer k");
        assert.strictEqual(r.body.max_tokens, B.DEFAULT_MAX_TOKENS);
        assert.strictEqual(r.body.stream, true);
        assert.deepStrictEqual(plain(r.body.messages[0]), {role: "system", content: "be brief"});
    },

    openai_without_key_sends_no_authorization() {
        const r = B.buildRequest({type: "openai", baseUrl: "http://localhost:11434/v1", model: "m", messages: []});
        assert.ok(!("Authorization" in r.headers));
    },

    anthropic_request_shape() {
        const r = B.buildRequest({type: "anthropic", baseUrl: "https://api.anthropic.com/v1", apiKey: "k", model: "c",
                                  system: "s", messages: [{role: "user", content: "hi"}], maxTokens: 512});
        assert.strictEqual(r.url, "https://api.anthropic.com/v1/messages");
        assert.strictEqual(r.headers["x-api-key"], "k");
        assert.strictEqual(r.body.system, "s");
        assert.strictEqual(r.body.max_tokens, 512);
    },

    openai_stream_text_reasoning_usage_done() {
        const {events, xhr} = run({type: "openai", baseUrl: "https://x/v1", model: "m", messages: []}, 200, [
            'data: {"choices":[{"delta":{"reasoning":"think "}}]}\n\n',
            'data: {"choices":[{"delta":{"content":"Hel"}}]}\n',
            '\ndata: {"choices":[{"delta":{"content":"lo <think>x</think>!"}}]}\n\n',
            'data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":3}}\n\ndata: [DONE]\n\n',
        ]);
        xhr.play();
        assert.strictEqual(events[0].type, "start");
        assert.strictEqual(collect(events, "text_delta"), "Hello !");
        assert.strictEqual(collect(events, "reasoning_delta"), "think x");
        assert.deepStrictEqual(plain(events.find(e => e.type === "usage")), {type: "usage", input: 5, output: 3});
        assert.deepStrictEqual(plain(events[events.length - 1]), {type: "done", reason: "complete"});
    },

    anthropic_stream() {
        const {events, xhr} = run({type: "anthropic", apiKey: "k", model: "c", messages: []}, 200, [
            'event: message_start\ndata: {"type":"message_start","message":{"usage":{"input_tokens":9,"output_tokens":1}}}\n\n',
            'event: content_block_delta\ndata: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}\n\n',
            'event: content_block_delta\ndata: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}\n\n',
            'event: message_delta\ndata: {"type":"message_delta","usage":{"output_tokens":4}}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n',
        ]);
        xhr.play();
        assert.strictEqual(collect(events, "text_delta"), "Hi");
        assert.strictEqual(collect(events, "reasoning_delta"), "hmm");
        assert.strictEqual(events.filter(e => e.type === "usage").length, 2);
        assert.strictEqual(events[events.length - 1].reason, "complete");
    },

    error_inside_stream_ends_request() {
        const {events, xhr} = run({type: "openai", baseUrl: "https://x/v1", model: "m", messages: []}, 200, [
            'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
            'data: {"error":{"message":"rate limited"}}\n\n',
            'data: {"choices":[{"delta":{"content":"ignored"}}]}\n\n',
        ]);
        xhr.play();
        assert.strictEqual(collect(events, "text_delta"), "partial");
        const err = events.find(e => e.type === "error");
        assert.strictEqual(err.message, "rate limited");
        assert.deepStrictEqual(plain(events[events.length - 1]), {type: "done", reason: "error"});
        assert.strictEqual(events.filter(e => e.type === "done").length, 1);
    },

    http_error_message() {
        const {events, xhr} = run({type: "openai", baseUrl: "https://openrouter.ai/api/v1", model: "m", messages: []}, 402, [
            '{"error":{"message":"This request requires more credits"}}',
        ]);
        xhr.play();
        const err = events.find(e => e.type === "error");
        assert.strictEqual(err.status, 402);
        assert.ok(err.message.includes("HTTP 402") && err.message.includes("requires more credits"), err.message);
    },

    auth_error_is_explained() {
        assert.ok(B.errorMessage(401, '{"error":"bad key"}', "u").startsWith("The provider rejected the API key (HTTP 401)"));
    },

    non_streaming_response() {
        const {events, xhr} = run({type: "openai", baseUrl: "https://x/v1", model: "m", messages: [], stream: false}, 200, [
            '{"choices":[{"message":{"content":"<think>r</think>Answer"}}],"usage":{"prompt_tokens":1,"completion_tokens":2}}',
        ]);
        xhr.play();
        assert.strictEqual(collect(events, "text_delta"), "Answer");
        assert.strictEqual(collect(events, "reasoning_delta"), "r");
        assert.strictEqual(events[events.length - 1].reason, "complete");
    },

    abort_stops_events() {
        const {events, xhr, handle} = run({type: "openai", baseUrl: "https://x/v1", model: "m", messages: []}, 200, [
            'data: {"choices":[{"delta":{"content":"late"}}]}\n\n',
        ]);
        handle.abort();
        xhr.play();
        assert.ok(xhr.aborted);
        assert.deepStrictEqual(plain(events.map(e => e.type)), ["start", "done"]);
        assert.strictEqual(events[1].reason, "aborted");
    },

    network_error() {
        const xhr = fakeXhr(0, []);
        const events = [];
        B.send({type: "openai", baseUrl: "http://nowhere/v1", model: "m", messages: [], xhrFactory: () => xhr, onEvent: e => events.push(e)});
        xhr.onerror();
        assert.ok(events.find(e => e.type === "error").message.startsWith("Could not reach http://nowhere/v1/chat/completions"));
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + (e.stack || e).toString().split("\n").slice(0, 3).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
