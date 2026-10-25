// Tests for model variants (reasoning / thinking levels), run by tests/test_variants.py:
// Variants.js, the variant parsing in ProviderCheck.js, ProviderVariants.js, the request
// bodies of DirectBackend.js / OpenCodeBackend.js and OpenCodeCatalog.js, on recorded
// samples in tests/fixtures (OpenRouter's public /models, Anthropic's documented
// capabilities object, OpenCode's /config/providers with every `key` removed).
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const UI = path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/");
const load = (file, names) => {
    const ctx = {Date};
    vm.runInNewContext(fs.readFileSync(UI + file, "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "") + "\nthis.exports = {" + names + "};", ctx);
    return ctx.exports;
};
const V = load("Variants.js", "title, make, find, sendFor, isValid, fromOpenCodeNames, fromPi");
const PC = load("ProviderCheck.js", "variantsFromModel, variantMap, listModels, parseModelItems, THINKING_BUDGET_TOKENS");
const PV = load("ProviderVariants.js", "forModel, remember, clear, cached");
const DB = load("backends/DirectBackend.js", "buildRequest");
const OB = load("backends/OpenCodeBackend.js", "promptBody");
const OC = load("backends/OpenCodeCatalog.js", "parse");
const EC = load("chat/EffectiveConfig.js", "PI_THINKING_LEVELS");
const plain = x => JSON.parse(JSON.stringify(x));
const fixture = name => JSON.parse(fs.readFileSync(path.join(__dirname, "../fixtures/", name), "utf8"));

const openRouter = fixture("openrouter-models-sample.json");
const anthropic = fixture("anthropic-models-sample.json");
const openCode = fixture("opencode-1.18-config-providers.json");
const nim = fixture("nim-models-sample.json");
const byId = (list, id) => list.data.find(m => m.id === id);

// A fake server: handler({method, url, body}) -> {status, body}.
function server(handler) {
    const requests = [];
    const factory = () => {
        const x = {headers: {}, readyState: 0, status: 0, responseText: ""};
        x.open = (method, url) => { x.method = method; x.url = url; };
        x.setRequestHeader = (k, v) => { x.headers[k] = v; };
        x.send = body => {
            const req = {method: x.method, url: x.url, body: body ? JSON.parse(body) : null};
            requests.push(req);
            const r = handler(req);
            x.status = r.status;
            x.responseText = typeof r.body === "string" ? r.body : JSON.stringify(r.body);
            x.readyState = 4;
            x.onreadystatechange();
        };
        return x;
    };
    return {factory, requests};
}
const wait = fn => { let out; fn(r => { out = r; }); assert.ok(out !== undefined, "callback not called"); return plain(out); };

const tests = {
    // --- Variants.js ---

    send_fragment_for_a_stored_id_only_when_the_model_still_offers_it() {
        const list = [V.make("low", {reasoning: {effort: "low"}}), V.make("high", {reasoning: {effort: "high"}})];
        assert.deepStrictEqual(plain(V.sendFor(list, "high")), {reasoning: {effort: "high"}});
        assert.deepStrictEqual(plain(V.sendFor(list, "max")), {}, "an id that is not in the list sends nothing");
        assert.deepStrictEqual(plain(V.sendFor(list, "")), {}, "no variant chosen");
        assert.deepStrictEqual(plain(V.sendFor([], "high")), {}, "a model without variants");
        assert.deepStrictEqual(plain(V.sendFor(undefined, "high")), {});
        const sent = V.sendFor(list, "low");
        sent.reasoning.effort = "x";
        assert.strictEqual(list[0].send.reasoning.effort, "low", "the fragment is a copy");
        assert.strictEqual(V.isValid(list, "low"), true);
        assert.strictEqual(V.isValid(list, "none"), false);
    },

    opencode_names_become_variants_sent_by_name() {
        const list = plain(V.fromOpenCodeNames(["low", "high", "low", ""]));
        assert.deepStrictEqual(list.map(v => v.id), ["low", "high"]);
        assert.deepStrictEqual(list[1], {id: "high", label: "High", send: {variant: "high"}});
        assert.deepStrictEqual(plain(V.fromOpenCodeNames(undefined)), []);
    },

    pi_levels_only_for_a_model_that_thinks_and_are_pis_own_list() {
        assert.deepStrictEqual(plain(V.fromPi(EC.PI_THINKING_LEVELS, false)), [], "a model that does not think has no picker");
        assert.deepStrictEqual(plain(V.fromPi(EC.PI_THINKING_LEVELS, undefined)), []);
        const list = plain(V.fromPi(EC.PI_THINKING_LEVELS, true));
        assert.deepStrictEqual(list.map(v => v.id), plain(EC.PI_THINKING_LEVELS).filter(x => x !== ""), "Pi's own vocabulary, minus the empty 'default'");
        assert.deepStrictEqual(list.find(v => v.id === "high").send, {thinking: "high"});
    },

    // --- ProviderCheck.js: variants from a /models answer ---

    openrouter_sample_gives_the_efforts_the_model_reports() {
        const eff = id => plain(PC.variantsFromModel(byId(openRouter, id)));
        const gpt = eff("openai/gpt-5");
        assert.deepStrictEqual(gpt.map(v => v.id), ["high", "medium", "low", "minimal"]);
        assert.deepStrictEqual(gpt[0].send, {reasoning: {effort: "high"}});
        const kimi = eff("moonshotai/kimi-k3.1-pro");
        assert.deepStrictEqual(kimi.map(v => v.id), ["max", "high", "low", "none"], "levels as reported, including none");
        assert.deepStrictEqual(kimi[3].send, {reasoning: {effort: "none"}});
        assert.deepStrictEqual(eff("minimax/minimax-m3.1-flash").map(v => v.id), ["max", "xhigh", "high", "medium", "low"]);
        assert.deepStrictEqual(eff("recursive/flint-v1.0:free"), [], "reasoning is always on, no levels reported");
        assert.deepStrictEqual(eff("elorian/glimpse"), [], "reasoning without levels");
        assert.deepStrictEqual(eff("unbiased/pareto-26.10"), [], "no reasoning at all");
        assert.deepStrictEqual(eff("openrouter/auto"), []);
    },

    anthropic_sample_gives_effort_levels_or_a_thinking_toggle() {
        const eff = id => plain(PC.variantsFromModel(byId(anthropic, id)));
        const adaptive = eff("sample-adaptive-model");
        assert.deepStrictEqual(adaptive.map(v => v.id), ["low", "medium", "high", "max", "off"], "supported levels only (xhigh is null), then off");
        assert.deepStrictEqual(adaptive[2].send, {thinking: {type: "adaptive"}, output_config: {effort: "high"}});
        assert.deepStrictEqual(adaptive[4].send, {thinking: {type: "disabled"}});
        const older = eff("sample-older-thinking-model");
        assert.deepStrictEqual(older.map(v => v.id), ["on", "off"], "older model: thinking on/off only");
        assert.deepStrictEqual(older[0].send, {thinking: {type: "enabled", budget_tokens: PC.THINKING_BUDGET_TOKENS}});
        assert.ok(PC.THINKING_BUDGET_TOKENS >= 1024, "the API minimum");
        assert.deepStrictEqual(eff("sample-plain-model"), []);
    },

    providers_that_report_nothing_get_no_variants() {
        const items = PC.parseModelItems(nim);
        assert.deepStrictEqual(plain(PC.variantMap(items)), {}, "NVIDIA NIM's list has ids only");
        assert.deepStrictEqual(plain(PC.variantMap(PC.parseModelItems({data: [{id: "gpt-x", object: "model", owned_by: "o"}, {id: "llama", object: "model"}]}))), {});
        assert.deepStrictEqual(plain(PC.variantsFromModel(null)), []);
        assert.deepStrictEqual(plain(PC.variantsFromModel({})), []);
    },

    list_result_carries_the_variants_of_the_list_without_another_request() {
        const s = server(() => ({status: 200, body: openRouter}));
        const r = wait(cb => PC.listModels({type: "openai-compat", baseUrl: "https://openrouter.ai/api/v1"}, "k", cb, {xhrFactory: s.factory}));
        assert.strictEqual(s.requests.length, 1);
        assert.deepStrictEqual(Object.keys(r.variants).sort(), ["minimax/minimax-m3.1-flash", "moonshotai/kimi-k3.1-pro", "openai/gpt-5"]);
        const a = server(() => ({status: 200, body: anthropic}));
        const ra = wait(cb => PC.listModels({type: "anthropic", baseUrl: "https://api.anthropic.com/v1"}, "k", cb, {xhrFactory: a.factory}));
        assert.deepStrictEqual(Object.keys(ra.variants), ["sample-adaptive-model", "sample-older-thinking-model"]);
    },

    // --- ProviderVariants.js: cache and local servers ---

    variants_are_cached_with_the_list_per_provider() {
        PV.clear();
        const s = server(() => ({status: 200, body: openRouter}));
        const cfg = {type: "openai-compat", baseUrl: "https://openrouter.ai/api/v1"};
        const first = wait(cb => PV.forModel(cfg, "k", "openai/gpt-5", PC.listModels, cb, {xhrFactory: s.factory}));
        assert.deepStrictEqual(first.map(v => v.id), ["high", "medium", "low", "minimal"]);
        assert.strictEqual(s.requests.length, 1);
        const second = wait(cb => PV.forModel(cfg, "k", "moonshotai/kimi-k3.1-pro", PC.listModels, cb, {xhrFactory: s.factory}));
        assert.strictEqual(second.length, 4);
        assert.deepStrictEqual(wait(cb => PV.forModel(cfg, "k", "unbiased/pareto-26.10", PC.listModels, cb, {xhrFactory: s.factory})), []);
        assert.strictEqual(s.requests.length, 1, "no request after the list was fetched");
    },

    a_failing_list_or_an_empty_model_gives_no_variants() {
        PV.clear();
        const down = server(() => ({status: 500, body: "boom"}));
        const cfg = {type: "openai-compat", baseUrl: "https://x.example/v1"};
        assert.deepStrictEqual(wait(cb => PV.forModel(cfg, "k", "m", PC.listModels, cb, {xhrFactory: down.factory})), []);
        assert.deepStrictEqual(wait(cb => PV.forModel(cfg, "k", "", PC.listModels, cb, {xhrFactory: down.factory})), []);
        assert.strictEqual(down.requests.length, 1, "no model, no request");
        assert.strictEqual(PV.cached(cfg, "m"), null, "a failed list is not cached");
    },

    a_local_ollama_reports_thinking_models_through_api_show() {
        PV.clear();
        const s = server(req => {
            if (req.method === "GET") return {status: 200, body: {data: [{id: "qwen3:latest"}, {id: "llama3.2:latest"}]}};
            if (req.url !== "http://localhost:11434/api/show") return {status: 404, body: ""};
            return {status: 200, body: {capabilities: req.body.model === "qwen3:latest" ? ["completion", "tools", "thinking"] : ["completion", "tools"]}};
        });
        const cfg = {type: "openai-compat", baseUrl: "http://localhost:11434/v1"};
        const thinking = wait(cb => PV.forModel(cfg, "", "qwen3:latest", PC.listModels, cb, {xhrFactory: s.factory}));
        assert.deepStrictEqual(thinking, [{id: "off", label: "Thinking off", send: {reasoning_effort: "none"}}]);
        assert.deepStrictEqual(wait(cb => PV.forModel(cfg, "", "llama3.2:latest", PC.listModels, cb, {xhrFactory: s.factory})), []);
        const before = s.requests.length;
        wait(cb => PV.forModel(cfg, "", "qwen3:latest", PC.listModels, cb, {xhrFactory: s.factory}));
        assert.strictEqual(s.requests.length, before, "each model is asked once");
        assert.strictEqual(s.requests.filter(r => r.method === "GET").length, 1, "the list too");
    },

    a_local_server_without_api_show_has_no_variants_and_a_remote_one_is_never_asked() {
        PV.clear();
        const lm = server(req => req.method === "GET" ? {status: 200, body: {data: [{id: "m"}]}} : {status: 404, body: "not found"});
        assert.deepStrictEqual(wait(cb => PV.forModel({type: "openai-compat", baseUrl: "http://localhost:1234/v1"}, "", "m", PC.listModels, cb, {xhrFactory: lm.factory})), []);
        PV.clear();
        const remote = server(req => ({status: 200, body: {data: [{id: "m"}], capabilities: ["thinking"]}}));
        assert.deepStrictEqual(wait(cb => PV.forModel({type: "openai-compat", baseUrl: "https://api.example.com/v1"}, "k", "m", PC.listModels, cb, {xhrFactory: remote.factory})), []);
        assert.ok(remote.requests.every(r => r.method === "GET"), "no /api/show on a remote provider");
    },

    // --- Request bodies ---

    direct_body_is_unchanged_without_a_variant_and_for_a_stale_id() {
        const base = {type: "openai-compat", baseUrl: "https://openrouter.ai/api/v1", apiKey: "k", model: "openai/gpt-5", messages: [{role: "user", content: "hi"}], maxTokens: 100};
        const plainBody = plain(DB.buildRequest(base).body);
        assert.ok(!("reasoning" in plainBody) && !("thinking" in plainBody) && !("reasoning_effort" in plainBody) && !("output_config" in plainBody));
        const list = plain(PC.variantsFromModel(byId(openRouter, "openai/gpt-5")));
        assert.deepStrictEqual(plain(DB.buildRequest(Object.assign({}, base, {variantSend: V.sendFor(list, "")})).body), plainBody);
        assert.deepStrictEqual(plain(DB.buildRequest(Object.assign({}, base, {variantSend: V.sendFor(list, "max")})).body), plainBody, "stored id not offered: nothing sent");
        assert.deepStrictEqual(plain(DB.buildRequest(Object.assign({}, base, {variantSend: V.sendFor([], "high")})).body), plainBody, "no variants: nothing sent");
    },

    openrouter_body_with_a_variant_sends_reasoning_effort() {
        const base = {type: "openai-compat", baseUrl: "https://openrouter.ai/api/v1", apiKey: "k", model: "openai/gpt-5", messages: [{role: "user", content: "hi"}], maxTokens: 100};
        const list = plain(PC.variantsFromModel(byId(openRouter, "openai/gpt-5")));
        const body = plain(DB.buildRequest(Object.assign({}, base, {variantSend: V.sendFor(list, "low")})).body);
        assert.deepStrictEqual(body.reasoning, {effort: "low"});
        assert.strictEqual(body.model, "openai/gpt-5");
        assert.strictEqual(body.stream, true);
    },

    anthropic_bodies_adaptive_effort_and_older_budget() {
        const base = {type: "anthropic", baseUrl: "https://api.anthropic.com/v1", apiKey: "k", model: "m", messages: [{role: "user", content: "hi"}], maxTokens: 4096};
        const adaptive = plain(PC.variantsFromModel(byId(anthropic, "sample-adaptive-model")));
        let body = plain(DB.buildRequest(Object.assign({}, base, {variantSend: V.sendFor(adaptive, "high")})).body);
        assert.deepStrictEqual([body.thinking, body.output_config, body.max_tokens], [{type: "adaptive"}, {effort: "high"}, 4096]);
        body = plain(DB.buildRequest(Object.assign({}, base, {variantSend: V.sendFor(adaptive, "off")})).body);
        assert.deepStrictEqual(body.thinking, {type: "disabled"});
        const older = plain(PC.variantsFromModel(byId(anthropic, "sample-older-thinking-model")));
        body = plain(DB.buildRequest(Object.assign({}, base, {variantSend: V.sendFor(older, "on")})).body);
        assert.strictEqual(body.thinking.type, "enabled");
        assert.ok(body.max_tokens > body.thinking.budget_tokens, "max_tokens stays above the thinking budget");
        assert.strictEqual(plain(DB.buildRequest(Object.assign({}, base, {maxTokens: 20000, variantSend: V.sendFor(older, "on")})).body).max_tokens, 20000, "enough room already: unchanged");
    },

    a_variant_can_never_replace_the_model_or_the_conversation() {
        const base = {type: "openai-compat", baseUrl: "https://x.example/v1", apiKey: "k", model: "real", messages: [{role: "user", content: "hi"}], maxTokens: 50};
        const body = plain(DB.buildRequest(Object.assign({}, base, {variantSend: {model: "evil", messages: [], stream: false, max_tokens: 1, reasoning_effort: "low"}})).body);
        assert.deepStrictEqual([body.model, body.messages.length, body.stream, body.max_tokens, body.reasoning_effort], ["real", 1, true, 50, "low"]);
    },

    opencode_prompt_sends_the_variant_name_only_when_given() {
        const base = {parts: [{type: "text", text: "hi"}], providerId: "openrouter", modelId: "openai/gpt-5"};
        assert.ok(!("variant" in plain(OB.promptBody(base))));
        assert.ok(!("variant" in plain(OB.promptBody(Object.assign({}, base, {variantSend: {}})))), "stale or empty: nothing sent");
        const list = V.fromOpenCodeNames(["low", "high"]);
        const body = plain(OB.promptBody(Object.assign({}, base, {variantSend: V.sendFor(list, "high")})));
        assert.strictEqual(body.variant, "high");
        assert.deepStrictEqual(body.model, {providerID: "openrouter", modelID: "openai/gpt-5"});
        assert.ok(!("variant" in plain(OB.promptBody(Object.assign({}, base, {variantSend: V.sendFor(list, "gone")})))), "a name the server no longer lists");
        assert.deepStrictEqual(Object.keys(plain(OB.promptBody(Object.assign({}, base, {variantSend: {variant: "high", model: "x", agent: "y"}})))).sort(), ["model", "parts", "variant"], "only the variant key is taken");
    },

    // --- OpenCodeCatalog.js ---

    opencode_catalogue_gives_variant_names_per_model() {
        const c = plain(OC.parse(openCode));
        assert.deepStrictEqual(c.providers.map(p => p.id), ["nvidia", "openrouter", "groq", "google"]);
        const withVariants = Object.keys(c.variants);
        assert.ok(withVariants.length >= 4, "models with variants in the sample");
        for (const names of Object.values(c.variants))
            assert.ok(Array.isArray(names) && names.length > 0 && names.every(n => typeof n === "string"), "names only");
        const gemini = c.variants["google/gemini-3.7-flash"];
        assert.ok(gemini.includes("low") && gemini.includes("high"));
        assert.ok(c.models.some(m => !c.variants[m]), "a model without variants has none, so no picker");
    },

    opencode_catalogue_never_keeps_the_api_keys_of_the_response() {
        const SECRET = "sk-SECRET-DO-NOT-KEEP-1234567890";
        const live = {providers: [{id: "p", name: "P", key: SECRET, options: {apiKey: SECRET}, env: [SECRET],
                                   models: {"m1": {id: "m1", name: "M1", variants: {low: {reasoningEffort: "low", token: SECRET}}}, "m2": {id: "m2", key: SECRET}}}]};
        const out = JSON.stringify(plain(OC.parse(live)));
        assert.ok(out.indexOf(SECRET) < 0, "no key anywhere in the reduced result");
        assert.deepStrictEqual(plain(OC.parse(live)).variants, {"p/m1": ["low"]});
        assert.deepStrictEqual(plain(OC.parse(null)), {providers: [], models: [], modelsByProvider: {}, variants: {}});
        assert.deepStrictEqual(plain(OC.parse({providers: "x"})).providers, []);
    },

    the_saved_opencode_sample_has_no_keys() {
        const text = fs.readFileSync(path.join(__dirname, "../fixtures/opencode-1.18-config-providers.json"), "utf8");
        assert.ok(!/"key"|sk-|nvapi-|gsk_|AIza/.test(text), "the fixture is stripped of keys");
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try {
        fn();
        console.log("ok   " + name);
    } catch (e) {
        failed++;
        console.log("FAIL " + name + "\n" + e.stack);
    }
}
process.exit(failed ? 1 : 0);
