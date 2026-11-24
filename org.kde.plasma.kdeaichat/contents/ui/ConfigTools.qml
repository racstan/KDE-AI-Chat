// Settings → Tools: what the AI may use in a direct chat besides its own knowledge: the tools of the
// user's MCP servers, a web search and reading web pages. Every call asks the user first (Allow /
// Always allow / Reject) in the chat; scheduled runs get no tools.
//
// The servers are JSON text in the common "mcpServers" format. "Check servers" starts the tool bridge
// (kdeaichat/tool_bridge_server.py, through the helper) with the values on this page, saved or not, and
// lists what each server offers. The Brave / Tavily key goes to KWallet through the helper and is never
// read back: this page only knows whether one is saved.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "store" as Store
import "config" as Config
import "chat" as Chat
import "config/ToolsCheck.js" as ToolsCheck

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    property alias cfg_toolServers: serversArea.text
    property string cfg_webSearchProvider: "none"
    property alias cfg_searxngUrl: searxField.text
    property alias cfg_webFetchEnabled: fetchCheck.checked
    property string cfg_toolsAlwaysAllowed: "[]"

    // Runs the helper's commands; tests pass a fake with run(command, payload, onDone).
    property var helperRunner: defaultRunner
    // Replaces XMLHttpRequest for the tool bridge in tests.
    property var toolXhrFactory: null

    // Which search keys are saved: {brave, tavily}. Never the keys.
    property var keyStatus: ({"brave": false, "tavily": false})
    property string keyMessage: ""
    property bool keyMessageIsError: false
    // The result of Check servers: [{name, text, ok}], and whether it is running.
    property var checkRows: []
    property bool checking: false
    property bool checked: false

    readonly property var searchChoices: [
        {"text": i18n("None"), "value": "none"},
        {"text": i18n("SearXNG"), "value": "searxng"},
        {"text": i18n("Brave Search"), "value": "brave"},
        {"text": i18n("Tavily"), "value": "tavily"}
    ]
    readonly property bool needsKey: page.cfg_webSearchProvider === "brave" || page.cfg_webSearchProvider === "tavily"
    readonly property var parsedServers: parse(serversArea.text)
    readonly property var allowedTools: {
        try {
            var list = JSON.parse(page.cfg_toolsAlwaysAllowed || "[]");
            return Array.isArray(list) ? list : [];
        } catch (e) {
            return [];
        }
    }

    function searchIndex(value) {
        for (var i = 0; i < page.searchChoices.length; i++)
            if (page.searchChoices[i].value === value)
                return i;
        return 0;
    }

    // {ok, count, message} for the server text: empty is fine (no servers); otherwise a JSON object,
    // optionally wrapped in "mcpServers".
    function parse(text) {
        var raw = String(text || "").trim();
        if (raw === "")
            return {"ok": true, "count": 0, "message": ""};
        try {
            var value = JSON.parse(raw);
            if (!value || typeof value !== "object" || Array.isArray(value))
                return {"ok": false, "count": 0, "message": i18n("it must be an object like { \"name\": { ... } }")};
            if (value.mcpServers && typeof value.mcpServers === "object")
                value = value.mcpServers;
            return {"ok": true, "count": Object.keys(value).length, "message": ""};
        } catch (e) {
            return {"ok": false, "count": 0, "message": String(e.message || e)};
        }
    }

    function serverNames() {
        var raw = String(serversArea.text || "").trim();
        try {
            var value = raw === "" ? {} : JSON.parse(raw);
            if (value && value.mcpServers && typeof value.mcpServers === "object")
                value = value.mcpServers;
            return value && typeof value === "object" && !Array.isArray(value) ? Object.keys(value) : [];
        } catch (e) {
            return [];
        }
    }

    // Starts the bridge with the values on the page and lists each server with its tool count or its error.
    function checkServers() {
        if (!checker.isEnabled()) {
            page.checkRows = [];
            page.checked = true;
            return;
        }
        page.checking = true;
        checker.reload(function(ok) {
            page.checkRows = ToolsCheck.rows(page.serverNames(), checker.tools, checker.errors, {
                "webName": i18n("Web"), "toolsName": i18n("Tools"),
                "notWorking": function(message) { return i18n("Not working: %1", message); },
                "count": function(n) { return i18np("%1 tool", "%1 tools", n); }});
            page.checking = false;
            page.checked = true;
        });
    }

    function refreshKeys() {
        helperRunner.run("tools_key_status", {}, function(stdout) {
            try {
                var status = JSON.parse(String(stdout).trim().split("\n").pop());
                page.keyStatus = {"brave": status.brave === true, "tavily": status.tavily === true};
            } catch (e) {}
        });
    }

    // Saves (or, with remove, deletes) the key of the chosen search service. The field is cleared at once.
    function saveKey(remove) {
        var name = page.cfg_webSearchProvider;
        if (!page.needsKey || (!remove && keyField.text.trim() === ""))
            return;
        var key = remove ? "" : keyField.text;
        keyField.text = "";
        helperRunner.run("tools_key_set", {"name": name, "key": key}, function(stdout) {
            var result = {};
            try { result = JSON.parse(String(stdout).trim().split("\n").pop()); } catch (e) { result = {}; }
            page.keyMessageIsError = result.status !== "saved" && result.status !== "removed";
            page.keyMessage = result.status === "saved" ? i18n("The key is saved.") : result.status === "removed" ? i18n("The key is removed.")
                : (result.message || i18n("The key could not be saved."));
            page.refreshKeys();
        });
    }

    function askAgain() {
        page.cfg_toolsAlwaysAllowed = "[]";
    }

    Component.onCompleted: refreshKeys()

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    // The chat's own bridge code, fed the values on this page instead of the saved ones.
    Chat.ToolBridge {
        id: checker
        xhrFactory: page.toolXhrFactory
        runHelper: function(command, payload, onDone) { page.helperRunner.run(command, payload, onDone); }
        chat: QtObject {
            property var plasmoid: QtObject {
                property var configuration: ({"toolServers": serversArea.text, "webSearchProvider": page.cfg_webSearchProvider,
                                              "searxngUrl": searxField.text, "webFetchEnabled": fetchCheck.checked})
            }
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.75
            text: i18n("Tools let the AI do things for you, like reading a file through an MCP server or searching the web. They work in direct chats only (not OpenCode or Pi), and every single use asks you first: Allow, Always allow or Reject. Scheduled runs get no tools.")
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("MCP servers")
            }

            QQC2.ScrollView {
                Kirigami.FormData.label: i18n("Servers:")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 28
                Layout.preferredHeight: Kirigami.Units.gridUnit * 10

                QQC2.TextArea {
                    id: serversArea
                    objectName: "serversArea"
                    Accessible.name: i18n("MCP servers as JSON")
                    font.family: "monospace"
                    wrapMode: TextEdit.NoWrap
                    selectByMouse: true
                    placeholderText: "{\n  \"files\": {\n    \"command\": \"npx\",\n    \"args\": [\"-y\", \"@modelcontextprotocol/server-filesystem\", \"/home/me/docs\"]\n  }\n}"
                }
            }

            Config.SettingHelp {
                text: i18n("The servers whose tools the AI may use, as JSON in the format most MCP programs use: a name for each server with either a command to start it (“command”, “args”, “env”) or a web address (“url”, “headers”). Leave it empty to use none. A server named “files” that runs a command looks like { \"files\": { \"command\": \"npx\", \"args\": [\"-y\", \"@modelcontextprotocol/server-filesystem\", \"/home/me/docs\"] } }. The commands run as you, so only add servers you trust.")
            }

            QQC2.Label {
                objectName: "serversStatus"
                Kirigami.FormData.label: i18n("Check:")
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: !page.parsedServers.ok ? i18n("Not valid JSON: %1", page.parsedServers.message)
                    : page.parsedServers.count === 0 ? i18n("Valid. No servers.")
                    : i18np("Valid JSON: %1 server.", "Valid JSON: %1 servers.", page.parsedServers.count)
                color: page.parsedServers.ok ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
            }

            RowLayout {
                QQC2.Button {
                    objectName: "checkButton"
                    text: page.checking ? i18n("Checking…") : i18n("Check servers")
                    icon.name: "view-refresh"
                    enabled: !page.checking && page.parsedServers.ok
                    onClicked: page.checkServers()
                }
            }

            Config.SettingHelp {
                text: i18n("Starts the servers with what is above (you do not have to save first) and shows how many tools each one offers, or why it does not work. The first start of a server can take a moment.")
            }

            ColumnLayout {
                objectName: "checkResults"
                Layout.fillWidth: true
                visible: page.checked

                QQC2.Label {
                    objectName: "checkNothing"
                    visible: page.checkRows.length === 0
                    text: i18n("Nothing to check yet: add a server or turn on a web tool.")
                    opacity: 0.75
                }

                Repeater {
                    model: page.checkRows

                    QQC2.Label {
                        required property var modelData
                        objectName: "checkRow"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: modelData.name + ": " + modelData.text
                        color: modelData.ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    }
                }
            }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Web")
            }

            QQC2.ComboBox {
                id: searchCombo
                objectName: "searchCombo"
                Kirigami.FormData.label: i18n("Web search:")
                Accessible.name: Kirigami.FormData.label
                textRole: "text"
                valueRole: "value"
                model: page.searchChoices
                currentIndex: page.searchIndex(page.cfg_webSearchProvider)
                onActivated: page.cfg_webSearchProvider = currentValue
            }

            Config.SettingHelp {
                text: i18n("Lets the AI search the web with the “web_search” tool. SearXNG is a search site you run yourself or use at an address you trust; Brave Search and Tavily need an account and a key. Each search asks you first.")
            }

            QQC2.TextField {
                id: searxField
                objectName: "searxField"
                Kirigami.FormData.label: i18n("SearXNG address:")
                Accessible.name: Kirigami.FormData.label
                visible: page.cfg_webSearchProvider === "searxng"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 20
                placeholderText: "https://searx.example.org"
            }

            Config.SettingHelp {
                visible: page.cfg_webSearchProvider === "searxng"
                text: i18n("The web address of the SearXNG site. It has to allow JSON results.")
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Search key:")
                visible: page.needsKey

                QQC2.TextField {
                    id: keyField
                    objectName: "keyField"
                    Accessible.name: i18n("Search key")
                    echoMode: TextInput.Password
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                    placeholderText: page.keyStatus[page.cfg_webSearchProvider] === true ? i18n("A key is saved") : i18n("Paste the key here")
                    onAccepted: page.saveKey(false)
                }

                QQC2.Button {
                    objectName: "saveKeyButton"
                    text: i18n("Save")
                    icon.name: "document-save"
                    enabled: keyField.text.trim() !== ""
                    onClicked: page.saveKey(false)
                }

                QQC2.Button {
                    objectName: "removeKeyButton"
                    text: i18n("Remove")
                    icon.name: "edit-delete"
                    enabled: page.keyStatus[page.cfg_webSearchProvider] === true
                    onClicked: page.saveKey(true)
                }
            }

            Config.SettingHelp {
                visible: page.needsKey
                text: i18n("The key is kept in KWallet, not in the settings, and is never shown again: to change it, save a new one.")
            }

            QQC2.Label {
                objectName: "keyStatusLabel"
                Kirigami.FormData.label: i18n("Key:")
                visible: page.needsKey
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: page.keyMessage !== "" ? page.keyMessage
                    : page.keyStatus[page.cfg_webSearchProvider] === true ? i18n("A key is saved") : i18n("No key is saved")
                color: page.keyMessageIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            }

            QQC2.CheckBox {
                id: fetchCheck
                objectName: "fetchCheck"
                Kirigami.FormData.label: i18n("Web pages:")
                text: i18n("Let the AI read web pages (fetch_url)")
            }

            Config.SettingHelp {
                text: i18n("Lets the AI open a web address and read the page with the “fetch_url” tool. Each page asks you first. Addresses on your own computer or network are refused.")
            }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Always allowed")
            }

            QQC2.Label {
                objectName: "allowedList"
                Kirigami.FormData.label: i18n("Tools:")
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: page.allowedTools.length === 0 ? i18n("None: every tool asks first.") : page.allowedTools.join(", ")
            }

            QQC2.Button {
                objectName: "askAgainButton"
                Kirigami.FormData.label: i18n("Reset:")
                text: i18n("Ask again for all tools")
                icon.name: "edit-clear-history"
                enabled: page.allowedTools.length > 0
                onClicked: page.askAgain()
            }

            Config.SettingHelp {
                text: i18n("Tools you chose “Always allow” for run without asking. This button makes every tool ask again.")
            }
        }
    }
}
