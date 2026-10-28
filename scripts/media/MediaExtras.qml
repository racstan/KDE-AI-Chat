// The extra chat states of the docs media (see MediaTour.qml): quoting, editing, menus,
// agent cards, pictures, errors, notices, first run, a narrow popup... Each one is built
// from the widget's own state (made-up messages put into a scratch chat, flags, config) and
// saved with the same kit. A state that can't be reached is logged as MEDIA_SKIP and the
// tour carries on (TourKit.guard); the scratch chat is always removed.
import QtQuick
import QtQuick.Window

Item {
    id: extras

    property var tour: null
    property var kit: null
    readonly property var app: tour.app
    readonly property var composer: tour.body.composerItem
    readonly property string longText: "Here is a comparison of the three modes.\n\n| Mode | Talks to | Good for |\n|---|---|---|\n| Direct | any provider over HTTP | quick questions |\n| OpenCode | a local OpenCode server | coding in a folder |\n| Pi | the Pi agent | small agent tasks |\n\nA tiny example of the direct request:\n\n```python\nimport json, urllib.request\n\nbody = {\"model\": \"nova-demo\", \"stream\": True,\n        \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]}\nreq = urllib.request.Request(\"http://127.0.0.1:8080/v1/chat/completions\",\n                             json.dumps(body).encode())\n```\n\n**Tip:** pick the mode once per chat; a chat keeps its mode."

    function m(role, content, extra) {
        var now = Date.now();
        return Object.assign({"role": role, "content": content, "at": now - 60000, "model": role === "assistant" ? "nova-demo" : undefined}, extra || {});
    }

    // A popup (menu, picker) lives in the window's overlay: move its visual item into the widget's tree.
    function pull(popup) {
        var item = popup.contentItem ? popup.contentItem.parent : null;
        if (item) { item.parent = tour.target; item.z = 6000; }
    }

    // An object (not an item) among `owner`'s data that has all of these members.
    function findObject(owner, members) {
        var data = owner.data || [];
        for (var i = 0; i < data.length; i++) {
            var ok = true;
            for (var j = 0; j < members.length; j++)
                if (data[i][members[j]] === undefined) ok = false;
            if (ok) return data[i];
        }
        return null;
    }
    readonly property var runner: composer ? findObject(composer, ["notice", "track", "runMode"]) : null

    function isSeeded(id) { return String(id).indexOf("s-1000000000") === 0; }

    // Back to the demo chat with everything put away, whatever happened.
    function restore(then) {
        app.editingMessageIndex = -1;
        app.modeNotice = "";
        app.chatInputText = "";
        composer.quoteChips.quotes = [];
        tour.settingsDialog.close();
        tour.target.Window.window.width = tour.width_;
        tour.dismissUndo();
        var id = app.currentSessionId;
        var go = function() { tour.goTo(tour.demoChat, then); };
        if (!isSeeded(id)) tour.deleteOpenChat(go); else go();
    }

    // One state: `messages` go into a new chat (or `chat` is opened), setup(done) prepares the rest,
    // the shot is saved, cleanup() puts things back.
    function scene(name, spec, next) {
        var leave = function() { tour.keepToast = false; kit.unguard(); extras.restore(next); };
        kit.guard(name, function() { extras.restore(next); });
        tour.keepToast = !!spec.keepToast;
        var begin = function() {
            if (spec.messages) app.messages = spec.messages;
            kit.later(spec.settle || 900, function() {
                var done = function() {
                    kit.later(spec.after || 500, function() {
                        tour.shot(name, function() {
                            if (spec.cleanup) spec.cleanup();
                            leave();
                        });
                    });
                };
                if (spec.setup) spec.setup(done); else done();
            });
        };
        if (spec.chat) tour.goTo(spec.chat, begin); else tour.newChat(begin);
    }

    function step(name, spec) { return function(next) { extras.scene(name, spec, next); }; }

    readonly property var steps: [
        step("chat-quote", {chat: tour.demoChat, setup: function(done) {
            composer.quoteChips.quotes = [{"id": "", "role": "assistant", "text": "'static means \"valid for the whole program\", e.g. string literals."}];
            app.chatInputText = "Can you show an example of that?";
            done();
        }, cleanup: function() { composer.quoteChips.quotes = []; app.chatInputText = ""; }}),

        step("chat-edit", {chat: tour.demoChat, setup: function(done) {
            var list = tour.body.chatView.list;
            app.editingDraft = String(app.messages[0].content);
            app.editingMessageIndex = 0;
            // The view jumps to the end when the editor opens: scroll back to Alex's question.
            kit.later(800, function() {
                if (list && typeof list.positionViewAtBeginning === "function") list.positionViewAtBeginning();
                kit.later(300, done);
            });
        }}),

        step("chat-variants", {chat: tour.demoChat, setup: function(done) {
            tour.plasmoidRef.configuration.perChatModelSettings = true;
            tour.settingsDialog.openForSession(app.currentSessionId);
            kit.waitFor("the own-model check", function() { var c = kit.find(tour.target, "ownModelCheck"); return c !== null && c.visible; }, 8000, function() {
                var check = kit.find(tour.target, "ownModelCheck");
                check.checked = true;
                check.toggled();
                kit.later(900, done);
            });
        }, cleanup: function() { tour.plasmoidRef.configuration.perChatModelSettings = false; }}),

        step("chat-more-menu", {chat: tour.demoChat, setup: function(done) {
            var button = kit.find(tour.target, "moreButton");
            button.clicked();
            kit.waitFor("the menu", function() { return button.menu.opened; }, 5000, function() { extras.pull(button.menu); done(); });
        }, cleanup: function() { kit.find(tour.target, "moreButton").menu.close(); }}),

        step("chat-export", {chat: tour.demoChat, setup: function(done) {
            // Qt's FileDialog: a native window in a real session, which grabToImage can't capture.
            kit.fail("the export dialog is a native file dialog, which grabToImage can't capture");
        }}),

        step("chat-workspace", {chat: tour.demoChat, setup: function(done) {
            app.chooseWorkspace("/home/alex/projects/nova");
            kit.waitFor("the workspace", function() { return String(app.openCodeWorkspaceCwd) !== ""; }, 5000, done);
        }, cleanup: function() { app.chooseWorkspace(""); }}),

        step("chat-opencode", {messages: [
            extras.m("user", "Can you fix the failing test in parser.py?"),
            extras.m("assistant", "Found it. The parser drops the last line:\n\n```python\nlines = text.split(\"\\n\")[:-1]\n```\n\nI will keep every line.",
                     {"model": "OpenCode · build", "reasoning": "The test fails because the last line is cut off.", "contextItems": ["✓ read: parser.py", "✓ edit: parser.py"],
                      "tokens": {"input": 2087, "output": 95}}),
            extras.m("permission_request", "OpenCode asks for permission: edit parser.py",
                     {"model": "OpenCode", "status": "pending", "canAlways": true, "permissionId": "p1"})]}),

        step("chat-pi", {messages: [
            extras.m("user", "List the TODO comments in this folder."),
            extras.m("assistant", "There are two TODOs: one in `parser.py` and one in `cli.py`.",
                     {"model": "Pi · qwen3:8b", "contextItems": ["✓ grep: TODO", "✓ read: parser.py"], "tokens": {"input": 1204, "output": 61}}),
            extras.m("question_request", "Pi is asking", {"model": "Pi", "status": "pending", "questionId": "q1", "allowCustom": false,
                     "questions": [{"question": "Open both files?", "options": [{"label": "Yes"}, {"label": "No"}]}]})]}),

        step("chat-image", {messages: [
            extras.m("user", "Paint a lighthouse at dusk, watercolor."),
            extras.m("assistant", "Here is your picture.", {"images": [{"path": "demo-picture.png", "prompt": "A lighthouse at dusk, watercolor",
                     "service": "AI Horde", "model": "nova-demo"}]})], settle: 1500,
            setup: function(done) {
                var list = tour.body.chatView.list;
                if (list && typeof list.positionViewAtBeginning === "function") list.positionViewAtBeginning();
                kit.later(400, done);
            }}),

        step("chat-error", {messages: [
            extras.m("user", "Summarize my notes."),
            extras.m("error", "Nova demo (local): HTTP 429: too many requests. Wait a moment and try again.")]}),

        // The real banner (chat/ModeMismatchBanner.qml): Settings select Pi for new chats, this chat is Direct.
        step("chat-mode-notice", {chat: tour.demoChat, setup: function(done) {
            tour.plasmoidRef.configuration.usePi = true;
            kit.waitFor("the mode banner", function() {
                var b = kit.find(tour.target, "modeMismatchBanner");
                return b !== null && b.visible && b.text !== "";
            }, 8000, function() { kit.later(600, done); });
        }, cleanup: function() { tour.plasmoidRef.configuration.usePi = false; }}),

        // "/model" with per-chat model settings off: the suggestions popup shows the notice entry.
        step("chat-model-notice", {chat: tour.demoChat, setup: function(done) {
            app.chatInputText = "/model ";
            kit.waitFor("the model notice popup", function() {
                var s = composer.suggestions;
                return s && s.visible && s.height > 20;
            }, 8000, function() { kit.later(600, done); });
        }, cleanup: function() { app.chatInputText = ""; }}),

        step("chat-remember", {keepToast: true, chat: tour.demoChat, setup: function(done) {
            if (!extras.runner) { kit.fail("the command runner was not found"); return; }
            extras.runner.run("/remember I prefer metric units");
            done();
        }}),

        step("chat-first-run", {setup: function(done) {
            var c = tour.plasmoidRef.configuration;
            extras.saved = [c.providersJson, c.provider];
            c.providersJson = "[]";
            c.provider = "";
            kit.waitFor("the welcome card", function() { var card = kit.find(tour.target, "firstRunCard"); return card !== null && card.visible; }, 8000, done);
        }, cleanup: function() {
            var c = tour.plasmoidRef.configuration;
            c.providersJson = extras.saved[0];
            c.provider = extras.saved[1];
        }}),

        step("chat-scheduled", {messages: [
            extras.m("user", "Give me a short briefing for today.", {"scheduleName": "Morning briefing", "scheduleRunId": "run-demo-1"}),
            extras.m("assistant", "Good morning, Alex. It is sunny in Lisbon, 22 degrees.\n\n- Stand-up at 10:00\n- Invoice for Sam is due on the 17th\n- Rust study group tonight", {"scheduleRunId": "run-demo-1"})]}),

        step("chat-long-reply", {messages: [
            extras.m("user", "Compare the three modes in a table, with an example."),
            extras.m("assistant", extras.longText, {"tokens": {"input": 310, "output": 380}})]}),

        step("chat-avatars", {chat: "s-1000000000003-0003"}),

        step("chat-narrow", {chat: tour.demoChat, setup: function(done) {
            tour.target.Window.window.width = 320;
            kit.waitFor("the narrow popup", function() { return Math.abs(tour.target.width - 320) < 2; }, 8000, function() { kit.later(900, done); });
        }})
    ]

    property var saved: []

    function run(next) {
        var i = 0;
        var go = function() {
            if (i >= steps.length) { next(); return; }
            steps[i++](go);
        };
        go();
    }
}
