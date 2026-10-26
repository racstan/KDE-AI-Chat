// chat/PiChatSettings.qml: a Pi chat's provider, model and thinking level.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 400
    height: 320

    // i18n() comes from Plasma at runtime.
    function i18n(text) { return text; }

    Chat.PiChatSettings {
        id: pi
        width: 380
        providers: [{"text": "ollama", "value": "ollama"}, {"text": "opencode", "value": "opencode"}]
        providerModels: ({"ollama": ["qwen3:8b", "llama3.2"], "opencode": ["big-pickle"]})
        provider: "ollama"
        model: "llama3.2"
        thinking: "high"
        variants: [{"id": "low", "label": "Low", "send": {}}, {"id": "high", "label": "High", "send": {}}]
    }

    SignalSpy {
        id: edited
        target: pi
        signalName: "edited"
    }

    HarnessTestCase {
        name: "PiChatSettings"

        // The drop-downs in order (each sits in a SettingField with its explanation).
        function collect(item, test, found) {
            if (test(item))
                found.push(item);
            for (var i = 0; i < item.children.length; i++)
                collect(item.children[i], test, found);
            return found;
        }
        function combos() {
            return collect(pi, function(item) { return item instanceof QQC2.ComboBox; }, []);
        }

        function test_0_every_setting_is_explained() {
            var helps = collect(pi, function(item) { return item.isSettingHelp === true; }, []);
            compare(helps.length, 3, "provider, model and thinking");
            for (var i = 0; i < helps.length; i++)
                verify(helps[i].text.length > 20, "explanation " + i);
        }

        function test_1_shows_the_chats_values() {
            var c = combos();
            compare(c.length, 3);
            compare(c[0].currentText, "ollama");
            tryCompare(c[1], "editText", "llama3.2");
            compare(c[2].currentText, "High");
            verify(c[2].visible);
            screenshot(root, "pi-chat-settings");
        }

        function test_2_choosing_a_provider_picks_its_first_model() {
            var c = combos();
            c[0].currentIndex = 1;
            c[0].activated(1);
            compare(pi.provider, "opencode");
            compare(pi.model, "big-pickle");
            verify(edited.count > 0);
        }

        function test_3_thinking_default_is_empty() {
            var c = combos();
            c[2].currentIndex = 0;
            c[2].activated(0);
            compare(pi.thinking, "");
            compare(c[2].currentText, "Default");
        }

        function test_4_a_model_that_does_not_think_has_no_thinking_picker() {
            pi.variants = [];
            verify(!combos()[2].visible);
            pi.variants = [{"id": "low", "label": "Low", "send": {}}];
            verify(combos()[2].visible);
        }
    }
}
