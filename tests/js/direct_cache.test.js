// Tests for backends/DirectCache.js (prompt-cache marks) and the cache token counts in
// backends/DirectBackend.js usage events, run by tests/test_direct_cache.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const read = name => fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/backends/" + name), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(read("DirectBackend.js") + "\n" + read("DirectStream.js") + read("DirectCache.js")
    + "\nthis.exports = {buildRequest, send, createThinkSplitter, DirectCache: {apply, targetIndex}};", ctx);
const B = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));
const E = {"cache_control": {"type": "ephemeral"}};

const anthropic = extra => Object.assign({type: "anthropic", baseUrl: "https://api.anthropic.com/v1", apiKey: "k", model: "claude", cache: B.DirectCache}, extra);
const openai = extra => Object.assign({type: "openai", baseUrl: "https://api.test/v1", model: "m", cache: B.DirectCache}, extra);
const tools = [{name: "a", input_schema: {}}, {name: "b", input_schema: {}}];

function fakeXhr(status, chunks) {
    return {
        readyState: 0, status: 0, responseText: "", headers: {},
        open() {}, setRequestHeader() {}, send() {}, abort() {},
        play() {
            this.status = status;
            for (const c of chunks) { this.responseText += c; this.readyState = 3; this.onreadystatechange(); }
            this.readyState = 4; this.onreadystatechange();
        },
    };
}
function usageEvents(type, stream, payload) {
    const xhr = fakeXhr(200, stream ? payload : [JSON.stringify(payload)]);
    const events = [];
    B.send({type, baseUrl: "https://u.test/v1", model: "m", messages: [], stream, thinkFactory: B.createThinkSplitter,
            xhrFactory: () => xhr, onEvent: e => events.push(e)});
    xhr.play();
    return plain(events.filter(e => e.type === "usage"));
}

const tests = {
    anthropic_marks_tools_system_and_the_message_before_the_new_turn() {
        const body = B.buildRequest(anthropic({system: "Be brief.", tools, messages: [
            {role: "user", content: "hi"}, {role: "assistant", content: "hello"}, {role: "user", content: "next"}]})).body;
        assert.deepStrictEqual(plain(body.tools[0]), {name: "a", input_schema: {}});
        assert.deepStrictEqual(plain(body.tools[1]), Object.assign({name: "b", input_schema: {}}, E));
        assert.deepStrictEqual(plain(body.system), [Object.assign({type: "text", text: "Be brief."}, E)]);
        assert.deepStrictEqual(plain(body.messages[1].content), [Object.assign({type: "text", text: "hello"}, E)]);
        assert.strictEqual(body.messages[0].content, "hi");
        assert.strictEqual(body.messages[2].content, "next");
        // 3 breakpoints, below the limit of 4
        assert.strictEqual(JSON.stringify(body).split("cache_control").length - 1, 3);
    },

    anthropic_block_content_gets_the_mark_on_its_last_block_without_touching_the_input() {
        const messages = [{role: "user", content: "hi"},
            {role: "assistant", content: [{type: "text", text: "a"}, {type: "tool_use", id: "t", name: "a", input: {}}]},
            {role: "user", content: [{type: "text", text: "q"}]}];
        const before = JSON.stringify(messages);
        const body = B.buildRequest(anthropic({messages})).body;
        assert.deepStrictEqual(plain(body.messages[1].content[1]), Object.assign({type: "tool_use", id: "t", name: "a", input: {}}, E));
        assert.strictEqual(body.messages[1].content[0].cache_control, undefined);
        assert.strictEqual(JSON.stringify(messages), before);
        assert.strictEqual(body.system, undefined);
        assert.strictEqual(body.tools, undefined);
    },

    anthropic_tool_results_in_a_tool_loop_are_marked_and_thinking_blocks_never() {
        const loop = [{role: "user", content: "go"},
            {role: "assistant", content: [{type: "tool_use", id: "t", name: "a", input: {}}]},
            {role: "user", content: [{type: "tool_result", tool_use_id: "t", content: "ok"}]}];
        const body = B.buildRequest(anthropic({messages: loop})).body;
        assert.strictEqual(body.messages[2].content[0].cache_control.type, "ephemeral");
        assert.strictEqual(body.messages[1].content[0].cache_control, undefined);
        const thinking = [{role: "assistant", content: [{type: "thinking", thinking: "x", signature: "s"}]}, {role: "user", content: "q"}];
        assert.strictEqual(JSON.stringify(B.buildRequest(anthropic({messages: thinking})).body.messages).indexOf("cache_control"), -1);
    },

    anthropic_a_single_user_message_and_an_empty_system_get_no_marks() {
        const body = B.buildRequest(anthropic({system: "", messages: [{role: "user", content: "hi"}]})).body;
        assert.strictEqual(JSON.stringify(body).indexOf("cache_control"), -1);
        assert.strictEqual(body.messages[0].content, "hi");
    },

    openrouter_with_an_anthropic_model_gets_content_part_marks() {
        const body = B.buildRequest(openai({baseUrl: "https://openrouter.ai/api/v1", model: "anthropic/claude-sonnet-4", system: "Sys",
            messages: [{role: "user", content: "hi"}, {role: "assistant", content: "yo"}, {role: "user", content: "next"}]})).body;
        assert.deepStrictEqual(plain(body.messages[0]), {role: "system", content: [Object.assign({type: "text", text: "Sys"}, E)]});
        assert.strictEqual(body.messages[1].content, "hi");
        assert.deepStrictEqual(plain(body.messages[2].content), [Object.assign({type: "text", text: "yo"}, E)]);
        assert.strictEqual(body.messages[3].content, "next");
    },

    openrouter_tool_loops_mark_only_the_system_message_and_content_parts_keep_their_other_parts() {
        const body = B.buildRequest(openai({baseUrl: "https://openrouter.ai/api/v1", model: "anthropic/x", system: "Sys", messages: [
            {role: "user", content: [{type: "image_url", image_url: {url: "u"}}, {type: "text", text: "see"}]},
            {role: "assistant", content: "a"}, {role: "user", content: [{type: "text", text: "q"}]}]})).body;
        assert.strictEqual(body.messages[0].content[0].cache_control.type, "ephemeral");
        assert.strictEqual(JSON.stringify(body.messages[1]).indexOf("cache_control"), -1);
        assert.strictEqual(body.messages[2].content[0].cache_control.type, "ephemeral");
        assert.strictEqual(body.messages[3].content[0].cache_control, undefined);
        const loop = B.buildRequest(openai({baseUrl: "https://openrouter.ai/api/v1", model: "anthropic/x", system: "S", messages: [
            {role: "user", content: "go"}, {role: "assistant", content: null, tool_calls: []}, {role: "tool", tool_call_id: "1", content: "r"}]})).body;
        assert.strictEqual(JSON.stringify(loop.messages.slice(1)).indexOf("cache_control"), -1);
    },

    other_servers_get_no_new_fields() {
        const messages = [{role: "user", content: "hi"}, {role: "assistant", content: "yo"}, {role: "user", content: "next"}];
        const cases = [["https://openrouter.ai/api/v1", "openai/gpt-5"], ["https://api.openai.com/v1", "gpt-5"],
            ["http://localhost:11434/v1", "llama3"], ["http://localhost:1234/v1", "anthropic/claude"],
            ["https://notopenrouter.ai.example.com/v1", "anthropic/claude"], ["http://127.0.0.1:8080/v1", "qwen"]];
        for (const [baseUrl, model] of cases) {
            const withCache = B.buildRequest(openai({baseUrl, model, system: "Sys", messages})).body;
            const without = B.buildRequest(openai({baseUrl, model, system: "Sys", messages, cache: undefined})).body;
            assert.deepStrictEqual(plain(withCache), plain(without), baseUrl + " " + model);
            assert.strictEqual(JSON.stringify(withCache).indexOf("cache_control"), -1);
            assert.strictEqual(withCache.messages[0].content, "Sys");
        }
    },

    marks_are_not_added_without_the_cache_option() {
        const body = B.buildRequest(anthropic({cache: undefined, system: "S", messages: [{role: "user", content: "x"}]})).body;
        assert.strictEqual(body.system, "S");
    },

    openai_usage_reads_cached_tokens_streaming_and_not() {
        const usage = {prompt_tokens: 100, completion_tokens: 5, prompt_tokens_details: {cached_tokens: 64}};
        const streamed = usageEvents("openai", true, ["data: " + JSON.stringify({choices: [], usage}) + "\n\ndata: [DONE]\n\n"]);
        assert.deepStrictEqual(streamed, [{type: "usage", input: 100, output: 5, cacheRead: 64}]);
        assert.deepStrictEqual(usageEvents("openai", false, {choices: [{message: {content: "x"}}], usage}),
            [{type: "usage", input: 100, output: 5, cacheRead: 64}]);
        const none = usageEvents("openai", false, {choices: [{message: {content: "x"}}], usage: {prompt_tokens: 3, completion_tokens: 1}});
        assert.deepStrictEqual(none, [{type: "usage", input: 3, output: 1}]);
        const router = {prompt_tokens: 10, completion_tokens: 1, cost: 0.5, prompt_tokens_details: {cached_tokens: 0, cache_write_tokens: 7}};
        assert.deepStrictEqual(usageEvents("openai", false, {choices: [{message: {content: "x"}}], usage: router}),
            [{type: "usage", input: 10, output: 1, cost: 0.5, cacheRead: 0, cacheWrite: 7}]);
    },

    anthropic_usage_reads_cache_read_and_creation_streaming_and_not() {
        const start = {type: "message_start", message: {usage: {input_tokens: 4, output_tokens: 1, cache_read_input_tokens: 900, cache_creation_input_tokens: 50}}};
        const sse = o => "event: " + o.type + "\ndata: " + JSON.stringify(o) + "\n\n";
        const streamed = usageEvents("anthropic", true, [sse(start), sse({type: "message_delta", usage: {output_tokens: 12}}), sse({type: "message_stop"})]);
        assert.deepStrictEqual(streamed, [{type: "usage", input: 954, output: 1, cacheRead: 900, cacheWrite: 50}, {type: "usage", output: 12}]);
        const delta = usageEvents("anthropic", true, [sse({type: "message_delta", usage: {output_tokens: 12, cache_read_input_tokens: 900, cache_creation_input_tokens: 0}})]);
        assert.deepStrictEqual(delta, [{type: "usage", output: 12, cacheRead: 900, cacheWrite: 0}]);
        const full = usageEvents("anthropic", false, {content: [{type: "text", text: "x"}], usage: {input_tokens: 4, output_tokens: 6, cache_read_input_tokens: 10, cache_creation_input_tokens: 2}});
        assert.deepStrictEqual(full, [{type: "usage", input: 16, output: 6, cacheRead: 10, cacheWrite: 2}]);
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + (e.stack || e).toString().split("\n").slice(0, 4).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
