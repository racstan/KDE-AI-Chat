// The privacy badge above the message box: where this chat's messages go.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 420
    height: 60

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    Chat.ComposerStatus {
        id: status
        anchors.left: parent.left
        anchors.right: parent.right
        chat: chat
    }

    HarnessTestCase {
        name: "PrivacyBadge"

        function init() {
            chat.messages = [];
            chat.openCodeMode = false;
            chat.piMode = false;
            chat.providerId = "openrouter";
            chat.providerBaseUrl = "https://openrouter.ai/api/v1";
            wait(30);
        }

        function badge() { return findChild(status, "privacyBadge"); }
        function label() { return findChild(status, "privacyLabel").text; }

        function test_online_provider() {
            compare(label(), "OpenRouter · online");
            verify(badge().Accessible.name.indexOf("sent to its servers") > 0);
            screenshot(root, "privacy-badge-online");
        }

        function test_this_computer() {
            chat.providerId = "ollama";
            chat.providerBaseUrl = "http://127.0.0.1:11434/v1";
            wait(30);
            compare(label(), "Ollama · this computer");
            verify(badge().Accessible.name.indexOf("don't leave it") > 0);
        }

        function test_a_lookalike_host_is_online() {
            chat.providerId = "ollama";
            chat.providerBaseUrl = "https://127.0.0.1.example.com/v1";
            wait(30);
            compare(label(), "Ollama · online");
        }

        function test_local_network() {
            chat.providerId = "ollama";
            chat.providerBaseUrl = "http://192.168.1.20:11434/v1";
            wait(30);
            compare(label(), "Ollama · your network");
        }

        function test_agents_dont_claim_local() {
            chat.piMode = true;
            wait(30);
            compare(label(), "Pi agent");
            verify(badge().Accessible.name.indexOf("may be online") > 0);
            chat.piMode = false;
            chat.openCodeMode = true;
            wait(30);
            compare(label(), "OpenCode agent");
        }

        function test_shown_in_a_chat_with_messages_too() {
            chat.messages = [{"role": "user", "content": "hi"}];
            wait(30);
            verify(badge().visible);
            compare(label(), "OpenRouter · online");
        }
    }
}
