// "Check setup" (config/SetupCheck.qml): the list with ✓/⚠/✗ and a fix per
// line, its one action (Recreate timers = schedules_sync), and the same check
// under an error card in the chat (chat/ErrorActions.qml), which maps the
// error to plain words and offers Check setup where it can find the cause.
// The helper and KWallet are fakes; nothing real is run.
// Screenshots: build/qml-screens/setup-check*.png.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/config" as Config
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 620
    height: 720

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    readonly property var configuration: ({
        "providersJson": JSON.stringify([
            {id: "openrouter", name: "OpenRouter", type: "openai-compat", baseUrl: "https://openrouter.ai/api/v1", model: "openrouter/auto"},
            {id: "nvidia", name: "NVIDIA NIM", type: "openai-compat", baseUrl: "https://integrate.api.nvidia.com/v1", model: "x"},
            {id: "ollama", name: "Ollama (local)", type: "openai-compat", baseUrl: "http://localhost:11434/v1", model: "qwen3"},
            {id: "aihorde", name: "AI Horde", type: "image", service: "horde", baseUrl: "https://aihorde.net/api/v2"}]),
        "useOpenCode": false, "usePi": false, "openCodeUrl": "http://127.0.0.1:4096/v1",
        "sttEnabled": true, "sttEngine": "remote", "voiceTtsEnabled": false
    })

    QtObject {
        id: fakeWallet
        property string status: "ready"
        property var keys: ({"openrouter": "or-key"})
        property int loads: 0
        function load(cb) { loads++; status = "ready"; if (cb) cb(); }
    }

    QtObject {
        id: fakeHelper
        property var calls: []
        property var reply: ({"checks": [
            {"id": "endpoint:ollama", "area": "connection", "status": "error", "code": "local-refused", "args": ["Ollama (local)", "http://localhost:11434/v1"]},
            {"id": "attach-pdf", "area": "attachments", "status": "ok", "code": "pdf-ok", "args": []},
            {"id": "attach-docx", "area": "attachments", "status": "warn", "code": "docx-basic", "args": []},
            {"id": "stt-engine", "area": "voice", "status": "warn", "code": "stt-remote-url", "args": []},
            {"id": "schedules", "area": "scheduler", "status": "error", "code": "sched-timers-missing", "args": ["2"]}]})
        function run(command, payload, done) {
            calls = calls.concat([{"command": command, "payload": payload}]);
            done(JSON.stringify(command === "setup_check" ? reply : {"ok": true}), 0, "");
        }
    }

    Rectangle { anchors.fill: parent; color: "white" }

    Config.SetupCheck {
        id: check
        x: 10
        y: 10
        width: 600
        configuration: root.configuration
        wallet: fakeWallet
        helper: fakeHelper
    }

    FakeChat {
        id: chat
        wallet: fakeWallet
        setupCheckHelper: fakeHelper
        plasmoid: ({"configuration": root.configuration})
    }

    Chat.ChatView {
        id: view
        visible: false
        anchors.fill: parent
        chat: chat
    }

    HarnessTestCase {
        name: "SetupCheck"

        function init() {
            fakeHelper.calls = [];
            fakeWallet.status = "ready";
            view.visible = false;
            check.visible = true;
            check.rows = [];
            check.checked = false;
        }

        function texts(item, name) {
            return findChildren(item, name).filter(function(l) { return l.visible; }).map(function(l) { return l.text; });
        }

        function test_lists_every_check_with_its_fix() {
            mouseClick(findChild(check, "setupCheckButton"));
            tryVerify(function() { return check.checked && !check.running; }, 3000);
            compare(fakeHelper.calls[0].command, "setup_check");
            var payload = fakeHelper.calls[0].payload;
            compare(payload.mode, "direct");
            compare(JSON.stringify(payload.endpoints), JSON.stringify([{id: "ollama", name: "Ollama (local)", url: "http://localhost:11434/v1"}]));
            compare(payload.stt.sttEnabled, true);
            verify(JSON.stringify(payload).indexOf("or-key") < 0, "no key goes to the helper");
            // Only what needs doing; what passed is one click away.
            compare(texts(check, "setupCheckText"), ["NVIDIA NIM has no API key.",
                            "Nothing answers at http://localhost:11434/v1, so Ollama (local) isn't running there.",
                            "Word files are read with a simpler built-in reader: pandoc is missing.",
                            "Dictation has no speech server address.",
                            "2 schedules are missing their timer, so they won't run."]);
            var more = findChild(check, "setupCheckShowPassed");
            compare(more.text, "Show what passed (3 checks)");
            more.clicked();
            var shown = texts(check, "setupCheckText");
            compare(shown, ["KWallet is open, so API keys can be read.", "OpenRouter is set up.", "NVIDIA NIM has no API key.",
                            "Nothing answers at http://localhost:11434/v1, so Ollama (local) isn't running there.",
                            "PDF files can be attached.",
                            "Word files are read with a simpler built-in reader: pandoc is missing.",
                            "Dictation has no speech server address.",
                            "2 schedules are missing their timer, so they won't run."]);
            more.clicked();
            var fixes = texts(check, "setupCheckFix");
            verify(fixes.indexOf("Start Ollama (local), or correct the address. For Ollama, the command is: ollama serve") >= 0, fixes);
            verify(fixes.indexOf("Add the key in Settings → Connection; it is kept in KWallet.") >= 0, fixes);
            compare(findChild(check, "setupCheckSummary").text, "3 problems, 2 warnings");
            screenshot(root, "setup-check");
        }

        function test_recreate_timers_runs_the_existing_sync_then_checks_again() {
            check.run();
            tryVerify(function() { return check.checked && !check.running; }, 3000);
            var actions = findChildren(check, "setupCheckAction").filter(function(b) { return b.visible; });
            compare(actions.length, 1);
            mouseClick(actions[0]);
            tryVerify(function() { return fakeHelper.calls.length === 3 && !check.running; }, 3000);
            compare(fakeHelper.calls.map(function(c) { return c.command; }), ["setup_check", "schedules_sync", "setup_check"]);
        }

        function test_all_good_is_one_line() {
            check.rows = [{"id": "wallet", "area": "keys", "status": "ok", "code": "wallet-ok", "args": []},
                          {"id": "attach-pdf", "area": "attachments", "status": "ok", "code": "pdf-ok", "args": []}];
            check.checked = true;
            compare(texts(check, "setupCheckText"), [], "nothing that passed is listed");
            compare(findChild(check, "setupCheckSummary").text, "Everything is ready.");
            compare(findChild(check, "setupCheckShowPassed").text, "Show what passed (2 checks)");
            screenshot(root, "setup-check-all-good");
        }

        function test_wallet_is_loaded_first_when_not_yet_asked() {
            fakeWallet.status = "unknown";
            var before = fakeWallet.loads;
            check.run();
            tryVerify(function() { return check.checked; }, 3000);
            compare(fakeWallet.loads, before + 1);
        }

        function test_locked_wallet_is_one_line() {
            fakeWallet.status = "denied";
            check.run();
            tryVerify(function() { return check.checked; }, 3000);
            var shown = texts(check, "setupCheckText");
            compare(shown[0], "KWallet is locked or refused access.");
            verify(shown.indexOf("NVIDIA NIM has no API key.") < 0, "keys aren't reported missing while the wallet is shut");
        }

        function test_error_card_offers_check_setup_and_lists_problems_only() {
            check.visible = false;
            view.visible = true;
            chat.messages = [
                {role: "user", content: "Hello", time: "10:00"},
                {role: "error", content: "⚠️ Cannot send message with NVIDIA NIM. Missing: API key. Please open Widget Settings", time: "10:00"}
            ];
            var delegate = null;
            tryVerify(function() { delegate = view.list.itemAtIndex(1); return delegate !== null; }, 3000);
            var button = null;
            tryVerify(function() { button = findChild(delegate, "checkSetupButton"); return button !== null && button.visible; }, 3000);
            mouseClick(button);
            var loader = findChild(delegate, "setupCheckLoader");
            tryVerify(function() { return loader.item && loader.item.checked; }, 3000);
            var shown = texts(loader.item, "setupCheckText");
            compare(shown[0], "NVIDIA NIM has no API key.");
            verify(shown.indexOf("PDF files can be attached.") < 0, "only problems under an error");
            wait(100);
            screenshot(root, "setup-check-error-card");
        }

        function test_errors_without_a_setup_cause_have_no_check_button() {
            check.visible = false;
            view.visible = true;
            chat.messages = [{role: "error", content: "Request to https://x failed (HTTP 429): Rate limit reached", time: "10:00"}];
            var delegate = null;
            tryVerify(function() { delegate = view.list.itemAtIndex(0); return delegate !== null; }, 3000);
            var retry = null;
            tryVerify(function() { retry = findChild(delegate, "retryButton"); return retry !== null; }, 3000);
            var button = findChild(delegate, "checkSetupButton");
            verify(!button || !button.visible);
        }
    }
}
