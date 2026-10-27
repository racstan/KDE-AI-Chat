// "Find local servers" (config/LocalServers.qml): the quiet scan when the page
// opens, the button, the list (name, address, model count, Use), servers that
// are already in the provider list, an empty and a failed scan. The helper is
// a fake; nothing is probed. The step through ConfigConnection (Use fills in a
// provider) is in tst_config_connection.qml.
// Screenshots: build/qml-screens/local-servers-<wide|narrow>.png.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/config" as Config

Item {
    id: root
    width: 820
    height: 420

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    readonly property var found: [
        {id: "ollama-11434", kind: "ollama", name: "Ollama", port: 11434, baseUrl: "http://127.0.0.1:11434/v1",
         models: ["llama3.2:latest", "qwen3:8b"], count: 2, needsKey: false, provider: "ollama"},
        {id: "lmstudio-1234", kind: "lmstudio", name: "LM Studio", port: 1234, baseUrl: "http://127.0.0.1:1234/v1",
         models: ["gemma-3-4b"], count: 1, needsKey: false, provider: "lmstudio"},
        {id: "openai-8000", kind: "openai", name: "OpenAI-compatible server", port: 8000, baseUrl: "http://127.0.0.1:8000/v1",
         models: ["a", "b", "c"], count: 3, needsKey: false, provider: "custom"},
        {id: "litellm-4000", kind: "litellm", name: "LiteLLM proxy", port: 4000, baseUrl: "http://127.0.0.1:4000/v1",
         models: [], count: 0, needsKey: true, provider: "litellm"}]

    QtObject {
        id: fakeHelper
        property var calls: []
        property string reply: ""
        property int exitCode: 0
        function run(command, payload, done) {
            calls = calls.concat([{"command": command, "payload": payload}]);
            done(reply, exitCode, "");
        }
    }

    Rectangle { anchors.fill: parent; color: "white" }

    Component {
        id: panelComponent
        Config.LocalServers {
            x: 10
            y: 10
            helper: fakeHelper
            providers: [{id: "ollama", type: "openai-compat", baseUrl: "http://localhost:11434/v1", model: "x"},
                        {id: "aihorde", type: "image", baseUrl: "http://localhost:1337"}]
        }
    }

    HarnessTestCase {
        name: "LocalServers"

        property var panel: null

        function make(width, props) {
            panel = createTemporaryObject(panelComponent, root, Object.assign({"width": width}, props || {}));
            verify(panel !== null);
            return panel;
        }

        function init() {
            fakeHelper.calls = [];
            fakeHelper.exitCode = 0;
            fakeHelper.reply = JSON.stringify({servers: root.found});
        }

        function texts(name) {
            return findChildren(panel, name).filter(function(l) { return l.visible; }).map(function(l) { return l.text; });
        }

        function test_quiet_scan_on_open_lists_what_answers() {
            make(600);
            tryVerify(function() { return panel.phase === "ok"; }, 3000);
            compare(fakeHelper.calls.length, 1);
            compare(fakeHelper.calls[0].command, "local_servers_scan");
            compare(JSON.stringify(fakeHelper.calls[0].payload), "{}", "no setting or key goes with the scan");
            compare(texts("localServerName"), ["Ollama", "LM Studio", "OpenAI-compatible server", "LiteLLM proxy"]);
            compare(texts("localServerDetail"), ["127.0.0.1:11434 · 2 models", "127.0.0.1:1234 · 1 model",
                                                 "127.0.0.1:8000 · 3 models", "127.0.0.1:4000 · asks for a key"]);
            // Ollama's port already has a provider; the picture service on 1337 doesn't count (a LiteLLM proxy that asks for its key is found by its open health check).
            compare(texts("localServerAdded"), ["In your list"]);
            compare(findChildren(panel, "useLocalServer").filter(function(b) { return b.visible; }).length, 3);
        }

        function test_use_sends_the_server() {
            make(600);
            tryVerify(function() { return panel.phase === "ok"; }, 3000);
            var got = [];
            panel.useServer.connect(function(server) { got.push(server.id); });
            var buttons = findChildren(panel, "useLocalServer").filter(function(b) { return b.visible; });
            var lmstudio = buttons.filter(function(b) { return b.Accessible.name === "Use LM Studio"; })[0];
            wait(300);   // let the rows settle before clicking at a position
            mouseClick(lmstudio);
            compare(got.join(), "lmstudio-1234");
            panel.busy = true;
            verify(!lmstudio.enabled, "Use is off while a provider is being edited");
        }

        function test_quiet_scan_with_nothing_shows_nothing_but_the_button_says_so() {
            fakeHelper.reply = JSON.stringify({servers: []});
            make(600);
            tryVerify(function() { return panel.phase === "ok"; }, 3000);
            verify(!findChild(panel, "localServersEmpty").visible, "the quiet check stays silent");
            mouseClick(findChild(panel, "findLocalServers"));
            tryVerify(function() { return findChild(panel, "localServersEmpty").visible; }, 3000);
            compare(fakeHelper.calls.length, 2);
        }

        function test_a_failed_scan_is_quiet_then_reported_by_the_button() {
            fakeHelper.exitCode = 1;
            fakeHelper.reply = "boom";
            make(600);
            tryVerify(function() { return panel.phase === "failed"; }, 3000);
            verify(!findChild(panel, "localServersFailed").visible);
            mouseClick(findChild(panel, "findLocalServers"));
            tryVerify(function() { return findChild(panel, "localServersFailed").visible; }, 3000);
        }

        function test_no_scan_while_another_way_of_chatting_is_chosen() {
            make(600, {"active": false});
            wait(100);
            compare(fakeHelper.calls.length, 0);
            panel.active = true;
            tryVerify(function() { return panel.phase === "ok"; }, 3000);
        }

        function test_the_explanation_is_there() {
            make(600);
            var help = findChild(panel, "localServersHelp");
            verify(help.isSettingHelp && help.text.length > 20 && help.details.length > 20);
        }

        function test_wide_and_narrow_screenshots() {
            make(800);
            tryVerify(function() { return panel.phase === "ok"; }, 3000);
            wait(200);
            screenshot(root, "local-servers-wide");
            panel.width = 460;
            wait(200);
            screenshot(root, "local-servers-narrow");
            // Nothing is cut off at 480: every row stays inside the panel.
            findChildren(panel, "useLocalServer").forEach(function(b) {
                var p = b.mapToItem(panel, b.width, 0);
                verify(p.x <= panel.width, "Use button inside the panel");
            });
        }
    }
}
