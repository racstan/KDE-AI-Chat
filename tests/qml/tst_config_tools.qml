// Settings → Tools (ConfigTools.qml and config/Mcp*.qml, ToolApprovals.qml) against a fake helper that keeps
// mcp.json and the remembered approvals in memory, a fake KWallet and a fake MCP bridge: the server list, on/off,
// Test (tool count or the server's error), delete, adding a program or a web address with secret values going
// to the wallet and never through the helper, importing from other apps, forgetting approvals, and the
// rounds setting being the only cfg_ property.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest

Item {
    id: root
    width: 820
    height: 900

    property QtObject plasmoid: QtObject {
        property string id: ""
        property QtObject configuration: QtObject {
        }
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(singular, plural, count) {
        var text = count === 1 ? singular : plural;
        for (var i = 2; i < arguments.length; i++)
            text = text.replace("%" + (i - 1), arguments[i]);
        return text.replace("%1", count);
    }

    // The fake world.
    property var servers: []          // what mcp.json holds
    property var candidates: []       // what mcp_import finds
    property var approvals: []
    property var helperPayloads: []   // every command and payload the helper was given
    property var walletEntries: ({})  // "mcp-<id>" -> {FIELD: value}
    property var bridgeTools: ({})    // server id -> [names] | "error text"
    property var bridgeBodies: []

    function fakeHelper(command, payload, onDone) {
        root.helperPayloads = root.helperPayloads.concat([command + " " + JSON.stringify(payload)]);
        var out = {"status": "ok"};
        if (command === "mcp_list") {
            out.servers = root.servers.map(function(s) { return Object.assign({}, s); });
        } else if (command === "mcp_save") {
            var def = Object.assign({}, payload.server);
            var id = def.id;
            delete def.id;
            var next = root.servers.filter(function(s) { return s.id !== id; });
            root.servers = next.concat([Object.assign({"id": id}, def)]);
            out.id = id;
        } else if (command === "mcp_delete") {
            root.servers = root.servers.filter(function(s) { return s.id !== payload.id; });
        } else if (command === "mcp_import") {
            out.servers = root.candidates;
        } else if (command === "mcp_bridge_start") {
            out = {"status": "running", "port": 4242, "token": "tok"};
        } else if (command === "tool_approvals_list") {
            out = {"keys": root.approvals};
        } else if (command === "tool_approvals_remove") {
            root.approvals = root.approvals.filter(function(k) { return k !== payload.key; });
            out = {"keys": root.approvals};
        }
        if (onDone)
            onDone(JSON.stringify(out), 0, "");
    }

    property QtObject fakeWallet: QtObject {
        property bool fails: false
        function readEntry(name, cb) { cb(true, root.walletEntries[name] || {}); }
        function writeEntry(name, fields, cb) {
            if (fails) {
                cb(false);
                return;
            }
            var next = Object.assign({}, root.walletEntries);
            if (Object.keys(fields).length === 0)
                delete next[name];
            else
                next[name] = fields;
            root.walletEntries = next;
            cb(true);
        }
    }

    function makeBridgeXhr() {
        var x = {"readyState": 0, "status": 0, "responseText": "", "url": "",
            "open": function(m, url) { x.url = url; },
            "setRequestHeader": function() {},
            "send": function(body) {
                var b = JSON.parse(body);
                root.bridgeBodies = root.bridgeBodies.concat([b]);
                var answer = {"servers": {}};
                b.servers.forEach(function(d) {
                    var t = root.bridgeTools[d.id];
                    answer.servers[d.id] = typeof t === "string" ? {"error": t}
                        : {"tools": (t || []).map(function(n) { return {"name": n, "description": "", "inputSchema": {}}; })};
                });
                x.status = 200;
                x.responseText = JSON.stringify(answer);
                x.readyState = 4;
                x.onreadystatechange();
            }};
        return x;
    }

    HarnessTestCase {
        id: tc
        name: "ConfigTools"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        function open() {
            var component = Qt.createComponent(uiDir + "ConfigTools.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, {"width": root.width, "height": root.height, "cfg_directToolMaxRounds": 8,
                                                  "runHelper": root.fakeHelper, "wallet": root.fakeWallet, "xhrFactory": root.makeBridgeXhr});
            verify(page !== null);
            return page;
        }
        function init() {
            root.servers = [];
            root.candidates = [];
            root.approvals = [];
            root.helperPayloads = [];
            root.walletEntries = ({});
            root.bridgeTools = ({});
            root.bridgeBodies = [];
            root.fakeWallet.fails = false;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            wait(100);
        }
        function named(name) { return findChild(page, name); }
        function all(name) { return findChildren(page, name); }
        function helperText() { return root.helperPayloads.join("\n"); }
        function typeInto(field, text) {
            field.text = text;
            field.textEdited();
        }
        function addRowTo(prefix, name, value, secret) {
            var n = 0;
            while (named(prefix + "Name" + n) !== null)
                n++;
            named(prefix + "Add").clicked();
            tryVerify(function() { return named(prefix + "Name" + n) !== null; });
            typeInto(named(prefix + "Name" + n), name);
            typeInto(named(prefix + "Value" + n), value);
            named(prefix + "Secret" + n).checked = secret;
            named(prefix + "Secret" + n).toggled();
        }
        // The row of one server.
        function row(id) { return named("mcpRow-" + id); }

        function test_lists_servers_and_the_empty_state() {
            open();
            verify(named("mcpEmpty").visible);
            page.destroy();
            root.servers = [{"id": "files", "command": "mcp-files", "args": ["--ro"], "env": {"K": {"secret": "K"}}, "enabled": true},
                            {"id": "web", "url": "https://mcp.test/x", "headers": {}, "enabled": false}];
            open();
            compare(all("mcpEnabled").length, 2);
            verify(!named("mcpEmpty").visible);
            compare(findChild(row("files"), "mcpEnabled").checked, true);
            compare(findChild(row("web"), "mcpEnabled").checked, false);
            tc.screenshot(page, "config-tools-list");
        }

        function test_on_off_is_saved_at_once() {
            root.servers = [{"id": "files", "command": "mcp-files", "args": [], "env": {}, "enabled": true}];
            open();
            var sw = findChild(row("files"), "mcpEnabled");
            sw.toggle();
            sw.toggled();
            tryVerify(function() { return root.servers[0].enabled === false; });
            compare(root.servers[0].command, "mcp-files");
        }

        function test_test_shows_the_tool_count_or_the_error() {
            root.servers = [{"id": "files", "command": "mcp-files", "args": [], "env": {}, "enabled": true},
                            {"id": "bad", "command": "nope", "args": [], "env": {}, "enabled": true}];
            root.bridgeTools = ({"files": ["echo", "lookup"], "bad": "Couldn't start nope: No such file or directory"});
            open();
            findChild(row("files"), "mcpTest").clicked();
            tryCompare(findChild(row("files"), "mcpTestResult"), "visible", true);
            compare(findChild(row("files"), "mcpTestResult").text, "Works: 2 tools (echo, lookup)");
            findChild(row("bad"), "mcpTest").clicked();
            compare(findChild(row("bad"), "mcpTestResult").text, "Couldn't use this server: Couldn't start nope: No such file or directory");
            tc.screenshot(page, "config-tools-test");
        }

        function test_a_secret_missing_from_the_wallet_is_shown_when_testing() {
            root.servers = [{"id": "api", "url": "https://mcp.test/x", "headers": {"Authorization": {"secret": "Authorization"}}, "enabled": true}];
            open();
            findChild(row("api"), "mcpTest").clicked();
            verify(findChild(row("api"), "mcpTestResult").text.indexOf("The wallet has no value for: Authorization") >= 0);
            compare(root.bridgeBodies.length, 0, "the bridge was not asked");
        }

        function test_delete_asks_first_and_removes_the_wallet_entry() {
            root.servers = [{"id": "files", "command": "mcp-files", "args": [], "env": {"K": {"secret": "K"}}, "enabled": true}];
            root.walletEntries = ({"mcp-files": {"K": "v"}});
            open();
            mouseClick(named("mcpDelete"));
            verify(named("mcpDeleteConfirm").visible);
            compare(root.servers.length, 1);
            mouseClick(named("mcpDeleteConfirm"));
            compare(root.servers.length, 0);
            compare(Object.keys(root.walletEntries).length, 0);
            tryVerify(function() { return named("mcpEmpty").visible; });
        }

        function test_adding_a_program_with_a_secret_puts_the_value_in_the_wallet_only() {
            open();
            mouseClick(named("mcpAddButton"));
            typeInto(named("mcpNameField"), "My Files");
            typeInto(named("mcpCommandField"), "npx");
            named("mcpArgsField").text = "-y\n@scope/server-files\n/home/me";
            addRowTo("mcpEnv", "API_KEY", "s3cret-value", true);
            addRowTo("mcpEnv", "LEVEL", "debug", false);
            tc.screenshot(page, "config-tools-add");
            mouseClick(named("mcpSaveButton"));
            compare(root.servers.length, 1);
            var s = root.servers[0];
            compare(s.id, "my-files");
            compare(s.command, "npx");
            compare(JSON.stringify(s.args), '["-y","@scope/server-files","/home/me"]');
            compare(JSON.stringify(s.env), '{"API_KEY":{"secret":"API_KEY"},"LEVEL":"debug"}');
            compare(JSON.stringify(root.walletEntries["mcp-my-files"]), '{"API_KEY":"s3cret-value"}');
            verify(helperText().indexOf("s3cret-value") < 0, "the value never went through the helper");
            compare(page.view, "list");
            compare(all("mcpEnabled").length, 1);
        }

        function test_adding_a_web_address_with_a_secret_header() {
            open();
            mouseClick(named("mcpAddButton"));
            typeInto(named("mcpNameField"), "Remote");
            named("mcpKindUrl").checked = true;
            typeInto(named("mcpUrlField"), "https://mcp.example.com/mcp");
            addRowTo("mcpHeader", "Authorization", "Bearer tkn-123", true);
            mouseClick(named("mcpSaveButton"));
            compare(root.servers.length, 1);
            compare(root.servers[0].url, "https://mcp.example.com/mcp");
            compare(JSON.stringify(root.servers[0].headers), '{"Authorization":{"secret":"Authorization"}}');
            compare(root.walletEntries["mcp-remote"].Authorization, "Bearer tkn-123");
            verify(helperText().indexOf("tkn-123") < 0);
        }

        function test_a_name_that_is_taken_gets_a_new_id_and_mistakes_are_explained() {
            root.servers = [{"id": "files", "command": "a", "args": [], "env": {}, "enabled": true}];
            open();
            mouseClick(named("mcpAddButton"));
            mouseClick(named("mcpSaveButton"));
            verify(named("mcpSaveButton").enabled);
            compare(root.servers.length, 1);
            typeInto(named("mcpNameField"), "files");
            typeInto(named("mcpCommandField"), "b");
            mouseClick(named("mcpSaveButton"));
            compare(root.servers.map(function(s) { return s.id; }).join(), "files,files-2");
        }

        function test_a_wallet_that_refuses_saves_nothing() {
            root.fakeWallet.fails = true;
            open();
            mouseClick(named("mcpAddButton"));
            typeInto(named("mcpNameField"), "x");
            typeInto(named("mcpCommandField"), "run");
            addRowTo("mcpEnv", "TOKEN", "t", true);
            mouseClick(named("mcpSaveButton"));
            compare(root.servers.length, 0);
            compare(page.view, "add");
        }

        function test_import_offers_candidates_and_puts_secrets_in_the_wallet() {
            root.candidates = [
                {"id": "github", "name": "github", "source": "Claude Desktop", "enabled": true, "command": "npx", "args": ["-y", "gh-mcp"],
                 "env": {"GITHUB_TOKEN": {"secret": "GITHUB_TOKEN", "value": "ghp-secret-1"}, "MODE": "ro"}, "exists": false},
                {"id": "files", "name": "files", "source": "OpenCode", "enabled": true, "command": "x", "args": [], "env": {}, "exists": true},
                {"id": "broken", "name": "broken", "source": "OpenCode", "enabled": true, "command": "y", "args": [], "env": {}, "problem": "The id isn't valid.", "exists": false},
                {"id": "remote", "name": "remote", "source": "OpenCode", "enabled": true, "url": "https://mcp.test/x",
                 "headers": {"Authorization": {"secret": "Authorization", "value": "Bearer remote-secret-2"}}, "exists": false}];
            open();
            mouseClick(named("mcpImportOpen"));
            tryVerify(function() { return named("mcpImport-github") !== null; });
            verify(named("mcpImport-github").enabled);
            verify(!named("mcpImport-files").enabled, "already added");
            verify(!named("mcpImport-broken").enabled, "can't be used");
            verify(!named("mcpImportButton").enabled, "nothing is imported until something is ticked");
            tc.screenshot(page, "config-tools-import");
            mouseClick(named("mcpImport-github"));
            mouseClick(named("mcpImport-remote"));
            mouseClick(named("mcpImportButton"));
            compare(root.servers.map(function(s) { return s.id; }).sort().join(), "github,remote");
            compare(JSON.stringify(root.walletEntries["mcp-github"]), '{"GITHUB_TOKEN":"ghp-secret-1"}');
            compare(root.walletEntries["mcp-remote"].Authorization, "Bearer remote-secret-2");
            var github = root.servers.filter(function(s) { return s.id === "github"; })[0];
            compare(JSON.stringify(github.env), '{"GITHUB_TOKEN":{"secret":"GITHUB_TOKEN"},"MODE":"ro"}');
            verify(helperText().indexOf("ghp-secret-1") < 0, "no secret through the helper");
            verify(helperText().indexOf("remote-secret-2") < 0);
            verify(named("mcpImportResult").text.indexOf("Added 2") === 0);
        }

        function test_remembered_approvals_can_be_forgotten() {
            root.approvals = ["mcp:files:echo", "mcp:web:lookup"];
            open();
            compare(all("approvalLabel").length, 2);
            compare(all("approvalLabel").map(function(l) { return l.text; }).sort().join(), "echo (files),lookup (web)");
            mouseClick(all("approvalForget")[0]);
            compare(root.approvals.length, 1);
            compare(all("approvalLabel").length, 1);
            mouseClick(all("approvalForget")[0]);
            tryVerify(function() { return named("approvalsEmpty").visible; });
        }

        function test_the_rounds_setting_is_the_only_cfg_property_and_no_secret() {
            open();
            var box = named("maxRoundsBox");
            compare(box.from, 1);
            compare(box.to, 50);
            compare(box.value, 8);
            box.value = 20;
            box.valueModified();
            compare(page.cfg_directToolMaxRounds, 20);
            var cfg = [];
            for (var name in page)
                if (name.indexOf("cfg_") === 0 && name.indexOf("Changed") < 0)
                    cfg.push(name);
            compare(cfg.join(), "cfg_directToolMaxRounds");
        }
    }
}
