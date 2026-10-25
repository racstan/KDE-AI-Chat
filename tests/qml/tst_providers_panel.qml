// config/ProvidersPanel.qml with a fake configuration and fake KWallet.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/config" as Config
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

Item {
    id: root
    width: 640
    height: 560

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    property var walletFolder: ({})

    QtObject {
        id: config
        property string providersJson: ""
        property string provider: "nvidia"
        property string customProvidersJson: JSON.stringify([{id: "custom_1", name: "My server", type: "openai-compat", baseUrl: "http://127.0.0.1:8080/v1", model: "local-model"}])
        property string nvidiaModel: "meta/llama"
        property string mistralModel: ""
        property string openRouterModel: ""
        property int walletKeysRevision: 0
    }

    Store.Wallet {
        id: wallet
        int32: function(v) { return v; }
        int64: function(v) { return v; }
        bool_: function(v) { return v; }
        call: function(member, args, onReply, onError) {
            switch (member) {
            case "isEnabled": onReply(true); break;
            case "networkWallet": onReply("kdewallet"); break;
            case "open": onReply(1); break;
            case "close": onReply(0); break;
            case "hasFolder": onReply(true); break;
            case "createFolder": onReply(true); break;
            case "passwordList": onReply(Object.assign({}, root.walletFolder)); break;
            case "writePassword": root.walletFolder[args[2]] = args[3]; onReply(0); break;
            case "removeEntry": delete root.walletFolder[args[2]]; onReply(0); break;
            default: onError("unexpected " + member);
            }
        }
    }

    Config.ProvidersPanel {
        id: panel
        anchors.fill: parent
        anchors.margins: 12
        configuration: config
        wallet: wallet
    }

    HarnessTestCase {
        name: "ProvidersPanel"

        function initTestCase() {
            walletFolder = {"openrouter": "or-key", "nvidia": "nv-key"};
            var done = false;
            wallet.load(function() { done = true; });
            tryVerify(function() { return done; });
            panel.load();
        }

        function test_1_shows_providers_the_migration_will_create() {
            var ids = panel.providers.map(function(p) { return p.id; }).sort();
            compare(ids, ["custom_1", "nvidia", "openrouter"]);
            screenshot(root, "providers-panel-list");
        }

        function test_2_add_from_preset_save_with_key() {
            panel.addFromPreset("groq");
            compare(panel.editingIndex, panel.providers.length - 1);
            compare(panel.draft.baseUrl, "https://api.groq.com/openai/v1");
            panel.draft.model = "llama-3.3-70b";
            panel.draftKey = " gsk-test ";
            screenshot(root, "providers-panel-editor");
            panel.saveEdit();
            compare(panel.editingIndex, -1);
            tryVerify(function() { return walletFolder["groq"] === "gsk-test"; });
            var saved = JSON.parse(config.providersJson);
            var groq = saved.filter(function(p) { return p.id === "groq"; })[0];
            compare(groq.model, "llama-3.3-70b");
            verify(config.providersJson.indexOf("gsk-test") === -1, "the key must not be stored in the config");
            // The running widget re-reads the wallet when this changes.
            tryVerify(function() { return config.walletKeysRevision === 1; });
        }

        function test_3_cancel_new_provider_discards_it() {
            var before = panel.providers.length;
            panel.addFromPreset("openai");
            panel.cancelEdit();
            compare(panel.providers.length, before);
        }

        function test_4_invalid_url_is_refused() {
            panel.addFromPreset("custom");
            panel.draft.baseUrl = "ftp://nope";
            panel.saveEdit();
            verify(panel.editingIndex >= 0);
            verify(panel.status.indexOf("http") >= 0);
            panel.cancelEdit();
        }

        function test_4b_saving_without_a_key_change_keeps_the_revision() {
            var index = panel.providers.map(function(p) { return p.id; }).indexOf("nvidia");
            var before = config.walletKeysRevision;
            panel.startEdit(index);
            panel.saveEdit();
            wait(50);
            compare(config.walletKeysRevision, before);
        }

        function test_5_default_and_remove() {
            panel.setDefault("groq");
            compare(config.provider, "groq");
            var index = panel.providers.map(function(p) { return p.id; }).indexOf("groq");
            panel.removeAt(index);
            tryVerify(function() { return walletFolder["groq"] === undefined; });
            tryVerify(function() { return config.walletKeysRevision === 2; });
            verify(config.provider !== "groq");
            verify(config.providersJson.indexOf("\"groq\"") === -1);
        }
    }
}
