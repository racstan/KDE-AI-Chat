// Settings → General with a fake configuration and fake KWallet.
//
// Plasma saves every `cfg_<name>` property of a settings page to the widget's
// config file, so no key field may be one; providers are edited in
// config/ProvidersPanel.qml (tested in tst_providers_panel.qml).
import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "ConfigGeneral"
    when: windowShown
    width: 820
    height: 900

    property var page: null
    property var walletStore: ({"openrouter": "or-key"})

    // Plasma provides these to settings pages; names on the TestCase are in
    // scope for components it creates.
    property QtObject plasmoid: QtObject {
        property QtObject configuration: QtObject {
            property string providersJson: JSON.stringify([
                {id: "openrouter", name: "OpenRouter", type: "openai-compat", baseUrl: "https://openrouter.ai/api/v1", model: "openrouter/auto"},
                {id: "box", name: "Home server", type: "openai-compat", baseUrl: "http://127.0.0.1:8080/v1", model: "qwen3"}])
            property string provider: "openrouter"
            property string customProvidersJson: "[]"
            property int appearanceMode: 0
            property bool useOpenCode: false
            property bool usePi: false
            property bool playNotificationSound: false
            property int requestTimeout: 60
            property string openCodeUrl: "http://127.0.0.1:4096/v1"
            property string openCodeModel: ""
            property string openCodeProvider: ""
            property string openCodeStartCommand: ""
            property string openCodeStopCommand: ""
            property string piProvider: ""
            property string piModel: ""
        }
    }
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
        page = component.createObject(testCase, {"width": 820, "height": 900});
        verify(page !== null, "ConfigGeneral could not be created");
        page.wallet.call = fakeCall;
        page.wallet.int32 = function(v) { return v; };
        page.wallet.int64 = function(v) { return v; };
        page.wallet.bool_ = function(v) { return v; };
        var done = false;
        page.wallet.load(function() { done = true; });
        tryVerify(function() { return done; });
    }

    function cleanupTestCase() {
        if (page)
            page.destroy();
    }

    function test_no_key_is_a_saved_setting() {
        for (var name in page) {
            if (name.indexOf("cfg_") === 0)
                verify(!/apikey|providersjson/i.test(name), name + " would be saved by the settings dialog");
        }
    }

    function findPanel(item) {
        if (item.hasOwnProperty("providers") && item.hasOwnProperty("editingIndex"))
            return item;
        for (var i = 0; i < item.children.length; i++) {
            var found = findPanel(item.children[i]);
            if (found) return found;
        }
        return null;
    }

    function test_providers_panel_lists_saved_providers() {
        var panel = findPanel(page.contentItem || page);
        verify(panel !== null, "ProvidersPanel not found");
        compare(panel.providers.length, 2);
        compare(panel.defaultProvider, "openrouter");
    }
}
