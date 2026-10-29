// Tests for backends/PiBackend.js, run by tests/test_pi_backend.py. The
// fixtures are real `pi --mode rpc` output (Pi 0.84, local Ollama qwen3:8b).
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

function load(file, names) {
    const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/backends", file), "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/m, "");
    const ctx = {encodeURIComponent};
    vm.runInNewContext(src + "\nthis.exports = {" + names.join(",") + "};", ctx);
    return ctx.exports;
}
const PI = load("PiBackend.js", ["chatPath", "createEventMapper", "send", "replyDialog"]);
const DB = load("DirectBackend.js", ["createSseParser"]);
const plain = x => JSON.parse(JSON.stringify(x));
const fixture = name => fs.readFileSync(path.join(__dirname, "../fixtures", name), "utf8")
    .split("\n").filter(Boolean).map(line => JSON.parse(line));

function run(events) {
    const out = [];
    const m = PI.createEventMapper(e => out.push(plain(e)));
    for (const e of events) m.handle(e);
    return out;
}
const collect = (out, type) => out.filter(e => e.type === type).map(e => e.delta).join("");
const types = out => out.map(e => e.type).filter(t => t !== "text_delta" && t !== "reasoning_delta");

const tests = {
    write_run() {
        const out = run(fixture("pi-0.84-ollama-write.jsonl"));
        assert.strictEqual(collect(out, "text_delta"), "done");
        assert.ok(collect(out, "reasoning_delta").startsWith("Okay, the user wants me to use the write tool"));
        assert.ok(!collect(out, "text_delta").includes("Use the write tool"), "the user's own text must not be echoed");
        assert.deepStrictEqual(types(out), ["usage", "tool_start", "tool_end", "file_changed", "usage", "done"]);
        const start = out.find(e => e.type === "tool_start");
        assert.deepStrictEqual(start, {type: "tool_start", callId: "call_91pynjuz", name: "write", input: {path: "hello.txt", content: "hi"}});
        assert.deepStrictEqual(out.find(e => e.type === "tool_end"),
                               {type: "tool_end", callId: "call_91pynjuz", title: "", output: "Successfully wrote 2 bytes to hello.txt", isError: false});
        assert.deepStrictEqual(out.find(e => e.type === "file_changed"), {type: "file_changed", path: "hello.txt"});
        assert.deepStrictEqual(out.filter(e => e.type === "usage")[1], {type: "usage", input: 1889, output: 82, cost: 0, cacheRead: 0});
        assert.deepStrictEqual(out[out.length - 1], {type: "done", reason: "complete"});
    },

    permission_dialog_becomes_a_question() {
        const out = run(fixture("pi-0.84-ollama-permission-denied.jsonl"));
        const q = out.find(e => e.type === "question_request");
        assert.strictEqual(q.id, "5f429d11-6d98-445b-b6e7-69dfe163ff6b");
        assert.ok(q.questions[0].question.includes("rm -rf ./junk"));
        assert.deepStrictEqual(q.questions[0].options.map(o => o.label), ["Yes", "No"]);
        assert.strictEqual(q.questions[0].custom, false);
        const end = out.find(e => e.type === "tool_end");
        assert.strictEqual(end.isError, true);
        assert.strictEqual(end.output, "Blocked by user");
        assert.ok(!out.some(e => e.type === "file_changed"));
        assert.deepStrictEqual(out[out.length - 1], {type: "done", reason: "complete"});
    },

    model_error() {
        const out = run(fixture("pi-0.84-ollama-model-error.jsonl"));
        const err = out.find(e => e.type === "error");
        assert.ok(err.message.startsWith("Pi: 404:") && err.message.includes("model 'nope:1b' not found"), err.message);
        assert.deepStrictEqual(out[out.length - 1], {type: "done", reason: "error"});
    },

    aborted_run() {
        const out = run(fixture("pi-0.84-ollama-abort.jsonl"));
        assert.ok(!out.some(e => e.type === "error"));
        assert.deepStrictEqual(out[out.length - 1], {type: "done", reason: "aborted"});
    },

    text_blocks_across_turns_are_separated_and_end_fills_gaps() {
        const upd = (type, contentIndex, extra) => ({type: "message_update", assistantMessageEvent: Object.assign({type, contentIndex}, extra)});
        const out = run([
            {type: "message_start", message: {role: "assistant"}},
            upd("text_delta", 0, {delta: "First"}),
            upd("text_end", 0, {content: "First part."}),
            {type: "message_start", message: {role: "assistant"}},
            upd("text_delta", 0, {delta: "Second"}),
            upd("text_end", 0, {content: "Second"}),
            {type: "agent_settled"},
        ]);
        assert.strictEqual(collect(out, "text_delta"), "First part.\n\nSecond");
    },

    dialogs_and_notices() {
        const out = run([
            {type: "extension_ui_request", id: "c1", method: "confirm", title: "Clear session?", message: "All messages will be lost."},
            {type: "extension_ui_request", id: "i1", method: "input", title: "Name?", placeholder: "x"},
            {type: "extension_ui_request", id: "n1", method: "notify", message: "Blocked", notifyType: "warning"},
            {type: "extension_ui_request", id: "s1", method: "setStatus", statusKey: "k", statusText: "t"},
            {type: "response", command: "prompt", success: false, error: "busy"},
        ]);
        assert.deepStrictEqual(out[0], {type: "permission_request", id: "c1", permission: "Clear session?", patterns: ["All messages will be lost."], metadata: {}});
        assert.strictEqual(out[1].type, "question_request");
        assert.strictEqual(out[1].questions[0].custom, true);
        assert.deepStrictEqual(out[2], {type: "notice", message: "Blocked", level: "warning"});
        assert.deepStrictEqual(out.slice(3), [{type: "error", message: "Pi refused the message: busy", status: 0}, {type: "done", reason: "error"}]);
    },

    bridge_exit_is_an_error() {
        const out = run([{type: "bridge_exit", code: 1, stderr: "line1\nError: no API key"}]);
        assert.ok(out[0].message.includes("exit code 1") && out[0].message.includes("no API key"));
        assert.deepStrictEqual(out[1], {type: "done", reason: "error"});
    },

    send_waits_for_connection_then_prompts_and_aborts() {
        const requests = [];
        let stream = null;
        function xhrFactory() {
            return {readyState: 0, status: 0, responseText: "", headers: {},
                open(m, u) { this.method = m; this.url = u; }, setRequestHeader(k, v) { this.headers[k] = v; },
                abort() { this.aborted = true; },
                send(body) {
                    this.body = body ? JSON.parse(body) : null;
                    if (this.method === "GET") { stream = this; return; }
                    requests.push(this);
                    this.readyState = 4; this.status = 202;
                    this.onreadystatechange();
                }};
        }
        const events = [];
        const handle = PI.send({baseUrl: "http://127.0.0.1:5000", token: "tok", chatId: "chat 1", body: {message: "hi", directory: "/w"},
                                xhrFactory, parserFactory: DB.createSseParser, onEvent: e => events.push(plain(e))});
        assert.deepStrictEqual(events, [{type: "start"}]);
        assert.strictEqual(stream.url, "http://127.0.0.1:5000/chats/chat%201/events");
        assert.strictEqual(stream.headers.Authorization, "Bearer tok");
        assert.strictEqual(requests.length, 0, "prompt waits for the stream to connect");
        stream.readyState = 3; stream.status = 200;
        stream.responseText = 'data: {"type":"bridge_connected","running":false}\n\n';
        stream.onreadystatechange();
        assert.strictEqual(requests.length, 1);
        assert.strictEqual(requests[0].url, "http://127.0.0.1:5000/chats/chat%201/prompt");
        assert.strictEqual(requests[0].headers.Authorization, "Bearer tok");
        assert.deepStrictEqual(requests[0].body, {message: "hi", directory: "/w"});
        stream.responseText += 'data: {"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hel"}}\n\n';
        stream.onreadystatechange();
        assert.deepStrictEqual(events[1], {type: "text_delta", delta: "Hel"});
        handle.abort();
        assert.strictEqual(requests[1].url, "http://127.0.0.1:5000/chats/chat%201/abort");
        assert.ok(stream.aborted);
        assert.deepStrictEqual(events[events.length - 1], {type: "done", reason: "aborted"});
    },

    send_reports_refused_prompt() {
        let stream = null;
        const xhrFactory = () => ({open(m, u) { this.method = m; }, setRequestHeader() {}, abort() {},
            send() {
                if (this.method === "GET") { stream = this; return; }
                this.readyState = 4; this.status = 409; this.responseText = '{"error":"Pi is still working on this chat."}';
                this.onreadystatechange();
            }});
        const events = [];
        PI.send({baseUrl: "http://b", token: "t", chatId: "c", body: {}, xhrFactory, parserFactory: DB.createSseParser,
                 onEvent: e => events.push(plain(e))});
        stream.readyState = 3; stream.responseText = 'data: {"type":"bridge_connected"}\n\n';
        stream.onreadystatechange();
        assert.deepStrictEqual(events.slice(1), [{type: "error", message: "Pi: Pi is still working on this chat.", status: 0},
                                                 {type: "done", reason: "error"}]);
    },

    reply_dialog() {
        const sent = [];
        const xhrFactory = () => ({open(m, u) { this.u = u; }, setRequestHeader() {},
            send(body) { sent.push({u: this.u, body: JSON.parse(body)}); this.readyState = 4; this.status = 200; this.onreadystatechange(); }});
        let ok = null;
        PI.replyDialog({baseUrl: "http://b", token: "t", xhrFactory}, "c", "d1", {value: "No"}, r => { ok = r; });
        PI.replyDialog({baseUrl: "http://b", token: "t", xhrFactory}, "c", "d2", {cancelled: true});
        assert.strictEqual(ok, true);
        assert.deepStrictEqual(plain(sent), [{u: "http://b/chats/c/ui-response", body: {id: "d1", value: "No"}},
                                             {u: "http://b/chats/c/ui-response", body: {id: "d2", cancelled: true}}]);
    },
};

function watchdogRig(statusAnswer) {
    const calls = [];   // [method, path] of the requests that aren't the event stream
    const timers = [];  // {fn, ms, live}
    let stream = null;
    const xhrFactory = () => {
        const x = {open(m, u) { this.m = m; this.u = u; }, setRequestHeader() {},
            send() {
                if (this.m === "GET" && this.u.endsWith("/events")) { stream = this; return; }
                calls.push([this.m, this.u.replace("http://b", "")]);
                this.readyState = 4;
                const a = this.u.endsWith("/status") ? statusAnswer() : [202, "{}"];
                this.status = a[0]; this.responseText = a[1];
                this.onreadystatechange();
            }};
        return x;
    };
    const events = [];
    PI.send({baseUrl: "http://b", token: "t", chatId: "c", body: {}, xhrFactory, parserFactory: DB.createSseParser, stallMs: 60000,
             onEvent: e => events.push(plain(e)),
             timers: {start(ms, fn) { const t = {fn, ms, live: true}; timers.push(t); return t; }, clear(t) { t.live = false; }}});
    let text = "";
    const push = obj => { text += "data: " + JSON.stringify(obj) + "\n\n"; stream.readyState = 3; stream.responseText = text; stream.onreadystatechange(); };
    const live = () => timers.filter(t => t.live);
    const fire = () => { const t = live()[0]; t.live = false; t.fn(); };
    return {calls, events, push, live, fire, timers};
}

const WATCHDOG = {
    watchdog_ends_a_prompt_pi_never_answers() {
        const r = watchdogRig(() => [200, '{"running":true}']);
        assert.strictEqual(r.live().length, 0, "no timer before the bridge accepts the prompt");
        r.push({type: "bridge_connected", running: false});
        assert.strictEqual(r.live().length, 1);
        assert.strictEqual(r.live()[0].ms, 60000);
        r.fire();
        const last = r.events.slice(-2);
        assert.ok(/^Pi stopped responding/.test(last[0].message), last[0].message);
        assert.deepStrictEqual(last[1], {type: "done", reason: "error"});
        assert.ok(!/bridge/.test(last[0].message), "must not trigger the bridge-restart retry");
        assert.deepStrictEqual(r.calls.pop(), ["POST", "/chats/c/close"]);
        assert.strictEqual(r.live().length, 0);
    },

    watchdog_never_cuts_off_a_model_that_keeps_sending() {
        const r = watchdogRig(() => [200, '{"running":true}']);
        r.push({type: "bridge_connected"});
        r.push({type: "response", command: "prompt", success: true});
        const first = r.live()[0];
        r.push({type: "message_update", assistantMessageEvent: {type: "thinking_delta", contentIndex: 0, delta: "hm"}});
        assert.strictEqual(first.live, true, "an event doesn't make a new timer");
        assert.strictEqual(r.live().length, 1);
        // Events came since it started: it starts again without asking the bridge.
        r.fire();
        assert.ok(!r.calls.some(c => c[1] === "/chats/c/status"));
        assert.strictEqual(r.live().length, 1, "re-armed");
        assert.ok(!r.events.some(e => e.type === "error"));
        // Quiet for a minute but the bridge says Pi is still running (a long tool): keep waiting.
        r.fire();
        assert.deepStrictEqual(r.calls.pop(), ["GET", "/chats/c/status"]);
        assert.ok(!r.events.some(e => e.type === "error"));
        assert.strictEqual(r.live().length, 1, "re-armed");
    },

    watchdog_ends_when_the_bridge_says_pi_is_not_running() {
        for (const answer of [[200, '{"running":false,"alive":false}'], [0, ""], [500, "x"]]) {
            const r = watchdogRig(() => answer);
            r.push({type: "bridge_connected"});
            r.push({type: "agent_start"});
            r.fire();   // events came since it started: it starts again
            r.fire();   // a quiet minute: the bridge is asked
            assert.ok(r.events.some(e => e.type === "error" && /^Pi stopped responding/.test(e.message)), JSON.stringify(answer));
            assert.deepStrictEqual(r.events[r.events.length - 1], {type: "done", reason: "error"});
        }
    },

    watchdog_is_cleared_on_completion_and_on_failure() {
        const r = watchdogRig(() => [200, '{"running":true}']);
        r.push({type: "bridge_connected"});
        r.push({type: "agent_start"});
        r.push({type: "agent_settled"});
        assert.strictEqual(r.live().length, 0);
        assert.deepStrictEqual(r.events[r.events.length - 1], {type: "done", reason: "complete"});
        const r2 = watchdogRig(() => [200, '{"running":true}']);
        r2.push({type: "bridge_connected"});
        r2.push({type: "response", command: "prompt", success: false, error: "nope"});
        assert.strictEqual(r2.live().length, 0);
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(Object.assign({}, tests, WATCHDOG))) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + String(e.stack || e).split("\n").slice(0, 4).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
