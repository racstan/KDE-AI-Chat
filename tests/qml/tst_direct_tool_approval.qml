// Direct mode: the model calls a tool of the tool bridge (an MCP server's tool). The real request
// code (chat/DirectRequest.qml, ToolBridge.qml, DirectToolRounds.qml, ReplyEvents.qml,
// SendController.qml, MessageEdits.qml, Notifier.qml) runs against a fake XMLHttpRequest that plays
// streamed provider replies and a fake tool bridge, with the real permission card buttons
// (chat/PermissionButtons.qml, PermissionDetail.qml): allow once, always allow, reject, stop while the
// card is pending, an unknown tool, a failing tool, a bridge that is gone or does not start.
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 480
    height: 360

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(singular, plural, count) {
        return (count === 1 ? singular : plural).replace("%1", count);
    }

    // --- Provider: a fake XMLHttpRequest that plays streamed replies -----------------------------
    property var xhrs: []
    function makeXhr() {
        var x = {"readyState": 0, "status": 0, "responseText": "", "sent": null, "aborted": false,
            "open": function() {}, "setRequestHeader": function() {},
            "send": function(body) { x.sent = JSON.parse(body); },
            "abort": function() { x.aborted = true; },
            "play": function(status, chunks) {
                x.status = status;
                for (var i = 0; i < chunks.length; i++) {
                    x.responseText += chunks[i];
                    x.readyState = 3;
                    x.onreadystatechange();
                }
                x.readyState = 4;
                x.onreadystatechange();
            }};
        root.xhrs.push(x);
        return x;
    }

    function sse(obj) { return "data: " + JSON.stringify(obj) + "\n\n"; }
    function toolStream(name, args, id) {
        var json = JSON.stringify(args);
        var cut = Math.floor(json.length / 2);
        return [sse({"choices": [{"delta": {"content": "Let me look. "}}]}),
                sse({"choices": [{"delta": {"tool_calls": [{"index": 0, "id": id || "call_1", "type": "function", "function": {"name": name, "arguments": json.substring(0, cut)}}]}}]}),
                sse({"choices": [{"delta": {"tool_calls": [{"index": 0, "function": {"arguments": json.substring(cut)}}]}}]}),
                sse({"choices": [{"delta": {}, "finish_reason": "tool_calls"}]}), "data: [DONE]\n\n"];
    }
    function textStream(text) {
        return [sse({"choices": [{"delta": {"content": text}}]}), "data: [DONE]\n\n"];
    }

    // --- The tool bridge: a fake loopback server --------------------------------------------------
    property var bridgeCalls: []        // {path, body, auth}
    property var helperCalls: []        // helper commands asked for
    property var bridgeHandler: null    // function(path, body, n) -> {status, data}; n counts the requests so far
    property string bridgeStart: "ok"   // "ok" | "error"
    readonly property var defaultTools: [{"name": "files__read", "server": "files", "description": "Read a file",
                                           "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}]

    function bridgeAnswer(path, body, n) {
        if (root.bridgeHandler) {
            var custom = root.bridgeHandler(path, body, n);
            if (custom) return custom;
        }
        if (path === "/tools")
            return {"status": 200, "data": {"tools": root.defaultTools, "errors": []}};
        return {"status": 200, "data": {"output": "file contents", "isError": false}};
    }
    function makeBridgeXhr() {
        var x = {"readyState": 0, "status": 0, "responseText": "", "url": "", "auth": "", "timeout": 0,
            "open": function(method, url) { x.url = url; },
            "setRequestHeader": function(name, value) { if (name === "Authorization") x.auth = value; },
            "send": function(body) {
                var path = x.url.replace(/^http:\/\/127\.0\.0\.1:\d+/, "");
                var parsed = JSON.parse(body);
                root.bridgeCalls.push({"path": path, "body": parsed, "auth": x.auth, "timeout": x.timeout});
                var answer = root.bridgeAnswer(path, parsed, root.bridgeCalls.length);
                x.status = answer.status;
                x.responseText = JSON.stringify(answer.data || {});
                x.readyState = 4;
                x.onreadystatechange();
            }};
        return x;
    }
    function fakeHelper(command, payload, onDone) {
        root.helperCalls.push(command);
        var port = 40000 + root.helperCalls.length;
        onDone(root.bridgeStart === "ok" ? JSON.stringify({"status": "started", "port": port, "token": "tok" + port})
                                          : JSON.stringify({"status": "error", "message": "No python for the bridge."}));
    }

    // The widget root, as far as these modules use it.
    QtObject {
        id: chat
        property var plasmoid: QtObject { property var configuration: ({"contextMessageLimit": -1, "enableSystemPrompt": false, "disableStreaming": false, "requestTimeout": 0}) }
        property var sessions: [{"value": "s1", "messages": []}]
        property string currentSessionId: "s1"
        property string currentSessionTitle: "Files"
        property var messages: []
        property bool loading: false
        property var activeXhr: null
        property int requestGeneration: 0
        property string activeRequestSessionId: ""
        property string compiledSystemPrompt: ""
        property string currentStreamKey: ""
        property int currentStreamIndex: -1
        property string currentStreamText: ""
        property string currentStreamReasoning: ""
        property string currentStreamExtractedReasoning: ""
        property bool streamingResponse: false
        property var currentStreamUsage: ({})
        property var walletApiKeys: ({})
        property var wallet: QtObject { property bool usable: true }
        property string chatInputText: ""
        property var attachedFiles: []
        property var promptTemplates: []
        property int sent: 0
        property int saves: 0
        property var errors: []
        property var streamBuffer: Chat.StreamBuffer { target: chat; maxChars: 2000000 }
        property var imageStore: QtObject {
            function hasImages(message) { return false; }
            function takeInlineImages(sessionId, reply) { return reply; }
            function addFromReply() {}
        }
        signal clearChatInput()
        onMessagesChanged: {
            if (chat.currentStreamIndex >= 0)
                chat.currentStreamIndex = indexOfId(chat.currentStreamKey);
        }
        function indexOfId(id) {
            for (var i = 0; i < messages.length; i++)
                if (messages[i].id === id) return i;
            return -1;
        }
        function sessionIndexById(id) { return 0; }
        function switchSession(id) {}
        function getSessionProperty(id, key, fallback) { return fallback; }
        function effectiveConfig(id) { return {"mode": "provider", "variant": "", "direct": {"provider": "p", "model": ""}}; }
        function requestIsCurrent(s, g) { return sender.requestIsCurrent(s, g); }
        function applyBackendEvent(e, m, x) { replies.applyBackendEvent(e, m, x); }
        function updateMessageAt(i, f) { replies.updateMessageAt(i, f); }
        function findRequestMessage(r, f, id) { return replies.findRequestMessage(r, f, id); }
        function resetProviderStreamingState() { replies.resetProviderStreamingState(); }
        function saveCurrentSessionState(t) { saves++; }
        function pushErrorMessage(t) { errors = errors.concat([t]); }
        function triggerNotificationSound() {}
        function maybeGenerateChatTitle() {}
        function processNextQueuedMessage() {}
        function invalidateActiveRequest(p) { sender.invalidateActiveRequest(p); }
        function stopStreaming() { sender.stopStreaming(); }
        function scrollToBottom() {}
        function ensureWalletLoaded() {}
        function attachmentsReadyToSend() { return true; }
        function cleanupTemporaryAttachment(p) {}
        function nameChatFromFirstMessage(t) {}
        property bool openCodeMode: false
        property bool piMode: false
        function applySessionSource(s) {}
        function setCurrentSessionSource() {}
        function getEffectiveProvider(id) { return "p"; }
        function getProviderConfig(p, id) { return root.cfg; }
        function providerDisplayName(id) { return "Provider"; }
        function doDirectRequest(c, s, g) { sent++; }
        function respondToPermission(id, approved, always) { edits.respondToPermission(id, approved, always); }
        function respondToQuestion(id, v, reject) { edits.respondToQuestion(id, v, reject); }
    }

    Chat.ReplyEvents {
        id: replies
        chat: chat
        notifierRef: QtObject {
            property var needed: []
            function replyFinished() {}
            function failed() {}
            function inputNeeded(chatId, title, message) { needed = needed.concat([message]); }
            function inputResolved() {}
        }
    }
    Chat.DirectRequest {
        id: direct
        chat: chat
        xhrFactory: root.makeXhr
        toolXhrFactory: root.makeBridgeXhr
        Component.onCompleted: toolBridge.runHelper = root.fakeHelper
    }
    Chat.SendController {
        id: sender
        chat: chat
        notifierRef: QtObject { function failed() {} }
        directToolsRef: direct.toolRounds
    }
    Chat.MessageEdits {
        id: edits
        chat: chat
        directToolsRef: direct.toolRounds
    }
    Chat.Notifier { id: notifier }

    readonly property var cfg: ({"type": "openai-compat", "baseUrl": "https://api.test/v1", "apiKey": "k", "model": "test-model", "headers": {}})

    // The newest permission card message.
    readonly property var permissionMessage: {
        var list = chat.messages;
        for (var i = list.length - 1; i >= 0; i--)
            if (list[i].role === "permission_request") return list[i];
        return ({});
    }

    Column {
        width: 400
        Chat.PermissionDetail { id: detail; width: parent.width; message: root.permissionMessage }
        Chat.PermissionButtons {
            id: buttons
            width: parent.width
            message: root.permissionMessage
            onAnswered: (approved, always) => chat.respondToPermission(root.permissionMessage.permissionId, approved, always)
        }
    }

    HarnessTestCase {
        id: tc
        name: "DirectToolApproval"

        function init() {
            root.xhrs = [];
            root.bridgeCalls = [];
            root.helperCalls = [];
            root.bridgeHandler = null;
            root.bridgeStart = "ok";
            chat.messages = [{"id": "u1", "role": "user", "content": "Read my notes", "at": 1}];
            chat.loading = false;
            chat.currentStreamIndex = -1;
            chat.currentStreamText = "";
            chat.currentStreamReasoning = "";
            chat.errors = [];
            chat.sent = 0;
            chat.plasmoid.configuration.allowAskUser = true;
            chat.plasmoid.configuration.toolServers = "{\"files\": {\"command\": \"x\"}}";
            chat.plasmoid.configuration.webSearchProvider = "none";
            chat.plasmoid.configuration.searxngUrl = "";
            chat.plasmoid.configuration.webFetchEnabled = false;
            chat.plasmoid.configuration.toolsAlwaysAllowed = "[]";
            direct.toolBridge.connection = null;
            direct.toolBridge._loadedKey = "";
            direct.toolBridge.tools = [];
            direct.toolBridge.errors = [];
            direct.toolRounds.pending = null;
            replies.notifierRef.needed = [];
        }

        function start() {
            var generation = sender.beginRequest("s1");
            direct.sendDirectRequest(Object.assign({}, root.cfg), "s1", generation, {});
        }

        function findButton(item, text) {
            if (!item) return null;
            if (item.text === text && item.clicked !== undefined && item.visible) return item;
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++) {
                var found = findButton(kids[i], text);
                if (found) return found;
            }
            return null;
        }
        function press(text) {
            // The card was just added: let its buttons take their places before clicking.
            wait(50);
            var b = findButton(buttons, text);
            verify(b, "button " + text);
            mouseClick(b);
        }
        function roles() { return chat.messages.map(function(m) { return m.role; }); }
        function callsTo(path) { return root.bridgeCalls.filter(function(c) { return c.path === path; }); }

        // The model calls files__read; the card is up.
        function callAndWait(args, name) {
            start();
            compare(root.xhrs.length, 1);
            root.xhrs[0].play(200, root.toolStream(name || "files__read", args || {"path": "/notes.txt"}));
        }

        function test_nothing_starts_when_no_tools_are_configured() {
            chat.plasmoid.configuration.toolServers = "";
            start();
            compare(root.helperCalls.length, 0);
            compare(root.bridgeCalls.length, 0);
            verify(!direct.toolBridge.isEnabled());
            var tools = root.xhrs[0].sent.tools;
            compare(tools.length, 1);
            compare(tools[0].function.name, "ask_user");
        }

        function test_the_bridge_tools_are_offered_after_ask_user() {
            callAndWait();
            compare(root.helperCalls.length, 1);
            compare(root.helperCalls[0], "tools_bridge_start");
            var load = callsTo("/tools");
            compare(load.length, 1);
            compare(load[0].auth, "Bearer tok40001");
            compare(load[0].timeout, 60000);
            compare(load[0].body.servers.files.command, "x");
            compare(load[0].body.web.search, "none");
            compare(load[0].body.web.fetch, false);
            var tools = root.xhrs[0].sent.tools;
            compare(tools.map(function(t) { return t.function.name; }), ["ask_user", "files__read"]);
            compare(tools[1].function.parameters.required, ["path"]);
        }

        function test_allow_once_runs_the_tool_and_asks_again_next_time() {
            callAndWait();
            compare(root.permissionMessage.status, "pending");
            compare(roles().join(","), "user,assistant,permission_request");
            var card = root.permissionMessage;
            compare(card.harness, "direct");
            compare(card.tool, "files__read");
            compare(card.canAlways, true);
            compare(JSON.parse(card.arguments[0]).path, "/notes.txt");
            compare(callsTo("/call").length, 0, "nothing runs before the user answers");
            verify(findButton(buttons, "Always allow"));
            // With the popup closed this is what sends the "Input needed" notification.
            compare(replies.notifierRef.needed.length, 1);
            compare(replies.notifierRef.needed[0].role, "permission_request");
            tc.screenshot(root, "direct-tool-approval-pending");

            press("Allow");
            compare(root.permissionMessage.status, "allowed");
            var run = callsTo("/call");
            compare(run.length, 1);
            compare(run[0].body.name, "files__read");
            compare(run[0].body.arguments.path, "/notes.txt");
            compare(run[0].timeout, 150000);
            compare(root.xhrs.length, 2);
            var sent = root.xhrs[1].sent.messages;
            compare(sent.map(function(m) { return m.role; }).join(","), "user,assistant,tool");
            compare(sent[1].tool_calls[0].function.name, "files__read");
            compare(sent[2].content, "file contents");
            root.xhrs[1].play(200, root.textStream("It says hello."));
            compare(chat.messages[1].tools["call_1"].status, "done");
            compare(chat.messages[1].tools["call_1"].output, "file contents");
            compare(chat.plasmoid.configuration.toolsAlwaysAllowed, "[]", "Allow is for this call only");
            verify(!chat.loading);

            // The same tool again: asks again.
            chat.messages = chat.messages.concat([{"id": "u2", "role": "user", "content": "again", "at": 2}]);
            root.xhrs = [];
            start();
            root.xhrs[0].play(200, root.toolStream("files__read", {"path": "/b"}, "call_9"));
            compare(root.permissionMessage.status, "pending");
            compare(roles()[roles().length - 1], "permission_request");
        }

        function test_always_allow_is_remembered_and_the_next_call_runs_without_a_card() {
            callAndWait();
            press("Always allow");
            compare(root.permissionMessage.status, "allowed");
            compare(JSON.parse(chat.plasmoid.configuration.toolsAlwaysAllowed), ["files__read"]);
            compare(callsTo("/call").length, 1);
            root.xhrs[1].play(200, root.textStream("Done."));

            chat.messages = chat.messages.concat([{"id": "u2", "role": "user", "content": "again", "at": 2}]);
            root.xhrs = [];
            start();
            root.xhrs[0].play(200, root.toolStream("files__read", {"path": "/b"}, "call_2"));
            var cards = chat.messages.filter(function(m) { return m.role === "permission_request"; });
            compare(cards.length, 1, "no second card");
            compare(callsTo("/call").length, 2);
            compare(root.xhrs.length, 2, "the round went on at once");
            compare(root.xhrs[1].sent.messages[root.xhrs[1].sent.messages.length - 1].content, "file contents");
        }

        function test_reject_tells_the_model_and_the_round_goes_on() {
            callAndWait();
            press("Reject");
            compare(root.permissionMessage.status, "denied");
            compare(callsTo("/call").length, 0);
            compare(root.xhrs.length, 2);
            var last = root.xhrs[1].sent.messages[2];
            compare(last.content, "The user rejected this tool call.");
            compare(chat.messages[1].tools["call_1"].status, "error");
            root.xhrs[1].play(200, root.textStream("Okay, I won't."));
            verify(!chat.loading);
            compare(chat.plasmoid.configuration.toolsAlwaysAllowed, "[]");
        }

        function test_stop_while_the_card_is_pending_ends_it() {
            callAndWait();
            compare(root.permissionMessage.status, "pending");
            chat.stopStreaming();
            compare(root.permissionMessage.status, "denied");
            verify(!chat.loading);
            compare(root.xhrs.length, 1, "no further request");
            compare(callsTo("/call").length, 0);
            compare(chat.messages[1].tools["call_1"].output, "The user did not answer.");
            var history = direct.buildDirectRequestParts("s1", "openai", true).messages;
            compare(history.map(function(m) { return m.role; }).join(","), "user,assistant,tool");
            // A late answer to the closed card does nothing.
            chat.respondToPermission(root.permissionMessage.permissionId, true, false);
            compare(callsTo("/call").length, 0);
            compare(root.xhrs.length, 1);
        }

        function test_writing_a_message_instead_of_answering_stops_and_sends_it() {
            callAndWait();
            chat.chatInputText = "Never mind";
            sender.sendMessage();
            compare(root.permissionMessage.status, "denied");
            compare(root.xhrs.length, 1);
            compare(chat.messages[chat.messages.length - 1].content, "Never mind");
            compare(chat.sent, 1);
            compare(callsTo("/call").length, 0);
        }

        function test_an_answer_to_a_card_left_over_from_an_earlier_run_closes_it() {
            chat.messages = chat.messages.concat([{"id": "perm-old", "role": "permission_request", "permissionId": "direct-old", "status": "pending",
                                                   "harness": "direct", "tool": "files__read", "arguments": ["{}"], "canAlways": true}]);
            chat.respondToPermission("direct-old", true, false);
            compare(root.permissionMessage.status, "denied");
            compare(callsTo("/call").length, 0);
        }

        function test_an_unknown_tool_lists_what_is_available() {
            start();
            root.xhrs[0].play(200, root.toolStream("nope", {}, "c1"));
            compare(root.xhrs.length, 2);
            var text = root.xhrs[1].sent.messages[2].content;
            verify(text.indexOf("Unknown tool: nope") >= 0, text);
            verify(text.indexOf("ask_user") >= 0 && text.indexOf("files__read") >= 0, text);
            compare(chat.messages[1].tools["c1"].status, "error");
            compare(roles().indexOf("permission_request"), -1);
        }

        function test_an_error_from_the_tool_reaches_the_model() {
            root.bridgeHandler = function(path) {
                return path === "/call" ? {"status": 200, "data": {"output": "ENOENT: no such file", "isError": true}} : null;
            };
            callAndWait();
            press("Allow");
            compare(root.xhrs[1].sent.messages[2].content, "ENOENT: no such file");
            compare(chat.messages[1].tools["call_1"].status, "error");
            compare(chat.messages[1].tools["call_1"].output, "ENOENT: no such file");
        }

        function test_a_bridge_that_is_gone_is_restarted_and_the_call_tried_again() {
            var calls = 0;
            root.bridgeHandler = function(path) {
                if (path !== "/call") return null;
                calls++;
                return calls === 1 ? {"status": 404, "data": {"error": "unknown tool"}} : null;
            };
            callAndWait();
            press("Allow");
            compare(root.helperCalls, ["tools_bridge_start", "tools_bridge_start"], "the bridge was started again");
            compare(callsTo("/tools").length, 2, "the configuration was sent again");
            compare(callsTo("/call").length, 2);
            compare(callsTo("/call")[1].auth, "Bearer tok40002", "with the new token");
            compare(root.xhrs[1].sent.messages[2].content, "file contents");
        }

        function test_a_connection_error_is_retried_only_once() {
            root.bridgeHandler = function(path) { return path === "/call" ? {"status": 0, "data": {}} : null; };
            callAndWait();
            press("Allow");
            compare(callsTo("/call").length, 2);
            compare(chat.messages[1].tools["call_1"].status, "error");
            verify(root.xhrs[1].sent.messages[2].content.indexOf("did not answer") >= 0);
        }

        function test_a_bridge_that_does_not_start_never_blocks_the_chat() {
            root.bridgeStart = "error";
            start();
            compare(root.xhrs.length, 1, "the request still goes out");
            compare(root.xhrs[0].sent.tools.length, 1);
            compare(root.xhrs[0].sent.tools[0].function.name, "ask_user");
            root.xhrs[0].play(200, root.textStream("Hello."));
            var notices = chat.messages[1].notices || [];
            compare(notices.length, 1);
            verify(notices[0].indexOf("No python for the bridge.") >= 0, notices[0]);
            compare(chat.messages[1].content, "Hello.");
        }

        function test_a_server_that_fails_is_named_in_one_notice_and_the_rest_still_work() {
            root.bridgeHandler = function(path) {
                return path === "/tools" ? {"status": 200, "data": {"tools": root.defaultTools, "errors": [{"server": "broken", "message": "it exited"}]}} : null;
            };
            start();
            compare(root.xhrs[0].sent.tools.length, 2);
            root.xhrs[0].play(200, root.textStream("Hi."));
            var notices = chat.messages[1].notices || [];
            compare(notices.length, 1);
            verify(notices[0].indexOf("broken: it exited") >= 0, notices[0]);
            // The list is cached: the next message neither asks the bridge nor repeats the notice.
            chat.messages = chat.messages.concat([{"id": "u2", "role": "user", "content": "more", "at": 2}]);
            root.xhrs = [];
            start();
            compare(callsTo("/tools").length, 1);
            root.xhrs[0].play(200, root.textStream("Again."));
            compare((chat.messages[chat.messages.length - 1].notices || []).length, 0);
        }

        function test_changed_settings_load_the_list_again() {
            start();
            root.xhrs[0].play(200, root.textStream("a"));
            compare(callsTo("/tools").length, 1);
            chat.plasmoid.configuration.webFetchEnabled = true;
            chat.messages = chat.messages.concat([{"id": "u2", "role": "user", "content": "more", "at": 2}]);
            root.xhrs = [];
            start();
            var load = callsTo("/tools");
            compare(load.length, 2);
            compare(load[1].body.web.fetch, true);
        }

        function test_bad_json_in_the_settings_sends_no_servers_and_reports_it() {
            chat.plasmoid.configuration.toolServers = "{ nope";
            chat.plasmoid.configuration.webFetchEnabled = true;
            start();
            compare(callsTo("/tools")[0].body.servers, {});
            root.xhrs[0].play(200, root.textStream("x"));
            var notices = chat.messages[1].notices || [];
            compare(notices.length, 1);
            verify(notices[0].indexOf("not valid JSON") >= 0, notices[0]);
        }

        // The notification of the card: Allow / Deny when the whole call shows, otherwise it only opens the chat.
        function test_the_notification_offers_allow_and_deny_for_a_short_call() {
            callAndWait({"path": "/a"});
            var spec = notifier.inputSpec("s1", "Files", root.permissionMessage);
            compare(spec.kind, "permission");
            compare(spec.id, root.permissionMessage.permissionId);
            compare(spec.actions.map(function(a) { return a.label; }), ["Allow", "Deny"]);
            verify(spec.text.indexOf("files__read") >= 0);
            // Answering on the notification goes where the card's answer goes.
            notifier.chat = chat;
            verify(notifier.answerInput(spec, true));
            compare(root.permissionMessage.status, "allowed");
            compare(callsTo("/call").length, 1);
        }

        function test_the_notification_only_opens_the_chat_for_a_long_call() {
            callAndWait({"text": "y".repeat(400)});
            var spec = notifier.inputSpec("s1", "Files", root.permissionMessage);
            compare(spec.actions.length, 1);
            verify(spec.actions[0].open === true);
        }
    }
}
