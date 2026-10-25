// Regression tests for OpenCode mode's agent list, session and event syncing
// (backends/OpenCodeBackend.js, OpenCodeAgents.js, OpenCodeHistory.js), run
// by tests/test_opencode_stability.py. Fixtures under tests/fixtures/ were
// recorded from OpenCode 1.18.31.
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
const OC = load("OpenCodeBackend.js", ["send"]);
OC.createEventMapper = load("OpenCodeEvents.js", ["createEventMapper"]).createEventMapper;
const DB = load("DirectBackend.js", ["createSseParser"]);
const Agents = load("OpenCodeAgents.js", ["normalize", "comboModel", "indexOf"]);
const History = load("OpenCodeHistory.js", ["toMessages"]);
const AgentEvents = load("AgentEvents.js", ["applyToReply"]);
const plain = x => JSON.parse(JSON.stringify(x));
const fixture = name => fs.readFileSync(path.join(__dirname, "../fixtures", name), "utf8");
const texts = (out, type) => out.filter(e => e.type === type).map(e => e.delta).join("");

function mapFixture(text, sid, extra) {
    const out = [];
    const m = OC.createEventMapper(sid, e => out.push(plain(e)));
    const p = DB.createSseParser(msg => m.handle(JSON.parse(msg.data)));
    p.push(text + (extra || []).map(e => "data: " + JSON.stringify(e) + "\n\n").join(""));
    p.end();
    return out;
}

// A fake `opencode serve`: route(method, url, body) answers {status, text},
// or null to answer later with server.answer(xhr, status, text). /event
// requests become streams the test writes to.
function fakeServer(route) {
    const srv = {requests: [], streams: [], waiting: [], timers: []};
    srv.xhrFactory = () => ({
        readyState: 0, status: 0, responseText: "",
        open(method, url) { this.method = method; this.url = url; },
        setRequestHeader() {},
        abort() { this.aborted = true; },
        send(body) {
            this.body = body ? JSON.parse(body) : null;
            if (this.method === "GET" && /\/event(\?|$)/.test(this.url)) { srv.streams.push(this); return; }
            srv.requests.push(this);
            const answer = route(this.method, this.url, this.body);
            if (answer) srv.answer(this, answer.status, answer.text);
            else srv.waiting.push(this);
        }
    });
    srv.answer = (xhr, status, text) => {
        xhr.readyState = 4; xhr.status = status; xhr.responseText = text || ""; xhr.onreadystatechange();
    };
    srv.write = (stream, events) => {
        stream.readyState = 3; stream.status = 200;
        stream.responseText += events.map(e => "data: " + JSON.stringify(e) + "\n\n").join("");
        stream.onreadystatechange();
    };
    srv.drop = stream => { stream.readyState = 4; stream.onreadystatechange(); };
    srv.later = (fn, ms) => srv.timers.push({fn, ms});
    srv.tick = () => { const due = srv.timers; srv.timers = []; due.forEach(t => t.fn()); };
    srv.paths = () => srv.requests.map(r => r.method + " " + r.url.replace(/^http:\/\/[^/]+/, "").replace(/\?.*$/, ""));
    return srv;
}
const json = (status, data) => ({status, text: JSON.stringify(data)});
const ev = (sid, type, properties) => ({type, properties: Object.assign({sessionID: sid}, properties)});
const CONNECTED = {type: "server.connected", properties: {}};

function start(srv, sessionId, extra) {
    const events = [];
    const handle = OC.send(Object.assign({baseUrl: "http://127.0.0.1:4096", directory: "/w", sessionId, title: "T",
                                          body: {parts: [{type: "text", text: "hi"}]}, xhrFactory: srv.xhrFactory,
                                          parserFactory: DB.createSseParser, mapperFactory: OC.createEventMapper, later: srv.later,
                                          onEvent: e => events.push(plain(e))}, extra || {}));
    return {events, handle};
}

const tests = {
    recorded_reply_streams_once_and_completes() {
        const out = mapFixture(fixture("opencode-1.18-reply.sse"), "ses_e8db7237dffeAQ59l2IiIhGDKF");
        assert.strictEqual(texts(out, "text_delta"), "pong");
        assert.deepStrictEqual(out[out.length - 1], {type: "done", reason: "complete"});
        assert.strictEqual(out.filter(e => e.type === "usage").length, 1);
    },

    subagent_requests_reach_the_chat_but_not_its_errors() {
        // Recorded: the main session starts a subagent (session.created with
        // parentID); the subagent fails ("Model not found"), then the main
        // reply runs out of credits. A permission or question the subagent
        // asks carries the subagent's session id and must still be shown, or
        // the subagent waits for an answer forever.
        const text = fixture("opencode-1.18-subagent.sse");
        const main = "ses_e8db2b6dcffefGnaq4B56lXeLs";
        const child = "ses_e8db25defffe1IjtleDmlKMtnq";
        assert.ok(text.includes('"parentID":"' + main + '"'));
        const out = mapFixture(text.replace(/data: \{"id":"evt_[^"]*","type":"session\.status","properties":\{"sessionID":"ses_e8db2b6dcffefGnaq4B56lXeLs","status":\{"type":"idle"\}\}\}\n\n[\s\S]*$/, ""), main, [
            ev(child, "permission.asked", {id: "per_child", permission: "bash", patterns: ["echo hi"], metadata: {}, always: []}),
            ev("ses_unrelated", "question.asked", {id: "que_other", questions: []}),
            ev(child, "permission.replied", {requestID: "per_child", reply: "once"}),
            ev(main, "session.status", {status: {type: "idle"}}),
        ]);
        assert.deepStrictEqual(out.filter(e => e.type === "permission_request").map(e => e.id), ["per_child"]);
        assert.deepStrictEqual(out.filter(e => e.type === "permission_resolved").map(e => e.id), ["per_child"]);
        assert.strictEqual(out.filter(e => e.type === "question_request").length, 0, "another session's question");
        const errors = out.filter(e => e.type === "error").map(e => e.message);
        assert.strictEqual(errors.length, 1, JSON.stringify(errors));
        assert.ok(errors[0].includes("credits"), errors[0]);
        assert.ok(out.some(e => e.type === "tool_start" && e.name === "task"));
        assert.deepStrictEqual(out[out.length - 1], {type: "done", reason: "error"});
    },

    usage_is_counted_once_per_step() {
        const S = "ses_A";
        const step = ev(S, "message.part.updated", {part: {id: "p_s", messageID: "m", type: "step-finish", cost: 0.5, tokens: {input: 9, output: 2}}});
        const out = [];
        const m = OC.createEventMapper(S, e => out.push(plain(e)));
        [ev(S, "message.updated", {info: {id: "m", role: "assistant"}}), step, step].forEach(m.handle);
        assert.strictEqual(out.filter(e => e.type === "usage").length, 1);
    },

    lost_stream_reconnects_and_catches_up_without_repeating() {
        const history = [
            {info: {id: "u1", role: "user"}, parts: [{id: "pu1", messageID: "u1", type: "text", text: "earlier"}]},
            {info: {id: "a0", role: "assistant"}, parts: [{id: "pa0", messageID: "a0", type: "text", text: "old reply"}]},
            {info: {id: "u2", role: "user"}, parts: [{id: "pu2", messageID: "u2", type: "text", text: "hi"}]},
            {info: {id: "a1", role: "assistant"}, parts: [
                {id: "p1", messageID: "a1", type: "text", text: "Hello world"},
                {id: "s1", messageID: "a1", type: "step-finish", cost: 0, tokens: {input: 5, output: 2}}]},
        ];
        const srv = fakeServer((method, url) => {
            if (url.includes("/prompt_async")) return {status: 204};
            if (url.includes("/session/ses_A/message")) return json(200, history);
            if (url.includes("/permission?")) return json(200, [{id: "per_9", sessionID: "ses_A", permission: "bash", patterns: ["ls"], metadata: {}, always: []}]);
            if (url.includes("/question?")) return json(200, []);
            if (url.includes("/session/status")) return json(200, {});
            return json(404, {});
        });
        const {events} = start(srv, "ses_A");
        srv.write(srv.streams[0], [CONNECTED, ev("ses_A", "session.status", {status: {type: "busy"}}),
                                   ev("ses_A", "message.updated", {info: {id: "a1", role: "assistant"}}),
                                   ev("ses_A", "message.part.updated", {part: {id: "p1", messageID: "a1", type: "text", text: ""}}),
                                   ev("ses_A", "message.part.delta", {messageID: "a1", partID: "p1", field: "text", delta: "Hello"})]);
        srv.drop(srv.streams[0]);
        assert.ok(!events.some(e => e.type === "error" || e.type === "done"), JSON.stringify(events));
        assert.deepStrictEqual(srv.timers.map(t => t.ms), [500]);
        srv.tick();
        assert.strictEqual(srv.streams.length, 2, "the event stream is reopened");
        srv.write(srv.streams[1], [CONNECTED]);
        assert.strictEqual(texts(events, "text_delta"), "Hello world");
        assert.deepStrictEqual(events.filter(e => e.type === "permission_request").map(e => e.id), ["per_9"]);
        assert.strictEqual(events.filter(e => e.type === "usage").length, 1);
        assert.deepStrictEqual(events[events.length - 1], {type: "done", reason: "complete"});
        assert.strictEqual(srv.paths().filter(p => p.includes("prompt_async")).length, 1, "the prompt is sent once");
    },

    reconnect_while_still_busy_keeps_streaming() {
        const srv = fakeServer((method, url) => {
            if (url.includes("/prompt_async")) return {status: 204};
            if (url.includes("/session/ses_A/message")) return json(200, []);
            if (url.includes("/session/status")) return json(200, {ses_A: {type: "busy"}});
            return json(200, []);
        });
        const {events} = start(srv, "ses_A");
        srv.write(srv.streams[0], [CONNECTED]);
        srv.drop(srv.streams[0]);
        srv.tick();
        srv.write(srv.streams[1], [CONNECTED]);
        assert.ok(!events.some(e => e.type === "done"));
        srv.write(srv.streams[1], [ev("ses_A", "session.status", {status: {type: "idle"}})]);
        assert.deepStrictEqual(events[events.length - 1], {type: "done", reason: "complete"});
    },

    gives_up_after_the_reconnect_limit() {
        const srv = fakeServer(() => ({status: 204}));
        const {events} = start(srv, "ses_A", {maxReconnects: 2});
        for (let i = 0; i < 3; i++) {
            srv.drop(srv.streams[i]);
            srv.tick();
        }
        assert.strictEqual(srv.streams.length, 3);
        assert.ok(events.some(e => e.type === "error" && e.message.includes("lost the connection")), JSON.stringify(events));
        assert.deepStrictEqual(events[events.length - 1], {type: "done", reason: "error"});
    },

    unknown_session_is_replaced_once() {
        // Recorded answer of OpenCode 1.18 for a session it doesn't have.
        const gone = json(404, {name: "NotFoundError", data: {message: "Session not found: ses_gone"}});
        const srv = fakeServer((method, url) => {
            if (url.includes("/session/ses_gone/prompt_async")) return gone;
            if (method === "POST" && /\/session\?/.test(url)) return json(200, {id: "ses_new"});
            if (url.includes("/session/ses_new/prompt_async")) return {status: 204};
            return json(404, {});
        });
        const {events} = start(srv, "ses_gone");
        srv.write(srv.streams[0], [CONNECTED]);
        assert.deepStrictEqual(srv.paths(), ["POST /session/ses_gone/prompt_async", "POST /session", "POST /session/ses_new/prompt_async"]);
        assert.ok(events.some(e => e.type === "session" && e.id === "ses_new"));
        assert.ok(events.some(e => e.type === "notice"));
        assert.ok(!events.some(e => e.type === "error"), JSON.stringify(events));
        srv.write(srv.streams[0], [ev("ses_gone", "session.status", {status: {type: "busy"}}),
                                   ev("ses_new", "session.status", {status: {type: "busy"}}),
                                   ev("ses_new", "session.idle", {})]);
        assert.deepStrictEqual(events[events.length - 1], {type: "done", reason: "complete"});
    },

    stopping_while_the_session_is_created_opens_no_stream() {
        const srv = fakeServer(() => null);
        const {events, handle} = start(srv, "");
        handle.abort();
        srv.answer(srv.waiting[0], 200, '{"id":"ses_late"}');
        assert.strictEqual(srv.streams.length, 0, "an event stream nobody closes");
        assert.deepStrictEqual(events, [{type: "done", reason: "aborted"}]);
    },

    recorded_agent_list_offers_only_primary_agents() {
        const list = Agents.normalize(JSON.parse(fixture("opencode-1.18-agents.json")));
        // helper is the workspace's own subagent; compaction/summary/title are hidden.
        assert.deepStrictEqual(plain(list.map(a => a.value)), ["build", "architect", "go", "plan"]);
        // A user's own primary agent may be called "general" when it says its mode.
        assert.deepStrictEqual(plain(Agents.normalize([{name: "general", mode: "primary"}, "title", "mine"]).map(a => a.value)), ["general", "mine"]);
        assert.deepStrictEqual(plain(Agents.normalize({agents: [{name: "a", mode: "all"}, {name: "b", hidden: true}]}).map(a => a.value)), ["a"]);
    },

    agent_selector_always_shows_the_chats_agent() {
        const list = [{text: "build", value: "build"}, {text: "plan", value: "plan"}];
        assert.deepStrictEqual(plain(Agents.comboModel(list, "plan")), list);
        const unknown = Agents.comboModel(list, "review");
        assert.strictEqual(Agents.indexOf(unknown, "review"), 2);
        assert.ok(unknown[2].text.includes("review"));
        const none = Agents.comboModel(list, "");
        assert.strictEqual(Agents.indexOf(none, ""), 0);
        assert.deepStrictEqual(plain(Agents.comboModel([], "plan")), [{text: "plan", value: "plan"}]);
    },

    recorded_history_syncs_like_a_live_reply() {
        const history = JSON.parse(fixture("opencode-1.18-history.json"));
        const msgs = History.toMessages(history, {createEventMapper: OC.createEventMapper, applyToReply: AgentEvents.applyToReply,
                                                   formatTime: ms => "t" + ms, sessionId: "ses_e8db2b6dcffefGnaq4B56lXeLs", now: 1});
        assert.deepStrictEqual(plain(msgs.map(m => m.role)), ["user", "assistant"], "one reply for the turn's steps");
        const reply = msgs[1];
        assert.strictEqual(reply.at, history[1].info.time.created);
        assert.strictEqual(reply.time, "t" + history[1].info.time.created);
        assert.strictEqual(Object.keys(reply.tools).length, 2);
        assert.ok(Object.values(reply.tools).every(t => t.name === "task" && t.status === "error"));
        assert.ok(reply.reasoning.length > 0);
        assert.ok(reply.notices.some(n => n.includes("credits")), JSON.stringify(reply.notices));
        assert.deepStrictEqual(plain(reply.tokens), {input: history[2].info.tokens.input, output: history[2].info.tokens.output});
        assert.strictEqual(msgs[0].content, history[0].parts[0].text);
        assert.strictEqual(msgs[0].at, history[0].info.time.created);
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + String(e.stack || e).split("\n").slice(0, 6).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
