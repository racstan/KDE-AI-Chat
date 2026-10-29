// Harness settings for OpenCode: the server address, starting/stopping a
// server the widget owns, and the default provider and model, read from the
// server's /config/providers, and the model's variant when the server reports
// any for it (only the variant NAMES are read from that answer: it also carries
// the user's API keys, which are never kept).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components" as Components
import "../Security.js" as Sec
import "../Variants.js" as Variants
import "../backends/OpenCodeBackend.js" as OpenCodeBackend
import "../backends/OpenCodeCatalog.js" as OpenCodeCatalog

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: oc

    property string url: ""
    property string provider: ""
    property string model: ""
    property string variant: ""      // the variant's name ("" = none)
    property var helper: null        // store/HelperRunner.qml
    property bool active: false      // loads the server's providers when true

    property var providers: []
    property var modelsByProvider: ({})
    property var variantsByModel: ({})   // "provider/model" -> variant names
    readonly property var variants: Variants.fromOpenCodeNames(variantsByModel[provider + "/" + model])
    property string status: ""
    property bool busy: false

    onActiveChanged: if (active) refresh()
    Component.onCompleted: if (active) refresh()

    function serverRoot() {
        var value = String(url || "").replace(/\/$/, "");
        return value.slice(-3) === "/v1" ? value.slice(0, -3) : value;
    }

    function port() {
        var match = /:(\d+)/.exec(String(url || "").replace(/^[a-z]+:\/\//i, ""));
        return match ? Number(match[1]) : 4096;
    }

    function modelIds(entry) {
        var ids = [];
        var models = entry && entry.models;
        if (!models)
            return ids;
        var list = Array.isArray(models) ? models : Object.keys(models).map(function(key) {
            return models[key] && models[key].id ? models[key].id : key;
        });
        for (var i = 0; i < list.length; i++) {
            var id = typeof list[i] === "string" ? list[i] : (list[i] && list[i].id) || "";
            if (id && ids.indexOf(id) < 0)
                ids.push(id);
        }
        return ids;
    }

    // Picks `providerId` and keeps the model when that provider has it.
    function choose(providerId, preferredModel) {
        var models = modelsByProvider[providerId] || [];
        var next = preferredModel || model;
        if (models.length > 0 && models.indexOf(next) < 0)
            next = models[0];
        if (providerId !== provider || (next || "") !== model)
            variant = "";
        provider = providerId;
        model = next || "";
    }

    function applyProviders(obj) {
        var list = (obj && obj.providers) || [];
        var ids = [];
        var map = {};
        for (var i = 0; i < list.length; i++) {
            var id = list[i] && (list[i].id || list[i].name);
            if (!id || ids.indexOf(id) >= 0)
                continue;
            ids.push(id);
            map[id] = modelIds(list[i]);
        }
        modelsByProvider = map;
        variantsByModel = OpenCodeCatalog.parse(obj).variants;
        providers = ids;
        if (ids.length === 0) {
            status = i18n("The server answered but has no providers configured.");
            return;
        }
        var chosen = ids.indexOf(provider) >= 0 ? provider : ids[0];
        choose(chosen, model || ((obj && obj["default"]) || {})[chosen] || "");
        status = i18np("Connected. %1 provider available.", "Connected. %1 providers available.", ids.length);
    }

    function refresh() {
        var target = Sec.validateHttpUrl(serverRoot() + "/config/providers");
        if (!target) {
            status = i18n("Enter an http:// or https:// address.");
            return;
        }
        status = i18n("Checking the OpenCode server…");
        if (!helper) {
            oc.request(target);
            return;
        }
        // The server the widget started has a password (helper opencode_server_auth); a local address only.
        helper.run("opencode_server_auth", {"port": port()}, function(stdout) {
            var result = {};
            try { result = JSON.parse(String(stdout).trim().split("\n").pop()); } catch (e) { result = {}; }
            OpenCodeBackend.setAuthorization(/^https?:\/\/(127\.0\.0\.1|localhost|\[::1\]):/i.test(target) ? result.authorization : "");
            oc.request(target);
        });
    }

    function request(target) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", target, true);
        OpenCodeBackend.authorize(xhr);
        xhr.timeout = 15000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    oc.applyProviders(JSON.parse(xhr.responseText));
                } catch (e) {
                    oc.status = i18n("The server sent a reply that isn't JSON.");
                }
            } else {
                oc.providers = [];
                oc.status = xhr.status > 0 ? i18n("The server answered with HTTP %1.", xhr.status)
                                           : i18n("No OpenCode server is answering at this address.");
            }
        };
        xhr.send();
    }

    function runServer(command) {
        if (!helper)
            return;
        busy = true;
        status = command === "opencode_server_start" ? i18n("Starting OpenCode…") : i18n("Stopping OpenCode…");
        helper.run(command, {"port": port()}, function(stdout, exitCode, stderr) {
            oc.busy = false;
            var result = {};
            try { result = JSON.parse(stdout); } catch (e) { result = {"status": "error", "message": stderr || stdout}; }
            var messages = {"started": i18n("OpenCode started."), "already-running": i18n("OpenCode is already running."),
                            "stopped": i18n("OpenCode stopped.")};
            oc.status = messages[result.status] || result.message || i18n("OpenCode: %1", result.status);
            if (result.status === "started" || result.status === "already-running")
                oc.refresh();
        });
    }

    QQC2.TextField {
        Accessible.name: Kirigami.FormData.label
        Kirigami.FormData.label: i18n("Server address:")
        Layout.fillWidth: true
        text: oc.url
        placeholderText: "http://127.0.0.1:4096/v1"
        onTextEdited: oc.url = text
        onEditingFinished: oc.refresh()
    }

    SettingHelp {
        text: i18n("Where the OpenCode program can be reached on this computer. Keep the suggested address unless you started OpenCode on another port.")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Server:")
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            text: i18n("Start")
            icon.name: "media-playback-start"
            enabled: !oc.busy
            onClicked: oc.runServer("opencode_server_start")
        }
        QQC2.Button {
            text: i18n("Stop")
            icon.name: "media-playback-stop"
            enabled: !oc.busy
            onClicked: oc.runServer("opencode_server_stop")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Stops a server started by this widget. Servers you started yourself keep running.")
        }
        QQC2.Button {
            text: i18n("Check")
            icon.name: "view-refresh"
            enabled: !oc.busy
            onClicked: oc.refresh()
        }
        QQC2.BusyIndicator {
            visible: oc.busy
            running: visible
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        }
    }

    SettingHelp {
        text: i18n("OpenCode has to be running for these chats. Start runs it in the background; Check looks whether it answers.")
    }

    QQC2.ComboBox {
        Accessible.name: Kirigami.FormData.label
        Kirigami.FormData.label: i18n("Provider:")
        Layout.fillWidth: true
        enabled: oc.providers.length > 0
        model: oc.providers.length > 0 ? oc.providers : (oc.provider ? [oc.provider] : [])
        currentIndex: Math.max(0, model.indexOf(oc.provider))
        onActivated: oc.choose(currentText, "")
    }

    SettingHelp {
        text: i18n("The AI service OpenCode uses. The list comes from OpenCode's own settings, where its keys are kept.")
    }

    Components.ModelPicker {
        Kirigami.FormData.label: i18n("Model:")
        Layout.fillWidth: true
        model: oc.modelsByProvider[oc.provider] || []
        value: oc.model
        onPicked: function(id) { oc.variant = ""; oc.model = id; }
    }

    SettingHelp {
        text: i18n("The AI model new OpenCode chats use. Each chat can choose another one in its Chat info panel if per-chat model settings are on.")
    }

    Components.VariantPicker {
        objectName: "variantPicker"
        Kirigami.FormData.label: i18n("Variant:")
        Layout.fillWidth: true
        variants: oc.variants
        value: oc.variant
        onPicked: function(id) { oc.variant = id; }
    }

    SettingHelp {
        visible: oc.variants.length > 0
        text: i18n("How hard the model thinks before answering. More thinking helps with hard tasks, but is slower and costs more.")
    }

    QQC2.Label {
        textFormat: Text.PlainText
        Kirigami.FormData.label: i18n("Status:")
        Layout.fillWidth: true
        visible: oc.status !== ""
        text: oc.status
        wrapMode: Text.Wrap
        opacity: 0.8
    }
}
