// Settings → Tools: the MCP servers direct chats can use (add, import, on/off, Test, delete), the tools the
// user chose "Always allow" for (Forget), and how many rounds of tool calls one reply may take.
// Servers and approvals are written at once through the helper (mcp.json, tool-approvals.json) and their
// secrets go to KWallet entries `mcp-<id>`: the only setting here is cfg_directToolMaxRounds. A chat picks
// which servers it uses in its Chat info panel.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "config" as Config
import "store" as Store

// i18n() and plasmoid are provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    // Most rounds of tool calls in one reply (1 to 50).
    property int cfg_directToolMaxRounds: 8

    // Tests replace these.
    property var runHelper: defaultRunner.run
    property var wallet: walletStore
    property var xhrFactory: null

    // "list", "add" or "import".
    property string view: "list"
    readonly property alias store: mcpStore

    function openImport() {
        importList.reset();
        mcpStore.loadCandidates();
        page.view = "import";
    }

    Config.McpStore {
        id: mcpStore
        runHelper: page.runHelper
        wallet: page.wallet
        xhrFactory: page.xhrFactory
    }

    Store.Wallet {
        id: walletStore
    }

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            const path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    Component.onCompleted: mcpStore.load(null)

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            level: 2
            text: i18n("MCP servers")
            Layout.fillWidth: true
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 36
            wrapMode: Text.Wrap
            text: i18n("MCP servers give the AI extra tools, such as reading files or searching a service. Chats that talk to a model directly can use them; OpenCode and Pi chats have their own tools. The AI always asks you before a tool runs, until you choose “Always” for it.")
        }

        Kirigami.InlineMessage {
            objectName: "mcpMessage"
            Layout.fillWidth: true
            visible: mcpStore.message !== ""
            type: Kirigami.MessageType.Warning
            text: mcpStore.message
            showCloseButton: true
            onVisibleChanged: if (!visible) mcpStore.message = ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: page.view === "list"
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                objectName: "mcpEmpty"
                Layout.fillWidth: true
                visible: mcpStore.loaded && mcpStore.servers.length === 0
                opacity: 0.7
                wrapMode: Text.Wrap
                text: i18n("No servers yet. Add one, or import the ones you already use in Claude Desktop or OpenCode.")
            }

            Repeater {
                model: mcpStore.servers

                delegate: Config.McpServerRow {
                    required property var modelData
                    Layout.fillWidth: true
                    server: modelData
                    testResult: mcpStore.tests[modelData.id]
                    onEnabledToggled: function(on) { mcpStore.setEnabled(modelData.id, on); }
                    onTestRequested: mcpStore.test(modelData.id)
                    onDeleteRequested: mcpStore.remove(modelData.id)
                }
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                QQC2.Button {
                    objectName: "mcpAddButton"
                    icon.name: "list-add"
                    text: i18n("Add server…")
                    onClicked: {
                        addForm.reset();
                        page.view = "add";
                    }
                }
                QQC2.Button {
                    objectName: "mcpImportOpen"
                    icon.name: "document-import"
                    text: i18n("Import…")
                    onClicked: page.openImport()
                }
            }
        }

        Config.McpAddForm {
            id: addForm
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 36
            visible: page.view === "add"
            onCancelled: page.view = "list"
            onSaveRequested: function(values) {
                addForm.saving = true;
                mcpStore.add(values, function(ok, error) {
                    addForm.saving = false;
                    addForm.error = ok ? "" : error;
                    if (ok)
                        page.view = "list";
                });
            }
        }

        Config.McpImportList {
            id: importList
            Layout.fillWidth: true
            visible: page.view === "import"
            candidates: mcpStore.candidates
            loaded: mcpStore.candidatesLoaded
            onCancelled: page.view = "list"
            onImportRequested: function(ids) {
                mcpStore.importCandidates(ids, function(count, problems) {
                    importList.result = problems.length > 0
                        ? i18n("Added %1. Not added: %2", count, problems.join("; "))
                        : i18np("Added 1 server.", "Added %1 servers.", count);
                    importList.ticked = ({});
                    mcpStore.loadCandidates();
                });
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            level: 2
            text: i18n("Remembered approvals")
            Layout.fillWidth: true
        }

        Config.ToolApprovals {
            id: approvals
            Layout.fillWidth: true
            runHelper: page.runHelper
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.SpinBox {
                id: roundsBox
                objectName: "maxRoundsBox"
                Kirigami.FormData.label: i18n("Most tool rounds per reply:")
                from: 1
                to: 50
                value: page.cfg_directToolMaxRounds
                onValueModified: page.cfg_directToolMaxRounds = value
            }
            Config.SettingHelp {
                text: i18n("After this many rounds of tool calls in one reply, the AI has to answer with what it has. Raise it for long jobs.")
            }
        }
    }
}
