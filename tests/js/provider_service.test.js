// Tests for ProviderService.js, run by tests/test_provider_service.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const source = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/ProviderService.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(source + "\nthis.exports = {PRESETS, LEGACY, parseProviders, serializeProviders, newProviderId, legacyProviders, getProviderConfig, getProviderDisplayName, getSupportedProviders, defaultFirstOrder, sortDefaultFirst, parseModelIds, modelsRequest, fetchModels};", ctx);
const P = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));

const tests = {
    legacy_keeps_providers_with_keys_selection_or_model_and_all_customs() {
        const configuration = {
            provider: "nvidia",
            mistralModel: "mistral-large",
            groqModel: "",
            openRouterModel: "",
            customProvidersJson: JSON.stringify([{id: "custom_1", name: "Mine", type: "openai-compat", baseUrl: "https://x/v1", apiKey: "SECRET", model: "m"}]),
        };
        const list = plain(P.legacyProviders(configuration, {openrouter: "k"}));
        const ids = list.map(p => p.id);
        assert.deepStrictEqual(ids.sort(), ["custom_1", "mistral", "nvidia", "openrouter"]);
        assert.ok(!JSON.stringify(list).includes("SECRET"), "keys must not be copied into the list");
        const or = list.find(p => p.id === "openrouter");
        assert.strictEqual(or.headers["X-Title"], "KDE AI Chat");
        assert.strictEqual(list.find(p => p.id === "mistral").model, "mistral-large");
    },

    legacy_uses_custom_base_url() {
        const list = plain(P.legacyProviders({provider: "ollama", ollamaBaseUrl: "http://box:11434/v1", ollamaModel: "qwen3"}, {}));
        assert.deepStrictEqual(list, [{id: "ollama", name: "Ollama (local)", type: "openai-compat", baseUrl: "http://box:11434/v1", model: "qwen3"}]);
    },

    config_from_list() {
        const configuration = {providersJson: JSON.stringify([
            {id: "work", name: "Work", type: "anthropic", baseUrl: "https://a/v1", model: "claude"},
            {id: "box", name: "Box", type: "openai-compat", baseUrl: "http://127.0.0.1:8080/v1", model: "local"},
        ])};
        const work = plain(P.getProviderConfig("work", configuration));
        assert.strictEqual(work.type, "anthropic");
        assert.strictEqual(work.model, "claude");
        assert.strictEqual(work.apiKey, "");
        assert.strictEqual(work.allowEmptyKey, false);
        assert.strictEqual(P.getProviderConfig("box", configuration).allowEmptyKey, true);
        assert.strictEqual(P.getProviderConfig("missing", configuration).found, false);
        assert.deepStrictEqual(plain(P.getSupportedProviders(configuration)), ["work", "box"]);
        assert.strictEqual(P.getProviderDisplayName("work", configuration), "Work");
    },

    before_migration_old_settings_still_work() {
        const cfg = plain(P.getProviderConfig("openrouter", {openRouterModel: "openrouter/auto"}));
        assert.strictEqual(cfg.baseUrl, "https://openrouter.ai/api/v1");
        assert.strictEqual(cfg.model, "openrouter/auto");
        assert.strictEqual(cfg.found, true);
    },

    old_providers_are_still_migrated() {
        for (const id of ["maritaca", "perplexity", "mimo", "local", "cloudflare"])
            assert.ok(id in P.LEGACY, id);
    },

    image_providers_are_gone() {
        assert.ok(!P.PRESETS.some(p => /image|pollinations/.test(p.id)));
        assert.ok(!Object.keys(P.LEGACY).some(id => /image|pollinations/.test(id)));
    },

    serialize_cleans_entries_and_drops_keys() {
        const json = P.serializeProviders([{id: "a", name: "A", type: "weird", baseUrl: " https://x ", apiKey: "SECRET"}, {name: "no id"}]);
        assert.deepStrictEqual(JSON.parse(json), [{id: "a", name: "A", type: "openai-compat", baseUrl: "https://x", model: ""}]);
    },

    new_ids_are_unique() {
        assert.strictEqual(P.newProviderId([], "groq"), "groq");
        assert.strictEqual(P.newProviderId([{id: "groq"}], "groq"), "groq_2");
        assert.strictEqual(P.newProviderId([{id: "groq"}, {id: "groq_2"}], "groq"), "groq_3");
        assert.strictEqual(P.newProviderId([], "custom"), "custom_2");
    },

    model_ids_from_various_shapes() {
        assert.deepStrictEqual(plain(P.parseModelIds({data: [{id: "a"}, {id: "b"}, {id: "a"}]})), ["a", "b"]);
        assert.deepStrictEqual(plain(P.parseModelIds({models: [{name: "models/gemini-pro"}]})), ["gemini-pro"]);
        assert.deepStrictEqual(plain(P.parseModelIds(["x", {id: "y"}])), ["x", "y"]);
    },

    default_provider_sorts_first() {
        const list = [{id: "a"}, {id: "b"}, {id: "c"}];
        assert.deepStrictEqual(plain(P.defaultFirstOrder(list, "c")), [2, 0, 1]);
        assert.deepStrictEqual(plain(P.sortDefaultFirst(["a", "b", "c"], "b")), ["b", "a", "c"]);
        assert.deepStrictEqual(plain(P.defaultFirstOrder(list, "zzz")), [0, 1, 2]);
        assert.deepStrictEqual(plain(P.defaultFirstOrder(list, "")), [0, 1, 2]);
        assert.deepStrictEqual(plain(P.defaultFirstOrder(null, "a")), []);
        const cfg = {provider: "b", providersJson: JSON.stringify(list)};
        assert.deepStrictEqual(plain(P.getSupportedProviders(cfg)), ["b", "a", "c"]);
        assert.strictEqual(cfg.providersJson, JSON.stringify(list));
    },

    models_request_headers() {
        const a = plain(P.modelsRequest({type: "anthropic", baseUrl: "https://api.anthropic.com/v1/"}, "k"));
        assert.strictEqual(a.url, "https://api.anthropic.com/v1/models");
        assert.strictEqual(a.headers["x-api-key"], "k");
        const o = plain(P.modelsRequest({type: "openai-compat", baseUrl: "https://x/v1/chat/completions"}, ""));
        assert.strictEqual(o.url, "https://x/v1/models");
        assert.ok(!("Authorization" in o.headers));
    },

    fetch_models_rejects_bad_urls() {
        let error = "";
        P.fetchModels({type: "openai-compat", baseUrl: "file:///etc"}, "", () => {}, e => { error = e; }, () => { throw new Error("should not request"); });
        assert.ok(error.includes("http(s)"));
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + String(e.stack || e).split("\n").slice(0, 3).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
