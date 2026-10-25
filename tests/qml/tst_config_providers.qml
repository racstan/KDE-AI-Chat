// Settings → Providers with a fake configuration and fake KWallet.
//
// Plasma saves every `cfg_<name>` property of a settings page to the widget's
// config file, so no key field may be one; providers are edited in
// config/ProvidersPanel.qml (tested in tst_providers_panel.qml).
import QtQuick
import QtQuick.Controls as QQC2
import QtTest

// A TestCase is never visible, so the page lives in this Item.
Item {
    id: root
    width: 820
    height: 900

    // Plasma provides these to settings pages; names on the root item are in
    // scope for components created from this file.
    property QtObject plasmoid: QtObject {
        property QtObject configuration: QtObject {
            property string providersJson: JSON.stringify([
                {id: "openrouter", name: "OpenRouter", type: "openai-compat", baseUrl: "https://openrouter.ai/api/v1", model: "openrouter/auto"},
                {id: "box", name: "Home server", type: "openai-compat", baseUrl: "http://127.0.0.1:8080/v1", model: "qwen3"}])
            property string provider: "openrouter"
            property string customProvidersJson: "[]"
            property bool useOpenCode: false
            property bool usePi: false
        }
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    HarnessTestCase {
        id: testCase
        name: "ConfigProviders"

        property var page: null
        property var walletStore: ({"openrouter": "or-key"})

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
            var component = Qt.createComponent(Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/ConfigProviders.qml"));
            verify(component.status === Component.Ready, component.errorString());
            // Plasma passes the saved values as initial properties.
            page = component.createObject(root, {"width": root.width, "height": root.height, "cfg_requestTimeout": 60, "cfg_disableStreaming": false});
            verify(page !== null, "ConfigProviders could not be created");
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
            wait(250);
        }

        function find(item, test) {
            if (test(item))
                return item;
            for (var i = 0; i < item.children.length; i++) {
                var found = find(item.children[i], test);
                if (found) return found;
            }
            return null;
        }

        function test_no_key_is_a_saved_setting() {
            for (var name in page) {
                if (name.indexOf("cfg_") === 0)
                    verify(!/apikey|providersjson/i.test(name), name + " would be saved by the settings dialog");
            }
        }

        function test_providers_panel_lists_saved_providers() {
            var panel = find(page.contentItem || page, function(item) {
                return item.hasOwnProperty("providers") && item.hasOwnProperty("editingIndex");
            });
            verify(panel !== null, "ProvidersPanel not found");
            compare(panel.providers.length, 2);
            compare(panel.defaultProvider, "openrouter");
            wait(300);
            screenshot(page, "config-providers");
        }

        function test_time_limit_can_be_turned_off() {
            var check = find(page.contentItem || page, function(item) {
                return item instanceof QQC2.CheckBox && item.text === "Give up after";
            });
            verify(check !== null, "time limit check box not found");
            verify(check.checked);
            check.toggle();
            check.toggled();
            compare(page.cfg_requestTimeout, 0);
            check.toggle();
            check.toggled();
            compare(page.cfg_requestTimeout, 60);
        }

        function test_streaming_check_box_inverts_disableStreaming() {
            var check = find(page.contentItem || page, function(item) {
                return item instanceof QQC2.CheckBox && item.text === "Show replies while they are written";
            });
            verify(check !== null);
            verify(check.checked);
            check.toggle();
            check.toggled();
            compare(page.cfg_disableStreaming, true);
        }
    }
}
