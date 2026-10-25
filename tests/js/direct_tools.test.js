// Tests for backends/DirectTools.js and the tool hooks of backends/DirectBackend.js,
// run by tests/test_direct_tools.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const read = name => fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/backends/" + name), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(read("DirectBackend.js") + "\n" + read("DirectStream.js") + "\n" + read("DirectTools.js")
    + "\nthis.exports = {send, buildRequest, rejectsTools, createThinkSplitter, toolDefinitions, createCollector, askUserQuestion,"
    + " assistantMessage, resultMessages, historyMessages, hasToolRounds, parseArgs, ASK_USER, MAX_ROUNDS};", ctx);
const T = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));

function fakeXhr(status, chunks) {
    return {
        readyState: 0, status: 0, responseText: "", sent: null,
        open() {}, setRequestHeader() {}, send(body) { this.sent = JSON.parse(body); }, abort() {},
        play() {
            this.status = status;
            for (const c of chunks) { this.responseText += c; this.readyState = 3; this.onreadystatechange(); }
            this.readyState = 4; this.onreadystatechange();
        },
    };
}

const sse = obj => "data: " + JSON.stringify(obj) + "\n\n";

function runSend(options, status, chunks) {
    const xhr = fakeXhr(status, chunks);
    const events = [];
    T.send(Object.assign({xhrFactory: () => xhr, onEvent: e => events.push(e), thinkFactory: T.createThinkSplitter}, options));
    xhr.play();
    return {xhr, events};
}

const askCall = {id: "call_1", name: "ask_user", args: {question: "Which one?", options: ["A", "B"]}};

const tests = {
    tool_definitions_per_provider_and_none_when_off() {
        assert.deepStrictEqual(plain(T.toolDefinitions("openai", {askUser: false})), []);
        assert.deepStrictEqual(plain(T.toolDefinitions("anthropic", {})), []);
        const openai = plain(T.toolDefinitions("openai", {askUser: true}));
        assert.strictEqual(openai[0].type, "function");
        assert.strictEqual(openai[0].function.name, "ask_user");
        assert.deepStrictEqual(openai[0].function.parameters.required, ["question"]);
        assert.deepStrictEqual(Object.keys(openai[0].function.parameters.properties), ["question", "options", "allow_typed"]);
        const anth = plain(T.toolDefinitions("anthropic", {askUser: true}));
        assert.strictEqual(anth[0].name, "ask_user");
        assert.strictEqual(anth[0].input_schema.type, "object");
    },

    request_carries_tools_only_when_given() {
        const tools = T.toolDefinitions("openai", {askUser: true});
        const base = {type: "openai", baseUrl: "https://tools-a.test/v1", model: "m", messages: []};
        assert.ok(!("tools" in T.buildRequest(base).body));
        assert.ok(!("tools" in T.buildRequest(Object.assign({tools: []}, base)).body));
        assert.strictEqual(T.buildRequest(Object.assign({tools}, base)).body.tools[0].function.name, "ask_user");
        const anth = T.buildRequest({type: "anthropic", model: "c", messages: [], tools: T.toolDefinitions("anthropic", {askUser: true})});
        assert.strictEqual(anth.body.tools[0].name, "ask_user");
    },

    openai_stream_accumulates_tool_call_arguments_by_index() {
        const collector = T.createCollector("openai");
        const {events} = runSend({type: "openai", baseUrl: "https://tools-b.test/v1", model: "m", messages: [], collector, tools: [{x: 1}]}, 200, [
            sse({choices: [{delta: {content: "Let me ask. "}}]}),
            sse({choices: [{delta: {tool_calls: [{index: 0, id: "call_a", type: "function", function: {name: "ask_user", arguments: ""}}]}}]}),
            sse({choices: [{delta: {tool_calls: [{index: 0, function: {arguments: "{\"question\":\"Pi"}}]}}]}),
            sse({choices: [{delta: {tool_calls: [{index: 1, id: "call_b", type: "function", function: {name: "other", arguments: "{}"}}]}}]}),
            sse({choices: [{delta: {tool_calls: [{index: 0, function: {arguments: "ck?\",\"options\":[\"A\",\"B\"]}"}}]}}]}),
            sse({choices: [{delta: {}, finish_reason: "tool_calls"}]}),
            "data: [DONE]\n\n",
        ]);
        assert.strictEqual(events.filter(e => e.type === "text_delta").map(e => e.delta).join(""), "Let me ask. ");
        const calls = events.find(e => e.type === "tool_calls");
        assert.ok(calls, JSON.stringify(events));
        assert.deepStrictEqual(plain(calls.calls), [
            {id: "call_a", name: "ask_user", args: {question: "Pick?", options: ["A", "B"]}},
            {id: "call_b", name: "other", args: {}}]);
        const types = events.map(e => e.type);
        assert.ok(types.indexOf("tool_calls") < types.indexOf("done"), "tool_calls comes before done");
        assert.strictEqual(events[events.length - 1].reason, "complete");
    },

    openai_without_index_or_id_in_later_chunks_still_joins_the_call() {
        const c = T.createCollector("openai");
        c.stream({choices: [{delta: {tool_calls: [{id: "x1", function: {name: "ask_user", arguments: "{\"question\":"}}]}}]});
        c.stream({choices: [{delta: {tool_calls: [{function: {arguments: "\"Hi\"}"}}]}}]});
        assert.deepStrictEqual(plain(c.calls()), [{id: "x1", name: "ask_user", args: {question: "Hi"}}]);
    },

    openai_call_without_an_id_gets_one_and_bad_json_gives_empty_args() {
        const c = T.createCollector("openai");
        c.stream({choices: [{delta: {tool_calls: [{index: 0, function: {name: "ask_user", arguments: "{not json"}}]}}]});
        const calls = plain(c.calls());
        assert.strictEqual(calls[0].id, "call_0");
        assert.deepStrictEqual(calls[0].args, {});
    },

    anthropic_stream_collects_tool_use_and_thinking_blocks() {
        const collector = T.createCollector("anthropic");
        const {events} = runSend({type: "anthropic", model: "c", messages: [], collector, tools: [{x: 1}]}, 200, [
            sse({type: "message_start", message: {usage: {input_tokens: 9, output_tokens: 1}}}),
            sse({type: "content_block_start", index: 0, content_block: {type: "thinking", thinking: ""}}),
            sse({type: "content_block_delta", index: 0, delta: {type: "thinking_delta", thinking: "hm"}}),
            sse({type: "content_block_delta", index: 0, delta: {type: "signature_delta", signature: "SIG"}}),
            sse({type: "content_block_start", index: 1, content_block: {type: "text", text: ""}}),
            sse({type: "content_block_delta", index: 1, delta: {type: "text_delta", text: "Asking."}}),
            sse({type: "content_block_start", index: 2, content_block: {type: "tool_use", id: "toolu_1", name: "ask_user", input: {}}}),
            sse({type: "content_block_delta", index: 2, delta: {type: "input_json_delta", partial_json: "{\"question\":"}}),
            sse({type: "content_block_delta", index: 2, delta: {type: "input_json_delta", partial_json: "\"Which?\",\"allow_typed\":false}"}}),
            sse({type: "content_block_stop", index: 2}),
            sse({type: "message_delta", delta: {stop_reason: "tool_use"}, usage: {output_tokens: 20}}),
            sse({type: "message_stop"}),
        ]);
        assert.strictEqual(events.filter(e => e.type === "text_delta").map(e => e.delta).join(""), "Asking.");
        const ev = events.find(e => e.type === "tool_calls");
        assert.deepStrictEqual(plain(ev.calls), [{id: "toolu_1", name: "ask_user", args: {question: "Which?", allow_typed: false}}]);
        assert.deepStrictEqual(plain(ev.thinking), [{type: "thinking", thinking: "hm", signature: "SIG"}]);
    },

    complete_responses_are_collected_too() {
        const openai = T.createCollector("openai");
        runSend({type: "openai", baseUrl: "https://tools-c.test/v1", model: "m", messages: [], stream: false, collector: openai, tools: [{x: 1}]}, 200, [
            JSON.stringify({choices: [{message: {content: null, tool_calls: [{id: "c9", type: "function", function: {name: "ask_user", arguments: "{\"question\":\"Q\"}"}}]}}]})]);
        assert.deepStrictEqual(plain(openai.calls()), [{id: "c9", name: "ask_user", args: {question: "Q"}}]);
        const anth = T.createCollector("anthropic");
        runSend({type: "anthropic", model: "c", messages: [], stream: false, collector: anth, tools: [{x: 1}]}, 200, [
            JSON.stringify({content: [{type: "text", text: "t"}, {type: "tool_use", id: "tu", name: "ask_user", input: {question: "Q2"}}]})]);
        assert.deepStrictEqual(plain(anth.calls()), [{id: "tu", name: "ask_user", args: {question: "Q2"}}]);
    },

    a_reply_without_tool_calls_emits_no_tool_calls_event() {
        const {events} = runSend({type: "openai", baseUrl: "https://tools-d.test/v1", model: "m", messages: [], collector: T.createCollector("openai"), tools: [{x: 1}]}, 200, [
            sse({choices: [{delta: {content: "Plain answer"}}]}), "data: [DONE]\n\n"]);
        assert.ok(!events.some(e => e.type === "tool_calls"));
        assert.strictEqual(events[events.length - 1].reason, "complete");
    },

    a_400_about_tools_retries_once_without_them_and_remembers_the_model() {
        const first = fakeXhr(400, ['{"error":{"message":"This model does not support tools"}}']);
        const second = fakeXhr(200, [sse({choices: [{delta: {content: "ok"}}]}) + "data: [DONE]\n\n"]);
        const xhrs = [first, second];
        const events = [];
        const messages = [{role: "assistant", content: "x", tool_calls: []}, {role: "tool", tool_call_id: "1", content: "r"}];
        const plainMessages = [{role: "assistant", content: "x"}];
        const options = {type: "openai", baseUrl: "https://notools.test/v1", model: "dumb", messages, plainMessages,
                         tools: T.toolDefinitions("openai", {askUser: true}), collector: T.createCollector("openai"),
                         xhrFactory: () => xhrs.shift(), onEvent: e => events.push(e), thinkFactory: T.createThinkSplitter};
        assert.strictEqual(T.rejectsTools(options), false);
        T.send(options);
        first.play();
        assert.ok(first.sent.tools);
        assert.strictEqual(first.sent.messages.length, 2);
        assert.ok(second.sent, "retried");
        assert.ok(!("tools" in second.sent));
        assert.deepStrictEqual(plain(second.sent.messages), plainMessages, "the retry sends the history as text");
        second.play();
        assert.strictEqual(events[events.length - 1].reason, "complete");
        assert.strictEqual(events.filter(e => e.type === "error").length, 0);
        assert.strictEqual(T.rejectsTools(options), true);
        assert.ok(!("tools" in T.buildRequest(options).body));
        // only this model: another model on the same server still gets tools
        assert.ok("tools" in T.buildRequest(Object.assign({}, options, {model: "smart"})).body);
    },

    a_400_that_does_not_mention_tools_is_not_retried() {
        const first = fakeXhr(400, ['{"error":{"message":"max_tokens is too large"}}']);
        let made = 0;
        const events = [];
        T.send({type: "openai", baseUrl: "https://notools2.test/v1", model: "m", messages: [], tools: [{x: 1}], xhrFactory: () => { made++; return first; },
                onEvent: e => events.push(e), thinkFactory: T.createThinkSplitter});
        first.play();
        assert.strictEqual(made, 1);
        assert.ok(events.some(e => e.type === "error"));
    },

    ask_user_arguments_are_made_safe() {
        assert.deepStrictEqual(plain(T.askUserQuestion({question: " Hi ", options: ["A", "A", "", " B "], allow_typed: false})),
                               {question: "Hi", options: ["A", "B"], allowTyped: false});
        assert.deepStrictEqual(plain(T.askUserQuestion({question: "Q"})), {question: "Q", options: [], allowTyped: true});
        // without options the user must be able to type
        assert.strictEqual(T.askUserQuestion({question: "Q", allow_typed: false}).allowTyped, true);
        assert.deepStrictEqual(plain(T.askUserQuestion({question: "Q", options: [{label: "X"}, 5]})).options, ["X", "5"]);
        assert.strictEqual(T.askUserQuestion(null).question, "");
        assert.strictEqual(T.askUserQuestion({options: "nope", question: "Q"}).options.length, 0);
    },

    wire_format_openai() {
        const a = plain(T.assistantMessage("openai", "Asking", [askCall], []));
        assert.deepStrictEqual(a, {role: "assistant", content: "Asking", tool_calls: [
            {id: "call_1", type: "function", function: {name: "ask_user", arguments: JSON.stringify(askCall.args)}}]});
        const r = plain(T.resultMessages("openai", [{id: "call_1", output: "B", isError: false}]));
        assert.deepStrictEqual(r, [{role: "tool", tool_call_id: "call_1", content: "B"}]);
    },

    wire_format_anthropic() {
        const thinking = [{type: "thinking", thinking: "hm", signature: "S"}];
        const a = plain(T.assistantMessage("anthropic", "Asking", [askCall], thinking));
        assert.deepStrictEqual(a, {role: "assistant", content: [
            {type: "thinking", thinking: "hm", signature: "S"}, {type: "text", text: "Asking"},
            {type: "tool_use", id: "call_1", name: "ask_user", input: askCall.args}]});
        assert.deepStrictEqual(plain(T.assistantMessage("anthropic", "", [askCall], [])).content.map(b => b.type), ["tool_use"]);
        const r = plain(T.resultMessages("anthropic", [{id: "call_1", output: "no", isError: true}, {id: "call_2", output: "yes", isError: false}]));
        assert.deepStrictEqual(r, [{role: "user", content: [
            {type: "tool_result", tool_use_id: "call_1", content: "no", is_error: true},
            {type: "tool_result", tool_use_id: "call_2", content: "yes"}]}]);
    },

    // A stored reply: it asked, got "B", then answered.
    stored_reply_history_in_both_formats() {
        const msg = {role: "assistant", content: "Let me ask.\n\nYou picked B.",
                     toolRounds: [{text: "Let me ask.", calls: [askCall]}],
                     tools: {call_1: {name: "ask_user", status: "done", output: "B"}}};
        const openai = plain(T.historyMessages("openai", msg, true));
        assert.deepStrictEqual(openai.map(m => m.role), ["assistant", "tool", "assistant"]);
        assert.strictEqual(openai[0].tool_calls[0].id, "call_1");
        assert.strictEqual(openai[1].tool_call_id, "call_1");
        assert.strictEqual(openai[1].content, "B");
        assert.strictEqual(openai[2].content, "You picked B.");
        const anth = plain(T.historyMessages("anthropic", msg, true));
        assert.deepStrictEqual(anth.map(m => m.role), ["assistant", "user", "assistant"]);
        assert.strictEqual(anth[0].content[1].type, "tool_use");
        assert.strictEqual(anth[1].content[0].tool_use_id, "call_1");
        assert.strictEqual(anth[2].content, "You picked B.");
    },

    every_tool_call_in_history_has_a_result() {
        // Stopped while the question was open: no result was recorded for the second call.
        const second = {id: "call_2", name: "ask_user", args: {question: "More?"}};
        const msg = {role: "assistant", content: "", toolRounds: [{text: "", calls: [askCall, second]}],
                     tools: {call_1: {name: "ask_user", status: "done", output: "The user did not answer."}}};
        const openai = plain(T.historyMessages("openai", msg, true));
        assert.deepStrictEqual(openai.map(m => m.role), ["assistant", "tool", "tool"]);
        assert.deepStrictEqual(openai.slice(1).map(m => m.tool_call_id), ["call_1", "call_2"]);
        assert.ok(openai[2].content.length > 0);
        const anth = plain(T.historyMessages("anthropic", msg, true));
        assert.strictEqual(anth[1].content.length, 2);
    },

    several_rounds_in_one_reply_keep_their_order() {
        const c2 = {id: "call_2", name: "ask_user", args: {question: "Again?"}};
        const msg = {role: "assistant", content: "one\n\ntwo\n\nend",
                     toolRounds: [{text: "one", calls: [askCall]}, {text: "two", calls: [c2]}],
                     tools: {call_1: {output: "a"}, call_2: {output: "b"}}};
        const out = plain(T.historyMessages("openai", msg, true));
        assert.deepStrictEqual(out.map(m => m.role), ["assistant", "tool", "assistant", "tool", "assistant"]);
        assert.deepStrictEqual([out[0].content, out[2].content, out[4].content], ["one", "two", "end"]);
    },

    history_is_text_when_tools_are_off_or_the_text_was_edited() {
        const msg = {role: "assistant", content: "Let me ask.\n\nYou picked B.", toolRounds: [{text: "Let me ask.", calls: [askCall]}],
                     tools: {call_1: {name: "ask_user", status: "done", output: "B"}}};
        const flat = plain(T.historyMessages("openai", msg, false));
        assert.strictEqual(flat.length, 1);
        assert.strictEqual(flat[0].role, "assistant");
        assert.ok(!("tool_calls" in flat[0]));
        assert.ok(flat[0].content.includes("Which one?") && flat[0].content.includes("B") && flat[0].content.includes("You picked B."));
        const edited = Object.assign({}, msg, {content: "Something else entirely"});
        const out = plain(T.historyMessages("anthropic", edited, true));
        assert.strictEqual(out.length, 1);
        assert.strictEqual(typeof out[0].content, "string");
    },

    replies_without_tools_and_empty_replies() {
        assert.deepStrictEqual(plain(T.historyMessages("openai", {role: "assistant", content: "hi"}, true)), [{role: "assistant", content: "hi"}]);
        assert.deepStrictEqual(plain(T.historyMessages("openai", {role: "assistant", content: ""}, true)), []);
        assert.strictEqual(T.hasToolRounds([{role: "user"}, {toolRounds: []}]), false);
        assert.strictEqual(T.hasToolRounds([{toolRounds: [{text: "", calls: []}]}]), true);
    },

    the_round_limit_is_eight() {
        assert.strictEqual(T.MAX_ROUNDS, 8);
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + (e.stack || e).toString().split("\n").slice(0, 4).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
