// A chat keeps the mode it was started in (provider / OpenCode / Pi): changing
// the main mode or the per-chat settings never moves an open chat, nor a reply
// that is streaming, to another mode; only new chats get the new main mode.
// Covers chat/ModeSync.qml (what main.qml delegates to), the notice when a
// chat's mode is unavailable (OpenCodeMode.qml, PiMode.qml, NoticeBanner.qml).
import QtQuick
import QtQuick.Layouts
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 640
    height: 220

    function i18n(text) { return text; }

    FakeChat {
        id: chat
        plasmoid: ({configuration: cfg})
    }

    // plasmoid.configuration: a real QObject so the settings emit change signals.
    QtObject {
        id: cfg
        property bool useOpenCode: false
        property bool usePi: false
        property bool perChatModelSettings: false
        property string perChatPriority: "chat"
        property string provider: "openai"
        property string openCodeAgent: "build"
        property string openCodeWorkspaceCwd: ""
        property string openCodeProvider: "opencode"
        property string openCodeModel: "zen-x"
        property string piProvider: "ollama"
        property string piModel: "qwen"
    }

    Chat.ModeSync {
        id: sync
        chat: chat
    }

    // What OpenCodeMode.qml / PiMode.qml need from main.qml, with a helper that always fails.
    QtObject {
        id: stub
        property bool loading: false
        property string modeNotice: ""
        property bool openCodeMode: true
        property bool piMode: false
        property var currentStreamUsage: ({})
        property var activeXhr: null
        property var events: []
        property var store: ({"runHelper": function(command, payload, done) {
            done(JSON.stringify({"status": "error", "message": command === "pi_bridge_start" ? "the Pi bridge didn't start (see the log)." : "no opencode binary"}));
        }})
        function openCodeBaseUrl() { return "http://127.0.0.1:1"; }
        function getSessionProperty(id, key, fallback) { return fallback; }
        function requestIsCurrent() { return true; }
        function applyBackendEvent(event) { events = events.concat([event]); }
    }
    Chat.OpenCodeMode { id: ocSender; chat: stub }
    Chat.PiMode { id: piSender; chat: stub }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        Chat.NoticeBanner {
            id: banner
            objectName: "modeNotice"
            isError: true
            dismissible: true
            text: chat.modeNotice
            onDismissed: chat.modeNotice = ""
        }
        Item { Layout.fillHeight: true }
    }

    HarnessTestCase {
        name: "ChatMode"

        readonly property var modes: ["provider", "opencode", "pi"]

        function mainSettings(mode) {
            cfg.useOpenCode = mode === "opencode";
            cfg.usePi = mode === "pi";
        }

        function init() {
            chat.plasmoid = {configuration: cfg};
            cfg.perChatModelSettings = false;
            cfg.perChatPriority = "chat";
            mainSettings("provider");
            chat.sessions = [
                {value: "p", text: "Direct", source: "provider", messages: []},
                {value: "o", text: "OpenCode", source: "opencode", messages: [], openCodeSessionId: "ses_0123456789abcdef"},
                {value: "x", text: "Pi", source: "pi", messages: []}
            ];
            chat.modeNotice = "";
            chat.loading = false;
            chat.streamingResponse = false;
            chat.currentStreamText = "";
            sync._appliedSessionId = "";
        }

        // Opens the chat the way main.qml's switchSession does.
        function open(id) {
            chat.currentSessionId = id;
            return sync.apply(chat.sessions[chat.sessionIndexById(id)]);
        }

        function widgetMode() {
            return chat.openCodeMode ? "opencode" : (chat.piMode ? "pi" : "provider");
        }

        function chatId(mode) {
            return {"provider": "p", "opencode": "o", "pi": "x"}[mode];
        }

        function test_01_each_chat_opens_in_its_own_mode_whatever_the_main_mode() {
            for (const main of modes) {
                mainSettings(main);
                for (const own of modes) {
                    compare(open(chatId(own)), own, "chat " + own + " under main " + main);
                    compare(widgetMode(), own);
                }
            }
        }

        function test_02_switching_the_main_mode_while_a_chat_is_open_does_not_move_it() {
            for (const own of modes) {
                mainSettings("provider");
                open(chatId(own));
                compare(widgetMode(), own);
                for (const main of ["opencode", "pi", "provider", "pi", "opencode"]) {
                    mainSettings(main);
                    compare(widgetMode(), own, "chat " + own + " after main -> " + main);
                    compare(chat.effectiveConfig(chatId(own)).mode, own);
                }
            }
        }

        function test_03_the_per_chat_settings_do_not_move_it_either() {
            chat.sessions = chat.sessions.map(s => Object.assign({}, s, {ownModel: true, chatModel: "m", openCodeModel: "oc", piModel: "pm"}));
            for (const own of modes) {
                mainSettings("opencode");
                open(chatId(own));
                for (const priority of ["chat", "main"]) {
                    for (const perChat of [true, false, true]) {
                        cfg.perChatPriority = priority;
                        cfg.perChatModelSettings = perChat;
                        compare(widgetMode(), own, own + " " + priority + " " + perChat);
                    }
                }
            }
        }

        function test_04_a_reply_streaming_when_the_main_mode_changes_is_undisturbed() {
            for (const own of modes) {
                mainSettings("provider");
                open(chatId(own));
                chat.messages = [{role: "user", content: "hi"}, {role: "assistant", content: "par", streaming: true}];
                chat.loading = true;
                chat.streamingResponse = true;
                chat.currentStreamIndex = 1;
                chat.currentStreamText = "partial answer";
                for (const main of ["opencode", "pi", "provider"]) {
                    mainSettings(main);
                    cfg.perChatModelSettings = !cfg.perChatModelSettings;
                    compare(widgetMode(), own, "streaming " + own + " after main -> " + main);
                    verify(chat.loading, "still loading");
                    verify(chat.streamingResponse, "still streaming");
                    compare(chat.currentStreamText, "partial answer");
                    compare(chat.currentStreamIndex, 1);
                    compare(chat.messages.length, 2);
                }
                chat.loading = false;
                chat.streamingResponse = false;
                chat.currentStreamIndex = -1;
            }
        }

        function test_05_a_new_chat_gets_the_new_main_mode() {
            for (const main of ["opencode", "pi", "provider"]) {
                mainSettings(main);
                compare(sync.newChatMode(), main);
            }
            // A chat made under one main mode stays when the main mode changes, and a later chat differs.
            mainSettings("pi");
            var first = sync.newChatMode();
            chat.sessions = chat.sessions.concat([{value: "n1", text: "New Chat", source: first, messages: []}]);
            open("n1");
            mainSettings("opencode");
            compare(widgetMode(), "pi");
            var second = sync.newChatMode();
            compare(second, "opencode");
            chat.sessions = chat.sessions.concat([{value: "n2", text: "New Chat", source: second, messages: []}]);
            compare(open("n2"), "opencode");
            compare(open("n1"), "pi");
        }

        function test_06_an_old_chat_without_a_mode_is_a_direct_chat_not_the_main_mode() {
            mainSettings("pi");
            chat.sessions = chat.sessions.concat([{value: "old", text: "Old", messages: []}]);
            compare(open("old"), "provider");
        }

        function test_07_the_notice_belongs_to_one_chat_and_survives_setting_changes() {
            open("o");
            chat.modeNotice = "OpenCode is down";
            mainSettings("pi");
            cfg.perChatPriority = "main";
            compare(chat.modeNotice, "OpenCode is down", "a settings change keeps the notice and the mode");
            compare(widgetMode(), "opencode");
            open("p");
            compare(chat.modeNotice, "", "another chat has its own situation");
        }

        function test_08_an_unreachable_opencode_says_so_and_the_chat_stays_in_opencode() {
            stub.events = [];
            stub.modeNotice = "";
            stub.openCodeMode = true;
            ocSender.send("o", 1);
            tryVerify(() => stub.events.length === 2, 5000);
            compare(stub.events[0].type, "error");
            verify(stub.events[0].message.indexOf("OpenCode chat") >= 0, stub.events[0].message);
            verify(stub.events[0].message.indexOf("no opencode binary") >= 0, stub.events[0].message);
            verify(stub.events[0].message.indexOf("stays in OpenCode mode") >= 0, stub.events[0].message);
            compare(stub.events[1].type, "done");
            compare(stub.modeNotice, stub.events[0].message);
            verify(stub.openCodeMode && !stub.piMode, "no fallback to another mode");
        }

        function test_09_an_unavailable_pi_says_so_and_the_chat_stays_in_pi() {
            stub.events = [];
            stub.modeNotice = "";
            stub.openCodeMode = false;
            stub.piMode = true;
            piSender.send("x", 1);
            tryVerify(() => stub.events.length === 2);
            compare(stub.events[0].type, "error");
            verify(stub.events[0].message.indexOf("a Pi chat") >= 0, stub.events[0].message);
            verify(stub.events[0].message.indexOf("bridge didn't start") >= 0, stub.events[0].message);
            verify(stub.events[0].message.indexOf("stays in Pi mode") >= 0, stub.events[0].message);
            compare(stub.modeNotice, stub.events[0].message);
            verify(stub.piMode && !stub.openCodeMode, "no fallback to another mode");
        }

        function test_10_the_notice_is_shown_and_can_be_dismissed() {
            verify(!banner.visible);
            chat.modeNotice = "This is a Pi chat and it can't answer right now. Pi: the Pi bridge didn't start. It stays in Pi mode (a chat never switches mode). Fix that and send again, or start a new chat in another mode.";
            verify(banner.visible);
            wait(30);
            screenshot(root, "chat-mode-notice");
            banner.dismissed();
            compare(chat.modeNotice, "");
            verify(!banner.visible);
        }
    }
}
