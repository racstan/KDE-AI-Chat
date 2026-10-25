// Tests for backends/DirectBackend.js, run by tests/test_direct_backend.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const read = name => fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/backends/" + name), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const DB = {};
// DirectStream.js (the <think> splitter) is passed to send() as options.thinkFactory in the widget; here it is
// loaded next to DirectBackend.js and added to every send.
vm.runInNewContext(read("DirectBackend.js") + "\n" + read("DirectStream.js") + read("DirectTools.js")
    + "\nconst rawSend = send;\nthis.exports = {createSseParser, createThinkSplitter, buildRequest, errorMessage, rejectsTools, createCollector,"
    + " send: o => rawSend(Object.assign({thinkFactory: createThinkSplitter}, o)), DEFAULT_MAX_TOKENS};", DB);
const B = DB.exports;
// chat/ImageExtract.js is passed to send() as options.images in the widget.
const IX = {};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/ImageExtract.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "") + "\nthis.exports = {fromMessage, textOf};", IX);
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

    an_empty_system_prompt_sends_no_system_message() {
        for (const type of ["openai", "anthropic"]) {
            for (const system of ["", undefined, null]) {
                const r = B.buildRequest({type, baseUrl: "https://x.test/v1", model: "m", system, messages: [{role: "user", content: "hi"}]});
                assert.ok(!("system" in r.body), type);
                assert.deepStrictEqual(plain(r.body.messages), [{role: "user", content: "hi"}], type);
            }
        }
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

    // --- usage straight from the provider (never estimated) ---

    openai_streaming_request_asks_for_usage() {
        const r = B.buildRequest({type: "openai", baseUrl: "https://usage1.test/v1", model: "m", messages: []});
        assert.deepStrictEqual(plain(r.body.stream_options), {include_usage: true});
        assert.ok(!("usage" in r.body), "only OpenRouter gets the usage accounting field");
    },

    non_streaming_and_opted_out_requests_do_not_send_stream_options() {
        const base = {type: "openai", baseUrl: "https://usage2.test/v1", model: "m", messages: []};
        assert.ok(!("stream_options" in B.buildRequest(Object.assign({stream: false}, base)).body));
        assert.ok(!("stream_options" in B.buildRequest(Object.assign({streamUsage: false}, base)).body));
    },

    anthropic_request_has_no_openai_fields() {
        const r = B.buildRequest({type: "anthropic", apiKey: "k", model: "c", messages: []});
        assert.ok(!("stream_options" in r.body) && !("usage" in r.body));
    },

    openrouter_requests_usage_accounting() {
        const r = B.buildRequest({type: "openai", baseUrl: "https://openrouter.ai/api/v1", model: "m", messages: []});
        assert.deepStrictEqual(plain(r.body.usage), {include: true});
        assert.deepStrictEqual(plain(r.body.stream_options), {include_usage: true});
        const nonStream = B.buildRequest({type: "openai", baseUrl: "https://openrouter.ai/api/v1", model: "m", messages: [], stream: false});
        assert.deepStrictEqual(plain(nonStream.body.usage), {include: true});
    },

    openrouter_final_chunk_gives_tokens_and_cost() {
        const {events, xhr} = run({type: "openai", baseUrl: "https://openrouter.ai/api/v1", model: "m", messages: []}, 200, [
            'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n',
            ': OPENROUTER PROCESSING\n\n',
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":null}\n\n',
            'data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":34,"total_tokens":46,"cost":0.000321,"cost_details":{"upstream_inference_cost":0.0003}}}\n\ndata: [DONE]\n\n',
        ]);
        xhr.play();
        const usage = events.filter(e => e.type === "usage");
        assert.deepStrictEqual(plain(usage), [{type: "usage", input: 12, output: 34, cost: 0.000321}]);
        // reported once, just before done
        assert.strictEqual(events[events.length - 2].type, "usage");
        assert.strictEqual(events[events.length - 1].type, "done");
    },

    usage_repeated_in_several_chunks_is_reported_once() {
        // Gemini's OpenAI endpoint (and some proxies) put usage in every chunk.
        const {events, xhr} = run({type: "openai", baseUrl: "https://usage3.test/v1", model: "m", messages: []}, 200, [
            'data: {"choices":[{"delta":{"content":"a"}}],"usage":{"prompt_tokens":7,"completion_tokens":1}}\n\n',
            'data: {"choices":[{"delta":{"content":"b"}}],"usage":{"prompt_tokens":7,"completion_tokens":2}}\n\n',
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":7,"completion_tokens":2}}\n\n',
        ]);
        xhr.play();
        assert.deepStrictEqual(plain(events.filter(e => e.type === "usage")), [{type: "usage", input: 7, output: 2}]);
    },

    ollama_style_usage_chunk_is_captured() {
        const {events, xhr} = run({type: "openai", baseUrl: "http://localhost:11434/v1", model: "m", messages: []}, 200, [
            'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n',
            'data: {"choices":[],"usage":{"prompt_tokens":26,"completion_tokens":9,"total_tokens":35}}\n\ndata: [DONE]\n\n',
        ]);
        xhr.play();
        assert.deepStrictEqual(plain(events.filter(e => e.type === "usage")), [{type: "usage", input: 26, output: 9}]);
    },

    usage_is_not_reported_for_an_aborted_or_failed_request() {
        const {events, xhr, handle} = run({type: "openai", baseUrl: "https://usage4.test/v1", model: "m", messages: []}, 200, [
            'data: {"choices":[],"usage":{"prompt_tokens":1,"completion_tokens":1}}\n\n',
        ]);
        handle.abort();
        xhr.play();
        assert.ok(!events.some(e => e.type === "usage"));
    },

    non_streaming_openrouter_cost() {
        const {events, xhr} = run({type: "openai", baseUrl: "https://openrouter.ai/api/v1", model: "m", messages: [], stream: false}, 200, [
            '{"choices":[{"message":{"content":"Answer"}}],"usage":{"prompt_tokens":3,"completion_tokens":4,"cost":0.01}}',
        ]);
        xhr.play();
        assert.deepStrictEqual(plain(events.find(e => e.type === "usage")), {type: "usage", input: 3, output: 4, cost: 0.01});
    },

    a_missing_or_invalid_cost_is_left_out() {
        for (const cost of [undefined, null, "n/a", -1]) {
            const usage = {prompt_tokens: 1, completion_tokens: 1};
            if (cost !== undefined) usage.cost = cost;
            const {events, xhr} = run({type: "openai", baseUrl: "https://usage5.test/v1", model: "m", messages: [], stream: false}, 200, [
                JSON.stringify({choices: [{message: {content: "x"}}], usage})]);
            xhr.play();
            assert.ok(!("cost" in events.find(e => e.type === "usage")), "cost " + cost);
        }
    },

    anthropic_usage_includes_cached_prompt_tokens() {
        const {events, xhr} = run({type: "anthropic", apiKey: "k", model: "c", messages: []}, 200, [
            'event: message_start\ndata: {"type":"message_start","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":200,"cache_creation_input_tokens":30,"output_tokens":1}}}\n\n',
            'event: message_delta\ndata: {"type":"message_delta","usage":{"output_tokens":42}}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n',
        ]);
        xhr.play();
        assert.deepStrictEqual(plain(events.filter(e => e.type === "usage")), [
            {type: "usage", input: 240, output: 1},
            {type: "usage", output: 42},
        ]);
    },

    stream_options_rejected_with_400_is_retried_once_without_it() {
        const first = fakeXhr(400, ['{"error":{"message":"Unrecognized request argument supplied: stream_options"}}']);
        const second = fakeXhr(200, [
            'data: {"choices":[{"delta":{"content":"fine"}}]}\n\ndata: [DONE]\n\n',
        ]);
        const xhrs = [first, second];
        const events = [];
        const options = {type: "openai", baseUrl: "https://strict.test/v1", model: "m", messages: [],
                         xhrFactory: () => xhrs.shift(), onEvent: e => events.push(e)};
        B.send(options);
        first.play();
        assert.deepStrictEqual(plain(first.sent.stream_options), {include_usage: true});
        assert.ok(second.sent, "retried");
        assert.ok(!("stream_options" in second.sent));
        second.play();
        assert.strictEqual(collect(events, "text_delta"), "fine");
        assert.deepStrictEqual(plain(events.map(e => e.type).filter(t => t === "start" || t === "error" || t === "done")), ["start", "done"]);
        assert.strictEqual(events[events.length - 1].reason, "complete");
        // remembered: the next request to this server leaves it out from the start
        const next = B.buildRequest(options);
        assert.ok(!("stream_options" in next.body));
    },

    a_400_that_is_not_about_stream_options_is_not_retried() {
        const first = fakeXhr(400, ['{"error":{"message":"max_tokens is too large"}}']);
        let created = 0;
        const events = [];
        B.send({type: "openai", baseUrl: "https://other400.test/v1", model: "m", messages: [],
                xhrFactory: () => { created++; return first; }, onEvent: e => events.push(e)});
        first.play();
        assert.strictEqual(created, 1);
        const err = events.find(e => e.type === "error");
        assert.ok(err && err.message.includes("max_tokens is too large"), JSON.stringify(events));
    },

    a_second_stream_options_rejection_is_an_error() {
        const a = fakeXhr(400, ['{"error":"stream_options not allowed"}']);
        const b = fakeXhr(400, ['{"error":"stream_options not allowed"}']);
        const xhrs = [a, b];
        const events = [];
        B.send({type: "openai", baseUrl: "https://stubborn.test/v1", model: "m", messages: [],
                xhrFactory: () => xhrs.shift(), onEvent: e => events.push(e)});
        a.play();
        b.play();
        assert.strictEqual(events.filter(e => e.type === "error").length, 1);
        assert.strictEqual(events[events.length - 1].reason, "error");
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

    streamed_images_arrive_as_one_event_next_to_the_text() {
        const img = {type: "image_url", image_url: {url: "data:image/png;base64,QUJD"}};
        const {events, xhr} = run({type: "openai", baseUrl: "https://x/v1", model: "m", messages: [], images: IX.exports}, 200, [
            'data: {"choices":[{"delta":{"content":"Here: "}}]}\n\n',
            'data: {"choices":[{"delta":{"content":"done","images":[' + JSON.stringify(img) + ']}}]}\n\n',
            'data: {"choices":[{"delta":{"images":[' + JSON.stringify(img) + ']}}]}\n\n',
            "data: [DONE]\n\n",
        ]);
        xhr.play();
        assert.strictEqual(collect(events, "text_delta"), "Here: done");
        const found = events.filter(e => e.type === "images");
        assert.strictEqual(found.length, 2);   // the backend reports each chunk's images; the widget drops repeats
        assert.deepStrictEqual(plain(found[0].items), [{kind: "data", b64: "QUJD", mime: "image/png"}]);
        assert.strictEqual(events[events.length - 1].reason, "complete");
    },

    full_response_images_and_content_parts() {
        const body = {choices: [{message: {content: [{type: "text", text: "A cat."}, {type: "image_url", image_url: {url: "https://cdn.example.com/c.png"}}],
                                           images: [{type: "image_url", image_url: {url: "data:image/webp;base64,QUJE"}}]}}]};
        const {events, xhr} = run({type: "openai", baseUrl: "https://x/v1", model: "m", messages: [], stream: false, images: IX.exports}, 200, [JSON.stringify(body)]);
        xhr.play();
        assert.strictEqual(collect(events, "text_delta"), "A cat.");
        const urls = [].concat(...events.filter(e => e.type === "images").map(e => e.items.map(i => i.kind)));
        assert.deepStrictEqual(plain(urls.sort()), ["data", "url"]);
    },

    without_the_image_module_a_reply_is_read_as_before() {
        const {events, xhr} = run({type: "openai", baseUrl: "https://x/v1", model: "m", messages: []}, 200, [
            'data: {"choices":[{"delta":{"content":"x","images":[{"image_url":"https://a.example.com/a.png"}]}}]}\n\n',
        ]);
        xhr.play();
        assert.strictEqual(events.filter(e => e.type === "images").length, 0);
        assert.strictEqual(collect(events, "text_delta"), "x");
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
