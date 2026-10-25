// Tests for chat/EffectiveConfig.js (which mode/provider/model a chat uses), run by tests/test_effective_config.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/EffectiveConfig.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {resolve, hasOwnModelSettings, forSession, describe, mainMode, inferSource, chatMode, isMode, unavailableText, agentOwner, variantText, PI_THINKING_LEVELS};", ctx);
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
    switch_off_ignores_the_chats_model_settings_but_not_its_mode() {
        for (const priority of ["chat", "main"]) {
            // A Pi chat under OpenCode main settings: still Pi, with the main settings' Pi provider and model.
            const r = plain(E.resolve(mainOC, chatPi, {perChat: false, priority}));
            assert.strictEqual(r.mode, "pi");
            assert.strictEqual(r.provider, "ollama");
            assert.strictEqual(r.model, "qwen");
            assert.strictEqual(r.thinking, "");
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

    owner_example_main_wins_within_the_chats_mode() {
        // "main" priority decides provider/model, not the mode: the chat is a Pi chat.
        const r = plain(E.resolve(mainOC, chatPi, on("main")));
        assert.strictEqual(r.mode, "pi");
        assert.strictEqual(r.provider, "ollama");
        assert.strictEqual(r.model, "qwen");
        assert.strictEqual(r.agent, "");
        assert.strictEqual(r.thinking, "high", "main has no thinking level, so the chat's fills in");
        assert.strictEqual(r.source, "chat");
    },

    a_chat_keeps_its_mode_whatever_the_settings_say() {
        const mains = {provider: mainDirect, opencode: mainOC, pi: mainPi};
        const chats = {provider: {source: "provider"}, opencode: {source: "opencode"}, pi: {source: "pi"}};
        for (const chatMode of Object.keys(chats)) {
            for (const mainName of Object.keys(mains)) {
                for (const opts of [off, on("chat"), on("main"), {}, undefined]) {
                    for (const own of [{}, {ownModel: true}, {ownModel: false}, {chatModel: "x"}, {openCodeModel: "y"}, {piModel: "z"}]) {
                        const chat = Object.assign({}, chats[chatMode], own);
                        assert.strictEqual(E.resolve(mains[mainName], chat, opts).mode, chatMode, JSON.stringify([chatMode, mainName, opts, own]));
                    }
                }
            }
        }
        // Even when the chat's own fields name another mode's settings.
        const r = plain(E.resolve(mainPi, {ownModel: true, source: "provider", chatProvider: "anthropic", chatModel: "claude-y",
                                           piProvider: "openai", piModel: "gpt-y"}, on("chat")));
        assert.deepStrictEqual([r.mode, r.provider, r.model], ["provider", "anthropic", "claude-y"]);
    },

    a_chat_without_a_stored_mode_gets_the_inferred_one_not_the_main_mode() {
        assert.strictEqual(E.resolve(mainPi, {text: "old"}, off).mode, "provider");
        assert.strictEqual(E.resolve(mainDirect, {openCodeSessionId: "ses_1"}, off).mode, "opencode");
        assert.strictEqual(E.resolve(mainDirect, {source: "weird", openCodeSessionId: "ses_1"}, on("main")).mode, "opencode");
    },

    infer_source_for_old_chats() {
        assert.strictEqual(E.inferSource({}), "provider");
        assert.strictEqual(E.inferSource(null), "provider");
        assert.strictEqual(E.inferSource({openCodeSessionId: "ses_abc"}), "opencode");
        assert.strictEqual(E.inferSource({openCodeSessionId: "  "}), "provider");
        assert.strictEqual(E.inferSource({messages: [{role: "user"}, {role: "question_request", harnessChatId: "c1"}]}), "pi");
        assert.strictEqual(E.inferSource({messages: [{role: "user"}], piModel: "x", chatModel: "y"}), "provider",
                           "stale model fields do not decide the mode");
        assert.strictEqual(E.inferSource({openCodeSessionId: "ses_1", messages: [{harnessChatId: "c"}]}), "opencode");
        assert.strictEqual(E.chatMode({source: "pi", openCodeSessionId: "ses_1"}), "pi", "a stored mode wins");
        assert.strictEqual(E.chatMode({source: "nope", openCodeSessionId: "ses_1"}), "opencode");
        assert.strictEqual(E.isMode("pi"), true);
        assert.strictEqual(E.isMode("Pi"), false);
        assert.strictEqual(E.isMode(undefined), false);
    },

    unavailable_text_names_the_mode_and_says_it_stays() {
        const t = E.unavailableText("opencode", "OpenCode isn't reachable at http://127.0.0.1:4096.");
        assert.ok(t.indexOf("an OpenCode chat") >= 0 && t.indexOf("isn't reachable at http://127.0.0.1:4096.") >= 0, t);
        assert.ok(t.indexOf("stays in OpenCode mode") >= 0, t);
        const p = E.unavailableText("pi", "Pi: the Pi bridge didn't start");
        assert.ok(p.indexOf("a Pi chat") >= 0 && p.indexOf("bridge didn't start.") >= 0 && p.indexOf("stays in Pi mode") >= 0, p);
        assert.ok(E.unavailableText("provider", "").indexOf("stays in direct provider mode") >= 0);
    },

    priority_defaults_to_chat() {
        assert.strictEqual(E.resolve(mainOC, chatPi, {perChat: true}).mode, "pi");
        assert.strictEqual(E.resolve(mainOC, chatPi, {perChat: true, priority: "bogus"}).mode, "pi");
    },

    missing_overrides_use_main_in_every_combination() {
        // No chat at all: the main settings, including the main mode.
        for (const opts of [off, on("chat"), on("main")]) {
            for (const main of [mainOC, mainDirect, mainPi]) {
                for (const chat of [null, undefined]) {
                    assert.deepStrictEqual(plain(E.resolve(main, chat, opts)), plain(E.resolve(main, null, off)));
                }
                // A chat with no model settings of its own: the main settings' fields for the chat's mode.
                for (const chat of [{source: "provider"}, {source: "provider", ownModel: true}, {source: "provider", ownModel: false, chatModel: "z"}, {text: "x", messages: []}]) {
                    const r = plain(E.resolve(main, chat, opts));
                    assert.strictEqual(r.mode, "provider");
                    assert.strictEqual(r.source, "main");
                    assert.deepStrictEqual([r.provider, r.model], [main.provider, modelFor(main.provider)]);
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
        r = plain(E.resolve(ocNoModel, {ownModel: true, source: "opencode", openCodeModel: "chat-m"}, on("main")));
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
        assert.strictEqual(r.mode, "opencode", "the chat's mode, not the main mode");
        assert.strictEqual(r.provider, "opencode", "the main settings' OpenCode provider");
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

    invalid_chat_source_is_inferred_not_taken_from_the_main_mode() {
        const r = plain(E.resolve(mainOC, {ownModel: true, source: "weird", chatModel: "x"}, on("chat")));
        assert.strictEqual(r.mode, "provider");
        assert.strictEqual(r.model, "x");
    },

    for_session_reads_the_two_settings_from_the_configuration() {
        const config = {useOpenCode: true, provider: "openai", openCodeProvider: "opencode", openCodeModel: "zen-x",
                        perChatModelSettings: true, perChatPriority: "chat"};
        assert.deepStrictEqual(["pi", "openai", "gpt-y"], [E.forSession(config, chatPi, modelFor)].map(r => [r.mode, r.provider, r.model])[0]);
        for (const changed of [{perChatPriority: "main"}, {perChatModelSettings: false}, {useOpenCode: false, usePi: true}, {useOpenCode: false}]) {
            assert.strictEqual(E.forSession(Object.assign({}, config, changed), chatPi, modelFor).mode, "pi", JSON.stringify(changed));
        }
        assert.strictEqual(E.forSession(config, null, modelFor).mode, "opencode", "no chat: the main mode");
        assert.strictEqual(E.forSession({}, chatPi, modelFor).mode, "pi", "empty configuration -> the chat's mode");
        assert.strictEqual(E.forSession(null, null, null).mode, "provider");
        assert.strictEqual(E.mainMode({useOpenCode: true, usePi: true}), "opencode");
    },

    // The agent picked above an OpenCode chat is stored where resolve() takes
    // the chat's agent from, so the chat really uses it (it used to always go
    // to the main settings: ignored for a chat with its own agent, and
    // changing every other chat).
    agent_owner_is_where_the_chats_agent_comes_from() {
        const ownAgent = {source: "opencode", ownModel: true, openCodeAgent: "plan"};
        const cfg = (perChat, priority, agent) => ({useOpenCode: true, perChatModelSettings: perChat, perChatPriority: priority,
                                                    openCodeAgent: agent, openCodeProvider: "opencode", openCodeModel: "zen-x"});
        const cases = [
            [cfg(false, "chat", "build"), ownAgent, "main"],
            [cfg(true, "chat", "build"), ownAgent, "chat"],
            [cfg(true, "main", "build"), ownAgent, "main"],
            [cfg(true, "main", ""), ownAgent, "chat"],
            [cfg(true, "chat", "build"), {source: "opencode", ownModel: false, openCodeAgent: "plan"}, "main"],
            [cfg(true, "chat", "build"), {source: "opencode"}, "main"],
            [cfg(true, "chat", "build"), null, "main"],
        ];
        for (const [config, chat, owner] of cases) {
            assert.strictEqual(E.agentOwner(config, chat), owner, JSON.stringify([config, chat]));
            // Storing the pick there makes it the chat's agent.
            const picked = owner === "chat" ? [config, Object.assign({}, chat, {openCodeAgent: "go"})]
                                            : [Object.assign({}, config, {openCodeAgent: "go"}), chat];
            assert.strictEqual(E.forSession(picked[0], picked[1], modelFor).agent, "go", JSON.stringify([config, chat]));
        }
    },

    describe_builds_the_line() {
        const names = id => ({openai: "OpenAI", opencode: "OpenCode Zen"}[id]);
        assert.strictEqual(E.describe(E.resolve(mainOC, chatPi, on("chat")), names), "Pi · OpenAI · gpt-y");
        assert.strictEqual(E.describe(E.resolve(mainOC, chatPi, off), names), "Pi · ollama · qwen");
        assert.strictEqual(E.describe(E.resolve(mainOC, null, off), names), "OpenCode · OpenCode Zen · zen-x");
        assert.strictEqual(E.describe(E.resolve(mainDirect, null, off), names), "OpenAI · gpt-main");
        assert.strictEqual(E.describe({mode: "provider", provider: "x", model: ""}), "x");
    },
    describe_for_the_composer_bar_names_the_mode_and_adds_the_variant() {
        const names = id => ({nvidia: "NVIDIA NIM"}[id]);
        const bar = eff => E.describe(eff, names, {directLabel: "Direct", variant: E.variantText(eff, "")});
        assert.strictEqual(bar({mode: "provider", provider: "nvidia", model: "m"}), "Direct · NVIDIA NIM · m");
        assert.strictEqual(bar({mode: "pi", provider: "openai", model: "gpt", thinking: "high"}), "Pi · openai · gpt · thinking high");
        assert.strictEqual(bar({mode: "pi", provider: "openai", model: "gpt", thinking: ""}), "Pi · openai · gpt");
        assert.strictEqual(bar({mode: "opencode", provider: "p", model: "m", agent: "build"}), "OpenCode · p · m · agent build");
        assert.strictEqual(bar({mode: "opencode", provider: "", model: "", agent: "build"}), "OpenCode · agent build");
        assert.strictEqual(E.describe({mode: "provider", provider: "nvidia", model: "m"}, names, {directLabel: "Direct", variant: "fast"}), "Direct · NVIDIA NIM · m · fast");
        assert.strictEqual(E.variantText({mode: "pi", thinking: "low"}, "fast"), "fast", "a direct variant wins");
        assert.strictEqual(E.variantText({mode: "provider"}, ""), "");
        assert.strictEqual(E.PI_THINKING_LEVELS[0], "");
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
