// The default provider is listed first in Settings → Providers and in the
// per-chat provider picker, and changing the default re-sorts at once. The
// saved order of providersJson is not touched.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/config" as Config
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 640
    height: 480

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    readonly property string saved: JSON.stringify([
        {id: "openrouter", name: "OpenRouter", type: "openai-compat", baseUrl: "https://openrouter.ai/api/v1", model: "m"},
        {id: "nvidia", name: "NVIDIA NIM", type: "openai-compat", baseUrl: "https://nim.example/v1", model: "m"},
        {id: "groq", name: "Groq", type: "openai-compat", baseUrl: "https://api.groq.com/openai/v1", model: "m"}])

    QtObject {
        id: config
        property string providersJson: root.saved
        property string provider: "nvidia"
        property int walletKeysRevision: 0
    }

    Config.ProvidersPanel {
        id: panel
        anchors.fill: parent
        anchors.margins: 12
        configuration: config
    }

    QtObject {
        id: chat
        property var plasmoid: ({configuration: {provider: "nvidia", providersJson: root.saved}})
        property var walletApiKeys: ({"openrouter": "k", "nvidia": "k", "groq": "k"})
        property var sessions: [{value: "a", text: "Chat"}]
        property string currentSessionTitle: "Chat"
        function getSessionProperty(id, key, fallback) { return fallback; }
    }

    Chat.ChatSettingsDraft {
        id: draft
        rootRef: chat
        active: true
    }

    HarnessTestCase {
        name: "DefaultProviderFirst"

        function rowIds() {
            var list = findChild(panel, "providerList");
            var ids = [];
            for (var i = 0; i < list.count; i++)
                ids.push(list.itemAt(i).entry.id);
            return ids;
        }

        function pickerValues() {
            return draft.providerEntries().map(function(e) { return e.value; });
        }

        function test_1_the_panel_lists_the_default_first() {
            compare(rowIds(), ["nvidia", "openrouter", "groq"]);
            compare(panel.providers.map(function(p) { return p.id; }), ["openrouter", "nvidia", "groq"]);
            wait(100);
            screenshot(root, "providers-default-first");
        }

        function test_2_changing_the_default_re_sorts() {
            panel.setDefault("groq");
            tryCompare(panel, "defaultProvider", "groq");
            compare(rowIds(), ["groq", "openrouter", "nvidia"]);
            verify(config.providersJson === root.saved, "saved order untouched");
            panel.setDefault("nvidia");
        }

        function test_3_the_chat_picker_lists_the_default_first() {
            var entries = draft.providerEntries();
            compare(entries[0].value, "");
            compare(entries[0].text, "Default · NVIDIA NIM");
            compare(pickerValues(), ["", "nvidia", "openrouter", "groq"]);
            chat.plasmoid.configuration.provider = "groq";
            compare(pickerValues(), ["", "groq", "openrouter", "nvidia"]);
            compare(draft.providerEntries()[0].text, "Default · Groq");
        }
    }
}
