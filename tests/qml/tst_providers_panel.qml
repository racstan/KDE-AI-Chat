// config/ProvidersPanel.qml with a fake configuration, fake KWallet and a fake
// provider server (no network): key checks before saving, live model lists,
// dead models.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/config" as Config
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store
import "../../org.kde.plasma.kdeaichat/contents/ui/ProviderVariants.js" as ProviderVariants

Item {
    id: root
    width: 640
    height: 640

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    property var walletFolder: ({})

    // ── The fake provider: NIM-like (the model list is open to anyone; the chat
    // request checks the key, then the model). ───────────────────────────
    property var requests: []
    property var pending: []
    property bool hold: false
    property var chatModelIds: ["acme/chat-big", "acme/chat-small", "acme/embed-text-1", "acme/guard-safety-8b", "acme/rerank-1", "dead/gone-model"]
    property var handler: function(req) {
        if (req.method === "GET")
            return {status: 200, body: {object: "list", data: root.chatModelIds.map(function(id) { return {id: id, object: "model"}; })}};
        if (req.headers["Authorization"] !== "Bearer good")
            return {status: 403, body: {status: 403, title: "Forbidden", detail: "Authorization failed"}};
        if (req.body.model === "dead/gone-model")
            return {status: 410, body: {title: "Gone", detail: "The model has reached its end of life and is no longer available."}};
        return {status: 200, body: {choices: [{message: {content: "Hi"}}]}};
    }
    function makeXhr() {
        var x = {headers: {}, readyState: 0, status: 0, responseText: ""};
        x.open = function(method, url) { x.method = method; x.url = url; };
        x.setRequestHeader = function(k, v) { x.headers[k] = v; };
        x.send = function(body) {
            var req = {method: x.method, url: x.url, headers: x.headers, body: body ? JSON.parse(body) : null};
            root.requests.push(req);
            var finish = function() {
                var r = root.handler(req);
                if (r.error === "network") { x.onerror(); return; }
                x.status = r.status;
                x.responseText = JSON.stringify(r.body);
                x.readyState = 4;
                x.onreadystatechange();
            };
            if (root.hold) root.pending.push(finish); else Qt.callLater(finish);
        };
        return x;
    }
    function release() {
        var list = root.pending;
        root.pending = [];
        list.forEach(function(f) { f(); });
    }
    function count(method) {
        return root.requests.filter(function(r) { return r.method === method; }).length;
    }

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
        xhrFactory: root.makeXhr
    }

    HarnessTestCase {
        id: tc
        name: "ProvidersPanel"

        function indexOfProvider(id) {
            return panel.providers.map(function(p) { return p.id; }).indexOf(id);
        }

        function init() {
            root.requests = [];
            root.pending = [];
            root.hold = false;
        }

        function initTestCase() {
            walletFolder = {"openrouter": "or-key", "nvidia": "nv-key"};
            var done = false;
            wallet.load(function() { done = true; });
            tryVerify(function() { return done; });
            panel.load();
        }

        function test_01_shows_providers_the_migration_will_create() {
            var ids = panel.providers.map(function(p) { return p.id; }).sort();
            compare(ids, ["custom_1", "nvidia", "openrouter"]);
            screenshot(root, "providers-panel-list");
        }

        function test_02_add_from_preset_save_with_a_good_key() {
            panel.addFromPreset("groq");
            compare(panel.editingIndex, panel.providers.length - 1);
            compare(panel.draft.baseUrl, "https://api.groq.com/openai/v1");
            panel.onFieldEdited("model", "acme/chat-small");
            panel.onFieldEdited("key", " good ");
            root.hold = true;
            panel.saveEdit(false);
            // While the provider is being asked: a busy indicator, Save disabled, nothing written.
            tryVerify(function() { return panel.providerChecker.checking; });
            verify(!tc.findChild(panel, "saveButton").enabled, "Save is disabled while checking");
            verify(tc.findChild(panel, "busy").running);
            compare(walletFolder["groq"], undefined);
            wait(150);   // let the layout settle
            screenshot(root, "providers-editor-checking");
            // The models request goes first, then the chat request.
            tryVerify(function() { return root.pending.length > 0; });
            root.release();
            tryVerify(function() { return root.pending.length > 0; });
            root.release();
            tryVerify(function() { return panel.editingIndex === -1; });
            tryVerify(function() { return walletFolder["groq"] === "good"; });
            var saved = JSON.parse(config.providersJson);
            var groq = saved.filter(function(p) { return p.id === "groq"; })[0];
            compare(groq.model, "acme/chat-small");
            verify(config.providersJson.indexOf("good") === -1, "the key must not be stored in the config");
            tryVerify(function() { return config.walletKeysRevision === 1; });
            var chat = root.requests.filter(function(r) { return r.method === "POST"; })[0];
            compare(chat.body.max_tokens, 1);
            compare(chat.url, "https://api.groq.com/openai/v1/chat/completions");
        }

        function test_03_cancel_new_provider_discards_it() {
            var before = panel.providers.length;
            panel.addFromPreset("openai");
            panel.cancelEdit();
            compare(panel.providers.length, before);
        }

        function test_04_invalid_url_is_refused() {
            panel.addFromPreset("custom");
            panel.onFieldEdited("baseUrl", "ftp://nope");
            panel.saveEdit(false);
            verify(panel.editingIndex >= 0);
            verify(panel.status.indexOf("http") >= 0);
            compare(root.requests.length, 0);
            panel.cancelEdit();
        }

        function test_04b_plain_http_to_another_computer_with_a_key_is_warned_about() {
            panel.addFromPreset("custom");
            var warning = tc.findChild(panel, "plainHttpWarning");
            verify(warning);
            panel.onFieldEdited("baseUrl", "http://192.168.1.5:8000/v1");
            panel.onFieldEdited("key", "");
            verify(!warning.visible, "no key, nothing to protect");
            panel.onFieldEdited("key", "k");
            verify(warning.visible);
            panel.onFieldEdited("baseUrl", "https://192.168.1.5:8000/v1");
            verify(!warning.visible);
            panel.onFieldEdited("baseUrl", "http://localhost:8000/v1");
            verify(!warning.visible, "local http stays fine");
            panel.cancelEdit();
        }

        function test_05_saving_without_changes_sends_nothing_and_keeps_the_revision() {
            panel.startEdit(indexOfProvider("nvidia"));
            tryVerify(function() { return !panel.providerChecker.listing && !panel.providerChecker.checking; });
            var before = config.walletKeysRevision;
            var requestsBefore = root.requests.length;
            panel.saveEdit(false);
            wait(50);
            compare(root.requests.length, requestsBefore, "no check when nothing changed");
            compare(config.walletKeysRevision, before);
        }

        function test_06_a_rejected_key_is_not_saved() {
            panel.startEdit(indexOfProvider("nvidia"));
            tryVerify(function() { return !panel.providerChecker.listing && !panel.providerChecker.checking; });
            var before = config.walletKeysRevision;
            panel.onFieldEdited("key", "nvapi-wrong");
            panel.saveEdit(false);
            tryVerify(function() { return panel.status.indexOf("rejected this key (403)") >= 0; });
            verify(panel.status.indexOf("Check you copied the whole key") >= 0);
            verify(panel.editingIndex >= 0, "the editor stays open");
            compare(walletFolder["nvidia"], "nv-key", "the old key is untouched");
            compare(config.walletKeysRevision, before);
            compare(panel.overrideKind, "", "a rejected key cannot be saved anyway");
            compare(tc.findChild(panel, "overrideButton").visible, false);
            wait(150);   // let the layout settle
            screenshot(root, "providers-editor-rejected-key");
            panel.cancelEdit();
        }

        function test_07_a_good_key_replaces_the_old_one() {
            panel.startEdit(indexOfProvider("nvidia"));
            tryVerify(function() { return !panel.providerChecker.listing && !panel.providerChecker.checking; });
            var before = config.walletKeysRevision;
            panel.onFieldEdited("key", "good");
            panel.onFieldEdited("model", "acme/chat-big");
            panel.saveEdit(false);
            tryVerify(function() { return panel.editingIndex === -1; });
            tryVerify(function() { return walletFolder["nvidia"] === "good"; });
            tryVerify(function() { return config.walletKeysRevision === before + 1; });
        }

        function test_08_network_error_offers_save_anyway() {
            panel.startEdit(indexOfProvider("openrouter"));
            tryVerify(function() { return !panel.providerChecker.listing && !panel.providerChecker.checking; });
            var before = config.walletKeysRevision;
            root.handler = function() { return {error: "network"}; };
            panel.onFieldEdited("key", "or-new-key");
            panel.saveEdit(false);
            tryVerify(function() { return panel.overrideKind === "unverified"; });
            verify(panel.status.indexOf("could not be reached") >= 0);
            verify(panel.editingIndex >= 0);
            compare(walletFolder["openrouter"], "or-key", "nothing is written until the user confirms");
            var button = tc.findChild(panel, "overrideButton");
            verify(button.visible);
            compare(button.text, "Save anyway");
            tryVerify(function() { return button.enabled; }, 5000, "the button is enabled once the check is over");
            mouseClick(button);
            tryVerify(function() { return panel.editingIndex === -1; });
            tryVerify(function() { return walletFolder["openrouter"] === "or-new-key"; });
            compare(config.walletKeysRevision, before + 1);
            root.handler = tc.defaultHandler;
        }

        property var defaultHandler: null

        function test_09_a_dead_model_is_flagged_and_needs_confirmation() {
            root.handler = tc.defaultHandler;
            panel.startEdit(indexOfProvider("openrouter"));
            tryVerify(function() { return !panel.providerChecker.listing && !panel.providerChecker.checking; });
            panel.onFieldEdited("key", "good");
            panel.onFieldEdited("model", "dead/gone-model");
            panel.saveEdit(false);
            tryVerify(function() { return panel.overrideKind === "model"; });
            verify(panel.status.indexOf("The key works") >= 0, panel.status);
            verify(panel.status.indexOf("end of life") >= 0, panel.status);
            verify(panel.editingIndex >= 0);
            compare(walletFolder["openrouter"], "or-new-key");
            compare(tc.findChild(panel, "overrideButton").text, "Use this model anyway");
            verify(panel.providerChecker.deadReason("openrouter", "dead/gone-model") !== "");
            // The picker marks it, and the editor says why.
            var entry = panel.modelCandidates.filter(function(m) { return m.id === "dead/gone-model"; })[0];
            compare(entry.name, "(unavailable)");
            verify(tc.findChild(panel, "modelWarning").visible);
            wait(150);   // let the layout settle
            screenshot(root, "providers-editor-dead-model");
            // The button is off while a check runs (ProviderEditor: enabled: !checking): click it once it is on.
            tryVerify(function() { return tc.findChild(panel, "overrideButton").enabled; }, 5000, "the override button is enabled");
            mouseClick(tc.findChild(panel, "overrideButton"));
            tryVerify(function() { return panel.editingIndex === -1; });
            tryVerify(function() { return walletFolder["openrouter"] === "good"; });
            // The provider row warns too.
            var rows = [];
            for (var i = 0; i < panel.children.length; i++)
                tc.findChildren(panel.children[i], "detailLabel", rows);
            var texts = rows.map(function(l) { return l.text; }).join("\n");
            verify(texts.indexOf("model unavailable") >= 0, texts);
        }

        function test_10_the_editor_lists_models_by_itself_and_hides_non_chat_ones() {
            root.handler = tc.defaultHandler;
            panel.providerChecker.cache = ({});
            var gets = root.count("GET");
            panel.startEdit(indexOfProvider("nvidia"));
            tryVerify(function() { return panel.listAll.length > 0; });
            compare(root.count("GET"), gets + 1, "fetched without pressing a button");
            compare(panel.listAll.length, 6);
            verify(panel.listChat.indexOf("acme/chat-big") >= 0);
            compare(panel.listChat.indexOf("acme/embed-text-1"), -1);
            compare(panel.listChat.indexOf("acme/guard-safety-8b"), -1);
            compare(panel.listChat.indexOf("acme/rerank-1"), -1);
            var ids = panel.modelCandidates.map(function(m) { return m.id; });
            verify(ids.indexOf("acme/embed-text-1") < 0);
            // Nothing is hidden for good.
            var check = tc.findChild(panel, "showAllCheck");
            verify(check.visible);
            mouseClick(check);
            ids = panel.modelCandidates.map(function(m) { return m.id; });
            verify(ids.indexOf("acme/embed-text-1") >= 0);
            verify(ids.indexOf("acme/guard-safety-8b") >= 0);
            panel.cancelEdit();
        }

        function test_11_lists_are_cached_for_the_session_until_refreshed() {
            tryVerify(function() { return !panel.providerChecker.listing; });
            var gets = root.count("GET");
            panel.startEdit(indexOfProvider("nvidia"));
            compare(root.count("GET"), gets, "second open uses the cached list");
            verify(panel.listChat.length > 0);
            var refresh = tc.findChild(panel, "refreshButton");
            tryVerify(function() { return refresh.enabled; }, 5000, "Refresh is enabled once the checks are over");
            mouseClick(refresh);
            tryVerify(function() { return root.count("GET") === gets + 1; });
            panel.cancelEdit();
        }

        function test_12_local_provider_without_a_key_lists_models_and_saves_unchecked() {
            panel.startEdit(indexOfProvider("custom_1"));
            tryVerify(function() { return panel.listAll.length > 0; });
            panel.onFieldEdited("model", "acme/chat-small");
            var posts = root.count("POST");
            panel.saveEdit(false);
            tryVerify(function() { return panel.editingIndex === -1; });
            compare(root.count("POST"), posts, "no chat request to a local server");
        }

        // --- Variants: a picker next to the model only when the provider reports some for it ---

        function variantHandler(req) {
            if (req.method === "GET")
                return {status: 200, body: {object: "list", data: [
                    {id: "acme/chat-big", reasoning: {supported_efforts: ["low", "high"]}},
                    {id: "acme/chat-small", reasoning: {mandatory: false}},
                    {id: "acme/plain"}]}};
            return tc.defaultHandler(req);
        }

        function test_14_a_model_with_variants_gets_a_picker_and_the_choice_is_saved() {
            root.handler = tc.variantHandler;
            panel.providerChecker.cache = ({});
            ProviderVariants.clear();
            panel.startEdit(indexOfProvider("nvidia"));
            tryVerify(function() { return panel.listAll.length === 3; });
            var picker = tc.findChild(panel, "variantPicker");
            verify(picker !== null);
            panel.onFieldEdited("model", "meta/llama");
            verify(!picker.visible, "a model that is not in the list has no variants");
            panel.onFieldEdited("model", "acme/chat-big");
            tryVerify(function() { return picker.visible; });
            compare(picker.count, 3, "Default, low, high: as the provider reports them");
            compare(picker.currentText, "Default");
            picker.currentIndex = 2;
            picker.activated(2);
            compare(panel.draft.variant, "high");
            screenshot(root, "providers-panel-variant");
            panel.saveEdit(true);
            tryVerify(function() { return panel.editingIndex === -1; });
            var saved = JSON.parse(config.providersJson).filter(function(p) { return p.id === "nvidia"; })[0];
            compare(saved.model, "acme/chat-big");
            compare(saved.variant, "high", "only the id is stored");
            compare(Object.keys(saved).sort().join(), "baseUrl,id,model,name,type,variant");
            // Opening it again shows the stored choice.
            panel.startEdit(indexOfProvider("nvidia"));
            tryVerify(function() { return picker.visible && picker.currentText === "High"; });
            panel.cancelEdit();
        }

        function test_15_a_model_without_variants_has_no_picker_and_clears_the_variant() {
            root.handler = tc.variantHandler;
            panel.providerChecker.cache = ({});
            ProviderVariants.clear();
            panel.startEdit(indexOfProvider("nvidia"));
            tryVerify(function() { return panel.listAll.length === 3; });
            var picker = tc.findChild(panel, "variantPicker");
            tryVerify(function() { return picker.visible; });
            panel.onFieldEdited("model", "acme/plain");
            verify(!picker.visible, "acme/plain reports nothing");
            compare(panel.draft.variant, "", "another model starts without a variant");
            panel.onFieldEdited("model", "acme/chat-small");
            wait(50);
            verify(!picker.visible, "reasoning without levels is not a variant");
            panel.saveEdit(true);
            tryVerify(function() { return panel.editingIndex === -1; });
            var saved = JSON.parse(config.providersJson).filter(function(p) { return p.id === "nvidia"; })[0];
            verify(!("variant" in saved), "nothing stored for a model without variants");
            root.handler = tc.defaultHandler;
        }

        function test_13_default_and_remove() {
            panel.setDefault("groq");
            compare(config.provider, "groq");
            var index = indexOfProvider("groq");
            panel.removeAt(index);
            tryVerify(function() { return walletFolder["groq"] === undefined; });
            verify(config.provider !== "groq");
            verify(config.providersJson.indexOf("\"groq\"") === -1);
        }
    }

    Component.onCompleted: tc.defaultHandler = root.handler
}
