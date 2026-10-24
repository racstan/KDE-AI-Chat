// chat/PiChatSettings.qml: a Pi chat's provider, model and thinking level.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 400
    height: 320

    Chat.PiChatSettings {
        id: pi
        width: 380
        providers: [{"text": "ollama", "value": "ollama"}, {"text": "opencode", "value": "opencode"}]
        providerModels: ({"ollama": ["qwen3:8b", "llama3.2"], "opencode": ["big-pickle"]})
        provider: "ollama"
        model: "llama3.2"
        thinking: "high"
    }

    SignalSpy {
        id: edited
        target: pi
        signalName: "edited"
    }

    HarnessTestCase {
        name: "PiChatSettings"

        function combos() {
            var found = [];
            for (var i = 0; i < pi.children.length; i++)
                if (pi.children[i] instanceof QQC2.ComboBox) found.push(pi.children[i]);
            return found;
        }

        function test_1_shows_the_chats_values() {
            var c = combos();
            compare(c.length, 3);
            compare(c[0].currentText, "ollama");
            compare(c[1].editText, "llama3.2");
            compare(c[2].currentText, "high");
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
            compare(c[2].currentText, "(model default)");
        }
    }
}
