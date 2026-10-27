// The first-run setup card (chat/FirstRun.qml) inside the empty chat: shown only
// while no direct-mode provider is usable; a found local server is one click;
// an online service needs a key (saved only to the wallet stand-in, never into
// the configuration), then a model from its list, then an optional test message;
// Skip is respected; never in OpenCode or Pi mode. KWallet, the helper and the
// provider are stand-ins: nothing real is touched.
// Screenshots: build/qml-screens/first-run-<wide|local|narrow|key|ready>.png.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

Item {
    id: root
    width: 520
    height: 600

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    // ── Stand-ins ─────────────────────────────────────────────────────
    property var walletFolder: ({})
    property var requests: []
    QtObject {
        id: cfg
        property string providersJson: ""
        property string provider: "openai"
        property bool firstRunDismissed: false
        property bool useOpenCode: false
        property bool usePi: false
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

    readonly property var found: [
        {id: "ollama-11434", kind: "ollama", name: "Ollama", port: 11434, baseUrl: "http://127.0.0.1:11434/v1",
         models: ["nomic-embed-text:latest", "qwen3:8b"], count: 2, needsKey: false, provider: "ollama"},
        {id: "litellm-4000", kind: "litellm", name: "LiteLLM proxy", port: 4000, baseUrl: "http://127.0.0.1:4000/v1",
         models: [], count: 0, needsKey: true, provider: "litellm"}]
    property var scanReply: ({servers: []})
    QtObject {
        id: fakeHelper
        property var commands: []
        function run(command, payload, done) {
            commands = commands.concat([command]);
            done(JSON.stringify(root.scanReply), 0, "");
        }
    }

    function makeXhr() {
        var x = {headers: {}, readyState: 0, status: 0, responseText: ""};
        x.open = function(method, url) { x.method = method; x.url = url; };
        x.setRequestHeader = function(k, v) { x.headers[k] = v; };
        x.send = function(body) {
            root.requests.push({method: x.method, url: x.url, headers: x.headers});
            Qt.callLater(function() {
                var good = x.headers["Authorization"] === "Bearer good-key";
                x.status = good ? 200 : 401;
                x.responseText = JSON.stringify(good ? (x.method === "GET"
                    ? {data: [{id: "gpt-embed-1"}, {id: "gpt-4o-mini"}, {id: "gpt-4o"}]} : {choices: [{message: {content: "Hi"}}]})
                    : {error: {message: "Incorrect API key"}});
                x.readyState = 4;
                x.onreadystatechange();
            });
        };
        return x;
    }

    FakeChat { id: fakeChat }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "white"
    }

    Component {
        id: viewComponent
        Chat.ChatView {
            anchors.fill: parent
            chat: fakeChat
        }
    }

    HarnessTestCase {
        id: tc
        name: "FirstRun"

        property var view: null

        function initTestCase() {
            var done = false;
            wallet.load(function() { done = true; });
            tryVerify(function() { return done; });
        }

        function init() {
            root.width = 520;
            root.height = 600;
            root.walletFolder = {};
            root.requests = [];
            root.scanReply = {servers: []};
            fakeHelper.commands = [];
            wallet.keys = ({});
            wallet.status = "ready";
            cfg.providersJson = "";
            cfg.provider = "openai";
            cfg.firstRunDismissed = false;
            cfg.useOpenCode = false;
            cfg.usePi = false;
            fakeChat.calls = [];
            fakeChat.messages = [];
            fakeChat.chatInputText = "";
            fakeChat.openCodeMode = false;
            fakeChat.piMode = false;
            fakeChat.wallet = wallet;
            fakeChat.setupCheckHelper = fakeHelper;
            fakeChat.plasmoid = {configuration: cfg};
            backdrop.color = "white";
        }

        function startView() {
            view = viewComponent.createObject(root);
            verify(view !== null);
            findChild(view, "firstRun").xhrFactory = root.makeXhr;
            wait(80);
        }

        function cleanup() {
            if (view)
                view.destroy();
            view = null;
            wait(30);
        }

        function card() { return findChild(view, "firstRunCard"); }
        function shown() { return findChild(view, "firstRun").shown && card().visible; }
        function rows(name) { return findChildren(view, name); }
        function click(item) { mouseClick(item); wait(30); }
        function usable() {
            cfg.providersJson = JSON.stringify([{id: "openrouter", name: "OpenRouter", type: "openai-compat", baseUrl: "https://openrouter.ai/api/v1", model: "openrouter/auto"}]);
            wallet.keys = ({"openrouter": "k"});
        }

        function test_01_fresh_install_shows_the_card_instead_of_the_empty_state() {
            startView();
            verify(shown(), "the card shows");
            verify(!findChild(view, "emptyTitle"), "not the normal empty state");
            compare(rows("firstRunCloud").length, 9);
            compare(rows("firstRunCloud")[0].title, "OpenAI");
            compare(rows("firstRunServer").length, 0);
            var privacy = findChild(view, "firstRunPrivacy").text;
            verify(privacy.indexOf("see the messages you send them") > 0, privacy);
            verify(privacy.indexOf("https://github.com/racstan/KDE-AI-Chat/blob/master/TERMS.md") > 0, privacy);
            screenshot(root, "first-run-wide");
        }

        function test_02_not_shown_when_a_provider_is_usable() {
            usable();
            startView();
            verify(!shown());
            verify(findChild(view, "emptyTitle"), "the normal empty state");
        }

        function test_03_the_placeholder_default_and_a_provider_without_a_key_still_show_it() {
            cfg.providersJson = JSON.stringify([{id: "openai", name: "OpenAI", type: "openai-compat", baseUrl: "https://api.openai.com/v1", model: ""}]);
            startView();
            verify(shown(), "no model yet");
            cfg.providersJson = JSON.stringify([{id: "openai", name: "OpenAI", type: "openai-compat", baseUrl: "https://api.openai.com/v1", model: "gpt-4o"}]);
            wait(30);
            verify(shown(), "a model but no key");
        }

        function test_04_not_while_the_wallet_has_not_been_read() {
            wallet.status = "unknown";
            startView();
            verify(!shown());
            wallet.status = "ready";
            wait(30);
            verify(shown());
        }

        function test_05_agent_modes_never_show_it() {
            cfg.useOpenCode = true;
            startView();
            verify(!shown(), "OpenCode default mode");
            cfg.useOpenCode = false;
            wait(30);
            verify(shown());
            fakeChat.piMode = true;
            wait(30);
            verify(!shown(), "a Pi chat");
            fakeChat.piMode = false;
            cfg.usePi = true;
            wait(30);
            verify(!shown(), "Pi default mode");
        }

        function test_06_found_servers_are_listed_and_a_click_sets_one_up() {
            root.scanReply = {servers: root.found};
            startView();
            compare(fakeHelper.commands, ["local_servers_scan"]);
            tryCompare(rows("firstRunServer"), "length", 2);
            var ollama = rows("firstRunServer")[0];
            compare(ollama.title, "Ollama");
            verify(ollama.detail.indexOf("stays on this computer") > 0, ollama.detail);
            screenshot(root, "first-run-local");
            click(ollama);
            var list = JSON.parse(cfg.providersJson);
            compare(list.length, 1);
            compare(list[0].id, "ollama");
            compare(list[0].model, "qwen3:8b", "not the embedding model");
            compare(list[0].baseUrl, "http://127.0.0.1:11434/v1");
            compare(cfg.provider, "ollama");
            compare(Object.keys(root.walletFolder).length, 0, "no key for a local server");
            verify(findChild(view, "firstRunReady"), "the last screen");
            verify(shown(), "stays up until the user is done");
            click(findChild(view, "firstRunFinish"));
            verify(!shown());
            verify(findChild(view, "emptyTitle"), "the normal empty state");
        }

        function test_07_a_server_that_asks_for_a_key_goes_to_the_key_step() {
            root.scanReply = {servers: root.found};
            startView();
            tryCompare(rows("firstRunServer"), "length", 2);
            click(rows("firstRunServer")[1]);
            verify(findChild(view, "firstRunKey"), "asks for the key");
            verify(!findChild(view, "getKeyLink").visible, "no key page for a local program");
            compare(cfg.providersJson, "", "nothing saved yet");
        }

        function test_08_an_online_service_key_model_and_test_message() {
            startView();
            click(rows("firstRunCloud")[0]);
            var link = findChild(view, "getKeyLink");
            verify(link.visible);
            verify(link.text.indexOf("https://platform.openai.com/api-keys") > 0, link.text);
            var field = findChild(view, "firstRunKey");
            field.text = "wrong-key";
            click(findChild(view, "firstRunContinue"));
            tryVerify(function() { return findChild(view, "firstRunStatus").visible; });
            verify(findChild(view, "firstRunStatus").text.indexOf("did not accept this key") > 0, findChild(view, "firstRunStatus").text);
            verify(!findChild(view, "firstRunModel").visible);
            compare(cfg.providersJson, "");
            compare(Object.keys(root.walletFolder).length, 0);

            field.text = "good-key";
            click(findChild(view, "firstRunContinue"));
            tryVerify(function() { return findChild(view, "firstRunModel").visible; });
            var box = findChild(view, "firstRunModel");
            compare(box.count, 2, "embedding models are not offered");
            compare(box.currentText, "gpt-4o-mini");
            screenshot(root, "first-run-key");
            click(findChild(view, "firstRunContinue"));   // Save and continue
            tryVerify(function() { return !!findChild(view, "firstRunReady"); });

            compare(root.walletFolder["openai"], "good-key", JSON.stringify(root.walletFolder));
            var json = cfg.providersJson;
            compare(JSON.parse(json)[0].id, "openai");
            compare(JSON.parse(json)[0].model, "gpt-4o-mini");
            verify(json.indexOf("good-key") < 0, "no key in the provider list");
            compare(cfg.provider, "openai");
            verify(JSON.stringify(cfg).indexOf("good-key") < 0);
            verify(cfg.walletKeysRevision > 0, "the widget is told to reload keys");
            screenshot(root, "first-run-ready");

            click(findChild(view, "firstRunSendTest"));
            compare(fakeChat.calls.filter(function(c) { return c.name === "send"; }).length, 1, "the normal send path");
            fakeChat.messages = [{role: "user", content: "Hello", time: "10:00"}];
            wait(30);
            verify(!shown());
            fakeChat.messages = [];
            wait(30);
            verify(!shown(), "gone for good once a provider works");
            verify(findChild(view, "emptyTitle"));
        }

        function test_09_skip_opens_settings_and_is_respected() {
            startView();
            findChild(view, "firstRunSkip").linkActivated("skip");
            wait(30);
            compare(cfg.firstRunDismissed, true);
            verify(fakeChat.calls.some(function(c) { return c.name === "openSettings"; }));
            verify(!shown());
            verify(findChild(view, "emptyTitle"));
            cleanup();
            startView();
            verify(!shown(), "still away in a new view");
        }

        function test_10_back_returns_to_the_list_and_forgets_the_key() {
            startView();
            click(rows("firstRunCloud")[1]);
            findChild(view, "firstRunKey").text = "abc";
            click(findChild(view, "firstRunBack"));
            verify(rows("firstRunCloud").length === 9 && rows("firstRunCloud")[0].visible);
            click(rows("firstRunCloud")[1]);
            compare(findChild(view, "firstRunKey").text, "");
        }

        function test_11_narrow_popup() {
            root.width = 380;
            root.height = 520;
            root.scanReply = {servers: root.found};
            startView();
            tryCompare(rows("firstRunServer"), "length", 2);
            var c = card();
            verify(c.x >= 0 && c.x + c.width <= root.width, "inside the popup: " + c.x + " + " + c.width);
            var skip = findChild(view, "firstRunSkip");
            verify(skip.width <= c.width);
            screenshot(root, "first-run-narrow");
            click(rows("firstRunCloud")[0]);
            screenshot(root, "first-run-narrow-key");
        }
    }
}
