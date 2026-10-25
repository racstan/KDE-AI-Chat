// How a chat's variant (reasoning level) reaches the request in each mode, with
// the stored id looked up at send time: a direct chat's fragment from what its
// provider reports (chat/DirectVariant.qml), an OpenCode chat's variant name from
// the server's catalogue (OpenCodeMode.variantSend), Pi's level only from Pi's own
// list (PiMode.thinkingFor). No variant, a model without variants and an id the
// model no longer offers all send nothing.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/ProviderVariants.js" as ProviderVariants

Item {
    id: root
    width: 200
    height: 100

    function i18n(text) { return text; }

    property var requests: []
    // The provider's /models answer.
    property var listBody: ({data: [
        {id: "openai/gpt-5", reasoning: {supported_efforts: ["high", "medium", "low"]}},
        {id: "plain/model"},
        {id: "elorian/glimpse", reasoning: {mandatory: false}}]})
    function makeXhr() {
        var x = {headers: {}, readyState: 0, status: 0, responseText: ""};
        x.open = function(method, url) { x.method = method; x.url = url; };
        x.setRequestHeader = function(k, v) { x.headers[k] = v; };
        x.send = function() {
            root.requests.push({method: x.method, url: x.url});
            x.status = 200;
            x.responseText = JSON.stringify(root.listBody);
            x.readyState = 4;
            x.onreadystatechange();
        };
        return x;
    }

    FakeChat { id: chat }
    Chat.DirectVariant { id: direct; chat: chat; xhrFactory: root.makeXhr }
    Chat.PiMode { id: pi; chat: chat }
    Chat.OpenCodeMode { id: openCode; chat: chat }

    HarnessTestCase {
        name: "VariantsInModes"

        readonly property var provider: ({id: "openrouter", name: "OpenRouter", type: "openai-compat", baseUrl: "https://or.example/api/v1", model: "openai/gpt-5"})

        function setup(session, config) {
            chat.plasmoid = {configuration: Object.assign({
                provider: "openrouter", perChatModelSettings: true, perChatPriority: "chat",
                providersJson: JSON.stringify([provider]), openCodeProvider: "openrouter", openCodeModel: "auto", piProvider: "openai", piModel: "gpt-5"
            }, config || {})};
            chat.sessions = [Object.assign({value: "a", text: "Chat"}, session)];
            chat.currentSessionId = "a";
        }

        function init() {
            ProviderVariants.clear();
            root.requests = [];
            chat.openCodeVariants = ({});
            chat.piThinkingModels = ({});
        }

        function resolve(sessionId) {
            var got = null;
            var cfg = {type: "openai-compat", baseUrl: provider.baseUrl, apiKey: "k", model: chat.effectiveConfig(sessionId).model, headers: null};
            direct.resolve(sessionId, cfg, function(send) { got = send; });
            tryVerify(function() { return got !== null; }, 2000);
            return JSON.parse(JSON.stringify(got));
        }

        // --- Direct ---

        function test_direct_a_chosen_variant_sends_the_providers_fragment() {
            setup({source: "provider", ownModel: true, chatVariant: "low"});
            compare(resolve("a"), {reasoning: {effort: "low"}});
            compare(root.requests.length, 1, "one /models request");
            resolve("a");
            compare(root.requests.length, 1, "the list is cached per provider");
        }

        function test_direct_no_variant_sends_nothing_and_asks_nothing() {
            setup({source: "provider", ownModel: true});
            compare(resolve("a"), {});
            compare(root.requests.length, 0, "no variant: not even a request");
        }

        function test_direct_a_stale_id_sends_nothing() {
            setup({source: "provider", ownModel: true, chatVariant: "xhigh"});
            compare(resolve("a"), {}, "the model does not offer xhigh");
        }

        function test_direct_a_model_without_variants_sends_nothing() {
            setup({source: "provider", ownModel: true, chatProvider: "", chatModel: "plain/model", chatVariant: "high"});
            compare(resolve("a"), {});
            setup({source: "provider", ownModel: true, chatModel: "elorian/glimpse", chatVariant: "high"});
            compare(resolve("a"), {}, "reasoning without levels is not a variant");
        }

        function test_direct_the_main_providers_variant_follows_the_priority_rule() {
            var withVariant = Object.assign({}, provider, {variant: "medium"});
            setup({source: "provider"}, {providersJson: JSON.stringify([withVariant])});
            compare(chat.effectiveConfig("a").variant, "medium");
            compare(resolve("a"), {reasoning: {effort: "medium"}});
            setup({source: "provider", ownModel: true, chatVariant: "low"}, {providersJson: JSON.stringify([withVariant])});
            compare(resolve("a"), {reasoning: {effort: "low"}}, "the chat's own wins");
            setup({source: "provider", ownModel: true, chatVariant: "low"}, {providersJson: JSON.stringify([withVariant]), perChatPriority: "main"});
            compare(resolve("a"), {reasoning: {effort: "medium"}}, "main wins");
        }

        function test_direct_an_unreachable_provider_sends_nothing() {
            setup({source: "provider", ownModel: true, chatVariant: "low"});
            var down = function() {
                var x = root.makeXhr();
                x.send = function() { x.status = 0; x.readyState = 4; x.onreadystatechange(); };
                return x;
            };
            direct.xhrFactory = down;
            compare(resolve("a"), {});
            direct.xhrFactory = root.makeXhr;
        }

        function test_other_modes_never_ask_the_direct_provider() {
            setup({source: "opencode", ownModel: true, openCodeVariant: "high", chatVariant: "low"});
            compare(resolve("a"), {});
            compare(root.requests.length, 0);
        }

        // --- OpenCode ---

        function test_opencode_the_variant_name_is_sent_only_when_the_server_offers_it() {
            setup({source: "opencode", ownModel: true, openCodeProvider: "openrouter", openCodeModel: "auto", openCodeVariant: "high"});
            var eff = chat.effectiveConfig("a");
            compare(eff.variant, "high");
            compare(openCode.variantSend(eff), {}, "catalogue not loaded: nothing");
            chat.openCodeVariants = {"openrouter/auto": ["low", "high"]};
            compare(openCode.variantSend(eff), {variant: "high"});
            compare(openCode.variantsOf("openrouter", "auto").length, 2);
            chat.openCodeVariants = {"openrouter/auto": ["low"]};
            compare(openCode.variantSend(eff), {}, "a name the server no longer lists");
            chat.openCodeVariants = {"openrouter/free": ["low", "high"]};
            compare(openCode.variantSend(eff), {}, "another model's variants do not apply");
            setup({source: "opencode", ownModel: true, openCodeProvider: "openrouter", openCodeModel: "auto"});
            chat.openCodeVariants = {"openrouter/auto": ["low", "high"]};
            compare(openCode.variantSend(chat.effectiveConfig("a")), {}, "none chosen");
        }

        function test_opencode_the_main_variant_is_used_when_the_chat_has_none() {
            setup({source: "opencode"}, {useOpenCode: true, openCodeVariant: "low"});
            chat.openCodeVariants = {"openrouter/auto": ["low", "high"]};
            compare(chat.effectiveConfig("a").variant, "low");
            compare(openCode.variantSend(chat.effectiveConfig("a")), {variant: "low"});
        }

        // --- Pi ---

        function test_pi_discovery_keeps_the_thinking_models_and_the_pickers_models() {
            var reply = {providers: [{id: "openai", models: ["gpt-5", "gpt-4o"], thinking: ["gpt-5"]}, {id: "ollama", models: ["llama3.2"], thinking: []}]};
            pi.applyDiscovery(JSON.stringify(reply));
            compare(chat.piProviderModelMap, {openai: ["gpt-5", "gpt-4o"], ollama: ["llama3.2"]});
            compare(chat.piThinkingModels, {"openai/gpt-5": true});
            compare(pi.variantsOf("openai", "gpt-5").length, 7, "Pi's own levels");
            compare(pi.variantsOf("openai", "gpt-4o").length, 0, "a model that does not think has no picker");
            // An older helper without the thinking column: no thinking models, models still listed.
            pi.applyDiscovery(JSON.stringify({providers: [{id: "openai", models: ["gpt-5"]}]}));
            compare(chat.piProviderModelMap, {openai: ["gpt-5"]});
            compare(chat.piThinkingModels, {});
            pi.applyDiscovery("not json");
            compare(chat.piProviderModelMap, {});
        }

        function test_pi_thinking_goes_to_the_bridge_only_for_pis_own_levels_and_thinking_models() {
            setup({source: "pi", ownModel: true, piProvider: "openai", piModel: "gpt-5", piThinking: "high"});
            compare(pi.promptBody("a", {content: "hi"}).thinking, "high", "the list is not loaded: as stored");
            chat.piThinkingModels = {"openai/gpt-5": true};
            compare(pi.promptBody("a", {content: "hi"}).thinking, "high");
            setup({source: "pi", ownModel: true, piProvider: "openai", piModel: "gpt-5", piThinking: "ludicrous"});
            chat.piThinkingModels = {"openai/gpt-5": true};
            compare(pi.promptBody("a", {content: "hi"}).thinking, "", "not one of Pi's levels");
            setup({source: "pi", ownModel: true, piProvider: "openai", piModel: "gpt-5", piThinking: "high"});
            chat.piThinkingModels = {"openai/gpt-5-mini": true};
            compare(pi.promptBody("a", {content: "hi"}).thinking, "", "Pi says gpt-5 does not think");
            setup({source: "pi", ownModel: true, piProvider: "openai", piModel: "gpt-5"});
            chat.piThinkingModels = {"openai/gpt-5": true};
            compare(pi.promptBody("a", {content: "hi"}).thinking, "", "none chosen");
        }

        function test_pi_the_main_thinking_level_is_the_default() {
            setup({source: "pi"}, {usePi: true, piThinking: "low"});
            chat.piThinkingModels = {"openai/gpt-5": true};
            compare(pi.promptBody("a", {content: "hi"}).thinking, "low");
            setup({source: "pi", ownModel: true, piThinking: "high"}, {usePi: true, piThinking: "low"});
            compare(pi.promptBody("a", {content: "hi"}).thinking, "high", "the chat's own wins");
        }
    }
}
