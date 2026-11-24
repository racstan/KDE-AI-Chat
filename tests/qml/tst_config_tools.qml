// Settings → Tools (ConfigTools.qml): the MCP servers text with live JSON feedback, Check servers
// (starts the tool bridge through the helper with the values on the page and lists each server), the
// web search choice with its address and key, saving a key through the helper (never read back, the
// field is cleared), reading web pages, and the always-allowed list. The helper and the bridge are
// stand-ins: nothing starts and nothing leaves the test.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami

Item {
    id: root
    width: 820
    height: 900

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(singular, plural, count) {
        return (count === 1 ? singular : plural).replace("%1", count);
    }

    property var helperCalls: []
    property var bridgeCalls: []
    property var savedKeys: ({"brave": false, "tavily": false})
    property string keyResult: "saved"

    // The helper: starts a "bridge", saves keys, reports which keys are saved.
    QtObject {
        id: helper
        function run(command, payload, onDone) {
            root.helperCalls = root.helperCalls.concat([{"command": command, "payload": payload}]);
            if (command === "tools_bridge_start")
                onDone(JSON.stringify({"status": "started", "port": 41234, "token": "secret-token"}), 0, "");
            else if (command === "tools_key_set") {
                if (root.keyResult === "saved" || root.keyResult === "removed") {
                    var saved = Object.assign({}, root.savedKeys);
                    saved[payload.name] = payload.key !== "";
                    root.savedKeys = saved;
                }
                onDone(JSON.stringify({"status": payload.key === "" && root.keyResult === "saved" ? "removed" : root.keyResult, "message": root.keyResult === "error" ? "KWallet is locked." : ""}), 0, "");
            } else if (command === "tools_key_status")
                onDone(JSON.stringify(root.savedKeys), 0, "");
            else if (onDone)
                onDone("{}", 0, "");
        }
    }

    function makeBridgeXhr() {
        var x = {"readyState": 0, "status": 0, "responseText": "", "url": "", "timeout": 0,
            "open": function(method, url) { x.url = url; },
            "setRequestHeader": function() {},
            "send": function(body) {
                var parsed = JSON.parse(body);
                root.bridgeCalls = root.bridgeCalls.concat([{"url": x.url, "body": parsed}]);
                var names = Object.keys(parsed.servers.mcpServers || parsed.servers);
                var tools = [];
                var errors = [];
                for (var i = 0; i < names.length; i++) {
                    if (names[i] === "broken")
                        errors.push({"server": "broken", "message": "it exited at once"});
                    else
                        for (var t = 0; t < 3; t++)
                            tools.push({"name": names[i] + "__t" + t, "server": names[i], "description": "", "inputSchema": {"type": "object"}});
                }
                if (parsed.web.search !== "none")
                    tools.push({"name": "web_search", "server": "web", "description": "", "inputSchema": {"type": "object"}});
                x.status = 200;
                x.responseText = JSON.stringify({"tools": tools, "errors": errors});
                x.readyState = 4;
                x.onreadystatechange();
            }};
        return x;
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    HarnessTestCase {
        id: tc
        name: "ConfigTools"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        function open(cfg) {
            var component = Qt.createComponent(uiDir + "ConfigTools.qml");
            verify(component.status === Component.Ready, component.errorString());
            var values = Object.assign({"width": root.width, "height": root.height, "helperRunner": helper, "toolXhrFactory": root.makeBridgeXhr}, cfg || {});
            page = component.createObject(root, values);
            verify(page !== null);
            return page;
        }
        function init() {
            root.helperCalls = [];
            root.bridgeCalls = [];
            root.savedKeys = {"brave": false, "tavily": false};
            root.keyResult = "saved";
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            wait(100);
        }
        function named(name) { return findChild(page, name); }
        function commands() { return root.helperCalls.map(function(c) { return c.command; }); }
        function rowTexts() {
            var rows = [];
            (function walk(item) {
                if (item.objectName === "checkRow" && item.visible) rows.push(item.text);
                for (var i = 0; i < (item.children || []).length; i++) walk(item.children[i]);
            })(page);
            return rows;
        }

        function test_defaults_start_nothing_and_have_no_secrets() {
            open();
            compare(commands(), ["tools_key_status"], "only asks which keys are saved");
            compare(named("serversArea").text, "");
            compare(named("serversStatus").text, "Valid. No servers.");
            compare(named("searchCombo").currentText, "None");
            verify(!named("searxField").visible);
            verify(!named("keyField").visible);
            compare(named("fetchCheck").checked, false);
            compare(page.cfg_toolsAlwaysAllowed, "[]");
            for (var name in page)
                if (name.indexOf("cfg_") === 0)
                    verify(!/apikey|token|password|sessions|messages|key$/i.test(name), name + " would be saved by the settings dialog");
            wait(200);
            screenshot(page, "config-tools-default");
        }

        function test_json_feedback_is_live() {
            open();
            var area = named("serversArea");
            area.text = "{ \"files\": { \"command\": \"npx\" }, \"web\": { \"url\": \"https://x.example/mcp\" } }";
            compare(named("serversStatus").text, "Valid JSON: 2 servers.");
            compare(page.cfg_toolServers, area.text);
            area.text = "{ \"files\": ";
            verify(named("serversStatus").text.indexOf("Not valid JSON:") === 0, named("serversStatus").text);
            verify(!named("checkButton").enabled, "nothing to check while it is not valid");
            area.text = "[1, 2]";
            verify(named("serversStatus").text.indexOf("Not valid JSON:") === 0);
            area.text = "{ \"mcpServers\": { \"one\": { \"command\": \"x\" } } }";
            compare(named("serversStatus").text, "Valid JSON: 1 server.");
            wait(100);
            screenshot(page, "config-tools-json");
        }

        function test_check_servers_lists_each_server_with_its_tools_or_its_error() {
            open({"cfg_toolServers": "{ \"files\": { \"command\": \"x\" }, \"broken\": { \"command\": \"y\" } }",
                  "cfg_webSearchProvider": "searxng", "cfg_searxngUrl": "https://searx.example.org"});
            compare(named("searchCombo").currentText, "SearXNG");
            verify(named("searxField").visible);
            compare(named("searxField").text, "https://searx.example.org");
            mouseClick(named("checkButton"));
            tryVerify(function() { return !page.checking; }, 3000);
            // The bridge was started and sent the values on the page, not saved ones.
            compare(commands().filter(function(c) { return c === "tools_bridge_start"; }).length, 1);
            compare(root.bridgeCalls.length, 1);
            compare(root.bridgeCalls[0].url, "http://127.0.0.1:41234/tools");
            compare(root.bridgeCalls[0].body.web.search, "searxng");
            compare(root.bridgeCalls[0].body.web.searxngUrl, "https://searx.example.org");
            compare(Object.keys(root.bridgeCalls[0].body.servers), ["files", "broken"]);
            compare(rowTexts(), ["files: 3 tools", "broken: Not working: it exited at once", "Web: 1 tool"]);
            wait(100);
            screenshot(page, "config-tools-checked");

            // Changed but not saved text is what the next check uses.
            named("serversArea").text = "{ \"files\": { \"command\": \"x\" } }";
            mouseClick(named("checkButton"));
            tryVerify(function() { return root.bridgeCalls.length === 2 && !page.checking; }, 3000);
            compare(commands().filter(function(c) { return c === "tools_bridge_start"; }).length, 1, "the running bridge is used again");
            compare(Object.keys(root.bridgeCalls[1].body.servers), ["files"]);
            compare(rowTexts(), ["files: 3 tools", "Web: 1 tool"]);
        }

        function test_check_with_nothing_configured_starts_nothing() {
            open();
            mouseClick(named("checkButton"));
            compare(root.bridgeCalls.length, 0);
            compare(commands().indexOf("tools_bridge_start"), -1);
            verify(named("checkNothing").visible);
        }

        function test_a_key_is_saved_through_the_helper_and_the_field_is_cleared() {
            root.savedKeys = {"brave": false, "tavily": true};
            open({"cfg_webSearchProvider": "brave"});
            verify(named("keyField").visible);
            compare(named("keyField").echoMode, TextInput.Password);
            compare(named("keyStatusLabel").text, "No key is saved");
            verify(!named("saveKeyButton").enabled, "nothing to save yet");
            named("keyField").text = "BSA-123456";
            verify(named("saveKeyButton").enabled);
            named("saveKeyButton").clicked();
            var set = root.helperCalls.filter(function(c) { return c.command === "tools_key_set"; });
            compare(set.length, 1);
            compare(set[0].payload, {"name": "brave", "key": "BSA-123456"});
            compare(named("keyField").text, "", "the key does not stay on the page");
            compare(named("keyStatusLabel").text, "The key is saved.");
            compare(page.keyStatus.brave, true);
            // The key is nowhere in the page's settings.
            for (var name in page)
                if (name.indexOf("cfg_") === 0)
                    verify(String(page[name]).indexOf("BSA-123456") < 0, name);
            // Switching to the service that has a key already says so.
            named("searchCombo").currentIndex = named("searchCombo").indexOfValue("tavily");
            named("searchCombo").activated(named("searchCombo").currentIndex);
            compare(page.cfg_webSearchProvider, "tavily");
            compare(page.keyMessage, "The key is saved.");
            wait(100);
            screenshot(page, "config-tools-key");
        }

        function test_a_key_can_be_removed_and_a_failure_is_shown() {
            root.savedKeys = {"brave": true, "tavily": false};
            open({"cfg_webSearchProvider": "brave"});
            tryVerify(function() { return page.keyStatus.brave === true; }, 2000);
            compare(named("keyStatusLabel").text, "A key is saved");
            named("removeKeyButton").clicked();
            var set = root.helperCalls.filter(function(c) { return c.command === "tools_key_set"; });
            compare(set[0].payload, {"name": "brave", "key": ""});
            compare(named("keyStatusLabel").text, "The key is removed.");
            compare(page.keyStatus.brave, false);

            root.keyResult = "error";
            named("keyField").text = "abc";
            named("saveKeyButton").clicked();
            compare(named("keyStatusLabel").text, "KWallet is locked.");
            compare(named("keyField").text, "");
        }

        function test_the_key_field_is_only_for_services_with_a_key() {
            open({"cfg_webSearchProvider": "searxng"});
            verify(!named("keyField").visible);
            page.cfg_webSearchProvider = "none";
            verify(!named("searxField").visible);
            page.cfg_webSearchProvider = "tavily";
            verify(named("keyField").visible);
        }

        function test_reading_web_pages_is_a_setting() {
            open();
            compare(named("fetchCheck").text, "Let the AI read web pages (fetch_url)");
            mouseClick(named("fetchCheck"));
            compare(page.cfg_webFetchEnabled, true);
        }

        function test_ask_again_clears_the_always_allowed_list() {
            open({"cfg_toolsAlwaysAllowed": "[\"files__read\", \"web_search\"]"});
            compare(named("allowedList").text, "files__read, web_search");
            verify(named("askAgainButton").enabled);
            mouseClick(named("askAgainButton"));
            compare(page.cfg_toolsAlwaysAllowed, "[]");
            compare(named("allowedList").text, "None: every tool asks first.");
            verify(!named("askAgainButton").enabled);
        }
    }
}
