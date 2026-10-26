// The export dialog offers Markdown, plain text and JSON; the chosen filter
// decides the format and the extension, and the file goes to the widget's
// write path with the chat's details.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 200
    height: 100

    function i18n(text) { return text; }

    QtObject {
        id: chat
        property string currentSessionId: "a"
        property string currentSessionTitle: "Trip planning"
        property var messages: [
            {role: "user", content: "Where to?", time: "10:00", at: 1761400000000},
            {role: "assistant", content: "Lisbon:\n```\nflights\n```", time: "10:01", at: 1761400060000, model: "openrouter/auto"}
        ]
        property var sessions: [{value: "a", createdAt: 1761390000000}]
        property var written: []
        // Settings → Personality names (empty = "You" / the model, as before).
        property var plasmoid: ({configuration: {userName: "", aiName: ""}})
        function sessionIndexById(id) { return id === "a" ? 0 : -1; }
        function effectiveConfig() { return {mode: "provider", provider: "openrouter", model: "openrouter/auto"}; }
        function providerDisplayName(id) { return id === "openrouter" ? "OpenRouter" : id; }
        function writeExportFile(path, content) { written = written.concat([{path: path, content: content}]); }
    }

    Chat.ExportDialog {
        id: dialog
        chat: chat
    }

    TestCase {
        name: "ExportDialog"
        when: windowShown

        function init() {
            chat.written = [];
            chat.plasmoid = {configuration: {userName: "", aiName: ""}};
        }

        function test_export_uses_the_personality_names() {
            dialog.exportTo("/home/u/Docs/Trip.md", 0);
            verify(chat.written[0].content.indexOf("## You · ") > 0, "no names: as before");
            verify(chat.written[0].content.indexOf("## Assistant (openrouter/auto)") > 0);
            chat.plasmoid = {configuration: {userName: "Rachit", aiName: "Nova"}};
            const d = dialog.describe();
            compare(d.userName, "Rachit");
            compare(d.aiName, "Nova");
            dialog.exportTo("/home/u/Docs/Trip.md", 0);
            verify(chat.written[1].content.indexOf("## Rachit · ") > 0, chat.written[1].content);
            verify(chat.written[1].content.indexOf("## Nova (openrouter/auto)") > 0, chat.written[1].content);
            dialog.exportTo("/home/u/Docs/Trip.json", 2);
            compare(JSON.parse(chat.written[2].content).aiName, "Nova");
        }

        function test_filters_are_markdown_text_json() {
            compare(dialog.nameFilters.length, 3);
            verify(dialog.nameFilters[0].indexOf("*.md") >= 0);
            verify(dialog.nameFilters[1].indexOf("*.txt") >= 0);
            verify(dialog.nameFilters[2].indexOf("*.json") >= 0);
        }

        function test_describe_reads_the_chat_details() {
            const d = dialog.describe();
            compare(d.title, "Trip planning");
            compare(d.createdAt, 1761390000000);
            compare(d.mode, "provider");
            compare(d.provider, "OpenRouter");
            compare(d.model, "openrouter/auto");
        }

        function test_markdown_filter_writes_markdown() {
            dialog.exportTo("/home/u/Docs/Trip.md", 0);
            compare(chat.written.length, 1);
            compare(chat.written[0].path, "/home/u/Docs/Trip.md");
            verify(chat.written[0].content.indexOf("# Trip planning") === 0);
            verify(chat.written[0].content.indexOf("- **Provider:** OpenRouter") > 0);
            verify(chat.written[0].content.indexOf("```\nflights\n```") > 0);
        }

        function test_filter_decides_extension_and_format() {
            dialog.exportTo("/home/u/Docs/Trip.md", 2);
            compare(chat.written[0].path, "/home/u/Docs/Trip.json");
            const parsed = JSON.parse(chat.written[0].content);
            compare(parsed.title, "Trip planning");
            compare(parsed.messages.length, 2);
            dialog.exportTo("/home/u/Docs/Trip", 1);
            compare(chat.written[1].path, "/home/u/Docs/Trip.txt");
            verify(chat.written[1].content.indexOf("Trip planning\n") > 0);
            verify(chat.written[1].content.indexOf("**") < 0);
        }
    }
}
