// Prompt caching needs the start of each request to be the same from turn to turn.
// Builds the request of one chat twice (before and after another exchange) with the real
// chat/DirectRequest.qml and backends/DirectBackend.js and checks that tools, system
// prompt and every earlier message are byte-identical, even though the memories (which
// go with the message being answered) and the Personality block are in play.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/backends/DirectBackend.js" as DirectBackend
import "../../org.kde.plasma.kdeaichat/contents/ui/backends/DirectCache.js" as DirectCache
import "../../org.kde.plasma.kdeaichat/contents/ui/backends/DirectTools.js" as DirectTools

Item {
    id: root

    function i18n(text) { return text; }

    QtObject {
        id: chat
        property var plasmoid: QtObject {
            property var configuration: ({"contextMessageLimit": -1, "enableSystemPrompt": true, "userName": "Rae", "aiName": "Kai", "userTone": "friendly"})
        }
        property var sessions: [{"value": "s1", "messages": []}]
        property string currentSessionId: "s1"
        property var messages: []
        property string compiledSystemPrompt: "Main instructions."
        property var projects: null
        property var messageLoader: null
        property int recalls: 0
        // Memories that differ on every request, like a recall that picks other ones.
        property var memory: QtObject {
            function withMemories(sessionId, text) { chat.recalls++; return "Memories (recall " + chat.recalls + ")\n\n---\n\n" + text; }
        }
        function sessionIndexById(id) { return 0; }
        function getSessionProperty(id, key, fallback) { return fallback; }
    }

    Chat.DirectRequest { id: direct; chat: chat }

    TestCase {
        name: "PromptPrefix"

        function request(apiType, withCache) {
            var tools = DirectTools.toolDefinitions(apiType, {"askUser": true});
            var parts = direct.buildDirectRequestParts("s1", apiType, true);
            var options = {"type": apiType, "baseUrl": apiType === "anthropic" ? "https://api.anthropic.com/v1" : "https://api.test/v1",
                           "model": "m", "system": parts.system, "messages": parts.messages, "tools": tools, "maxTokens": 1000};
            if (withCache)
                options.cache = DirectCache;
            return DirectBackend.buildRequest(options).body;
        }

        function strip(value) {
            return JSON.parse(JSON.stringify(value, function(key, v) { return key === "cache_control" ? undefined : v; }));
        }

        function twoTurns(apiType, withCache) {
            chat.messages = [{"role": "user", "content": "What is KDE?"}];
            var first = request(apiType, withCache);
            chat.messages = [{"role": "user", "content": "What is KDE?"}, {"role": "assistant", "content": "A desktop."},
                             {"role": "user", "content": "And Plasma?"}];
            return {"first": first, "second": request(apiType, withCache)};
        }

        function test_system_and_tools_do_not_change_between_turns_data() {
            return [{tag: "openai", type: "openai"}, {tag: "anthropic", type: "anthropic"}];
        }
        function test_system_and_tools_do_not_change_between_turns(data) {
            var t = twoTurns(data.type, false);
            var sys = function(b) { return data.type === "anthropic" ? b.system : b.messages[0]; };
            verify(String(JSON.stringify(sys(t.first))).indexOf("Rae") >= 0);   // the Personality block is in
            compare(JSON.stringify(sys(t.second)), JSON.stringify(sys(t.first)));
            verify(t.first.tools.length > 0);
            compare(JSON.stringify(t.second.tools), JSON.stringify(t.first.tools));
        }

        function test_memories_only_touch_the_last_user_message() {
            chat.messages = [{"role": "user", "content": "one"}, {"role": "assistant", "content": "two"}, {"role": "user", "content": "three"}];
            var body = request("openai", false);
            compare(body.messages.length, 4);
            compare(body.messages[1].content, "one");
            compare(body.messages[2].content, "two");
            verify(body.messages[3].content.indexOf("Memories") === 0);
        }

        function test_history_prefix_is_identical_after_another_exchange_data() {
            return [{tag: "openai", type: "openai"}, {tag: "anthropic", type: "anthropic"}];
        }
        function test_history_prefix_is_identical_after_another_exchange(data) {
            // Turn N+1 = turn N + the reply + a new question; the request up to the reply must match.
            var history = [{"role": "user", "content": "one"}, {"role": "assistant", "content": "two"}];
            chat.messages = history.concat([{"role": "user", "content": "three"}]);
            var a = request(data.type, false);
            chat.messages = history.concat([{"role": "user", "content": "three"}, {"role": "assistant", "content": "four"}, {"role": "user", "content": "five"}]);
            var b = request(data.type, false);
            var skip = data.type === "anthropic" ? 0 : 1;   // OpenAI: the system message is messages[0]
            compare(JSON.stringify(b.messages.slice(0, skip + 2)), JSON.stringify(a.messages.slice(0, skip + 2)));
            compare(JSON.stringify(b.tools), JSON.stringify(a.tools));
            compare(JSON.stringify(b.system || null), JSON.stringify(a.system || null));
            // The turn that was answered last time is the same text now, without its memory block.
            var answered = b.messages[skip + 2].content;
            compare(answered, "three");
        }

        function test_anthropic_cache_marks_move_but_the_content_before_them_does_not() {
            var t = twoTurns("anthropic", true);
            // First turn: system and last tool are marked, the lone user turn is not (nothing before it).
            compare(t.first.system[0].cache_control.type, "ephemeral");
            compare(t.first.tools[t.first.tools.length - 1].cache_control.type, "ephemeral");
            // Second turn: the assistant reply before the new question carries the third mark.
            compare(t.second.messages[1].content[0].cache_control.type, "ephemeral");
            compare(JSON.stringify(strip(t.second.system)), JSON.stringify(strip(t.first.system)));
            compare(JSON.stringify(strip(t.second.tools)), JSON.stringify(strip(t.first.tools)));
        }
    }
}
