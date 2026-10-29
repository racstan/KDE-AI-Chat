// chat/ScheduleInbox.qml: a scheduled run written into the chat folder's inbox
// (by kdeaichat/schedule_chat.py) shows up in the chat without any polling:
// the folder is watched, the run merged once, saved, notified, and the file removed.
import QtQuick
import QtCore
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

TestCase {
    id: testCase
    name: "ScheduleInbox"
    when: windowShown

    readonly property string root: decodeURIComponent(String(Qt.resolvedUrl("../../build/test-inbox/")).replace(/^file:\/\//, ""))

    QtObject {
        id: fakeChat
        property var sessions: []
        property var messages: []
        property string currentSessionId: "open"
        property bool loading: false
        property bool _initialLoadDone: true
        property int persisted: 0
        function sessionIndexById(id) {
            for (var i = 0; i < sessions.length; i++)
                if (sessions[i].value === id) return i;
            return -1;
        }
        function persistSessions() { persisted++; }
    }

    QtObject {
        id: fakeStore
        signal saved()
        property int flushes: 0
        function flush() { flushes++; saved(); }
    }

    QtObject {
        id: fakeNotifier
        property var sent: []
        function scheduledRan(chatId, name, text) { sent = sent.concat([{chatId: chatId, name: name, text: text}]); }
    }

    property var helperCalls: []

    Component {
        id: inboxComponent
        Chat.ScheduleInbox {
            chat: fakeChat
            notifierRef: fakeNotifier
            chatStore: fakeStore
            runHelper: function(command, payload, onDone) {
                testCase.helperCalls = testCase.helperCalls.concat([{command: command, payload: payload}]);
                if (onDone) onDone("");
            }
        }
    }

    Component {
        id: fileComponent
        Settings {}
    }

    function writeFile(dir, name, key, value) {
        var file = fileComponent.createObject(null, {"location": "file://" + dir + "/" + name});
        file.setValue(key, value);
        file.sync();
        file.destroy();
    }

    function run(runId, chatId, extra) {
        return Object.assign({"chatId": chatId, "runId": runId, "scheduleId": "news", "scheduleName": "Daily news",
                              "notify": true, "notified": false,
                              "messages": [{"role": "user", "content": "News?", "scheduleRunId": runId, "scheduled": true},
                                           {"role": "assistant", "content": "Here they are.", "scheduleRunId": runId, "scheduled": true}]},
                             extra || {});
    }

    function freshDir() {
        var dir = root + "applet-" + Date.now() + "-" + Math.floor(Math.random() * 1e6);
        writeFile(dir + "/inbox", "keep.cfg", "x", 1);   // makes the folder (Settings creates it)
        return dir;
    }

    function init() {
        helperCalls = [];
        fakeNotifier.sent = [];
        fakeChat.persisted = 0;
        fakeChat.loading = false;
        fakeChat.currentSessionId = "open";
        fakeChat.messages = [{role: "user", content: "hi"}];
        fakeChat.sessions = [{value: "open", messages: []}, {value: "other", messages: [{role: "user", content: "old"}]}];
    }

    function test_a_run_on_disk_appears_in_its_chat_without_polling() {
        var dir = freshDir();
        var inbox = createTemporaryObject(inboxComponent, testCase, {"directory": dir, "ready": true});
        verify(inbox);
        tryCompare(helperCalls, "length", 1);
        compare(helperCalls[0].command, "schedules_startup");

        writeFile(dir + "/inbox", "run-1792998774764-news.ini", "entry", JSON.stringify(run("news-1", "other")));
        tryVerify(function() { return fakeChat.sessions[1].messages.length === 3; }, 5000, "the run was merged");
        compare(fakeChat.sessions[1].messages[2].content, "Here they are.");
        compare(fakeChat.currentSessionId, "open", "the open chat is not switched");
        compare(fakeChat.messages.length, 1);
        verify(fakeChat.persisted >= 1);
        compare(fakeNotifier.sent.length, 1);
        compare(fakeNotifier.sent[0].chatId, "other");
        compare(fakeNotifier.sent[0].name, "Daily news");
        tryVerify(function() { return helperCalls.some(function(c) { return c.command === "schedule_inbox_done"; }); });
        var done = helperCalls.filter(function(c) { return c.command === "schedule_inbox_done"; })[0];
        compare(done.payload.files, ["run-1792998774764-news.ini"]);
        compare(done.payload.directory, dir);
    }

    function test_the_open_chat_waits_for_a_streaming_reply_and_merges_once() {
        var dir = freshDir();
        fakeChat.loading = true;
        var inbox = createTemporaryObject(inboxComponent, testCase, {"directory": dir, "ready": true});
        writeFile(dir + "/inbox", "run-1792998774765-news.ini", "entry", JSON.stringify(run("news-2", "open", {"notified": true})));
        wait(600);
        compare(fakeChat.messages.length, 1, "not while a reply streams in");
        fakeChat.loading = false;
        tryCompare(fakeChat.messages, "length", 3);
        compare(fakeChat.sessions[0].messages.length, 3);
        compare(fakeNotifier.sent.length, 0, "the job already notified");
        // the same run again (e.g. the file reappears): nothing is added twice
        writeFile(dir + "/inbox", "run-1792998774766-news.ini", "entry", JSON.stringify(run("news-2", "open")));
        wait(600);
        compare(fakeChat.messages.length, 3);
    }

    function test_a_new_opencode_session_is_kept_and_unknown_chats_are_dropped() {
        var dir = freshDir();
        var inbox = createTemporaryObject(inboxComponent, testCase, {"directory": dir, "ready": true});
        writeFile(dir + "/inbox", "run-1792998774767-news.ini", "entry",
                  JSON.stringify(run("news-3", "other", {"sessionUpdates": {"openCodeSessionId": "ses_9"}})));
        writeFile(dir + "/inbox", "run-1792998774768-news.ini", "entry", JSON.stringify(run("news-4", "deleted-chat")));
        tryVerify(function() { return fakeChat.sessions[1].openCodeSessionId === "ses_9"; }, 5000, "the new session id is kept");
        tryVerify(function() {
            var files = [];
            helperCalls.forEach(function(c) { if (c.command === "schedule_inbox_done") files = files.concat(c.payload.files); });
            return files.indexOf("run-1792998774768-news.ini") >= 0 && files.indexOf("run-1792998774767-news.ini") >= 0;
        });
        compare(fakeNotifier.sent.length, 1);
    }

    // A chat whose messages were never read: the job already put the run in its file and the widget
    // never writes such a chat, so only the list entry changes (and the notice is shown).
    function test_a_run_for_a_chat_that_was_not_read_updates_its_entry_only() {
        var dir = freshDir();
        fakeChat.sessions = [{value: "open", messages: []}, {value: "other", messages: [], messagesUnloaded: true, messageCount: 5, updatedAt: 1}];
        var inbox = createTemporaryObject(inboxComponent, testCase, {"directory": dir, "ready": true});
        writeFile(dir + "/inbox", "run-1792998774769-news.ini", "entry", JSON.stringify(run("news-5", "other")));
        tryVerify(function() { return fakeChat.sessions[1].messageCount === 7; }, 5000, "the count includes the run");
        compare(fakeChat.sessions[1].messages.length, 0, "its messages stay on disk");
        compare(fakeChat.sessions[1].messagesUnloaded, true);
        verify(fakeChat.sessions[1].updatedAt > 1);
        compare(fakeNotifier.sent.length, 1);
    }
}
