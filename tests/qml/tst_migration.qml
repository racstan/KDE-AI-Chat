// store/Migration.qml: plaintext keys -> KWallet, config chats -> files.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

TestCase {
    id: testCase
    name: "Migration"

    readonly property string root: decodeURIComponent(String(Qt.resolvedUrl("../../build/test-migration/")).replace(/^file:\/\//, ""))
    property var helperCalls: []
    property var keyfile: ({})
    property bool walletWritesFail: false
    property var walletFolder: ({})

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    function fakeKWallet(member, args, onReply, onError) {
        switch (member) {
        case "isEnabled": onReply(true); break;
        case "networkWallet": onReply("kdewallet"); break;
        case "open": onReply(1); break;
        case "close": onReply(0); break;
        case "hasFolder": onReply(args[1] === "KDE AI Chat"); break;
        case "createFolder": onReply(true); break;
        case "passwordList": onReply(Object.assign({}, walletFolder)); break;
        case "writePassword":
            if (walletWritesFail) { onReply(-1); break; }
            walletFolder[args[2]] = args[3]; onReply(0); break;
        case "removeFolder": onReply(true); break;
        case "removeEntry": delete walletFolder[args[2]]; onReply(0); break;
        default: onError("unexpected " + member);
        }
    }

    function runHelper(command, payload, onDone) {
        helperCalls.push(command);
        if (command === "read_legacy_keyfile") onDone(JSON.stringify({keys: keyfile}), 0, "");
        else if (onDone) onDone("{}", 0, "");
    }

    Component { id: walletComponent; Store.Wallet { int32: function(v) { return v; }; int64: function(v) { return v; }; bool_: function(v) { return v; } } }
    Component { id: storeComponent; Store.ChatStore { saveDelay: 10 } }
    Component { id: migrationComponent; Store.Migration {} }

    // plasmoid.configuration is a QObject whose properties can be written;
    // a plain JS object would be copied when handed to the component.
    function makeConfig(values) {
        var source = "import QtQuick; QtObject {";
        for (var key in values)
            source += " property string " + key + ": " + JSON.stringify(values[key]) + ";";
        return Qt.createQmlObject(source + " }", testCase);
    }

    function setup(config, walletEntries, status) {
        helperCalls = [];
        walletFolder = walletEntries || {};
        var wallet = createTemporaryObject(walletComponent, testCase);
        wallet.call = fakeKWallet;
        var loaded = false;
        wallet.load(function() { loaded = true; });
        tryVerify(function() { return loaded; });
        if (status) wallet.status = status;
        var store = createTemporaryObject(storeComponent, testCase, {directory: root + "applet-" + Date.now() + Math.floor(Math.random() * 1e6)});
        store.runHelper = runHelper;
        store.prepare(null);
        var migration = createTemporaryObject(migrationComponent, testCase, {configuration: config, wallet: wallet, chatStore: store});
        migration.runHelper = runHelper;
        return {wallet: wallet, store: store, migration: migration};
    }

    function migrateKeys(env) {
        var moved = null;
        env.migration.migrateKeys(function(n) { moved = n; });
        tryVerify(function() { return moved !== null; });
        return moved;
    }

    function init() {
        keyfile = {};
        walletWritesFail = false;
    }

    function test_keys_move_to_wallet_and_plaintext_is_cleared() {
        keyfile = {"openai": "o-file"};
        var config = makeConfig({
            mistralApiKey: "m-plain",
            qwenApiKey: "q-plain",
            groqApiKey: "",
            customProvidersJson: JSON.stringify([{id: "custom_1", name: "C", apiKey: "c-plain"}, {id: "custom_2", name: "D"}]),
            chatSessionsJson: ""
        });
        var env = setup(config, {"mistral": "m-wallet"});

        compare(migrateKeys(env), 3);   // qwen, custom_1, openai; mistral was already in KWallet
        compare(walletFolder["mistral"], "m-wallet");
        compare(walletFolder["qwen"], "q-plain");
        compare(walletFolder["custom_1"], "c-plain");
        compare(walletFolder["openai"], "o-file");
        compare(config.mistralApiKey, "");
        compare(config.qwenApiKey, "");
        verify(config.customProvidersJson.indexOf("apiKey") === -1, config.customProvidersJson);
        compare(JSON.parse(config.customProvidersJson).length, 2);
        verify(helperCalls.indexOf("remove_legacy_keyfile") !== -1);
        verify(env.migration.notice.indexOf("Moved 3 API keys") !== -1, env.migration.notice);
    }

    function test_nothing_changes_when_wallet_is_unavailable() {
        var config = makeConfig({mistralApiKey: "m-plain", customProvidersJson: "[]"});
        var env = setup(config, {}, "disabled");
        compare(migrateKeys(env), 0);
        compare(config.mistralApiKey, "m-plain");
        verify(helperCalls.indexOf("remove_legacy_keyfile") === -1);
    }

    function test_plaintext_kept_when_wallet_write_fails() {
        keyfile = {"openai": "o-file"};
        var config = makeConfig({mistralApiKey: "m-plain", customProvidersJson: "[]"});
        var env = setup(config, {});
        walletWritesFail = true;
        compare(migrateKeys(env), 0);
        compare(config.mistralApiKey, "m-plain");
        verify(helperCalls.indexOf("remove_legacy_keyfile") === -1);
    }

    function test_chats_move_to_files_once() {
        var sessions = [
            {value: "s-1", text: "One", updatedAt: 2, messages: [{role: "user", content: "hi"}, {role: "assistant", content: "hello"}]},
            {value: "s-2", text: "Two", updatedAt: 1, messages: []}
        ];
        var config = makeConfig({customProvidersJson: "[]", chatSessionsJson: JSON.stringify(sessions)});
        var env = setup(config, {});

        var ok = null;
        env.migration.migrateChats(sessions, function(result) { ok = result; });
        verify(ok);
        compare(config.chatSessionsJson, "");
        var loaded = env.store.loadAll();
        compare(loaded.length, 2);
        compare(loaded[0].messages[1].content, "hello");
        verify(env.migration.notice.indexOf("Moved 2 chats") !== -1);

        // A second run has nothing to do.
        config.chatSessionsJson = JSON.stringify(sessions);
        env.migration.migrateChats(sessions, function(result) { ok = result; });
        verify(!ok);
        compare(config.chatSessionsJson, JSON.stringify(sessions));
    }

    function test_chats_kept_when_store_not_ready() {
        var sessions = [{value: "s-1", text: "One", messages: [{role: "user", content: "hi"}]}];
        var config = makeConfig({customProvidersJson: "[]", chatSessionsJson: JSON.stringify(sessions)});
        var env = setup(config, {});
        var unready = createTemporaryObject(storeComponent, testCase, {directory: root + "unready-" + Date.now()});
        env.migration.chatStore = unready;
        var ok = null;
        env.migration.migrateChats(sessions, function(result) { ok = result; });
        verify(!ok);
        compare(config.chatSessionsJson, JSON.stringify(sessions));
    }
}
