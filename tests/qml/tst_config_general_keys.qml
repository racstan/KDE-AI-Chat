// The provider settings page keeps API keys in KWallet only.
//
// Plasma saves every `cfg_<name>` property of a settings page to the widget's
// config file, so no key field may be one. Uses an in-memory fake KWallet.
import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "ConfigGeneralKeys"
    when: windowShown
    width: 800
    height: 600

    property var page: null
    property var walletStore: ({})

    // Plasma provides these to settings pages; names on the TestCase are in
    // scope for components it creates.
    property var plasmoid: ({ configuration: { walletKeysRevision: 0, customProvidersJson: "[]", provider: "openai" } })
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    function fakeCall(member, args, onReply, onError) {
        switch (member) {
        case "isEnabled": onReply(true); break;
        case "networkWallet": onReply("kdewallet"); break;
        case "open": onReply(3); break;
        case "close": onReply(0); break;
        case "hasFolder": onReply(true); break;
        case "createFolder": onReply(true); break;
        case "passwordList": onReply(Object.assign({}, walletStore)); break;
        case "writePassword": walletStore[args[2]] = args[3]; onReply(0); break;
        case "removeFolder": onReply(true); break;
        case "removeEntry": delete walletStore[args[2]]; onReply(0); break;
        default: onError("unexpected " + member);
        }
    }

    function initTestCase() {
        var component = Qt.createComponent(Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/ConfigGeneral.qml"));
        verify(component.status === Component.Ready, component.errorString());
        page = component.createObject(testCase);
        verify(page !== null, "ConfigGeneral could not be created");
        page.wallet.call = fakeCall;
        page.wallet.int32 = function(v) { return v; };
        page.wallet.int64 = function(v) { return v; };
        page.wallet.bool_ = function(v) { return v; };
    }

    function cleanupTestCase() {
        if (page)
            page.destroy();
    }

    function test_no_key_is_a_saved_setting() {
        for (var name in page) {
            if (name.indexOf("cfg_") === 0)
                verify(!/apikey/i.test(name), name + " would be saved to the config file in plaintext");
        }
    }

    function test_load_fills_fields_from_wallet() {
        walletStore = {
            "mistral": "m-secret",
            "custom_abc": "c-secret"
        };
        page.cfg_customProvidersJson = JSON.stringify([{"id": "custom_abc", "name": "Mine", "type": "openai-compat", "baseUrl": "https://example.com/v1"}]);
        page.kwalletLoadAll();
        tryVerify(function() { return !page.keyringBusy; });
        compare(page.apiKeyForTarget("mistral"), "m-secret");
        compare(page.customProviderKeys["custom_abc"], "c-secret");
    }

    function test_save_and_clear_go_to_wallet() {
        walletStore = {};
        page.saveKey("deepseek", " d-secret ");
        tryVerify(function() { return !page.keyringBusy; });
        compare(walletStore["deepseek"], "d-secret");

        page.saveKey("deepseek", "");
        tryVerify(function() { return !page.keyringBusy; });
        verify(!walletStore.hasOwnProperty("deepseek"));
    }
}
