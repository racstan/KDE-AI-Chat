// Tests for ProviderCheck.js, run by tests/test_provider_check.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const source = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/ProviderCheck.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {Date};
vm.runInNewContext(source + "\nthis.exports = {parseModelItems, isChatModel, splitModels, listModels, probeChat, checkProvider, reasonFrom, markDead, clearDead, deadReason};", ctx);
const C = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));
const SECRET = "sk-SECRET-1234567890";

// A fake server. `handler({method, url, headers, body})` returns
// {status, body} or {error: "timeout" | "network"}; requests are recorded.
function server(handler) {
    const requests = [];
    const factory = () => {
        const x = {headers: {}, readyState: 0, status: 0, responseText: ""};
        x.open = (method, url) => { x.method = method; x.url = url; };
        x.setRequestHeader = (k, v) => { x.headers[k] = v; };
        x.send = body => {
            const req = {method: x.method, url: x.url, headers: x.headers, body: body ? JSON.parse(body) : null};
            requests.push(req);
            const r = handler(req);
            if (r.error === "timeout") { x.ontimeout(); return; }
            if (r.error === "network") { x.onerror(); return; }
            x.status = r.status;
            x.responseText = typeof r.body === "string" ? r.body : JSON.stringify(r.body);
            x.readyState = 4;
            x.onreadystatechange();
        };
        return x;
    };
    return {factory, requests};
}
const run = (fn) => {
    let out;
    fn(r => { out = r; });
    assert.ok(out !== undefined, "callback not called synchronously");
    return plain(out);
};

const NIM = {type: "openai-compat", baseUrl: "https://integrate.api.nvidia.com/v1"};
const nimModels = JSON.parse(fs.readFileSync(path.join(__dirname, "../fixtures/nim-models-sample.json"), "utf8"));
const ok200 = {status: 200, body: {id: "x", choices: [{message: {content: "Hi"}}]}};

// NIM-like: /models is open to anyone, chat checks the key then the model.
const nimServer = () => server(req => {
    if (req.method === "GET") return {status: 200, body: nimModels};
    if (req.headers.Authorization !== "Bearer good") return {status: 403, body: {status: 403, title: "Forbidden", detail: "Authorization failed"}};
    if (req.body.model === "mistralai/mistral-large") return {status: 404, body: {status: 404, title: "Not Found", detail: "Function 'abc': Not found for account 'ACCOUNT-ID-XYZ'"}};
    if (req.body.model === "meta/llama-3.1-8b-instruct") return {status: 410, body: {title: "Gone", status: 410, detail: "The model 'meta/llama-3.1-8b-instruct' has reached its end of life on 2026-08-26 and is no longer available."}};
    return ok200;
});

const tests = {
    model_items_from_various_shapes() {
        assert.deepStrictEqual(plain(C.parseModelItems({data: [{id: "a"}, {id: "b"}, {id: "a"}]}).map(m => m.id)), ["a", "b"]);
        assert.deepStrictEqual(plain(C.parseModelItems({models: [{name: "models/gemini-pro"}]}).map(m => m.id)), ["gemini-pro"]);
        assert.deepStrictEqual(plain(C.parseModelItems(["x", {id: "y"}]).map(m => m.id)), ["x", "y"]);
    },

    filter_on_nim_sample_hides_non_chat_models() {
        const split = plain(C.splitModels(C.parseModelItems(nimModels)));
        assert.strictEqual(split.all.length, nimModels.data.length);
        for (const id of ["nvidia/nemotron-3.5-bolt-e4b", "nvidia/nemotron-3-ultra-550b-a55b", "mistralai/mistral-large", "nvidia/llama-3.1-nemotron-70b-instruct",
                          "meta/llama-3.2-90b-vision-instruct", "openai/gpt-oss-20b", "z-ai/glm-5.3", "google/gemma-3-4b-it", "deepseek-ai/deepseek-v4.1-flash"])
            assert.ok(split.chat.includes(id), id + " should be listed");
        for (const id of ["nvidia/embed-qa-4", "nvidia/llama-3.2-nv-embedqa-1b-v1", "nvidia/nemotron-3.5-embed-8b", "nvidia/llama-3.1-nemoguard-8b-content-safety",
                          "nvidia/llama-3.1-nemotron-safety-guard-8b-v3", "meta/llama-guard-4-12b", "nvidia/nemotron-4-340b-reward", "nvidia/nvclip",
                          "nvidia/nemotron-parse", "google/deplot", "nvidia/llama-3.2-nemoretriever-1b-vlm-embed-v1", "snowflake/arctic-embed-l",
                          "nvidia/nemotron-3.5-content-safety", "nvidia/ai-synthetic-video-detector"])
            assert.ok(!split.chat.includes(id) && split.all.includes(id), id + " should be hidden but kept in 'all'");
        assert.strictEqual(split.hidden, split.all.length - split.chat.length);
    },

    filter_uses_provider_fields_before_names() {
        const f = (id, raw) => C.isChatModel({id, raw});
        assert.strictEqual(f("m1", {type: "embedding"}), false);
        assert.strictEqual(f("m1", {type: "chat"}), true);
        assert.strictEqual(f("m1", {capabilities: {completion_chat: false}}), false);
        assert.strictEqual(f("m1", {capabilities: {completion_chat: true}}), true);
        assert.strictEqual(f("m1", {architecture: {output_modalities: ["image"]}}), false);
        assert.strictEqual(f("m1", {architecture: {output_modalities: ["text"]}}), true);
        assert.strictEqual(f("m1", {supportedGenerationMethods: ["embedContent"]}), false);
        assert.strictEqual(f("whisper-large-v3", {}), false);
        assert.strictEqual(f("tts-1", {}), false);
        assert.strictEqual(f("text-embedding-3-small", {}), false);
        assert.strictEqual(f("gpt-image-1", {}), false);
        assert.strictEqual(f("rerank-v3", {}), false);
        assert.strictEqual(f("gpt-4o", {}), true);
        assert.strictEqual(f("claude-sonnet-4", {type: "model"}), true);
        assert.strictEqual(f("llama3.2:3b", {}), true);
    },

    list_200() {
        const s = server(() => ({status: 200, body: nimModels}));
        const r = run(cb => C.listModels(NIM, "k", cb, {xhrFactory: s.factory}));
        assert.strictEqual(r.ok, true);
        assert.ok(r.chat.length < r.all.length && r.chat.length > 20);
        assert.strictEqual(s.requests[0].url, "https://integrate.api.nvidia.com/v1/models");
    },

    list_401_403_are_rejections() {
        for (const status of [401, 403]) {
            const s = server(() => ({status, body: {error: {message: "bad"}}}));
            const r = run(cb => C.listModels(NIM, "k", cb, {xhrFactory: s.factory}));
            assert.strictEqual(r.ok, false);
            assert.strictEqual(r.error, "rejected");
            assert.strictEqual(r.status, status);
        }
    },

    list_timeout_and_network_error() {
        assert.strictEqual(run(cb => C.listModels(NIM, "k", cb, {xhrFactory: server(() => ({error: "timeout"})).factory})).error, "timeout");
        assert.strictEqual(run(cb => C.listModels(NIM, "k", cb, {xhrFactory: server(() => ({error: "network"})).factory})).error, "network");
    },

    check_good_key_good_model() {
        const s = nimServer();
        const r = run(cb => C.checkProvider({cfg: NIM, apiKey: "good", model: "nvidia/nemotron-3.5-bolt-e4b", xhrFactory: s.factory}, cb));
        assert.strictEqual(r.state, "ok");
        assert.strictEqual(r.modelChecked, true);
        const chat = s.requests.find(q => q.method === "POST");
        assert.strictEqual(chat.url, "https://integrate.api.nvidia.com/v1/chat/completions");
        assert.strictEqual(chat.body.max_tokens, 1);
        assert.strictEqual(chat.headers.Authorization, "Bearer good");
    },

    nim_200_on_models_with_bad_key_is_caught_by_the_chat_request() {
        const s = nimServer();
        const r = run(cb => C.checkProvider({cfg: NIM, apiKey: "wrong", model: "nvidia/nemotron-3.5-bolt-e4b", xhrFactory: s.factory}, cb));
        assert.strictEqual(r.state, "key_rejected");
        assert.strictEqual(r.status, 403);
        assert.strictEqual(s.requests.length, 2, "models list, then one chat request");
    },

    bad_key_is_rejected_from_models_without_a_chat_request() {
        for (const status of [401, 403]) {
            const s = server(() => ({status, body: {error: {message: "Incorrect API key provided: " + SECRET}}}));
            const r = run(cb => C.checkProvider({cfg: NIM, apiKey: SECRET, model: "m", xhrFactory: s.factory}, cb));
            assert.strictEqual(r.state, "key_rejected");
            assert.strictEqual(r.status, status);
            assert.strictEqual(s.requests.length, 1);
            assert.ok(!JSON.stringify(r).includes(SECRET));
        }
    },

    gemini_style_400_for_a_bad_key_is_a_rejection() {
        const s = server(() => ({status: 400, body: [{error: {code: 400, message: "API key not valid. Please pass a valid API key."}}]}));
        const r = run(cb => C.checkProvider({cfg: NIM, apiKey: "x", model: "m", xhrFactory: s.factory}, cb));
        assert.strictEqual(r.state, "key_rejected");
    },

    dead_models_are_model_problems_not_key_problems() {
        const s = nimServer();
        const r404 = run(cb => C.checkProvider({cfg: NIM, apiKey: "good", model: "mistralai/mistral-large", xhrFactory: s.factory}, cb));
        assert.strictEqual(r404.state, "model_unavailable");
        assert.strictEqual(r404.status, 404);
        assert.ok(!r404.reason.includes("ACCOUNT-ID-XYZ"), "account ids are not shown");
        assert.ok(/account/i.test(r404.reason));
        const r410 = run(cb => C.checkProvider({cfg: NIM, apiKey: "good", model: "meta/llama-3.1-8b-instruct", xhrFactory: s.factory}, cb));
        assert.strictEqual(r410.state, "model_unavailable");
        assert.strictEqual(r410.status, 410);
        assert.ok(/end of life/.test(r410.reason));
    },

    a_400_model_not_found_is_a_model_problem() {
        const s = server(req => req.method === "GET" ? {status: 200, body: {data: [{id: "a"}]}}
            : {status: 400, body: {error: {message: "The model `gpt-9` does not exist"}}});
        const r = run(cb => C.checkProvider({cfg: NIM, apiKey: "k", model: "gpt-9", xhrFactory: s.factory}, cb));
        assert.strictEqual(r.state, "model_unavailable");
    },

    max_completion_tokens_retry() {
        const s = server(req => {
            if (req.method === "GET") return {status: 200, body: {data: [{id: "o3"}]}};
            if (req.body.max_tokens) return {status: 400, body: {error: {message: "Unsupported parameter: 'max_tokens'. Use 'max_completion_tokens' instead."}}};
            return ok200;
        });
        const r = run(cb => C.checkProvider({cfg: NIM, apiKey: "k", model: "o3", xhrFactory: s.factory}, cb));
        assert.strictEqual(r.state, "ok");
        assert.strictEqual(s.requests[s.requests.length - 1].body.max_completion_tokens, 1);
    },

    timeout_and_network_error_are_unverified() {
        for (const error of ["timeout", "network"]) {
            const s1 = server(() => ({error}));
            const r1 = run(cb => C.checkProvider({cfg: NIM, apiKey: "k", model: "m", xhrFactory: s1.factory}, cb));
            assert.strictEqual(r1.state, "unverified");
            assert.strictEqual(r1.error, error);
            // /models answers but the chat request does not.
            const s2 = server(req => req.method === "GET" ? {status: 200, body: nimModels} : {error});
            const r2 = run(cb => C.checkProvider({cfg: NIM, apiKey: "k", model: "m", xhrFactory: s2.factory}, cb));
            assert.strictEqual(r2.state, "unverified");
        }
    },

    server_error_is_unverified() {
        const s = server(req => req.method === "GET" ? {status: 200, body: nimModels} : {status: 503, body: "busy"});
        assert.strictEqual(run(cb => C.checkProvider({cfg: NIM, apiKey: "k", model: "m", xhrFactory: s.factory}, cb)).state, "unverified");
    },

    rate_limit_and_no_credit_mean_the_key_works() {
        for (const status of [429, 402]) {
            const s = server(req => req.method === "GET" ? {status: 200, body: nimModels} : {status, body: {error: {message: "slow down"}}});
            const r = run(cb => C.checkProvider({cfg: NIM, apiKey: "k", model: "m", xhrFactory: s.factory}, cb));
            assert.strictEqual(r.state, "ok");
            assert.strictEqual(r.warning, "limit");
        }
    },

    no_model_chosen_probes_with_the_first_chat_model() {
        const s = nimServer();
        const r = run(cb => C.checkProvider({cfg: NIM, apiKey: "wrong", model: "", xhrFactory: s.factory}, cb));
        assert.strictEqual(r.state, "key_rejected");
        const chat = s.requests.find(q => q.method === "POST");
        assert.ok(chat.body.model && !/embed|guard/.test(chat.body.model));
        // A dead probe model does not blame a model the user never chose.
        const s2 = server(req => req.method === "GET" ? {status: 200, body: nimModels} : {status: 404, body: "gone"});
        const r2 = run(cb => C.checkProvider({cfg: NIM, apiKey: "k", model: "", xhrFactory: s2.factory}, cb));
        assert.strictEqual(r2.state, "ok");
        assert.strictEqual(r2.modelChecked, false);
    },

    a_known_list_saves_the_models_request() {
        const s = nimServer();
        const known = {ok: true, status: 200, chat: ["nvidia/nemotron-3.5-bolt-e4b"], all: ["nvidia/nemotron-3.5-bolt-e4b"], hidden: 0, items: []};
        const r = run(cb => C.checkProvider({cfg: NIM, apiKey: "wrong", model: "nvidia/nemotron-3.5-bolt-e4b", knownList: known, xhrFactory: s.factory}, cb));
        assert.strictEqual(r.state, "key_rejected");
        assert.deepStrictEqual(s.requests.map(q => q.method), ["POST"]);
        // Without a chosen model the list is still needed to pick a probe.
        const s2 = nimServer();
        run(cb => C.checkProvider({cfg: NIM, apiKey: "good", model: "", knownList: known, xhrFactory: s2.factory}, cb));
        assert.strictEqual(s2.requests[0].method, "GET");
    },

    anthropic_headers_and_endpoint() {
        const cfg = {type: "anthropic", baseUrl: "https://api.anthropic.com/v1/"};
        const s = server(req => req.method === "GET" ? {status: 200, body: {data: [{type: "model", id: "claude-x"}]}} : ok200);
        const r = run(cb => C.checkProvider({cfg, apiKey: "ak", model: "claude-x", xhrFactory: s.factory}, cb));
        assert.strictEqual(r.state, "ok");
        const list = s.requests[0], chat = s.requests[1];
        assert.strictEqual(list.url, "https://api.anthropic.com/v1/models");
        assert.strictEqual(list.headers["x-api-key"], "ak");
        assert.strictEqual(list.headers["anthropic-version"], "2023-06-01");
        assert.ok(!("Authorization" in list.headers));
        assert.strictEqual(chat.url, "https://api.anthropic.com/v1/messages");
        assert.strictEqual(chat.headers["x-api-key"], "ak");
        assert.strictEqual(chat.body.max_tokens, 1);
        const s2 = server(() => ({status: 401, body: {type: "error", error: {type: "authentication_error", message: "invalid x-api-key"}}}));
        assert.strictEqual(run(cb => C.checkProvider({cfg, apiKey: "bad", model: "claude-x", xhrFactory: s2.factory}, cb)).state, "key_rejected");
    },

    local_provider_and_empty_key_are_skipped() {
        const s = server(() => { throw new Error("no request expected"); });
        assert.strictEqual(run(cb => C.checkProvider({cfg: NIM, apiKey: "", model: "m", local: true, xhrFactory: s.factory}, cb)).state, "skipped");
        assert.strictEqual(run(cb => C.checkProvider({cfg: NIM, apiKey: "k", model: "m", local: true, xhrFactory: s.factory}, cb)).state, "skipped");
        assert.strictEqual(run(cb => C.checkProvider({cfg: NIM, apiKey: "", model: "m", xhrFactory: s.factory}, cb)).state, "skipped");
    },

    non_http_urls_are_never_requested() {
        const s = server(() => { throw new Error("no request expected"); });
        const r = run(cb => C.listModels({type: "openai-compat", baseUrl: "file:///etc"}, "k", cb, {xhrFactory: s.factory}));
        assert.strictEqual(r.error, "url");
        assert.strictEqual(run(cb => C.listModels({type: "openai-compat", baseUrl: ""}, "k", cb, {xhrFactory: s.factory})).error, "url");
    },

    extra_provider_headers_are_sent() {
        const cfg = {type: "openai-compat", baseUrl: "https://openrouter.ai/api/v1", headers: {"X-Title": "KDE AI Chat"}};
        const s = server(() => ({status: 200, body: {data: []}}));
        run(cb => C.listModels(cfg, "k", cb, {xhrFactory: s.factory}));
        assert.strictEqual(s.requests[0].headers["X-Title"], "KDE AI Chat");
    },

    reason_never_contains_the_key() {
        const text = JSON.stringify({error: {message: "Bad key " + SECRET + " here"}});
        assert.ok(!C.reasonFrom(text, SECRET).includes(SECRET));
    },

    dead_registry() {
        assert.strictEqual(C.deadReason("nvidia", "m"), "");
        C.markDead("nvidia", "m", "end of life");
        assert.strictEqual(C.deadReason("nvidia", "m"), "end of life");
        assert.strictEqual(C.deadReason("other", "m"), "");
        C.clearDead("nvidia", "m");
        assert.strictEqual(C.deadReason("nvidia", "m"), "");
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + String(e.stack || e).split("\n").slice(0, 4).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
