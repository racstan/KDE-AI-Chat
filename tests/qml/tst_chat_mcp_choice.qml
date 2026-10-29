// Chat info → MCP servers for this chat (chat/ChatMcpChoice.qml): every enabled server is ticked until the
// chat chooses, a choice is saved as a list of ids (all ticked = unset), servers that are off aren't offered,
// and OpenCode and Pi chats show nothing.
import QtQuick
import QtTest

Item {
    id: root
    width: 420
    height: 300

    function i18n(text) { return text; }

    property var servers: [{"id": "files", "enabled": true}, {"id": "web", "enabled": true}, {"id": "off", "enabled": false}]
    property var saved: ({})
    property var written: []

    QtObject {
        id: draft
        property string sessionId: "s1"
        property string mode: "provider"
        property bool dirty: false
        signal loaded()
        property var rootRef: QtObject {
            property var store: QtObject {
                function runHelper(command, payload, onDone) {
                    onDone(JSON.stringify({"status": "ok", "servers": root.servers}), 0, "");
                }
            }
            function getSessionProperty(id, key, fallback) { return root.saved[key] === undefined ? fallback : root.saved[key]; }
            function setSessionOverrides(id, overrides) { root.written = root.written.concat([overrides]); return true; }
        }
    }

    HarnessTestCase {
        id: tc
        name: "ChatMcpChoice"

        property var choice: null

        function init() {
            root.saved = ({});
            root.written = [];
            root.servers = [{"id": "files", "enabled": true}, {"id": "web", "enabled": true}, {"id": "off", "enabled": false}];
            draft.mode = "provider";
            draft.dirty = false;
            var component = Qt.createComponent(Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/chat/ChatMcpChoice.qml"));
            verify(component.status === Component.Ready, component.errorString());
            choice = component.createObject(root, {"draft": draft, "width": 400});
            draft.loaded();
        }

        function cleanup() {
            choice.destroy();
        }

        function test_every_enabled_server_is_ticked_by_default() {
            verify(choice.visible);
            compare(choice.servers.length, 2, "the server that is off isn't offered");
            verify(findChild(choice, "mcpChoice-files").checked);
            verify(findChild(choice, "mcpChoice-web").checked);
            verify(findChild(choice, "mcpChoice-off") === null);
            compare(choice.value(), null);
            tc.screenshot(root, "chat-mcp-choice");
        }

        function test_unticking_a_server_marks_the_draft_and_saves_a_list() {
            waitForRendering(root);
            mouseClick(findChild(choice, "mcpChoice-web"));
            verify(draft.dirty);
            choice.save();
            compare(JSON.stringify(root.written), '[{"mcpServers":["files"]}]');
            mouseClick(findChild(choice, "mcpChoice-web"));
            choice.save();
            compare(JSON.stringify(root.written[1]), '{"mcpServers":null}', "all ticked is the default again");
        }

        function test_a_saved_choice_is_shown() {
            root.saved = {"mcpServers": ["web"]};
            draft.loaded();
            verify(!findChild(choice, "mcpChoice-files").checked);
            verify(findChild(choice, "mcpChoice-web").checked);
        }

        function test_agent_chats_and_no_servers_show_nothing() {
            draft.mode = "opencode";
            verify(!choice.visible);
            choice.save();
            compare(root.written.length, 0);
            draft.mode = "provider";
            root.servers = [];
            draft.loaded();
            verify(!choice.visible);
        }
    }
}
