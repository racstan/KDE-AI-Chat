// The Chat info panel's line (chat/EffectiveLine.qml: mode, provider, model,
// variant, and its "Change…" button) and the quick model picker it opens
// (chat/ComposerPicker.qml, which /model also opens above the message box).
import QtQuick
import QtQuick.Window
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/ProviderVariants.js" as ProviderVariants

Item {
    id: root
    width: 520
    height: 420

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    property var requests: []
    // What the fake provider's /models answers (tests that need variants replace it).
    property var listBody: ({data: [{id: "acme/chat-big"}, {id: "acme/embed-text-1"}, {id: "acme/chat-small"}, {id: "nemotron-3.5-bolt-e4b"}]})
    function makeXhr() {
        var x = {headers: {}, readyState: 0, status: 0, responseText: ""};
        x.open = function(method, url) { x.method = method; x.url = url; };
        x.setRequestHeader = function(k, v) { x.headers[k] = v; };
        x.send = function() {
            root.requests.push({method: x.method, url: x.url});
            Qt.callLater(function() {
                x.status = 200;
                x.responseText = JSON.stringify(root.listBody);
                x.readyState = 4;
                x.onreadystatechange();
            });
        };
        return x;
    }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    Chat.EffectiveLine {
        id: bar
        x: 10
        y: 10
        width: root.barWidth
        chat: chat
        effective: chat.effectiveConfig(chat.currentSessionId)
        perChat: true
        providerName: function(id) { return chat.providerDisplayName(id); }

        readonly property string fullText: bar.description
    }
    property real barWidth: 500

    SignalSpy {
        id: changedSpy
        target: bar
        signalName: "modelChanged"
    }

    HarnessTestCase {
        id: tc
        name: "ChatInfoPicker"

        // Sets the chat up: extra config keys, and the one chat (id "a").
        function setup(session, config) {
            var configuration = Object.assign({
                provider: "nvidia",
                perChatModelSettings: true,
                providersJson: JSON.stringify([{id: "nvidia", name: "NVIDIA NIM", type: "openai-compat", baseUrl: "https://nim.example/v1", model: "acme/chat-big"}])
            }, config || {});
            chat.plasmoid = {configuration: configuration};
            chat.walletApiKeys = {"nvidia": "good"};
            chat.sessions = [Object.assign({value: "a", text: "Chat"}, session)];
            chat.currentSessionId = "a";
        }

        function directChat(extra) {
            return Object.assign({source: "provider", ownModel: true, chatProvider: "nvidia", chatModel: "nemotron-3.5-bolt-e4b"}, extra || {});
        }
        function piChat(extra) {
            return Object.assign({source: "pi", ownModel: true, piProvider: "openai", piModel: "gpt-5", piThinking: "high"}, extra || {});
        }
        function openCodeChat(extra) {
            return Object.assign({source: "opencode", ownModel: true, openCodeProvider: "openrouter", openCodeModel: "auto", openCodeAgent: "build"}, extra || {});
        }

        function init() {
            bar.picker.close();
            tryVerify(function() { return !bar.picker.visible; });
            ProviderVariants.clear();
            root.listBody = {data: [{id: "acme/chat-big"}, {id: "acme/embed-text-1"}, {id: "acme/chat-small"}, {id: "nemotron-3.5-bolt-e4b"}]};
            chat.openCodeVariants = ({});
            chat.piThinkingModels = ({});
            root.barWidth = 500;
            root.requests = [];
            chat.calls = [];
            chat.openCodeModelsList = [];
            chat.openCodeAgentsList = [];
            chat.piProviderModelMap = ({});
            bar.picker.xhrFactory = root.makeXhr;
            changedSpy.clear();
            setup(directChat());
        }

        function cleanup() { bar.picker.close(); }

        function open() {
            mouseClick(findChild(bar, "changeModelButton"));
            tryVerify(function() { return bar.picker.opened; }, 2000);
        }
        function inPicker(name) { return findChild(bar.picker.contentItem, name); }
        function rows() { return findChildren(bar.picker.contentItem, "modelRow"); }
        function windowShot(name) {
            var path = screensDir + name + ".png";
            var saved = false;
            verify(root.Window.contentItem.grabToImage(function(result) { saved = result.saveToFile(path); }));
            tryVerify(function() { return saved; }, 5000);
            return path;
        }

        // --- The line ---

        function test_1_direct_chat_shows_mode_provider_and_model() {
            compare(bar.fullText, "Direct · NVIDIA NIM · nemotron-3.5-bolt-e4b");
            compare(bar.variantText, "");
            var text = findChild(bar, "effectiveLine");
            verify(text.visible);
            compare(text.text, bar.fullText);
            verify(findChild(bar, "changeModelButton").visible, "a Change… button");
            compare(findChild(bar, "changeModelButton").text, "Change…");
            compare(findChild(bar, "effectiveSource").text, "From this chat's settings");
            wait(50);
            screenshot(root, "chat-info-line-direct");
        }

        function test_2_opencode_chat_shows_the_agent() {
            setup(openCodeChat());
            compare(bar.fullText, "OpenCode · openrouter · auto · agent build");
            wait(50);
            screenshot(root, "chat-info-line-opencode");
        }

        function test_3_pi_chat_shows_the_thinking_level_when_there_is_one() {
            setup(piChat());
            compare(bar.fullText, "Pi · openai · gpt-5 · thinking high");
            wait(50);
            screenshot(root, "chat-info-line-pi");
            setup(piChat({piThinking: ""}));
            compare(bar.fullText, "Pi · openai · gpt-5", "model default: nothing to show");
        }

        function test_4_a_direct_variant_shows_at_the_end_and_nothing_when_empty() {
            compare(bar.fullText, "Direct · NVIDIA NIM · nemotron-3.5-bolt-e4b");
            chat.setSessionProperty("a", "chatVariant", "fast");
            compare(bar.fullText, "Direct · NVIDIA NIM · nemotron-3.5-bolt-e4b · variant fast");
            chat.setSessionProperty("a", "chatVariant", "");
            compare(bar.fullText, "Direct · NVIDIA NIM · nemotron-3.5-bolt-e4b");
        }

        function test_5_the_line_follows_the_chat() {
            chat.setSessionProperty("a", "chatModel", "acme/chat-small");
            compare(bar.fullText, "Direct · NVIDIA NIM · acme/chat-small");
        }

        function test_6_a_narrow_panel_wraps_the_line_and_keeps_the_button() {
            setup(piChat({piModel: "a-really-long-model-name-for-a-narrow-panel-with-1m-context"}));
            root.barWidth = 260;
            wait(50);
            var text = findChild(bar, "effectiveLine");
            var button = findChild(bar, "changeModelButton");
            verify(text.lineCount > 1, "the line wraps");
            verify(text.text.indexOf("thinking high") > 0, "mode and variant are all there");
            verify(button.x + button.width <= bar.width, "the button stays inside the panel");
            screenshot(root, "chat-info-line-narrow");
        }

        // --- The picker ---

        function test_7_the_picker_lists_live_chat_models_and_changes_the_model() {
            open();
            tryVerify(function() { return rows().length === 3; }, 3000, "chat models only, no embeddings");
            compare(root.requests[0].url, "https://nim.example/v1/models");
            compare(inPicker("pickerMode").text.indexOf("Mode: Direct") === 0, true);
            wait(100);
            windowShot("composer-picker-direct");
            var target = null;
            for (var i = 0; i < rows().length; i++)
                if (rows()[i].modelData.id === "acme/chat-small")
                    target = rows()[i];
            verify(target, "row for acme/chat-small");
            mouseClick(target);
            compare(chat.calls.length, 1);
            compare(chat.calls[0].name, "overrides");
            compare(chat.calls[0].args[0], "a");
            compare(chat.calls[0].args[1].chatModel, "acme/chat-small");
            compare(chat.calls[0].args[1].ownModel, true);
            verify(chat.calls[0].args[1].source === undefined, "the mode is never written");
            compare(bar.fullText, "Direct · NVIDIA NIM · acme/chat-small");
            tryVerify(function() { return !bar.picker.opened; });
        }

        function test_8_a_chat_without_own_settings_gets_them_from_the_pick() {
            setup({source: "provider"});
            compare(bar.fullText, "Direct · NVIDIA NIM · acme/chat-big", "the main model");
            open();
            tryVerify(function() { return rows().length > 0; }, 3000);
            verify(inPicker("pickerHint").visible, "says choosing gives the chat its own settings");
            var big = rows()[0];
            mouseClick(rows()[rows().length - 1]);
            var overrides = chat.calls[0].args[1];
            compare(overrides.ownModel, true);
            compare(overrides.chatProvider, "", "still the main provider");
            verify(overrides.chatModel !== "acme/chat-big");
            compare(bar.fullText, "Direct · NVIDIA NIM · " + overrides.chatModel);
        }

        function test_9_filtering_and_enter_choose_a_model() {
            open();
            tryVerify(function() { return rows().length === 3; }, 3000);
            keyClick("s");
            keyClick("m");
            tryVerify(function() { return rows().length === 1; });
            keyClick(Qt.Key_Return);
            compare(chat.calls[0].args[1].chatModel, "acme/chat-small");
        }

        function test_10_pi_chat_picks_model_and_thinking() {
            setup(piChat());
            chat.piProviderModelMap = {"openai": ["gpt-5", "gpt-5-mini"]};
            chat.piThinkingModels = {"openai/gpt-5": true, "openai/gpt-5-mini": true};
            open();
            tryVerify(function() { return rows().length === 2; }, 3000);
            var choices = findChildren(bar.picker.contentItem, "variantChoice");
            verify(choices.length >= 5, "thinking levels offered");
            windowShot("composer-picker-pi");
            var low = null;
            for (var i = 0; i < choices.length; i++)
                if (choices[i].text === "Low")
                    low = choices[i];
            verify(low);
            mouseClick(low);
            compare(chat.calls[0].args[1].piThinking, "low");
            compare(chat.calls[0].args[1].piModel, "gpt-5", "the model is kept");
            compare(bar.fullText, "Pi · openai · gpt-5 · thinking low");
            tryVerify(function() { return !bar.picker.opened; });
            open();
            tryVerify(function() { return rows().length === 2; }, 3000);
            mouseClick(rows()[1]);
            compare(chat.calls[1].args[1].piModel, "gpt-5-mini");
            compare(chat.calls[1].args[1].piThinking, "low", "the thinking level is kept");
            compare(bar.fullText, "Pi · openai · gpt-5-mini · thinking low");
        }

        function test_11_opencode_chat_picks_a_model_of_its_provider_and_an_agent() {
            setup(openCodeChat());
            chat.openCodeModelsList = ["openrouter/auto", "openrouter/free", "anthropic/claude-x"];
            chat.openCodeAgentsList = ["build", "plan"];
            open();
            tryVerify(function() { return rows().length === 2; }, 3000, "only the models of openrouter");
            windowShot("composer-picker-opencode");
            compare(inPicker("pickerMode").text.indexOf("Mode: OpenCode") === 0, true);
            mouseClick(rows()[1]);
            compare(chat.calls[0].args[1].openCodeModel, "free");
            compare(chat.calls[0].args[1].openCodeProvider, "openrouter");
            compare(bar.fullText, "OpenCode · openrouter · free · agent build");
            open();
            var plan = null;
            var choices = findChildren(bar.picker.contentItem, "agentChoice");
            for (var i = 0; i < choices.length; i++)
                if (choices[i].text === "plan")
                    plan = choices[i];
            verify(plan, "the agents are offered");
            mouseClick(plan);
            compare(bar.fullText, "OpenCode · openrouter · free · agent plan");
        }

        function test_12_a_direct_chat_has_no_variant_choices() {
            open();
            tryVerify(function() { return rows().length === 3; }, 3000);
            wait(50);
            compare(findChildren(bar.picker.contentItem, "variantChoice").length, 0, "this provider reports no variants: no chips");
            verify(!inPicker("variantChoices").visible);
        }

        // --- Variants (reasoning levels), only where the source reports them ---

        function test_19_a_pi_model_that_does_not_think_has_no_thinking_chips() {
            setup(piChat());
            chat.piProviderModelMap = {"openai": ["gpt-5", "gpt-5-mini"]};
            chat.piThinkingModels = {"openai/gpt-5-mini": true};
            open();
            tryVerify(function() { return rows().length === 2; }, 3000);
            compare(findChildren(bar.picker.contentItem, "variantChoice").length, 0, "gpt-5 is not marked as thinking");
            verify(!inPicker("variantChoices").visible);
        }

        function test_1a_a_direct_model_that_reports_variants_gets_chips_and_the_choice_is_saved() {
            root.listBody = {data: [{id: "acme/chat-big", reasoning: {supported_efforts: ["low", "high"]}}, {id: "acme/chat-small"}, {id: "nemotron-3.5-bolt-e4b"}]};
            setup(directChat({chatModel: "acme/chat-big"}));
            compare(bar.fullText, "Direct · NVIDIA NIM · acme/chat-big");
            open();
            tryVerify(function() { return findChildren(bar.picker.contentItem, "variantChoice").length === 3; }, 3000, "default, low, high");
            var choices = findChildren(bar.picker.contentItem, "variantChoice");
            compare(choices[0].text, "default");
            compare(choices[1].text, "Low");
            verify(choices[0].checked, "nothing chosen yet");
            windowShot("composer-picker-variants-direct");
            mouseClick(choices[2]);
            compare(chat.calls[0].args[1].chatVariant, "high");
            compare(chat.calls[0].args[1].chatModel, "acme/chat-big", "the model is kept");
            compare(bar.fullText, "Direct · NVIDIA NIM · acme/chat-big · variant high");
            compare(bar.variantText, "variant high");
            tryVerify(function() { return !bar.picker.opened; });
            // Choosing another model starts without a variant (variants belong to a model).
            open();
            tryVerify(function() { return rows().length === 3; }, 3000);
            for (var i = 0; i < rows().length; i++)
                if (rows()[i].modelData.id === "acme/chat-small")
                    mouseClick(rows()[i]);
            compare(chat.calls[1].args[1].chatModel, "acme/chat-small");
            compare(chat.calls[1].args[1].chatVariant, "");
            compare(bar.fullText, "Direct · NVIDIA NIM · acme/chat-small");
        }

        function test_1b_a_stored_direct_variant_shows_in_the_bar_and_is_checked_in_the_picker() {
            root.listBody = {data: [{id: "acme/chat-big", reasoning: {supported_efforts: ["low", "high"]}}]};
            setup(directChat({chatModel: "acme/chat-big", chatVariant: "low"}));
            compare(bar.fullText, "Direct · NVIDIA NIM · acme/chat-big · variant low");
            open();
            tryVerify(function() { return findChildren(bar.picker.contentItem, "variantChoice").length === 3; }, 3000);
            var choices = findChildren(bar.picker.contentItem, "variantChoice");
            verify(choices[1].checked && !choices[0].checked && !choices[2].checked);
        }

        function test_1c_opencode_variants_are_chips_next_to_the_agents() {
            setup(openCodeChat());
            chat.openCodeModelsList = ["openrouter/auto", "openrouter/free"];
            chat.openCodeAgentsList = ["build", "plan"];
            chat.openCodeVariants = {"openrouter/auto": ["low", "high"]};
            open();
            tryVerify(function() { return rows().length === 2; }, 3000);
            compare(findChildren(bar.picker.contentItem, "agentChoice").length, 2);
            var choices = findChildren(bar.picker.contentItem, "variantChoice");
            compare(choices.length, 3, "default, low, high");
            windowShot("composer-picker-variants-opencode");
            mouseClick(choices[2]);
            compare(chat.calls[0].args[1].openCodeVariant, "high");
            compare(chat.calls[0].args[1].openCodeAgent, "build", "the agent is kept");
            compare(bar.fullText, "OpenCode · openrouter · auto · agent build · variant high");
            open();
            tryVerify(function() { return rows().length === 2; }, 3000);
            mouseClick(rows()[1]);
            compare(chat.calls[1].args[1].openCodeModel, "free");
            compare(chat.calls[1].args[1].openCodeVariant, "", "another model: no variant");
            compare(bar.fullText, "OpenCode · openrouter · free · agent build");
            open();
            tryVerify(function() { return rows().length === 2; }, 3000);
            compare(findChildren(bar.picker.contentItem, "variantChoice").length, 0, "openrouter/free reports none: no chips");
        }

        function test_1d_the_picker_opens_under_the_line_inside_the_panel() {
            open();
            var below = bar.picker.contentItem.mapToItem(root, 0, 0);
            verify(bar.picker.y >= bar.height, "under the line, not above it");
            verify(below.y > bar.y, "on screen below the line");
            verify(bar.picker.width <= bar.width + 1);
            wait(100);
            windowShot("chat-info-picker-open");
        }

        function test_13_with_per_chat_settings_off_the_picker_explains_and_offers_the_settings() {
            setup(directChat(), {perChatModelSettings: false});
            open();
            var note = inPicker("perChatOffNote");
            verify(note.visible);
            verify(note.text.indexOf("Let chats have their own model settings") >= 0);
            compare(rows().length, 0, "nothing to pick");
            verify(!inPicker("pickerFilter").visible);
            windowShot("composer-picker-per-chat-off");
            var button = inPicker("openSettingsButton");
            verify(button.visible);
            mouseClick(button);
            compare(chat.calls.length, 1);
            compare(chat.calls[0].name, "openSettings");
            tryVerify(function() { return !bar.picker.opened; });
            compare(root.requests.length, 0, "no model list is fetched");
        }

        function test_14_the_mode_cannot_be_changed_here() {
            for (var mode of ["provider", "opencode", "pi"]) {
                var session = mode === "provider" ? directChat() : mode === "pi" ? piChat() : openCodeChat();
                setup(session);
                open();
                var label = inPicker("pickerMode");
                verify(label.text.indexOf("fixed") >= 0, label.text);
                bar.picker.choose("model", "whatever");
                bar.picker.choose("variant", "whatever");
                tryVerify(function() { return chat.calls.length >= 1; });
                for (var i = 0; i < chat.calls.length; i++)
                    verify(chat.calls[i].args[1].source === undefined, "source is never written");
                compare(chat.effectiveConfig("a").mode, mode);
                bar.picker.close();
                tryVerify(function() { return !bar.picker.visible; });
                chat.calls = [];
            }
        }

        function test_15_main_settings_that_win_are_reported_not_hidden() {
            setup(directChat(), {perChatPriority: "main"});
            open();
            tryVerify(function() { return rows().length > 0; }, 3000);
            bar.picker.choose("model", "acme/chat-small");
            verify(bar.picker.opened, "stays open: the choice did not take effect");
            var note = inPicker("pickerNote");
            verify(note.visible);
            verify(note.text.indexOf("main settings win") >= 0, note.text);
            compare(bar.fullText, "Direct · NVIDIA NIM · acme/chat-big");
        }

        function test_16_a_failed_model_list_says_so() {
            bar.picker.xhrFactory = function() {
                var x = root.makeXhr();
                var send = x.send;
                x.send = function() {
                    Qt.callLater(function() { x.status = 403; x.responseText = "{}"; x.readyState = 4; x.onreadystatechange(); });
                };
                return x;
            };
            open();
            var status = inPicker("pickerStatus");
            tryVerify(function() { return status.visible && status.text.indexOf("rejected the API key") >= 0; }, 3000);
        }

        function test_17_the_message_box_only_option_is_not_offered_in_the_panel() {
            open();
            verify(!inPicker("moreSettingsButton").visible, "the Chat info panel is already open");
            compare(bar.picker.showMoreSettings, false);
        }

        function test_17b_a_saved_choice_is_announced_so_the_panel_reloads() {
            open();
            tryVerify(function() { return rows().length === 3; }, 3000);
            mouseClick(rows()[1]);
            tryVerify(function() { return !bar.picker.opened; });
            tryVerify(function() { return changedSpy.count >= 1; }, 2000, "modelChanged() after the picker closed");
        }

        function test_18_clicking_the_bar_again_closes_the_picker() {
            open();
            mouseClick(findChild(bar, "changeModelButton"));
            tryVerify(function() { return !bar.picker.opened; });
        }
    }
}
