// Tests for ProviderService.js, run by tests/test_provider_service.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const source = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/ProviderService.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(source + "\nthis.exports = {PRESETS, LEGACY, IMAGE_SERVICES, imageProviders, defaultImageProvider, presetById, parseProviders, serializeProviders, newProviderId, legacyProviders, getProviderConfig, getProviderDisplayName, getSupportedProviders, defaultFirstOrder, sortDefaultFirst, isPlainHttpRemote};", ctx);
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

    image_providers_exist_only_as_the_new_image_type() {
        // The pre-1.4.0 image providers were removed; the image services are a type of their own (see below).
        assert.ok(!Object.keys(P.LEGACY).some(id => /image|pollinations|horde/.test(id)));
        assert.ok(P.PRESETS.filter(p => /image|pollinations|horde/.test(p.id)).every(p => p.type === "image"));
        assert.ok(P.PRESETS.filter(p => p.type !== "image").every(p => p.service === undefined));
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

    image_presets_are_there_and_off_until_switched_on() {
        const ids = plain(P.PRESETS.filter(p => p.type === "image").map(p => p.id + ":" + p.service));
        assert.deepStrictEqual(ids, ["aihorde:horde", "pollinations:pollinations", "pollinations_free:pollinations-legacy"]);
        for (const preset of P.PRESETS.filter(p => p.type === "image")) {
            assert.ok(/^https:\/\//.test(preset.baseUrl), preset.id);
            assert.strictEqual(preset.accepted, undefined, "a preset never starts switched on");
        }
    },

    image_providers_keep_their_service_options_and_switch() {
        const list = [{id: "aihorde", name: "AI Horde", type: "image", service: "horde", baseUrl: "https://aihorde.net/api/v2", model: "Deliberate",
                       accepted: true, options: {width: 512, height: 576, steps: 22, n: 2, seed: 5, bogus: 1}},
                      {id: "x", name: "X", type: "image", service: "nope", baseUrl: "https://x", model: ""}];
        const saved = JSON.parse(P.serializeProviders(list));
        assert.deepStrictEqual(saved[0], {id: "aihorde", name: "AI Horde", type: "image", baseUrl: "https://aihorde.net/api/v2", model: "Deliberate",
                                          service: "horde", accepted: true, options: {width: 512, height: 576, steps: 22, n: 2, seed: 5}});
        assert.strictEqual(saved[1].type, "openai-compat", "an unknown service is not an image provider");
        assert.strictEqual(saved[1].service, undefined);
    },

    image_options_outside_the_limits_are_dropped_and_accepted_must_be_true() {
        const raw = JSON.stringify([{id: "h", name: "H", type: "image", service: "horde", baseUrl: "https://aihorde.net/api/v2", model: "",
                                      accepted: "yes", options: {width: 99999, height: "x", steps: 0, n: 99, seed: -1}}]);
        const entry = P.parseProviders({providersJson: raw})[0];
        assert.strictEqual(entry.accepted, false);
        assert.deepStrictEqual(plain(entry.options), {});
    },

    image_provider_config_says_whether_a_key_is_needed() {
        const make = (id, service, extra) => Object.assign({id, name: id, type: "image", service, baseUrl: "https://x.example.com", model: "m", accepted: true}, extra || {});
        const cfg = {providersJson: JSON.stringify([make("h", "horde"), make("p", "pollinations"), make("f", "pollinations-legacy")])};
        const h = plain(P.getProviderConfig("h", cfg));
        assert.deepStrictEqual([h.type, h.service, h.accepted, h.allowEmptyKey, h.found], ["image", "horde", true, true, true]);
        assert.strictEqual(P.getProviderConfig("p", cfg).allowEmptyKey, false);
        assert.strictEqual(P.getProviderConfig("f", cfg).allowEmptyKey, true);
        assert.strictEqual(P.getProviderConfig("h", cfg).apiKey, "");
        assert.strictEqual(P.getProviderConfig("nope", cfg).type, "openai-compat");
    },

    default_image_provider() {
        const list = [{id: "or", name: "OR", type: "openai-compat", baseUrl: "https://x", model: "m"},
                      {id: "h", name: "H", type: "image", service: "horde", baseUrl: "https://aihorde.net/api/v2", model: ""},
                      {id: "p", name: "P", type: "image", service: "pollinations", baseUrl: "https://gen.pollinations.ai", model: ""}];
        const json = JSON.stringify(list);
        assert.deepStrictEqual(plain(P.imageProviders({providersJson: json})).map(e => e.id), ["h", "p"]);
        assert.strictEqual(P.defaultImageProvider({providersJson: json, imageProvider: "p"}), "p");
        assert.strictEqual(P.defaultImageProvider({providersJson: json, imageProvider: "or"}), "h", "a text provider is never the image default");
        assert.strictEqual(P.defaultImageProvider({providersJson: json, imageProvider: "gone"}), "h");
        assert.strictEqual(P.defaultImageProvider({providersJson: JSON.stringify([list[0]])}), "");
        assert.strictEqual(P.defaultImageProvider(null), "");
    },

    isPlainHttpRemote() {
        for (const url of ["http://192.168.1.5:8000/v1", "http://example.com/v1", "HTTP://api.example.com", "http://10.0.0.2"])
            assert.strictEqual(P.isPlainHttpRemote(url), true, url);
        for (const url of ["https://example.com/v1", "http://localhost:11434/v1", "http://127.0.0.1:1234", "http://127.1.2.3/v1",
                           "http://[::1]:8080/v1", "http://foo.localhost/v1", "", null, "ftp://example.com"])
            assert.strictEqual(P.isPlainHttpRemote(url), false, String(url));
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("PASS " + name); }
    catch (e) { failed++; console.log("FAIL " + name + "\n  " + String(e.stack || e).split("\n").slice(0, 3).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
