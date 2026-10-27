// chat/AskInbox.qml: a question left by KRunner, the Dolphin menu or kdeaichat-ask opens the popup, goes
// into the open chat (or a new one), attaches its files and fills (or sends) the message. The helper and
// the widget root are stand-ins; the watched folder is a real one.
import QtQuick
import QtCore
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

TestCase {
    id: testCase
    name: "AskInbox"
    when: windowShown

    readonly property string root: decodeURIComponent(String(Qt.resolvedUrl("../../build/test-ask/")).replace(/^file:\/\//, ""))

    QtObject {
        id: fakeChat
        property bool expanded: false
        property string currentSessionId: "open"
        property string chatInputText: ""
        property var attached: []
        property var calls: []
        property bool filesReady: true
        function triggerInitialLoad() { calls.push("load"); }
        function createSession(switchToNew) { calls.push("newChat:" + switchToNew); currentSessionId = "fresh"; }
        function attachFile(url) { attached.push(url); calls.push("attach"); }
        function attachmentsReadyToSend() { return filesReady; }
        function sendMessage() { calls.push("send:" + chatInputText); chatInputText = ""; }
        function focusInput() { calls.push("focus"); }
    }

    property var queued: []        // what the helper hands out next
    property var helperCalls: []

    Component {
        id: inboxComponent
        Chat.AskInbox {
            chat: fakeChat
            ready: true
            runHelper: function(command, payload, onDone) {
                testCase.helperCalls = testCase.helperCalls.concat([command]);
                if (command === "ask_inbox_take") {
                    var items = testCase.queued;
                    testCase.queued = [];
                    if (onDone) onDone(JSON.stringify({"type": "ask_items", "directory": "", "items": items}), 0, "");
                } else if (onDone) {
                    onDone("{}", 0, "");
                }
            }
        }
    }

    Component {
        id: fileComponent
        Settings {}
    }

    function item(extra) {
        return Object.assign({"text": "", "files": [], "newChat": false, "send": false}, extra);
    }

    function init() {
        fakeChat.expanded = false;
        fakeChat.currentSessionId = "open";
        fakeChat.chatInputText = "";
        fakeChat.attached = [];
        fakeChat.calls = [];
        fakeChat.filesReady = true;
        queued = [];
        helperCalls = [];
    }

    function test_a_question_opens_the_popup_and_is_sent_in_the_open_chat() {
        var inbox = createTemporaryObject(inboxComponent, testCase);
        queued = [item({"text": "why is the sky blue?", "send": true})];
        inbox.take();
        compare(fakeChat.expanded, true, "the widget opens itself");
        tryVerify(function() { return fakeChat.calls.indexOf("send:why is the sky blue?") >= 0; }, 3000);
        compare(fakeChat.calls.indexOf("newChat:true"), -1, "the open chat is used: no mode change, no new chat");
        compare(fakeChat.currentSessionId, "open");
    }

    function test_new_chat_is_made_first_and_files_are_attached_with_the_normal_code() {
        var inbox = createTemporaryObject(inboxComponent, testCase);
        queued = [item({"text": "summarise", "newChat": true, "files": ["/home/u/My Docs/a#1.pdf"]})];
        inbox.take();
        compare(fakeChat.calls.indexOf("newChat:true") >= 0, true);
        compare(fakeChat.currentSessionId, "fresh");
        compare(fakeChat.attached, ["file:///home/u/My%20Docs/a%231.pdf"]);
        compare(fakeChat.chatInputText, "summarise");
        compare(fakeChat.calls.indexOf("send:summarise"), -1, "not marked send: the message waits in the box");
        verify(fakeChat.calls.indexOf("focus") >= 0);
    }

    function test_files_only_open_the_popup_with_the_box_ready() {
        var inbox = createTemporaryObject(inboxComponent, testCase);
        queued = [item({"files": ["/tmp/report.pdf", "/tmp/photo.png"]})];
        inbox.take();
        compare(fakeChat.expanded, true);
        compare(fakeChat.attached.length, 2);
        compare(fakeChat.chatInputText, "");
    }

    function test_text_already_typed_is_kept_and_nothing_is_sent_over_it() {
        var inbox = createTemporaryObject(inboxComponent, testCase);
        fakeChat.chatInputText = "my draft";
        queued = [item({"text": "extra question", "send": true})];
        inbox.take();
        compare(fakeChat.chatInputText, "my draft\nextra question");
        wait(500);
        compare(fakeChat.calls.filter(function(c) { return c.indexOf("send:") === 0; }).length, 0);
    }

    function test_sending_waits_for_the_attached_files() {
        var inbox = createTemporaryObject(inboxComponent, testCase);
        fakeChat.filesReady = false;
        queued = [item({"text": "what is this?", "send": true, "files": ["/tmp/a.txt"]})];
        inbox.take();
        wait(600);
        compare(fakeChat.calls.indexOf("send:what is this?"), -1, "the file is still loading");
        fakeChat.filesReady = true;
        tryVerify(function() { return fakeChat.calls.indexOf("send:what is this?") >= 0; }, 3000);
    }

    function test_the_text_stays_in_the_box_when_the_user_changes_chat_while_waiting() {
        var inbox = createTemporaryObject(inboxComponent, testCase);
        fakeChat.filesReady = false;
        queued = [item({"text": "hello", "send": true, "files": ["/tmp/a.txt"]})];
        inbox.take();
        fakeChat.currentSessionId = "elsewhere";
        wait(500);
        fakeChat.filesReady = true;
        wait(500);
        compare(fakeChat.calls.filter(function(c) { return c.indexOf("send:") === 0; }).length, 0);
        compare(fakeChat.chatInputText, "hello");
    }

    function test_several_requests_are_handled_one_after_the_other() {
        var inbox = createTemporaryObject(inboxComponent, testCase);
        queued = [item({"text": "one", "send": true}), item({"text": "two", "send": true})];
        inbox.take();
        tryVerify(function() { return fakeChat.calls.indexOf("send:two") >= 0; }, 3000);
        verify(fakeChat.calls.indexOf("send:one") < fakeChat.calls.indexOf("send:two"));
    }

    function test_a_file_appearing_in_the_watched_folder_is_taken_without_polling() {
        var dir = root + "inbox-" + Date.now();
        var keep = fileComponent.createObject(null, {"location": "file://" + dir + "/keep.cfg"});
        keep.setValue("x", 1);
        keep.sync();
        keep.destroy();
        var inbox = createTemporaryObject(inboxComponent, testCase, {"directory": dir});
        tryVerify(function() { return helperCalls.length >= 1; }, 3000);   // the start-up take
        helperCalls = [];
        queued = [item({"text": "from krunner", "send": true})];
        var request = fileComponent.createObject(null, {"location": "file://" + dir + "/ask-1792998774764-ab12cd34.json"});
        request.setValue("x", 1);
        request.sync();
        request.destroy();
        tryVerify(function() { return fakeChat.calls.indexOf("send:from krunner") >= 0; }, 5000, "the new file was noticed and taken");
        compare(helperCalls[0], "ask_inbox_take");
    }

    function test_the_start_reinstalls_the_desktop_files_only_when_a_switch_is_on() {
        createTemporaryObject(inboxComponent, testCase, {"config": {"krunnerEnabled": false, "dolphinMenuEnabled": false}});
        tryVerify(function() { return helperCalls.indexOf("ask_inbox_take") >= 0; });
        compare(helperCalls.indexOf("desktop_sync"), -1);
        helperCalls = [];
        createTemporaryObject(inboxComponent, testCase, {"config": {"krunnerEnabled": true, "dolphinMenuEnabled": false, "krunnerPrefix": "ask"}});
        tryVerify(function() { return helperCalls.indexOf("desktop_sync") >= 0; });
    }
}
