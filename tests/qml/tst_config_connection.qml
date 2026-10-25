// Settings → Connection (ConfigConnection.qml), loaded the way Plasma loads a
// settings page: saved values passed as cfg_ initial properties, `plasmoid`
// and i18n() from the surrounding context. KWallet is a fake, the helper
// that lists Pi's models is a fake, and nothing here touches the real wallet
// or config.
//
// Plasma saves every `cfg_<name>` property of a settings page to the widget's
// config file, so no key may be one; providers are edited in
// config/ProvidersPanel.qml (tested in tst_providers_panel.qml).
// Screenshots: build/qml-screens/config-connection-<mode>.png.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

// A TestCase is never visible, so the page lives in this Item.
Item {
    id: root
    width: 820
    height: 900

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

    Component {
        id: fakeWalletComponent
        Store.Wallet {
            id: fake
            property var store: ({"openrouter": "or-key"})
            property int calls: 0
            call: function(member, args, onReply, onError) {
                calls++;
                switch (member) {
                case "isEnabled": onReply(true); break;
                case "networkWallet": onReply("kdewallet"); break;
                case "open": onReply(3); break;
                case "close": onReply(0); break;
                case "hasFolder": onReply(true); break;
                case "createFolder": onReply(true); break;
                case "passwordList": onReply(Object.assign({}, store)); break;
                case "writePassword": store[args[2]] = args[3]; onReply(0); break;
                case "removeFolder": onReply(true); break;
                case "removeEntry": delete store[args[2]]; onReply(0); break;
                default: onError("unexpected " + member);
                }
            }
            int32: function(v) { return v; }
            int64: function(v) { return v; }
            bool_: function(v) { return v; }
        }
    }

    HarnessTestCase {
        id: testCase
        name: "ConfigConnection"

        property var page: null
        property var piCommands: []
        // Answers `get_pi_models`; no real command is run.
        property var piReply: ({"providers": [{"id": "ollama", "models": ["llama3.2", "qwen3:8b"]}, {"id": "opencode", "models": ["big-pickle"]}]})
        readonly property QtObject fakeHelper: QtObject {
            function run(command, payload, done) {
                testCase.piCommands.push(command);
                done(JSON.stringify(testCase.piReply), 0, "");
            }
        }

        readonly property var saved: ({
            "cfg_useOpenCode": false, "cfg_usePi": false,
            "cfg_openCodeUrl": "http://127.0.0.1:9/v1", "cfg_openCodeProvider": "anthropic", "cfg_openCodeModel": "claude-sonnet",
            "cfg_piProvider": "ollama", "cfg_piModel": "qwen3:8b",
            "cfg_requestTimeout": 60, "cfg_disableStreaming": false})

        function open(overrides) {
            var component = Qt.createComponent(Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/ConfigConnection.qml"));
            verify(component.status === Component.Ready, component.errorString());
            var wallet = fakeWalletComponent.createObject(root);
            // Plasma passes the saved values as initial properties.
            page = component.createObject(root, Object.assign({"width": root.width, "height": root.height, "wallet": wallet,
                                                               "helperRunner": fakeHelper}, saved, overrides || {}));
            verify(page !== null, "ConfigConnection could not be created");
            return page;
        }

        function init() {
            piReply = {"providers": [{"id": "ollama", "models": ["llama3.2", "qwen3:8b"]}, {"id": "opencode", "models": ["big-pickle"]}]};
        }

        function cleanup() {
            if (page) {
                var wallet = page.wallet;
                page.destroy();
                wallet.destroy();
            }
            page = null;
            // Let the style's animations end before the next page (or exit).
            wait(250);
        }

        function section(name) {
            return findChild(page.contentItem || page, name);
        }

        function find(item, test) {
            if (!item)
                return null;
            if (test(item))
                return item;
            for (var i = 0; i < item.children.length; i++) {
                var found = find(item.children[i], test);
                if (found) return found;
            }
            return null;
        }

        function radio(text) {
            var found = find(page.contentItem || page, function(item) { return item instanceof QQC2.RadioButton && item.text === text; });
            verify(found !== null, text + " not found");
            return found;
        }

        function chooseMode(text) {
            var button = radio(text);
            button.toggle();
            button.toggled();
        }

        // "light" or "dark", from the colour scheme Kirigami really reports.
        readonly property string themeName: root.Kirigami.Theme.backgroundColor.hslLightness < 0.5 ? "dark" : "light"

        function shot(name) {
            wait(300);
            screenshot(page, "config-connection-" + name + "-" + themeName);
        }

        // Which of the four mode sections show.
        function shown() {
            var names = ["providersSection", "requestsSection", "openCodeSection", "piSection"];
            return names.filter(function(name) { return section(name).visible; });
        }

        function stubPi() {
            return section("piSection");
        }

        function test_no_key_is_a_saved_setting() {
            open();
            for (var name in page) {
                if (name.indexOf("cfg_") === 0)
                    verify(!/apikey|token|password|secret|providersjson|sessions|messages/i.test(name), name + " would be saved by the settings dialog");
            }
        }

        function test_the_mode_choice_is_the_first_thing_on_the_page() {
            open();
            var chooser = section("modeChooser");
            verify(chooser.visible);
            verify(chooser.y < section("providersSection").y);
            verify(radio("Directly to a provider").checked);
            verify(!radio("Through OpenCode").checked);
            verify(!radio("Through Pi").checked);
        }

        function test_direct_mode_shows_providers_and_request_options_only() {
            open();
            compare(page.mode, "direct");
            compare(shown().join(), "providersSection,requestsSection");
            var panel = section("providersSection");
            compare(panel.providers.length, 2);
            compare(panel.defaultProvider, "openrouter");
            tryVerify(function() { return page.wallet.status === "ready"; });
            shot("direct");
        }

        function test_opencode_mode_shows_the_server_section_only() {
            open();
            chooseMode("Through OpenCode");
            compare(page.mode, "opencode");
            verify(page.cfg_useOpenCode && !page.cfg_usePi);
            compare(shown().join(), "openCodeSection");
            compare(page.cfg_openCodeUrl, "http://127.0.0.1:9/v1");
            shot("opencode");
        }

        function test_pi_mode_shows_provider_and_model_only() {
            piCommands = [];
            open();
            var pi = stubPi();
            chooseMode("Through Pi");
            compare(page.mode, "pi");
            verify(page.cfg_usePi && !page.cfg_useOpenCode);
            compare(shown().join(), "piSection");
            compare(piCommands[piCommands.length - 1], "get_pi_models");
            compare(page.cfg_piProvider, "ollama");
            compare(page.cfg_piModel, "qwen3:8b");
            pi.choose("opencode", "");
            compare(page.cfg_piModel, "big-pickle");
            shot("pi");
        }

        function test_the_wallet_is_opened_only_for_the_direct_mode() {
            open({"cfg_usePi": true});
            stubPi();
            compare(page.walletRequested, false);
            compare(page.wallet.calls, 0);
            chooseMode("Directly to a provider");
            compare(page.walletRequested, true);
            verify(page.wallet.calls > 0);
            tryVerify(function() { return page.wallet.status === "ready"; });
        }

        function test_switching_modes_keeps_every_value() {
            open({"cfg_requestTimeout": 30, "cfg_disableStreaming": true});
            stubPi();
            chooseMode("Through OpenCode");
            section("openCodeSection").model = "claude-opus";
            chooseMode("Through Pi");
            chooseMode("Directly to a provider");
            chooseMode("Through OpenCode");
            compare(page.cfg_openCodeModel, "claude-opus");
            compare(page.cfg_openCodeUrl, "http://127.0.0.1:9/v1");
            compare(page.cfg_openCodeProvider, "anthropic");
            compare(page.cfg_piProvider, "ollama");
            compare(page.cfg_piModel, "qwen3:8b");
            chooseMode("Directly to a provider");
            compare(page.cfg_requestTimeout, 30);
            compare(page.cfg_disableStreaming, true);
            verify(!page.cfg_useOpenCode && !page.cfg_usePi);
        }

        // What Plasma writes on OK/Apply is the page's cfg_ properties.
        function test_cfg_values_are_what_gets_saved() {
            open();
            stubPi();
            var check = find(page.contentItem || page, function(item) { return item instanceof QQC2.CheckBox && item.text === "Give up after"; });
            verify(check !== null && check.checked);
            check.toggle();
            check.toggled();
            compare(page.cfg_requestTimeout, 0);
            check.toggle();
            check.toggled();
            compare(page.cfg_requestTimeout, 60);
            var streaming = find(page.contentItem || page, function(item) { return item instanceof QQC2.CheckBox && item.text === "Show replies while they are written"; });
            verify(streaming.checked);
            streaming.toggle();
            streaming.toggled();
            compare(page.cfg_disableStreaming, true);

            chooseMode("Through Pi");
            // What the page hands to Plasma, as a settings dialog would read it.
            var snapshot = {};
            for (var name in page)
                if (name.indexOf("cfg_") === 0 && name.slice(-7) !== "Changed")
                    snapshot[name] = page[name];
            compare(Object.keys(snapshot).sort().join(), Object.keys(testCase.saved).sort().join());
            compare(snapshot.cfg_usePi, true);
            compare(snapshot.cfg_useOpenCode, false);
            compare(snapshot.cfg_disableStreaming, true);
            compare(snapshot.cfg_piModel, "qwen3:8b");
        }

        function test_model_fields_use_the_filterable_picker() {
            open({"cfg_usePi": true});
            var pi = stubPi();
            pi.refresh();
            var picker = find(pi, function(item) { return item.hasOwnProperty("matchCount") && item.hasOwnProperty("allowCustom"); });
            verify(picker !== null, "Pi's model field is not a ModelPicker");
            compare(picker.totalCount, 2);
            compare(picker.value, "qwen3:8b");
            picker.pick("llama3.2");
            compare(page.cfg_piModel, "llama3.2");
            chooseMode("Through OpenCode");
            var oc = section("openCodeSection");
            verify(find(oc, function(item) { return item.hasOwnProperty("matchCount") && item.hasOwnProperty("allowCustom"); }) !== null);
        }

        // Pi with an OpenRouter-sized list: the model field's drop-down filtered by "free".
        function test_long_model_list_is_searchable_in_the_page() {
            piReply = ({"providers": []});
            open({"cfg_usePi": true, "cfg_piProvider": "openrouter", "cfg_piModel": "openrouter/auto"});
            var pi = section("piSection");
            var ids = ["openrouter/auto"];
            for (var i = 0; i < 340; i++)
                ids.push(["meta-llama", "qwen", "google", "mistralai"][i % 4] + "/model-" + i + (i % 28 === 0 ? ":free" : ""));
            piReply = {"providers": [{"id": "openrouter", "models": ids}]};
            pi.refresh();
            var picker = find(pi, function(item) { return item.hasOwnProperty("matchCount") && item.hasOwnProperty("allowCustom"); });
            compare(picker.totalCount, 341);
            picker.open();
            tryVerify(function() { return picker.popupOpen; });
            keyClick("f");
            keyClick("r");
            keyClick("e");
            keyClick("e");
            compare(picker.countText, "13 of 341");
            wait(300);
            var path = screensDir + "config-connection-picker-" + themeName + ".png";
            var saved = false;
            verify(root.Window.contentItem.grabToImage(function(result) { saved = result.saveToFile(path); }));
            tryVerify(function() { return saved; }, 5000);
            keyClick(Qt.Key_Return);
            verify(page.cfg_piModel.indexOf(":free") > 0);
        }
    }
}
