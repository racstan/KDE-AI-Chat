// store/Wallet.qml against an in-memory fake KWallet.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

TestCase {
    name: "Wallet"

    // Minimal kwalletd: one wallet, folders of name -> password.
    function makeFake(options) {
        var fake = {
            enabled: options.enabled !== false,
            openHandle: options.openHandle === undefined ? 7 : options.openHandle,
            folders: options.folders || {},
            calls: [],
            opened: 0,
            closed: 0
        };
        fake.call = function(member, args, onReply, onError) {
            fake.calls.push(member);
            switch (member) {
            case "isEnabled": onReply(fake.enabled); break;
            case "networkWallet": onReply("kdewallet"); break;
            case "open": fake.opened++; onReply(fake.openHandle); break;
            case "close": fake.closed++; onReply(0); break;
            case "hasFolder": onReply(fake.folders.hasOwnProperty(args[1])); break;
            case "createFolder": fake.folders[args[1]] = {}; onReply(true); break;
            case "passwordList": onReply(Object.assign({}, fake.folders[args[1]] || {})); break;
            case "writePassword": fake.folders[args[1]][args[2]] = args[3]; onReply(0); break;
            case "removeEntry": delete fake.folders[args[1]][args[2]]; onReply(0); break;
            default: onError("unexpected call " + member);
            }
        };
        return fake;
    }

    Component {
        id: walletComponent
        Store.Wallet {
            int32: function(v) { return v; }
            int64: function(v) { return v; }
            bool_: function(v) { return v; }
        }
    }

    function makeWallet(fake) {
        var w = createTemporaryObject(walletComponent, null);
        w.call = fake.call;
        return w;
    }

    function test_load_reads_all_keys_in_one_call() {
        var fake = makeFake({folders: {"KaiChat": {
            "kai-chat-openai-api-key": "sk-1",
            "kai-chat-custom_abc-api-key": " sk-2 ",
            "kai-chat-empty-api-key": "",
            "unrelated": "x"
        }}});
        var w = makeWallet(fake);
        var result = null;
        w.load(function(ok, keys) { result = {ok: ok, keys: keys}; });
        tryVerify(function() { return result !== null; });
        verify(result.ok);
        compare(w.status, "ready");
        compare(JSON.stringify(w.keys), JSON.stringify({"openai": "sk-1", "custom_abc": "sk-2"}));
        compare(fake.calls.filter(function(c) { return c === "passwordList"; }).length, 1);
        compare(fake.opened, fake.closed);
    }

    function test_load_without_folder_is_ready_and_empty() {
        var w = makeWallet(makeFake({}));
        var done = false;
        w.load(function() { done = true; });
        tryVerify(function() { return done; });
        compare(w.status, "ready");
        compare(Object.keys(w.keys).length, 0);
    }

    function test_disabled_wallet_reports_status() {
        var w = makeWallet(makeFake({enabled: false}));
        var ok = null;
        w.load(function(result) { ok = result; });
        tryVerify(function() { return ok !== null; });
        verify(!ok);
        compare(w.status, "disabled");
        verify(!w.usable);
    }

    function test_refused_open_reports_denied() {
        var w = makeWallet(makeFake({openHandle: -1}));
        var ok = null;
        w.load(function(result) { ok = result; });
        tryVerify(function() { return ok !== null; });
        compare(w.status, "denied");
    }

    function test_write_creates_folder_and_remove_deletes() {
        var fake = makeFake({});
        var w = makeWallet(fake);
        var ok = null;
        w.writeMany({"mistral": "m-key", "qwen": "q-key"}, function(result) { ok = result; });
        tryVerify(function() { return ok !== null; });
        verify(ok);
        compare(fake.folders["KaiChat"]["kai-chat-mistral-api-key"], "m-key");
        compare(w.keys["qwen"], "q-key");

        ok = null;
        w.remove("mistral", function(result) { ok = result; });
        tryVerify(function() { return ok !== null; });
        verify(!fake.folders["KaiChat"].hasOwnProperty("kai-chat-mistral-api-key"));
        verify(!w.keys.hasOwnProperty("mistral"));
        compare(w.keys["qwen"], "q-key");
        compare(fake.opened, fake.closed);
    }
}
