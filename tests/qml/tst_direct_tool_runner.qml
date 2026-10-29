// Direct mode: tools besides ask_user (chat/DirectToolRunner.qml). The real request code
// (DirectRequest, DirectToolRounds, DirectToolRunner, ReplyEvents, SendController, MessageEdits)
// runs against a fake XMLHttpRequest, with a fake tool provider and runner plugged in the way
// MCP, skills and workspace tools will be, a fake helper for the remembered approvals, and the real
// chat/PermissionButtons.qml answering: read tools run at once, change tools ask first,
// Allow / Always / Deny, stop, a tool that hangs, a long result, and the no-providers case.
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 480
    height: 200

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

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
    function callStream(name, args, id) {
        return [sse({"choices": [{"delta": {"content": "Let me look. "}}]}),
                sse({"choices": [{"delta": {"tool_calls": [{"index": 0, "id": id || "call_1", "type": "function", "function": {"name": name, "arguments": JSON.stringify(args || {})}}]}}]}),
                sse({"choices": [{"delta": {}, "finish_reason": "tool_calls"}]}), "data: [DONE]\n\n"];
    }
    function textStream(text) {
        return [sse({"choices": [{"delta": {"content": text}}]}), "data: [DONE]\n\n"];
    }

    // What the fake runner ran, and what the fake helper was asked.
    property var ran: []
    property var helperCalls: []
    property var storedKeys: []
    property bool helperFails: false

    // The widget root, as far as these modules use it.
    QtObject {
        id: chat
        property var plasmoid: QtObject { property var configuration: ({"contextMessageLimit": -1, "enableSystemPrompt": false, "disableStreaming": false, "requestTimeout": 0}) }
        property var sessions: [{"value": "s1", "messages": []}]
        property string currentSessionId: "s1"
        property string currentSessionTitle: "Tools"
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
        property var errors: []
        property var streamBuffer: Chat.StreamBuffer { target: chat; maxChars: 2000000 }
        property var imageStore: QtObject {
            function hasImages(message) { return false; }
            function takeInlineImages(sessionId, reply) { return reply; }
            function addFromReply() {}
        }
        // The helper (kdeaichat/tool_approvals.py) as far as the runner uses it.
        property var store: QtObject {
            function runHelper(command, payload, onDone) {
                root.helperCalls = root.helperCalls.concat([command + " " + JSON.stringify(payload)]);
                if (root.helperFails) {
                    onDone("", 1, "failed");
                    return;
                }
                if (command === "tool_approvals_add" && root.storedKeys.indexOf(payload.key) < 0)
                    root.storedKeys = root.storedKeys.concat([payload.key]);
                onDone(JSON.stringify({"keys": root.storedKeys}), 0, "");
            }
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
        function saveCurrentSessionState(t) {}
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
            id: notice
            function replyFinished() {}
            function failed() {}
            property var needed: []
            function inputNeeded(chatId, title, message) { needed = needed.concat([message.role + ":" + (message.permissionId || message.questionId)]); }
            function inputResolved() {}
        }
    }
    Chat.DirectRequest {
        id: direct
        chat: chat
        xhrFactory: root.makeXhr
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

    readonly property var cfg: ({"type": "openai-compat", "baseUrl": "https://api.test/v1", "apiKey": "k", "model": "test-model", "headers": {}})

    // The newest permission card message.
    readonly property var permissionMessage: {
        var list = chat.messages;
        for (var i = list.length - 1; i >= 0; i--)
            if (list[i].role === "permission_request") return list[i];
        return ({});
    }

    Chat.PermissionButtons {
        id: buttons
        width: 400
        x: 10
        y: 10
        message: root.permissionMessage
        onAnswered: (approved, always) => chat.respondToPermission(root.permissionMessage.permissionId, approved, always)
    }

    HarnessTestCase {
        id: tc
        name: "DirectToolRunner"

        readonly property var runner: direct.toolRounds.runner

        function init() {
            root.xhrs = [];
            root.ran = [];
            root.helperCalls = [];
            root.storedKeys = [];
            root.helperFails = false;
            chat.currentSessionId = "s1";
            chat.messages = [{"id": "u1", "role": "user", "content": "Do something", "at": 1}];
            chat.loading = false;
            chat.currentStreamIndex = -1;
            chat.currentStreamText = "";
            chat.currentStreamReasoning = "";
            chat.errors = [];
            chat.sent = 0;
            chat.plasmoid.configuration.allowAskUser = true;
            chat.plasmoid.configuration.directToolMaxRounds = undefined;
            notice.needed = [];
            direct.toolRounds.pending = null;
            runner.pending = null;
            runner.toolProviders = [];
            runner.timeoutMs = 60000;
            runner.providerTimeoutMs = 2000;
            runner._runners = ({});
            runner._approvals = null;
        }

        // Plugs in a provider of two workspace tools and a runner for them, the way a later piece does.
        function plugIn(extra) {
            var tools = [
                {"name": "read_file", "description": "Reads a file.", "schema": {"type": "object", "properties": {"path": {"type": "string"}}}, "risk": "read", "folder": "/w"},
                {"name": "write_file", "description": "Writes a file.", "schema": {"type": "object", "properties": {"path": {"type": "string"}}}, "risk": "change", "folder": "/w"}
            ].concat(extra || []);
            runner.registerProvider({"source": "workspace", "tools": function(sessionId, cb) { cb(tools); }});
            runner.registerRunner("workspace", function(call, entry, done) {
                root.ran = root.ran.concat([call.name + " " + JSON.stringify(call.args)]);
                done("ran " + call.name);
            });
        }

        function start(sessionId) {
            var generation = sender.beginRequest(sessionId || "s1");
            direct.sendDirectRequest(Object.assign({}, root.cfg), sessionId || "s1", generation, {});
        }

        // The card was just added: let it lay out before clicking.
        function press(name) {
            waitForRendering(root);
            mouseClick(findChild(buttons, name));
        }

        function roles() { return chat.messages.map(function(m) { return m.role; }); }
        function toolNames(i) { return root.xhrs[i].sent.tools.map(function(t) { return t.function.name; }); }

        function callAndWait(name, args, id) {
            start();
            root.xhrs[0].play(200, root.callStream(name, args, id));
        }

        function test_without_providers_the_request_is_the_same_as_before() {
            start();
            compare(root.xhrs.length, 1, "sent at once");
            compare(toolNames(0).join(), "ask_user");
            root.xhrs[0].play(200, root.callStream("nope", {}));
            compare(root.xhrs.length, 2);
            compare(root.xhrs[1].sent.messages[2].content, "Unknown tool: nope. Only ask_user is available.");
            compare(root.helperCalls.length, 0);
            compare(roles().join(), "user,assistant");
        }

        function test_providers_add_their_tools_to_the_request() {
            plugIn();
            start();
            compare(toolNames(0).join(), "ask_user,read_file,write_file");
            compare(root.xhrs[0].sent.tools[1].function.description, "Reads a file.");
        }

        function test_a_read_tool_runs_without_asking() {
            plugIn();
            callAndWait("read_file", {"path": "a.txt"});
            compare(root.xhrs.length, 2);
            compare(root.ran.join(), 'read_file {"path":"a.txt"}');
            compare(roles().join(), "user,assistant", "no card");
            compare(root.xhrs[1].sent.messages[2].content, "ran read_file");
            compare(root.helperCalls.length, 0, "nothing to look up for a read tool");
            root.xhrs[1].play(200, root.textStream("Done."));
            compare(chat.messages[1].tools["call_1"].status, "done");
            verify(!chat.loading);
        }

        function test_a_change_tool_shows_the_card_and_runs_on_allow() {
            plugIn();
            callAndWait("write_file", {"path": "a.txt"});
            compare(root.xhrs.length, 1, "waiting for the answer");
            compare(root.ran.length, 0);
            var card = root.permissionMessage;
            compare(card.status, "pending");
            compare(card.harness, "direct");
            compare(card.tool, "write_file");
            compare(card.arguments.join(), '{"path":"a.txt"}');
            compare(card.canAlways, true);
            verify(chat.loading);
            compare(notice.needed.length, 1);
            verify(notice.needed[0].indexOf("permission_request:tool-") === 0);
            press("allowButton");
            compare(root.permissionMessage.status, "allowed");
            compare(root.ran.join(), 'write_file {"path":"a.txt"}');
            compare(root.xhrs.length, 2);
            compare(root.xhrs[1].sent.messages[2].content, "ran write_file");
            compare(root.helperCalls.filter(function(c) { return c.indexOf("tool_approvals_add") === 0; }).length, 0, "Allow once remembers nothing");
            root.xhrs[1].play(200, root.textStream("Written."));
            compare(roles().join(), "user,assistant,permission_request,assistant");
            tc.screenshot(root, "direct-tool-approved");
        }

        function test_deny_tells_the_model_and_does_not_run() {
            plugIn();
            callAndWait("write_file", {"path": "a.txt"});
            press("rejectButton");
            compare(root.permissionMessage.status, "denied");
            compare(root.ran.length, 0);
            compare(root.xhrs.length, 2);
            compare(root.xhrs[1].sent.messages[2].content, "The user denied this tool call.");
            compare(chat.messages[1].tools["call_1"].status, "error");
        }

        function test_always_is_remembered_and_the_second_call_does_not_ask() {
            plugIn();
            callAndWait("write_file", {"path": "a.txt"});
            tc.screenshot(root, "direct-tool-pending");
            press("alwaysAllowButton");
            compare(root.helperCalls.filter(function(c) { return c.indexOf("tool_approvals_add") === 0; }).join(),
                    'tool_approvals_add {"key":"workspace:/w:write_file"}');
            compare(root.storedKeys.join(), "workspace:/w:write_file");
            compare(root.ran.length, 1);
            // The model calls it again in the next round: no card this time.
            root.xhrs[1].play(200, root.callStream("write_file", {"path": "b.txt"}, "call_2"));
            compare(root.xhrs.length, 3);
            compare(root.ran.length, 2);
            compare(chat.messages.filter(function(m) { return m.role === "permission_request"; }).length, 1);
        }

        function test_a_remembered_approval_from_an_earlier_session_skips_the_card() {
            root.storedKeys = ["workspace:/w:write_file"];
            plugIn();
            callAndWait("write_file", {"path": "a.txt"});
            compare(root.xhrs.length, 2);
            compare(root.ran.length, 1);
            compare(roles().join(), "user,assistant");
            // Another folder's approval doesn't count.
            root.storedKeys = ["workspace:/other:write_file"];
            runner._approvals = null;
            root.xhrs = [];
            chat.messages = [{"id": "u2", "role": "user", "content": "again", "at": 2}];
            callAndWait("write_file", {"path": "c.txt"}, "call_9");
            compare(root.permissionMessage.status, "pending");
            compare(root.xhrs.length, 1);
        }

        function test_an_incognito_chat_never_remembers() {
            chat.currentSessionId = "s-incognito-1";
            chat.messages = [{"id": "u1", "role": "user", "content": "secret", "at": 1}];
            plugIn();
            start("s-incognito-1");
            root.xhrs[0].play(200, root.callStream("write_file", {}));
            compare(root.permissionMessage.canAlways, false);
            verify(!findChild(buttons, "alwaysAllowButton").visible);
            // Even an "always" that arrives anyway (a notification) only allows once.
            chat.respondToPermission(root.permissionMessage.permissionId, true, true);
            compare(root.ran.length, 1);
            compare(root.helperCalls.filter(function(c) { return c.indexOf("tool_approvals_add") === 0; }).length, 0);
        }

        function test_mcp_tools_ask_until_always_allowed_and_get_safe_names() {
            runner.registerProvider({"source": "mcp:my server", "tools": function(sessionId, cb) {
                cb([{"name": "search docs", "description": "Searches.", "risk": "read"}]);
            }});
            runner.registerRunner("mcp", function(call, entry, done) {
                root.ran = root.ran.concat([entry.server + "/" + call.name]);
                done("found");
            });
            start();
            compare(toolNames(0).join(), "ask_user,mcp__my_server__search_docs");
            root.xhrs[0].play(200, root.callStream("mcp__my_server__search_docs", {"q": "x"}));
            compare(root.permissionMessage.tool, "mcp__my_server__search_docs", "a read tool of an MCP server asks too");
            compare(root.ran.length, 0);
            chat.respondToPermission(root.permissionMessage.permissionId, true, true);
            compare(root.ran.join(), "my server/search docs", "the runner gets the real names");
            compare(root.storedKeys.join(), "mcp:my server:search docs");
        }

        function test_stopping_cancels_a_waiting_approval() {
            plugIn();
            callAndWait("write_file", {"path": "a.txt"});
            compare(root.permissionMessage.status, "pending");
            chat.stopStreaming();
            compare(root.permissionMessage.status, "denied");
            verify(!chat.loading);
            compare(runner.pending, null);
            compare(root.ran.length, 0);
            compare(root.xhrs.length, 1, "no further request");
            compare(chat.messages[1].tools["call_1"].output, "The user stopped the request before approving this tool call.");
            var history = direct.buildDirectRequestParts("s1", "openai", true).messages;
            compare(history.map(function(m) { return m.role; }).join(","), "user,assistant,tool");
            // A late click on the old card does nothing.
            chat.respondToPermission(root.permissionMessage.permissionId, true, false);
            compare(root.ran.length, 0);
            compare(root.xhrs.length, 1);
        }

        function test_writing_something_else_cancels_a_waiting_approval() {
            plugIn();
            callAndWait("write_file", {"path": "a.txt"});
            chat.chatInputText = "Never mind";
            sender.sendMessage();
            compare(root.permissionMessage.status, "denied");
            compare(root.ran.length, 0);
            compare(root.xhrs.length, 1);
            compare(chat.messages[chat.messages.length - 1].content, "Never mind");
            compare(chat.sent, 1);
        }

        function test_a_tool_that_never_answers_times_out() {
            plugIn();
            runner.timeoutMs = 40;
            runner.registerRunner("workspace", function(call, entry, done) { root.ran = root.ran.concat(["hung"]); });
            callAndWait("read_file", {});
            tryCompare(root.xhrs, "length", 2, 3000);
            verify(root.xhrs[1].sent.messages[2].content.indexOf("did not answer within") >= 0);
            compare(chat.messages[1].tools["call_1"].status, "error");
        }

        function test_a_tool_that_throws_gives_an_error_result() {
            plugIn();
            runner.registerRunner("workspace", function(call, entry, done) { throw new Error("boom"); });
            callAndWait("read_file", {});
            compare(root.xhrs.length, 2);
            verify(root.xhrs[1].sent.messages[2].content.indexOf("boom") >= 0);
        }

        function test_a_long_result_is_cut_with_a_note() {
            plugIn();
            runner.registerRunner("workspace", function(call, entry, done) { done("x".repeat(40000)); });
            callAndWait("read_file", {});
            var content = root.xhrs[1].sent.messages[2].content;
            verify(content.length < 33500, "cut, got " + content.length);
            verify(content.indexOf("The result was cut") >= 0);
            verify(content.indexOf("x".repeat(32768)) === 0);
        }

        function test_a_slow_provider_does_not_block_the_chat() {
            runner.providerTimeoutMs = 40;
            runner.registerProvider({"source": "slow", "tools": function(sessionId, cb) {}});
            start();
            compare(root.xhrs.length, 0, "waiting for the provider");
            verify(chat.loading);
            tryCompare(root.xhrs, "length", 1, 3000);
            compare(toolNames(0).join(), "ask_user");
        }

        function test_one_provider_failing_leaves_the_others() {
            plugIn();
            runner.registerProvider({"source": "broken", "tools": function(sessionId, cb) { throw new Error("no"); }});
            start();
            compare(toolNames(0).join(), "ask_user,read_file,write_file");
        }

        function test_a_tool_with_no_runner_gets_an_error_result() {
            plugIn();
            runner.unregisterRunner("workspace");
            callAndWait("read_file", {});
            compare(root.xhrs.length, 2);
            verify(root.xhrs[1].sent.messages[2].content.indexOf("nothing is set up to run it") >= 0);
        }

        function test_an_unknown_tool_lists_the_available_ones() {
            plugIn();
            callAndWait("delete_everything", {});
            verify(root.xhrs[1].sent.messages[2].content.indexOf("Available tools: ask_user, read_file, write_file.") >= 0);
        }

        function test_stopping_while_providers_are_asked_sends_nothing() {
            var answer = null;
            runner.registerProvider({"source": "late", "tools": function(sessionId, cb) { answer = cb; }});
            start();
            chat.stopStreaming();
            answer([{"name": "x", "source": "late", "risk": "read"}]);
            compare(root.xhrs.length, 0);
            verify(!chat.loading);
        }

        function test_the_round_limit_is_a_setting() {
            plugIn();
            chat.plasmoid.configuration.directToolMaxRounds = 1;
            callAndWait("read_file", {});
            compare(root.xhrs.length, 2);
            root.xhrs[1].play(200, root.callStream("read_file", {}, "call_2"));
            compare(root.xhrs.length, 2, "no third request");
            verify(chat.messages[chat.messages.length - 1].content.indexOf("Stopped: the AI asked for too many tools") >= 0);
        }

        function test_failing_to_remember_says_so_and_still_runs_the_tool() {
            plugIn();
            callAndWait("write_file", {});
            root.helperFails = true;
            runner._approvals = [];
            chat.respondToPermission(root.permissionMessage.permissionId, true, true);
            compare(root.ran.length, 1);
            compare(chat.errors.length, 1);
            compare(runner._approvals.length, 0);
        }
    }
}
