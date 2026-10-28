// Quoted messages on their way to the AI, in every mode: SendController.qml
// stores the quotes on the sent message (taking them from the composer's
// chips), and the direct, OpenCode and Pi requests all put them in front of
// the text through MessageContent.js. A stand-in root drives the real modules.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/chat/MessageContent.js" as MessageContent
import "../../org.kde.plasma.kdeaichat/contents/ui/backends/DirectBackend.js" as DirectBackend

TestCase {
    id: tc
    name: "QuoteSend"

    QtObject {
        id: chat
        property var plasmoid: QtObject { property var configuration: ({"contextMessageLimit": -1, "enableSystemPrompt": false}) }
        property var sessions: []
        property string currentSessionId: "s1"
        property var messages: []
        property bool loading: false
        property var activeXhr: null
        property int queueCounter: 0
        property var attachedFiles: []
        property string chatInputText: ""
        property var promptTemplates: []
        property var composerRef: null
        property bool openCodeMode: false
        property bool piMode: true
        property int currentStreamIndex: -1
        property string currentStreamText: ""
        property string currentStreamReasoning: ""
        property string currentStreamExtractedReasoning: ""
        property bool streamingResponse: false
        property int requestGeneration: 0
        property string activeRequestSessionId: ""
        property var streamBuffer: QtObject { function clear() {} }
        property string compiledSystemPrompt: ""
        property var piThinkingModels: ({})
        property string openCodeWorkspaceCwd: ""
        property var sent: []
        property var errors: []
        property int cleared: 0
        property var notifierRef: null
        function scrollToBottom(f) {}
        signal clearChatInput()
        onClearChatInput: cleared++
        function ensureWalletLoaded() {}
        function attachmentsReadyToSend() { return true; }
        function cleanupTemporaryAttachment(path) {}
        function nameChatFromFirstMessage(t) {}
        function saveCurrentSessionState(t) {}
        function applySessionSource(s) { return "pi"; }
        function setCurrentSessionSource() {}
        function sessionIndexById(id) { return 0; }
        function pushErrorMessage(t) { errors = errors.concat([t]); }
        function getSessionProperty(id, key, fallback) { return fallback; }
        function effectiveConfig(id) { return {"provider": "p", "model": "m", "thinking": ""}; }
        function buildMessageContent(text, attachments, apiType, quotes, agent) { return MessageContent.build(text, attachments, apiType, quotes, agent); }
    }

    // Pi mode: a send ends in piAgentRef.send(sessionId, generation).
    Chat.SendController {
        id: sender
        chat: chat
        notifierRef: QtObject { function failed(id, title, text) { chat.errors = chat.errors.concat([text]); } }
        piAgentRef: QtObject { function send(sessionId, generation) { chat.sent = chat.sent.concat([sessionId]); } }
    }
    Chat.DirectRequest { id: direct; chat: chat }
    Chat.OpenCodeMode { id: openCode; chat: chat }
    Chat.PiMode { id: pi; chat: chat }

    // What Composer.qml offers: the chips' quotes, handed over once.
    QtObject {
        id: composerStub
        property var pending: []
        property int taken: 0
        function takeQuotes() { taken++; var q = pending; pending = []; return q; }
    }

    readonly property var quotes: [
        {"id": "m-1", "role": "assistant", "text": "Use rsync.\nIt is faster."},
        {"id": "m-0", "role": "user", "text": "single line"}]

    function init() {
        chat.messages = [];
        chat.sent = [];
        chat.errors = [];
        chat.sessions = [{"value": "s1"}];
        chat.loading = false;
        chat.composerRef = composerStub;
        composerStub.pending = [];
        composerStub.taken = 0;
        chat.chatInputText = "And in zsh?";
    }

    function test_1_the_sent_message_keeps_the_quotes_and_its_own_text() {
        composerStub.pending = quotes;
        sender.sendMessage();
        compare(chat.errors.length, 0, chat.errors.join());
        compare(chat.messages.length, 1);
        var m = chat.messages[0];
        compare(m.role, "user");
        compare(m.content, "And in zsh?", "what is shown is only the text");
        compare(JSON.stringify(m.quotes), JSON.stringify(quotes));
        compare(composerStub.taken, 1, "the chips were emptied once");
        compare(chat.sent, ["s1"], "and the message was sent");
    }

    function test_2_no_quotes_means_no_quotes_field() {
        sender.sendMessage();
        compare(chat.messages.length, 1);
        verify(chat.messages[0].quotes === undefined, "unchanged message shape");
        chat.composerRef = null;
        chat.chatInputText = "Again";
        sender.sendMessage();
        verify(chat.messages[1].quotes === undefined);
    }

    function test_3_a_queued_message_keeps_the_quotes_too() {
        chat.loading = true;
        composerStub.pending = quotes;
        sender.sendMessage();
        compare(chat.messages[0].role, "queued");
        compare(chat.messages[0].quotes.length, 2);
        compare(chat.sent.length, 0, "not sent while a reply is written");
    }

    function test_4_direct_requests_put_the_quote_before_the_text() {
        chat.messages = [
            {"role": "user", "content": "First question"},
            {"role": "assistant", "content": "Use rsync.\nIt is faster."},
            {"role": "user", "content": "And in zsh?", "quotes": quotes}];
        var parts = direct.buildDirectRequestParts("s1", "openai");
        compare(parts.messages[0].content, "First question", "no quotes: the text as it was");
        compare(parts.messages[1].content, "Use rsync.\nIt is faster.");
        compare(parts.messages[2].content, "> Quoted (assistant):\n> Use rsync.\n> It is faster.\n\n> Quoted (user):\n> single line\n\nAnd in zsh?");
        // ...and that is what the request body carries, in both API formats.
        var openai = DirectBackend.buildRequest({"type": "openai", "baseUrl": "https://x/v1", "model": "m", "system": parts.system, "messages": parts.messages});
        compare(openai.body.messages[openai.body.messages.length - 1].content, parts.messages[2].content);
        var anthropic = DirectBackend.buildRequest({"type": "anthropic", "model": "m", "system": parts.system, "messages": parts.messages});
        compare(anthropic.body.messages[2].content, parts.messages[2].content);
    }

    function test_5_direct_requests_with_an_attachment_and_a_quote() {
        chat.messages = [{"role": "user", "content": "Look", "quotes": quotes,
                          "attachments": [{"type": "image", "mimeType": "image/png", "content": "AAAA"}]}];
        var content = direct.buildDirectRequestParts("s1", "openai").messages[0].content;
        compare(content[0].type, "text");
        verify(content[0].text.indexOf("> Quoted (assistant):") === 0, content[0].text);
        verify(content[0].text.endsWith("Look"));
        compare(content[1].type, "image_url");
    }

    function test_6_opencode_parts_carry_the_quote() {
        compare(openCode.openCodeParts({"content": "plain"})[0].text, "plain");
        var parts = openCode.openCodeParts({"content": "And in zsh?", "quotes": quotes});
        compare(parts.length, 1);
        compare(parts[0].type, "text");
        compare(parts[0].text, "> Quoted (assistant):\n> Use rsync.\n> It is faster.\n\n> Quoted (user):\n> single line\n\nAnd in zsh?");
    }

    function test_7_pi_prompt_carries_the_quote() {
        compare(pi.promptBody("s1", {"content": "plain"}).message, "plain");
        var body = pi.promptBody("s1", {"content": "And in zsh?", "quotes": quotes});
        compare(body.message, "> Quoted (assistant):\n> Use rsync.\n> It is faster.\n\n> Quoted (user):\n> single line\n\nAnd in zsh?");
        compare(body.images.length, 0);
    }

    function test_8_a_long_quote_is_capped_in_every_request() {
        var long = [{"id": "m-9", "role": "assistant", "text": "x".repeat(6000)}];
        var message = {"role": "user", "content": "q", "quotes": long};
        var expected = "> Quoted (assistant):\n> " + "x".repeat(4000) + "…\n\nq";
        compare(openCode.openCodeParts(message)[0].text, expected);
        compare(pi.promptBody("s1", message).message, expected);
        chat.messages = [message];
        compare(direct.buildDirectRequestParts("s1", "openai").messages[0].content, expected);
    }
}
