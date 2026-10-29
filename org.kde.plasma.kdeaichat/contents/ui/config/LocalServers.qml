// "Find local servers" (Settings → Connection): lists the AI programs that
// answer on this computer (Ollama, LM Studio, llama.cpp, LiteLLM, vLLM, Jan
// and other OpenAI-compatible servers), each with a "Use" button that adds it
// as a provider. The helper's local_servers_scan only asks 127.0.0.1 on six
// fixed ports, with short timeouts, and sends no key. It runs quietly when
// the page opens (nothing is shown unless something answers) and again on
// the button, which also says when nothing was found.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "LocalServers.js" as LocalServers

// i18n() and i18np() are provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: panel

    // The provider list (to mark servers already added) and the helper (tests pass a fake).
    property var providers: []
    property var helper: null
    // False while another way of chatting than direct is chosen: no scan then.
    property bool active: true
    // A provider is being edited: Use is off (as Add provider is).
    property bool busy: false

    property bool running: false
    // "" before a scan, then ok | failed.
    property string phase: ""
    property bool manual: false
    property var servers: []
    property int _generation: 0

    signal useServer(var server)

    spacing: Kirigami.Units.smallSpacing

    function scan(fromButton) {
        if (running || !helper)
            return;
        running = true;
        manual = fromButton === true;
        var generation = ++_generation;
        helper.run("local_servers_scan", {}, function(stdout, exitCode) {
            if (generation !== panel._generation)
                return;
            var list = LocalServers.parse(stdout, exitCode);
            panel.servers = list || [];
            panel.phase = list ? "ok" : "failed";
            panel.running = false;
        });
    }

    function title(server) {
        return server.kind === "openai" ? i18n("OpenAI-compatible server") : server.name;
    }

    function detail(server) {
        var where = "127.0.0.1:" + server.port;
        if (server.needsKey)
            return where + " · " + i18n("asks for a key");
        return where + " · " + i18np("%1 model", "%1 models", server.count);
    }

    Component.onCompleted: {
        if (active)
            Qt.callLater(function() { panel.scan(false); });
    }
    onActiveChanged: {
        if (active && phase === "")
            scan(false);
    }

    // The quiet scan shows only what it found; the button also reports an empty result or a failure.
    readonly property bool showResult: phase !== "" && (manual || servers.length > 0)

    RowLayout {
        Layout.fillWidth: true
        Kirigami.Heading {
            level: 4
            text: i18n("Local servers")
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        QQC2.BusyIndicator {
            objectName: "localServersBusy"
            visible: panel.running
            running: panel.running
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
        }
        QQC2.Button {
            objectName: "findLocalServers"
            text: i18n("Find local servers")
            icon.name: "view-refresh"
            enabled: !panel.running && panel.helper !== null
            onClicked: panel.scan(true)
        }
    }

    SettingHelp {
        objectName: "localServersHelp"
        text: i18n("Looks for AI programs running on this computer, such as Ollama or LM Studio, and lets you add one with a click. It only asks this computer, never the network, and never sends a saved key. Most need no key; one that asks for a key (such as a LiteLLM proxy) says so.")
        details: i18n("It checks these places on this computer only: Ollama (11434), LM Studio (1234), llama.cpp or LocalAI (8080), LiteLLM (4000), vLLM (8000) and Jan (1337). It just asks each one for its list of models, for about a second at most, and sends no key or other secret.")
    }

    QQC2.Label {
        objectName: "localServersEmpty"
        Layout.fillWidth: true
        visible: panel.showResult && panel.phase === "ok" && panel.servers.length === 0
        wrapMode: Text.Wrap
        text: i18n("No AI program answered on this computer. If you use one, start it and try again.")
    }

    QQC2.Label {
        objectName: "localServersFailed"
        Layout.fillWidth: true
        visible: panel.showResult && panel.phase === "failed"
        wrapMode: Text.Wrap
        color: Kirigami.Theme.negativeTextColor
        text: i18n("Could not look for local servers.")
    }

    Repeater {
        model: panel.servers
        delegate: ColumnLayout {
            id: line
            required property var modelData
            readonly property bool added: LocalServers.isAdded(line.modelData, panel.providers)
            Layout.fillWidth: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Kirigami.Icon {
                    source: "computer"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    QQC2.Label {
                        textFormat: Text.PlainText
                        objectName: "localServerName"
                        text: panel.title(line.modelData)
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        textFormat: Text.PlainText
                        objectName: "localServerDetail"
                        text: panel.detail(line.modelData)
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                QQC2.Label {
                    objectName: "localServerAdded"
                    visible: line.added
                    text: i18n("In your list")
                    opacity: 0.7
                }
                QQC2.Button {
                    objectName: "useLocalServer"
                    visible: !line.added
                    enabled: !panel.busy
                    text: i18n("Use")
                    icon.name: "list-add"
                    onClicked: panel.useServer(line.modelData)
                    Accessible.name: i18n("Use %1", panel.title(line.modelData))
                }
            }
            Kirigami.Separator {
                Layout.fillWidth: true
                opacity: 0.4
            }
        }
    }
}
