// Tests for chat/EffectiveConfig.js (which mode/provider/model a chat uses), run by tests/test_effective_config.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/EffectiveConfig.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {resolve, hasOwnModelSettings, forSession, describe, mainMode};", ctx);
const E = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));

const models = {openai: "gpt-main", anthropic: "claude-main", zen: ""};
const modelFor = id => models[id] || "";

// Main: OpenCode + OpenCode Zen + model X (and Pi / direct settings kept for the other modes).
const mainOC = {useOpenCode: true, provider: "openai", openCodeProvider: "opencode", openCodeModel: "zen-x",
                openCodeAgent: "build", piProvider: "ollama", piModel: "qwen", modelFor};
const mainDirect = {provider: "openai", openCodeProvider: "opencode", openCodeModel: "zen-x", piProvider: "ollama", piModel: "qwen", modelFor};
const mainPi = Object.assign({}, mainDirect, {usePi: true});

// A chat that says Pi + OpenAI + model Y.
const chatPi = {ownModel: true, source: "pi", piProvider: "openai", piModel: "gpt-y", piThinking: "high"};
const on = (priority) => ({perChat: true, priority});
const off = {perChat: false, priority: "chat"};

const tests = {
    switch_off_ignores_the_chat_completely() {
        for (const priority of ["chat", "main"]) {
            const r = plain(E.resolve(mainOC, chatPi, {perChat: false, priority}));
            assert.strictEqual(r.mode, "opencode");
            assert.strictEqual(r.provider, "opencode");
            assert.strictEqual(r.model, "zen-x");
            assert.strictEqual(r.agent, "build");
            assert.strictEqual(r.source, "main");
        }
        assert.strictEqual(E.resolve(mainOC, chatPi, undefined).source, "main");
        assert.strictEqual(E.resolve(mainOC, chatPi, {}).source, "main");
    },

    owner_example_chat_wins() {
        const r = plain(E.resolve(mainOC, chatPi, on("chat")));
        assert.strictEqual(r.mode, "pi");
        assert.strictEqual(r.provider, "openai");
        assert.strictEqual(r.model, "gpt-y");
        assert.strictEqual(r.thinking, "high");
        assert.strictEqual(r.agent, "");
        assert.strictEqual(r.source, "chat");
    },

    owner_example_main_wins() {
        const r = plain(E.resolve(mainOC, chatPi, on("main")));
        assert.strictEqual(r.mode, "opencode");
        assert.strictEqual(r.provider, "opencode");
        assert.strictEqual(r.model, "zen-x");
        assert.strictEqual(r.agent, "build");
        assert.strictEqual(r.source, "main");
    },

    priority_defaults_to_chat() {
        assert.strictEqual(E.resolve(mainOC, chatPi, {perChat: true}).mode, "pi");
        assert.strictEqual(E.resolve(mainOC, chatPi, {perChat: true, priority: "bogus"}).mode, "pi");
    },

    missing_overrides_use_main_in_every_combination() {
        for (const chat of [null, undefined, {}, {source: "pi"}, {ownModel: true}, {ownModel: false, chatModel: "z"}, {text: "x", messages: []}]) {
            for (const opts of [off, on("chat"), on("main")]) {
                for (const main of [mainOC, mainDirect, mainPi]) {
                    const r = plain(E.resolve(main, chat, opts));
                    const expected = plain(E.resolve(main, null, off));
                    // {ownModel: true} with nothing filled in: the mode is the chat's own choice, i.e. none -> main's.
                    assert.deepStrictEqual(r, expected, JSON.stringify([chat, opts]));
                    assert.strictEqual(r.source, "main");
                }
            }
        }
    },

    main_direct_resolves_the_providers_own_model() {
        const r = plain(E.resolve(mainDirect, null, off));
        assert.deepStrictEqual(r, {mode: "provider", provider: "openai", model: "gpt-main", agent: "", thinking: "", source: "main",
                                   direct: {provider: "openai", model: "gpt-main"}});
        assert.strictEqual(plain(E.resolve({}, null, off)).provider, "openai", "no provider set -> openai");
    },

    direct_chat_override_and_fallbacks() {
        const chat = {ownModel: true, source: "provider", chatProvider: "anthropic", chatModel: "claude-y"};
        let r = plain(E.resolve(mainDirect, chat, on("chat")));
        assert.deepStrictEqual([r.mode, r.provider, r.model, r.source], ["provider", "anthropic", "claude-y", "chat"]);
        // Chat picked a provider but no model: that provider's configured model.
        r = plain(E.resolve(mainDirect, {ownModel: true, source: "provider", chatProvider: "anthropic"}, on("chat")));
        assert.deepStrictEqual([r.provider, r.model, r.source], ["anthropic", "claude-main", "chat"]);
        // Chat picked only a model: the main provider with the chat's model.
        r = plain(E.resolve(mainDirect, {ownModel: true, source: "provider", chatModel: "gpt-y"}, on("chat")));
        assert.deepStrictEqual([r.provider, r.model, r.source], ["openai", "gpt-y", "chat"]);
        // Main wins: the main provider and its model; the chat's model for another provider is not borrowed.
        r = plain(E.resolve(mainDirect, chat, on("main")));
        assert.deepStrictEqual([r.provider, r.model, r.source], ["openai", "gpt-main", "main"]);
    },

    main_wins_but_chat_fills_what_main_left_empty() {
        const noModel = Object.assign({}, mainDirect, {modelFor: () => ""});
        // Chat's model belongs to the main provider (no provider override): used because main has none.
        let r = plain(E.resolve(noModel, {ownModel: true, source: "provider", chatModel: "gpt-y"}, on("main")));
        assert.deepStrictEqual([r.provider, r.model, r.source], ["openai", "gpt-y", "chat"]);
        // ...but not when it was chosen for a different provider.
        r = plain(E.resolve(noModel, {ownModel: true, source: "provider", chatProvider: "anthropic", chatModel: "claude-y"}, on("main")));
        assert.deepStrictEqual([r.provider, r.model, r.source], ["openai", "", "main"]);
        // OpenCode: main has no model, the chat has one.
        const ocNoModel = Object.assign({}, mainOC, {openCodeModel: ""});
        r = plain(E.resolve(ocNoModel, {ownModel: true, source: "pi", openCodeModel: "chat-m"}, on("main")));
        assert.deepStrictEqual([r.mode, r.provider, r.model, r.source], ["opencode", "opencode", "chat-m", "chat"]);
    },

    chat_wins_but_main_fills_what_the_chat_left_empty() {
        const chat = {ownModel: true, source: "opencode", openCodeModel: "chat-m"};
        const r = plain(E.resolve(mainOC, chat, on("chat")));
        assert.deepStrictEqual([r.mode, r.provider, r.model, r.agent, r.source], ["opencode", "opencode", "chat-m", "build", "chat"]);
        // Same mode as main and nothing of the chat's used -> main.
        const same = plain(E.resolve(mainOC, {ownModel: true, source: "opencode"}, on("chat")));
        assert.strictEqual(same.source, "main");
        assert.strictEqual(same.model, "zen-x");
    },

    a_chat_in_the_same_mode_with_other_model_is_from_the_chat() {
        const r = plain(E.resolve(mainPi, {ownModel: true, source: "pi", piModel: "other"}, on("chat")));
        assert.deepStrictEqual([r.mode, r.provider, r.model, r.source], ["pi", "ollama", "other", "chat"]);
    },

    direct_pair_is_always_reported() {
        const r = plain(E.resolve(mainOC, chatPi, on("chat")));
        assert.deepStrictEqual(r.direct, {provider: "openai", model: "gpt-main"});
        const own = plain(E.resolve(mainOC, {ownModel: true, source: "opencode", chatProvider: "anthropic", chatModel: "claude-y"}, on("chat")));
        assert.deepStrictEqual(own.direct, {provider: "anthropic", model: "claude-y"});
    },

    source_alone_is_not_an_override() {
        // send() stores source on every chat; that must not freeze a chat against the main settings.
        assert.strictEqual(E.hasOwnModelSettings({source: "opencode"}), false);
        const r = plain(E.resolve(mainPi, {source: "opencode", openCodeSessionId: "ses_1"}, on("chat")));
        assert.strictEqual(r.mode, "pi");
        assert.strictEqual(r.source, "main");
    },

    legacy_chats_without_the_flag_count_when_a_model_field_is_set() {
        assert.strictEqual(E.hasOwnModelSettings({chatModel: "x"}), true);
        assert.strictEqual(E.hasOwnModelSettings({chatProvider: "anthropic"}), true);
        assert.strictEqual(E.hasOwnModelSettings({openCodeAgent: "plan"}), true);
        assert.strictEqual(E.hasOwnModelSettings({chatModel: "  "}), false);
        assert.strictEqual(E.hasOwnModelSettings({ownModel: false, chatModel: "x"}), false, "explicitly off");
        assert.strictEqual(E.hasOwnModelSettings(null), false);
        const r = plain(E.resolve(mainDirect, {source: "provider", chatModel: "gpt-old"}, on("chat")));
        assert.deepStrictEqual([r.model, r.source], ["gpt-old", "chat"]);
    },

    legacy_pi_chat_keeps_provider_and_model_in_chat_keys() {
        const chat = {source: "pi", chatProvider: "ollama", chatModel: "llama-old"};
        const r = plain(E.resolve(mainDirect, chat, on("chat")));
        assert.deepStrictEqual([r.mode, r.provider, r.model, r.source], ["pi", "ollama", "llama-old", "chat"]);
        assert.deepStrictEqual(r.direct, {provider: "openai", model: "gpt-main"}, "not mistaken for a direct override");
    },

    invalid_chat_source_falls_back_to_the_main_mode() {
        const r = plain(E.resolve(mainOC, {ownModel: true, source: "weird", chatModel: "x"}, on("chat")));
        assert.strictEqual(r.mode, "opencode");
    },

    for_session_reads_the_two_settings_from_the_configuration() {
        const config = {useOpenCode: true, provider: "openai", openCodeProvider: "opencode", openCodeModel: "zen-x",
                        perChatModelSettings: true, perChatPriority: "chat"};
        assert.strictEqual(E.forSession(config, chatPi, modelFor).mode, "pi");
        assert.strictEqual(E.forSession(Object.assign({}, config, {perChatPriority: "main"}), chatPi, modelFor).mode, "opencode");
        assert.strictEqual(E.forSession(Object.assign({}, config, {perChatModelSettings: false}), chatPi, modelFor).mode, "opencode");
        assert.strictEqual(E.forSession({}, chatPi, modelFor).mode, "provider", "empty configuration -> defaults");
        assert.strictEqual(E.forSession(null, null, null).mode, "provider");
        assert.strictEqual(E.mainMode({useOpenCode: true, usePi: true}), "opencode");
    },

    describe_builds_the_line() {
        const names = id => ({openai: "OpenAI", opencode: "OpenCode Zen"}[id]);
        assert.strictEqual(E.describe(E.resolve(mainOC, chatPi, on("chat")), names), "Pi · OpenAI · gpt-y");
        assert.strictEqual(E.describe(E.resolve(mainOC, chatPi, off), names), "OpenCode · OpenCode Zen · zen-x");
        assert.strictEqual(E.describe(E.resolve(mainDirect, null, off), names), "OpenAI · gpt-main");
        assert.strictEqual(E.describe({mode: "provider", provider: "x", model: ""}), "x");
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
