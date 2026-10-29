// MCP servers in direct chats (chat/McpTools.qml): the real request code (DirectRequest, DirectToolRounds,
// DirectToolRunner, McpTools, McpBridge) against a fake XMLHttpRequest for the provider, a fake helper
// (mcp_list, mcp_bridge_start, remembered approvals), a fake KWallet and a fake MCP bridge. The tools of the
// enabled servers join the request, a call goes to the bridge only after approval, secrets come from the wallet
// and never travel through the helper, a chat can choose its servers, and a failing server is a note.
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

    // What the fake helper was asked, the MCP servers it lists, what the fake bridge was asked and what it answers.
    property var helperCalls: []
    property var storedKeys: []
    property bool helperFails: false
    property var mcpServers: []
    property var walletFields: ({})
    property var walletReads: []
    property var bridgeCalls: []
    property var bridgeTools: ({})     // server id -> [tools] | "error text"
    property bool bridgeIsError: false

    // A fake XMLHttpRequest for the MCP bridge: answers /tools and /call at once.
    function makeBridgeXhr() {
        var x = {"readyState": 0, "status": 0, "responseText": "", "headers": {}, "url": "",
            "open": function(method, url) { x.url = url; },
            "setRequestHeader": function(k, v) { x.headers[k] = v; },
            "send": function(body) {
                var b = JSON.parse(body);
                var path = x.url.replace(/^http:\/\/127\.0\.0\.1:[0-9]+/, "");
                root.bridgeCalls = root.bridgeCalls.concat([{"path": path, "auth": x.headers["Authorization"], "body": b, "url": x.url}]);
                var answer = {};
                if (path === "/tools") {
                    answer = {"servers": {}};
                    b.servers.forEach(function(d) {
                        var t = root.bridgeTools[d.id];
                        answer.servers[d.id] = typeof t === "string" ? {"error": t} : {"tools": t || []};
                    });
                } else {
                    answer = {"content": "echoed " + JSON.stringify(b.arguments), "isError": root.bridgeIsError};
                }
                x.status = 200;
                x.responseText = JSON.stringify(answer);
                x.readyState = 4;
                x.onreadystatechange();
            }};
        return x;
    }

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
        property var wallet: QtObject {
            property bool usable: true
            function readEntry(name, cb) {
                root.walletReads = root.walletReads.concat([name]);
                cb(true, root.walletFields[name] || {});
            }
        }
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
                if (command === "mcp_list") {
                    onDone(JSON.stringify({"status": "ok", "servers": root.mcpServers}), 0, "");
                    return;
                }
                if (command === "mcp_bridge_start") {
                    onDone(JSON.stringify({"status": "running", "port": 4242, "token": "tok-1"}), 0, "");
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
        function getSessionProperty(id, key, fallback) {
            for (var i = 0; i < sessions.length; i++)
                if (sessions[i].value === id && sessions[i][key] !== undefined && sessions[i][key] !== null)
                    return sessions[i][key];
            return fallback;
        }
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
        name: "McpTools"

        readonly property var mcp: direct.toolRounds.mcp
        readonly property var runner: direct.toolRounds.runner

        readonly property var echoTool: ({"name": "echo", "description": "Echoes.", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}})
        readonly property var otherTool: ({"name": "lookup", "description": "Looks up.", "inputSchema": {"type": "object"}})

        function init() {
            root.xhrs = [];
            root.helperCalls = [];
            root.storedKeys = [];
            root.helperFails = false;
            root.mcpServers = [{"id": "files", "command": "mcp-files", "args": ["--ro"], "enabled": true}];
            root.walletFields = ({});
            root.walletReads = [];
            root.bridgeCalls = [];
            root.bridgeTools = ({"files": [echoTool]});
            root.bridgeIsError = false;
            chat.sessions = [{"value": "s1", "messages": []}];
            chat.currentSessionId = "s1";
            chat.messages = [{"id": "u1", "role": "user", "content": "Do something", "at": 1}];
            chat.loading = false;
            chat.currentStreamIndex = -1;
            chat.currentStreamText = "";
            chat.currentStreamReasoning = "";
            chat.errors = [];
            chat.plasmoid.configuration.allowAskUser = true;
            chat.plasmoid.configuration.directToolMaxRounds = undefined;
            notice.needed = [];
            direct.toolRounds.pending = null;
            runner.pending = null;
            runner._approvals = null;
            mcp.xhrFactory = root.makeBridgeXhr;
            mcp.servers = [];
            mcp.notes = ({});
            mcp._cache = ({});
            mcp.bridge._info = null;
            mcp.invalidate();
        }

        function start(sessionId) {
            var generation = sender.beginRequest(sessionId || "s1");
            direct.sendDirectRequest(Object.assign({}, root.cfg), sessionId || "s1", generation, {});
        }

        function press(name) {
            waitForRendering(root);
            mouseClick(findChild(buttons, name));
        }

        function toolNames(i) { return root.xhrs[i].sent.tools.map(function(t) { return t.function.name; }); }
        function paths() { return root.bridgeCalls.map(function(c) { return c.path; }).join(); }

        function test_tools_of_enabled_servers_appear_in_a_direct_request() {
            root.mcpServers = [{"id": "files", "command": "mcp-files", "enabled": true},
                               {"id": "off", "command": "mcp-off", "enabled": false},
                               {"id": "web", "url": "https://mcp.test/x", "enabled": true}];
            root.bridgeTools = ({"files": [echoTool], "off": [otherTool], "web": [otherTool]});
            start();
            compare(toolNames(0).join(), "ask_user,mcp__files__echo,mcp__web__lookup");
            compare(root.xhrs[0].sent.tools[1].function.description, "Echoes.");
            compare(paths(), "/tools,/tools", "one request per server, none for the one that is off");
            compare(root.bridgeCalls[0].auth, "Bearer tok-1");
            compare(root.bridgeCalls[0].url, "http://127.0.0.1:4242/tools");
            compare(root.helperCalls.filter(function(c) { return c.indexOf("mcp_bridge_start") === 0; }).length, 1);
        }

        function test_without_servers_the_bridge_is_never_started() {
            root.mcpServers = [];
            start();
            compare(toolNames(0).join(), "ask_user");
            compare(root.helperCalls.filter(function(c) { return c.indexOf("mcp_bridge_start") === 0; }).length, 0);
            compare(root.bridgeCalls.length, 0);
        }

        function test_the_tool_list_is_cached_between_requests() {
            start();
            compare(paths(), "/tools");
            root.xhrs[0].play(200, root.textStream("ok"));
            start();
            compare(toolNames(1).join(), "ask_user,mcp__files__echo");
            compare(paths(), "/tools", "no second look inside the cache time");
            tc.mcp.toolsTtlMs = 0;
            tc.mcp.listTtlMs = 0;
            start();
            compare(toolNames(2).join(), "ask_user,mcp__files__echo", "the old list is used at once");
            compare(paths(), "/tools,/tools", "and refreshed in the background");
            tc.mcp.toolsTtlMs = 300000;
            tc.mcp.listTtlMs = 20000;
        }

        function test_a_call_goes_to_the_bridge_after_approval_and_the_result_reaches_the_model() {
            start();
            root.xhrs[0].play(200, root.callStream("mcp__files__echo", {"text": "hi"}));
            compare(root.permissionMessage.status, "pending", "every MCP tool asks first");
            compare(root.permissionMessage.tool, "mcp__files__echo");
            compare(paths(), "/tools", "nothing was called yet");
            tc.screenshot(root, "mcp-tool-pending");
            press("allowButton");
            compare(paths(), "/tools,/call");
            var call = root.bridgeCalls[1];
            compare(call.auth, "Bearer tok-1");
            compare(call.body.tool, "echo", "the server's own tool name");
            compare(call.body.arguments.text, "hi");
            compare(call.body.server.id, "files");
            compare(call.body.server.command, "mcp-files");
            verify(call.body.server.enabled === undefined);
            compare(root.xhrs.length, 2);
            compare(root.xhrs[1].sent.messages[2].content, 'echoed {"text":"hi"}');
            root.xhrs[1].play(200, root.textStream("Done."));
            compare(chat.messages[1].tools["call_1"].status, "done");
        }

        function test_a_denied_call_never_reaches_the_bridge_and_an_error_result_is_marked() {
            start();
            root.xhrs[0].play(200, root.callStream("mcp__files__echo", {}));
            press("rejectButton");
            compare(paths(), "/tools");
            compare(root.xhrs[1].sent.messages[2].content, "The user denied this tool call.");
            root.xhrs[1].play(200, root.textStream("ok"));
            chat.messages = [{"id": "u2", "role": "user", "content": "again", "at": 2}];
            root.xhrs = [];
            root.bridgeIsError = true;
            start();
            root.xhrs[0].play(200, root.callStream("mcp__files__echo", {}, "call_5"));
            press("allowButton");
            compare(chat.messages[1].tools["call_5"].status, "error");
        }

        function test_always_is_remembered_per_server_and_tool() {
            start();
            root.xhrs[0].play(200, root.callStream("mcp__files__echo", {}));
            press("alwaysAllowButton");
            compare(root.storedKeys.join(), "mcp:files:echo");
        }

        function test_a_secret_placeholder_is_resolved_from_the_wallet_and_never_sent_to_the_helper() {
            root.mcpServers = [{"id": "api", "url": "https://mcp.test/x", "headers": {"Authorization": {"secret": "TOKEN"}, "X-Plain": "p"}, "enabled": true},
                               {"id": "cmd", "command": "run", "env": {"API_KEY": {"secret": "KEY"}}, "enabled": true}];
            root.walletFields = ({"mcp-api": {"TOKEN": "s3cret-token"}, "mcp-cmd": {"KEY": "s3cret-key"}});
            root.bridgeTools = ({"api": [echoTool], "cmd": [otherTool]});
            start();
            compare(toolNames(0).join(), "ask_user,mcp__api__echo,mcp__cmd__lookup");
            compare(root.walletReads.join(), "mcp-api,mcp-cmd");
            compare(root.bridgeCalls[0].body.servers[0].headers.Authorization, "s3cret-token");
            compare(root.bridgeCalls[0].body.servers[0].headers["X-Plain"], "p");
            compare(root.bridgeCalls[1].body.servers[0].env.API_KEY, "s3cret-key");
            root.xhrs[0].play(200, root.callStream("mcp__api__echo", {"text": "x"}));
            press("allowButton");
            compare(root.bridgeCalls[2].body.server.headers.Authorization, "s3cret-token");
            verify(root.helperCalls.join("\n").indexOf("s3cret") < 0, "no secret in any helper payload");
            verify(JSON.stringify(chat.messages).indexOf("s3cret") < 0, "nor in the chat");
        }

        function test_a_secret_missing_from_the_wallet_leaves_the_server_out_with_a_note() {
            root.mcpServers = [{"id": "api", "url": "https://mcp.test/x", "headers": {"Authorization": {"secret": "TOKEN"}}, "enabled": true},
                               {"id": "files", "command": "mcp-files", "enabled": true}];
            start();
            compare(toolNames(0).join(), "ask_user,mcp__files__echo");
            verify(String(tc.mcp.notes["api"]).indexOf("TOKEN") >= 0);
            compare(paths(), "/tools", "the server without its secret was not contacted");
            compare(chat.errors.length, 0);
        }

        function test_a_chat_can_choose_its_servers() {
            root.mcpServers = [{"id": "files", "command": "a", "enabled": true}, {"id": "web", "command": "b", "enabled": true}];
            root.bridgeTools = ({"files": [echoTool], "web": [otherTool]});
            chat.sessions = [{"value": "s1", "messages": [], "mcpServers": ["web"]},
                             {"value": "s2", "messages": []}, {"value": "s3", "messages": [], "mcpServers": []}];
            start("s1");
            compare(toolNames(0).join(), "ask_user,mcp__web__lookup");
            root.xhrs[0].play(200, root.textStream("ok"));
            start("s2");
            compare(toolNames(1).join(), "ask_user,mcp__files__echo,mcp__web__lookup", "unset means every enabled server");
            root.xhrs[1].play(200, root.textStream("ok"));
            start("s3");
            compare(toolNames(2).join(), "ask_user", "an empty choice means none");
        }

        function test_a_failing_server_is_a_note_and_the_chat_goes_on() {
            root.mcpServers = [{"id": "files", "command": "a", "enabled": true}, {"id": "web", "command": "b", "enabled": true}];
            root.bridgeTools = ({"files": "Couldn't start a: No such file or directory", "web": [otherTool]});
            start();
            compare(toolNames(0).join(), "ask_user,mcp__web__lookup");
            compare(tc.mcp.notes["files"], "Couldn't start a: No such file or directory");
            compare(chat.errors.length, 0);
            root.xhrs[0].play(200, root.textStream("Fine."));
            compare(chat.messages[chat.messages.length - 1].content, "Fine.");
        }

        function test_an_unreachable_bridge_is_an_error_result_for_the_model_not_a_crash() {
            start();
            root.xhrs[0].play(200, root.callStream("mcp__files__echo", {}));
            tc.mcp.xhrFactory = function() {
                var x = {"open": function() {}, "setRequestHeader": function() {},
                         "send": function() { x.status = 0; x.readyState = 4; x.onreadystatechange(); }};
                return x;
            };
            press("allowButton");
            verify(root.xhrs[1].sent.messages[2].content.indexOf("didn't answer") >= 0);
            compare(chat.errors.length, 0);
        }
    }
}
