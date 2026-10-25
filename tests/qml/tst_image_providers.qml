// Settings → Connection, image services: config/ProvidersPanel.qml with
// config/ImageProvidersPanel.qml, a fake configuration, a fake KWallet and fake
// AI Horde / Pollinations model lists (no network). A service is off until the
// user switches it on, says where prompts go, keeps AI Horde within the
// anonymous limits, and never becomes the default for chats by itself.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/config" as Config
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

Item {
    id: root
    width: 640
    height: 900

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    property var walletFolder: ({})
    property var requests: []
    readonly property var hordeModels: [
        {name: "Deliberate", count: 5, eta: 12, queued: 3, type: "image"},
        {name: "stable_diffusion", count: 7, eta: 8, queued: 1, type: "image"},
        {name: "WAI-NSFW-illustrious-SDXL", count: 9, eta: 3, queued: 0, type: "image"},
        {name: "Grapefruit Hentai", count: 2, eta: 3, queued: 0, type: "image"},
        {name: "No Workers Model", count: 0, eta: 0, queued: 0, type: "image"}
    ]
    function makeXhr() {
        var x = {headers: {}, readyState: 0, status: 0, responseText: ""};
        x.open = function(method, url) { x.method = method; x.url = url; };
        x.setRequestHeader = function(k, v) { x.headers[k] = v; };
        x.getResponseHeader = function() { return null; };
        x.abort = function() {};
        x.send = function(body) {
            root.requests.push({method: x.method, url: x.url, headers: x.headers});
            Qt.callLater(function() {
                var horde = x.url.indexOf("aihorde.net") >= 0;
                x.status = 200;
                x.responseText = JSON.stringify(horde ? root.hordeModels
                    : [{name: "z-image-turbo", title: "Z Image", paid_only: false, output_modalities: ["image"]},
                       {name: "gpt-image-2", paid_only: true, output_modalities: ["image"]},
                       {name: "veo", output_modalities: ["video"]}]);
                x.readyState = 4;
                x.onreadystatechange();
            });
        };
        return x;
    }

    QtObject {
        id: config
        property string providersJson: JSON.stringify([{id: "nvidia", name: "NVIDIA NIM", type: "openai-compat", baseUrl: "https://nim.example/v1", model: "acme/chat"}])
        property string provider: "nvidia"
        property string imageProvider: ""
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

    QQC2.ScrollView {
        anchors.fill: parent
        anchors.margins: 12
        Config.ProvidersPanel {
            id: panel
            width: root.width - 24
            configuration: config
            wallet: wallet
            xhrFactory: root.makeXhr
        }
    }

    HarnessTestCase {
        id: tc
        name: "ImageProviders"

        readonly property var part: findChild(panel, "imageProvidersPanel")
        function child(name) { return findChild(panel, name); }
        function saved() { return JSON.parse(config.providersJson); }
        function savedEntry(id) { return saved().filter(function(p) { return p.id === id; })[0]; }

        function initTestCase() {
            var done = false;
            wallet.load(function() { done = true; });
            tryVerify(function() { return done; });
            panel.load();
        }

        function init() {
            root.requests = [];
        }

        function test_1_ai_horde_lists_only_safe_models_and_starts_switched_off() {
            panel.addFromPreset("aihorde");
            verify(part.visible, "the image editor is shown");
            verify(!child("urlField").visible, "the text-provider editor is not");
            tryVerify(function() { return part.models.list.length > 0; }, 2000);
            compare(root.requests.length, 1);
            compare(root.requests[0].url, "https://aihorde.net/api/v2/status/models?type=image&min_count=1");
            verify(/^KDE-AI-Chat:[^:]+:https:\/\//.test(root.requests[0].headers["Client-Agent"]), root.requests[0].headers["Client-Agent"]);
            compare(part.models.list.map(function(m) { return m.id; }), ["stable_diffusion", "Deliberate"], "adult-content and idle models are left out");
            verify(!child("acceptCheck").checked, "off until switched on");
            verify(child("privacyNote").text.indexOf("LAION") >= 0);
            verify(child("privacyNote").text.indexOf("volunteer") >= 0);
            compare(String(child("termsLink").url), "https://aihorde.net/terms");
            verify(!child("image_modelPicker").allowCustom, "no typed-in AI Horde model names");
            wait(200);
            screenshot(root, "image-providers-horde-editor");
        }

        function test_2_anonymous_horde_stays_within_its_limits() {
            var editor = part.editor;
            compare(editor.maxSize, 576);
            compare(editor.sizes[editor.sizes.length - 1], 576);
            compare(child("widthBox").currentText, "512");
            compare(child("stepsBox").to, 30);
            compare(child("stepsBox").value, 22);
            verify(!child("countBox").visible, "one picture at a time without a key");
            verify(child("sizeNote").visible);
            part.edit("key", "own-horde-key");
            compare(editor.maxSize, 1024);
            verify(child("countBox").visible);
            part.edit("key", "");
        }

        function test_3_switch_on_and_save() {
            mouseClick(child("acceptCheck"));
            part.edit("option.width", 384);
            mouseClick(child("image_saveButton"));
            var entry = savedEntry("aihorde");
            compare(entry.type, "image");
            compare(entry.service, "horde");
            compare(entry.accepted, true);
            compare(entry.model, "Deliberate", "a well-known model with workers is picked when none was chosen");
            compare(entry.options.width, 384);
            compare(config.provider, "nvidia", "an image service never becomes the chats' default");
            compare(panel.defaultImage, "aihorde", "the first image service is the one /image uses");
            compare(root.walletFolder["aihorde"], undefined, "no key: AI Horde is used without an account");
            verify(!part.visible);
            wait(100);
            screenshot(root, "image-providers-list");
        }

        function test_4_older_free_pollinations_says_what_it_is() {
            panel.addFromPreset("pollinations_free");
            verify(!child("image_keyField").visible, "it takes no key");
            var note = child("privacyNote").text;
            verify(note.indexOf("older free service") >= 0, note);
            verify(note.indexOf("may stop working") >= 0, note);
            verify(note.indexOf("45 seconds") >= 0, note);
            verify(note.indexOf("logo") >= 0, note);
            compare(part.models.list.map(function(m) { return m.id; }), ["sana"]);
            compare(root.requests.length, 0, "nothing to list: it has one model");
            wait(100);
            screenshot(root, "image-providers-pollinations-free");
            panel.cancelEdit();
        }

        function test_5_pollinations_with_a_key_keeps_it_in_kwallet() {
            panel.addFromPreset("pollinations");
            tryVerify(function() { return part.models.list.length > 0; }, 2000);
            compare(part.models.list.map(function(m) { return m.id; }), ["z-image-turbo", "gpt-image-2"], "video models are left out, free ones first");
            compare(root.requests[0].headers["Authorization"], undefined, "the model list needs no key");
            part.edit("key", "sk_test");
            mouseClick(child("acceptCheck"));
            mouseClick(child("image_saveButton"));
            tryVerify(function() { return root.walletFolder["pollinations"] === "sk_test"; });
            verify(config.providersJson.indexOf("sk_test") < 0, "the key is not in the settings");
            compare(savedEntry("pollinations").model, "z-image-turbo");
        }

        function test_6_use_for_image_picks_the_default_image_service() {
            var rows = findChildren(panel, "").filter(function(item) { return item.entry !== undefined && item.useByDefault !== undefined; });
            var row = rows.filter(function(r) { return r.entry.id === "pollinations"; })[0];
            verify(row.imageService);
            row.useByDefault();
            compare(config.imageProvider, "pollinations");
            compare(config.provider, "nvidia");
        }
    }
}
