// Tests for backends/OpenCodeBackend.js, run by tests/test_opencode_backend.py.
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
const OC = load("OpenCodeBackend.js", ["url", "promptBody", "send", "replyPermission", "replyQuestion"]);
OC.createEventMapper = load("OpenCodeEvents.js", ["createEventMapper"]).createEventMapper;
const DB = load("DirectBackend.js", ["createSseParser"]);
const plain = x => JSON.parse(JSON.stringify(x));
const SID = "ses_A";

function ev(type, properties) { return {type, properties: Object.assign({sessionID: SID}, properties)}; }
function run(events) {
    const out = [];
    const m = OC.createEventMapper(SID, e => out.push(plain(e)));
    for (const e of events) m.handle(e);
    return out;
}
const collect = (out, type) => out.filter(e => e.type === type).map(e => e.delta).join("");

// A successful run, shaped like OpenCode 1.18's /doc schemas.
const SUCCESS = [
    ev("message.updated", {info: {id: "msg_u", role: "user"}}),
    ev("message.part.updated", {part: {id: "p_u", messageID: "msg_u", type: "text", text: "Create hello.txt"}}),
    ev("session.status", {status: {type: "busy"}}),
    // Part arrives before its message's role is known: held, then replayed.
    ev("message.part.updated", {part: {id: "p_r", messageID: "msg_a", type: "reasoning", text: "I should "}}),
    ev("message.updated", {info: {id: "msg_a", role: "assistant"}}),
    ev("message.part.delta", {messageID: "msg_a", partID: "p_r", field: "text", delta: "write it."}),
    ev("message.part.updated", {part: {id: "p_t1", messageID: "msg_a", type: "tool", callID: "c1", tool: "write",
                                       state: {status: "pending", input: {filePath: "hello.txt"}, raw: ""}}}),
    ev("permission.asked", {id: "per_1", permission: "edit", patterns: ["hello.txt"], metadata: {}, always: []}),
    ev("permission.replied", {requestID: "per_1", reply: "once"}),
    ev("message.part.updated", {part: {id: "p_t1", messageID: "msg_a", type: "tool", callID: "c1", tool: "write",
                                       state: {status: "running", input: {filePath: "hello.txt"}, title: "hello.txt", time: {}}}}),
    // The write tool reports the edit while it runs (file.edited carries no session id).
    {type: "file.edited", properties: {file: "/work/hello.txt"}},
    ev("message.part.updated", {part: {id: "p_t1", messageID: "msg_a", type: "tool", callID: "c1", tool: "write",
                                       state: {status: "completed", input: {}, output: "Wrote file", title: "hello.txt", metadata: {}, time: {}}}}),
    // Another session of the same folder edits a file: not this reply's.
    {type: "file.edited", properties: {file: "/work/other.txt"}},
    ev("message.part.updated", {part: {id: "p_x", messageID: "msg_a", type: "text", text: ""}}),
    ev("message.part.delta", {messageID: "msg_a", partID: "p_x", field: "text", delta: "do"}),
    ev("message.part.delta", {messageID: "msg_a", partID: "p_x", field: "text", delta: "ne"}),
    ev("message.part.updated", {part: {id: "p_x", messageID: "msg_a", type: "text", text: "done"}}),
    ev("message.part.updated", {part: {id: "p_s", messageID: "msg_a", type: "step-finish", reason: "stop", cost: 0.001,
                                       tokens: {input: 900, output: 12, reasoning: 5}}}),
    ev("message.part.updated", {part: {id: "p_other", messageID: "msg_a", type: "text", text: "x"}, sessionID: "ses_OTHER"}),
    ev("session.status", {status: {type: "idle"}}),
    ev("session.idle", {}),
];

const tests = {
    url_and_directory() {
        assert.strictEqual(OC.url("http://127.0.0.1:4096/v1/", "/session", "/home/me/my project"),
                           "http://127.0.0.1:4096/session?directory=%2Fhome%2Fme%2Fmy%20project");
        assert.strictEqual(OC.url("http://h:1", "/event", ""), "http://h:1/event");
    },

    prompt_body_model_and_agent() {
        assert.deepStrictEqual(plain(OC.promptBody({parts: [{type: "text", text: "hi"}], providerId: "openrouter", modelId: "openrouter/auto"})),
                               {parts: [{type: "text", text: "hi"}], model: {providerID: "openrouter", modelID: "openrouter/auto"}});
        const withAgent = plain(OC.promptBody({parts: [], agent: "build", providerId: "p", modelId: "m"}));
        assert.deepStrictEqual(withAgent.model, {providerID: "p", modelID: "m"}, "the chosen model wins over the agent's own");
        assert.strictEqual(withAgent.agent, "build");
        assert.ok(!("model" in plain(OC.promptBody({parts: [], agent: "build", providerId: "p", modelId: "m", useAgentModel: true}))),
                  "the agent's own model only when asked for");
        assert.ok(!("model" in plain(OC.promptBody({parts: [], agent: "build", providerId: "", modelId: ""}))), "no model chosen: the agent's");
        assert.ok(!("model" in plain(OC.promptBody({parts: [], providerId: "", modelId: ""}))), "no empty model");
    },

    success_stream_maps_to_backend_events() {
        const out = run(SUCCESS);
        assert.strictEqual(collect(out, "text_delta"), "done");
        assert.strictEqual(collect(out, "reasoning_delta"), "I should write it.");
        assert.ok(!collect(out, "text_delta").includes("Create hello.txt"), "the user's own text must not be echoed");
        const tools = out.filter(e => e.type.startsWith("tool_"));
        assert.deepStrictEqual(tools.map(e => e.type), ["tool_start", "tool_update", "tool_end"]);
        assert.deepStrictEqual(tools[0], {type: "tool_start", callId: "c1", name: "write", input: {filePath: "hello.txt"}});
        assert.strictEqual(tools[2].output, "Wrote file");
        assert.strictEqual(tools[2].isError, false);
        assert.deepStrictEqual(out.find(e => e.type === "permission_request"),
                               {type: "permission_request", id: "per_1", permission: "edit", patterns: ["hello.txt"], metadata: {}});
        assert.deepStrictEqual(out.find(e => e.type === "permission_resolved"), {type: "permission_resolved", id: "per_1", reply: "once"});
        assert.deepStrictEqual(out.filter(e => e.type === "file_changed"), [{type: "file_changed", path: "/work/hello.txt"}]);
        assert.deepStrictEqual(out.find(e => e.type === "usage"), {type: "usage", input: 900, output: 12, reasoning: 5, cost: 0.001});
        assert.deepStrictEqual(out.filter(e => e.type === "done"), [{type: "done", reason: "complete"}]);
    },

    idle_before_work_is_ignored() {
        const out = run([ev("session.idle", {}), ev("session.status", {status: {type: "idle"}})]);
        assert.deepStrictEqual(out, []);
    },

    tool_error() {
        const out = run([
            ev("session.status", {status: {type: "busy"}}),
            ev("message.updated", {info: {id: "m", role: "assistant"}}),
            ev("message.part.updated", {part: {id: "t", messageID: "m", type: "tool", callID: "c", tool: "bash",
                                               state: {status: "error", input: {command: "false"}, error: "exit 1", time: {}}}}),
        ]);
        const end = out.find(e => e.type === "tool_end");
        assert.strictEqual(end.isError, true);
        assert.strictEqual(end.output, "exit 1");
    },

    v2_permission_and_questions() {
        const out = run([
            ev("permission.v2.asked", {id: "p2", action: "bash", resources: ["rm -rf build"], save: [], metadata: {}, source: {}}),
            ev("question.asked", {id: "q1", questions: [{question: "Which?", options: [{label: "A"}]}]}),
            ev("question.rejected", {requestID: "q1"}),
        ]);
        assert.strictEqual(out[0].permission, "bash");
        assert.deepStrictEqual(out[0].patterns, ["rm -rf build"]);
        assert.strictEqual(out[1].type, "question_request");
        assert.deepStrictEqual(out[2], {type: "question_resolved", id: "q1", status: "dismissed"});
    },

    real_recording_openrouter_402() {
        // Recorded from OpenCode 1.18.31 with an OpenRouter account short of credits.
        const text = fs.readFileSync(path.join(__dirname, "../fixtures/opencode-1.18-openrouter-402.sse"), "utf8");
        const sid = /"sessionID":"(ses_[^"]+)"/.exec(text)[1];
        const out = [];
        const m = OC.createEventMapper(sid, e => out.push(plain(e)));
        const p = DB.createSseParser(msg => m.handle(JSON.parse(msg.data)));
        p.push(text); p.end();
        const errors = out.filter(e => e.type === "error");
        assert.strictEqual(errors.length, 1, "one error, not one per event");
        assert.ok(errors[0].message.includes("requires more credits"), errors[0].message);
        assert.strictEqual(collect(out, "text_delta"), "", "the prompt text must not be echoed");
        assert.deepStrictEqual(out[out.length - 1], {type: "done", reason: "error"});
    },

    global_event_envelope() {
        const out = run([{directory: "/w", payload: ev("session.status", {status: {type: "busy"}})},
                         {directory: "/w", payload: ev("session.idle", {})}]);
        assert.deepStrictEqual(out, [{type: "done", reason: "complete"}]);
    },

    send_creates_session_waits_for_connection_then_prompts() {
        const requests = [];
        let stream = null;
        function xhrFactory() {
            const x = {readyState: 0, status: 0, responseText: "", headers: {},
                open(m, u) { this.method = m; this.url = u; }, setRequestHeader(k, v) { this.headers[k] = v; },
                abort() { this.aborted = true; },
                send(body) {
                    this.body = body ? JSON.parse(body) : null;
                    if (this.method === "GET") { stream = this; return; }
                    requests.push(this);
                    this.readyState = 4;
                    if (this.url.includes("/session?")) { this.status = 200; this.responseText = '{"id":"ses_new"}'; }
                    else this.status = 204;
                    this.onreadystatechange();
                }};
            return x;
        }
        const events = [];
        const handle = OC.send({baseUrl: "http://127.0.0.1:4096", directory: "/w", sessionId: "", title: "T",
                                body: {parts: [{type: "text", text: "hi"}]}, xhrFactory, parserFactory: DB.createSseParser, mapperFactory: OC.createEventMapper,
                                onEvent: e => events.push(plain(e))});
        assert.deepStrictEqual(events.slice(0, 2), [{type: "session", id: "ses_new"}, {type: "start"}]);
        assert.ok(stream.url.endsWith("/event?directory=%2Fw"));
        assert.strictEqual(requests.length, 1, "prompt waits for the stream to connect");
        stream.readyState = 3; stream.status = 200;
        stream.responseText = 'data: {"type":"server.connected","properties":{}}\n\n';
        stream.onreadystatechange();
        assert.strictEqual(requests.length, 2);
        assert.ok(requests[1].url.startsWith("http://127.0.0.1:4096/session/ses_new/prompt_async?directory="));
        assert.deepStrictEqual(requests[1].body, {parts: [{type: "text", text: "hi"}]});
        handle.abort();
        assert.ok(requests[2].url.includes("/session/ses_new/abort"));
        assert.ok(stream.aborted);
        assert.deepStrictEqual(events[events.length - 1], {type: "done", reason: "aborted"});
    },

    permission_and_question_replies() {
        const sent = [];
        const xhrFactory = () => ({open(m, u) { this.m = m; this.u = u; }, setRequestHeader() {},
            send(body) { sent.push({m: this.m, u: this.u, body: body ? JSON.parse(body) : null}); this.readyState = 4; this.status = 200; this.onreadystatechange(); }});
        const target = {baseUrl: "http://127.0.0.1:4096", directory: "/w", xhrFactory};
        let ok = null;
        OC.replyPermission(target, "per_1", "once", r => { ok = r; });
        OC.replyQuestion(target, "q 1", [["A"], ["B", "C"]], () => {});
        OC.replyQuestion(target, "q2", null, () => {});
        assert.strictEqual(ok, true);
        assert.deepStrictEqual(plain(sent), [
            {m: "POST", u: "http://127.0.0.1:4096/permission/per_1/reply?directory=%2Fw", body: {reply: "once"}},
            {m: "POST", u: "http://127.0.0.1:4096/question/q%201/reply?directory=%2Fw", body: {answers: [["A"], ["B", "C"]]}},
            {m: "POST", u: "http://127.0.0.1:4096/question/q2/reject?directory=%2Fw", body: null},
        ]);
    },

    send_reports_unreachable_server() {
        const events = [];
        OC.send({baseUrl: "http://127.0.0.1:1", directory: "", sessionId: "", body: {}, parserFactory: DB.createSseParser, mapperFactory: OC.createEventMapper,
                 xhrFactory: () => ({open() {}, setRequestHeader() {}, send() { this.onerror(); }}),
                 onEvent: e => events.push(plain(e))});
        assert.ok(events[0].message.includes("could not reach"), events[0].message);
        assert.deepStrictEqual(events[1], {type: "done", reason: "error"});
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + String(e.stack || e).split("\n").slice(0, 4).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
