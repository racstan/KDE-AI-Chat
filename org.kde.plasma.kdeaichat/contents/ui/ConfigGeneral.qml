// Settings → General: notifications, request timeout, chat mode (direct API,
// OpenCode or Pi) and that mode's settings. Direct-mode providers are edited
// in config/ProvidersPanel.qml; OpenCode and Pi settings stay here until
// Phase 3 rebuilds them.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "Security.js" as Sec
import "store" as Store
import "config" as Config

KCM.SimpleKCM {
    id: page

    property alias cfg_appearanceMode: appearanceModeCombo.currentIndex
    property alias cfg_useOpenCode: openCodeToggle.checked
    property alias cfg_usePi: piToggle.checked
    property alias cfg_playNotificationSound: playSoundToggle.checked
    property alias cfg_requestTimeout: requestTimeoutSpinBox.value
    property alias cfg_openCodeUrl: openCodeUrlField.text
    property alias cfg_openCodeModel: openCodeModelValueField.text
    property alias cfg_openCodeProvider: openCodeProviderValueField.text
    property alias cfg_piProvider: piProviderValueField.text
    property alias cfg_piModel: piModelValueField.text

    property string discoveryStatus: ""
    property bool pageReady: false
    property bool openCodeBusy: utilityDs.connectedSources.filter(function(sourceName) {
        return sourceName.indexOf("#opencode-") >= 0;
    }).length > 0
    property var openCodeProviderCandidates: []
    property var openCodeProviderModelMap: ({})
    property var openCodeModelCandidates: []
    property var filteredOpenCodeModels: []
    property string openCodeModelSearch: ""
    property var piProviderCandidates: []
    property var piProviderModelMap: ({})
    property var piModelCandidates: []
    property string piModelSearch: ""
    readonly property Store.Wallet wallet: Store.Wallet {}
    readonly property bool hasPlasmoidConfig: typeof plasmoid !== 'undefined' && plasmoid !== null && plasmoid.configuration !== undefined // qmllint disable unqualified

    function updateFilteredOpenCodeModels(searchText) {
        var search = (searchText || "").toLowerCase();
        if (search === "") {
            filteredOpenCodeModels = openCodeModelCandidates;
        } else {
            var filtered = [];
            for (var i = 0; i < openCodeModelCandidates.length; i++) {
                if (openCodeModelCandidates[i].toLowerCase().indexOf(search) >= 0)
                    filtered.push(openCodeModelCandidates[i]);

            }
            filteredOpenCodeModels = filtered;
        }
    }

    function updateFilteredPiModels(searchText) {
        var search = (searchText || "").toLowerCase();
        if (search === "") {
            piModelCandidates = piProviderModelMap[piProviderValueField.text] || [];
        } else {
            var all = piProviderModelMap[piProviderValueField.text] || [];
            var filtered = [];
            for (var i = 0; i < all.length; i++) {
                if (all[i].toLowerCase().indexOf(search) >= 0)
                    filtered.push(all[i]);
            }
            piModelCandidates = filtered;
        }
    }

    function syncPiProviderSelection(providerId, preferredModel) {
        var selectedProvider = providerId || "";
        var candidateModels = piProviderModelMap[selectedProvider] || [];
        var chosenModel = preferredModel || piModelValueField.text || "";
        if (candidateModels.indexOf(chosenModel) < 0)
            chosenModel = candidateModels.length > 0 ? candidateModels[0] : "";
        piProviderValueField.text = selectedProvider;
        piModelCandidates = candidateModels;
        piModelSearch = "";
        updateFilteredPiModels("");
        piModelValueField.text = chosenModel;
    }

    function shellEscape(s) {
        return (s || "").replace(/'/g, "'\\''");
    }

    function quoteForShell(s) {
        return "'" + shellEscape(s) + "'";
    }

    function getHelperPath() {
        var urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        var path = decodeURIComponent(urlStr);
        if (path.endsWith("/contents/ui/kde_ai_helper.py"))
            return path;
        return "";
    }

    function requestJson(url, headers, onSuccess, onError) {
        var safeUrl = Sec.validateHttpUrl(url);
        if (!safeUrl) {
            onError("Request blocked: only HTTP(S) provider URLs are allowed.");
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", safeUrl, true);
        xhr.timeout = 15000;
        xhr.ontimeout = function() {
            onError("Request to " + url + " timed out after 15 seconds.");
        };
        for (var h in headers) {
            if (Object.prototype.hasOwnProperty.call(headers, h) && headers[h])
                xhr.setRequestHeader(h, headers[h]);

        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    onSuccess(JSON.parse(xhr.responseText));
                } catch (e) {
                    onError("Invalid JSON from " + url);
                }
            } else {
                onError("HTTP " + xhr.status + " from " + url);
            }
        };
        xhr.onerror = function() {
            onError("Network error while requesting " + url);
        };
        try {
            xhr.send();
        } catch (e) {
            onError("Unable to start request: " + e);
        }
        return xhr;
    }

    function activeOpenCodeProvider() {
        return openCodeProviderValueField.text || "";
    }

    function setOpenCodeProviderValue(v) {
        openCodeProviderValueField.text = v || "";
    }

    function setOpenCodeModelValue(v) {
        openCodeModelValueField.text = v || "";
    }

    function openCodeServerRoot(baseUrl) {
        var value = (baseUrl || "").replace(/\/$/, "");
        if (value.slice(-3) === "/v1")
            return value.slice(0, -3);

        return value;
    }

    function parseOpenCodeProviderModels(providerObj) {
        function pushId(v) {
            if (!v)
                return ;

            if (ids.indexOf(v) < 0)
                ids.push(v);

        }

        var ids = [];
        if (!providerObj || !providerObj.models)
            return ids;

        if (Array.isArray(providerObj.models)) {
            for (var i = 0; i < providerObj.models.length; i++) {
                if (typeof providerObj.models[i] === "string")
                    pushId(providerObj.models[i]);
                else if (providerObj.models[i] && providerObj.models[i].id)
                    pushId(providerObj.models[i].id);
            }
            return ids;
        }
        for (var modelId in providerObj.models) {
            if (!Object.prototype.hasOwnProperty.call(providerObj.models, modelId))
                continue;

            pushId(providerObj.models[modelId].id || modelId);
        }
        return ids;
    }

    function syncOpenCodeProviderSelection(providerId, preferredModel) {
        var selectedProvider = providerId || "";
        var candidateModels = openCodeProviderModelMap[selectedProvider] || [];
        var chosenModel = preferredModel || openCodeModelValueField.text || "";
        if (candidateModels.indexOf(chosenModel) < 0)
            chosenModel = candidateModels.length > 0 ? candidateModels[0] : "";

        setOpenCodeProviderValue(selectedProvider);
        openCodeModelCandidates = candidateModels;
        openCodeModelSearch = "";
        updateFilteredOpenCodeModels("");
        setOpenCodeModelValue(chosenModel);
        if (openCodeProvidersCombo) {
            var pidx = openCodeProviderCandidates.indexOf(selectedProvider);
            if (pidx >= 0)
                openCodeProvidersCombo.currentIndex = pidx;

        }
        if (openCodeModelsCombo) {
            var midx = candidateModels.indexOf(chosenModel);
            if (midx >= 0)
                openCodeModelsCombo.currentIndex = midx;

        }
    }

    function refreshOpenCodeDiscovery() {
        probeOpenCodeProviders(openCodeUrlField.text);
    }

    function refreshPiDiscovery() {
        discoveryStatus = "Checking Pi Agent models...";
        var cmd = "python3 " + quoteForShell(getHelperPath()) + " get_pi_models";
        var uid = "pi_models_" + Date.now();
        utilityDs.connectSource(cmd + " #" + uid);
    }

    function probeOpenCodeProviders(baseUrl) {
        var url = openCodeServerRoot(baseUrl) + "/config/providers";
        discoveryStatus = "Checking OpenCode server...";
        requestJson(url, {
        }, function(obj) {
            if (!openCodeToggle.checked) return;
            var providers = (obj && obj.providers) || [];
            var ids = [];
            var defaults = (obj && obj.default) || {
            };
            var modelsByProvider = {
            };
            for (var i = 0; i < providers.length; i++) {
                var provider = providers[i];
                var providerId = provider && provider.id ? provider.id : (provider && provider.name ? provider.name : "");
                if (!providerId)
                    continue;

                if (ids.indexOf(providerId) < 0)
                    ids.push(providerId);

                modelsByProvider[providerId] = parseOpenCodeProviderModels(provider);
            }
            openCodeProviderCandidates = ids;
            openCodeProviderModelMap = modelsByProvider;
            if (ids.length === 0) {
                openCodeModelCandidates = [];
                openCodeModelSearch = "";
                updateFilteredOpenCodeModels("");
                setOpenCodeProviderValue("");
                setOpenCodeModelValue("");
                discoveryStatus = "OpenCode server is reachable, but it returned no configured providers.";
                return ;
            }
            var selectedProvider = activeOpenCodeProvider();
            if (ids.indexOf(selectedProvider) < 0)
                selectedProvider = ids[0];

            var rememberedModel = openCodeModelValueField.text || "";
            var fallbackModel = defaults[selectedProvider] || "";
            syncOpenCodeProviderSelection(selectedProvider, rememberedModel || fallbackModel);
            discoveryStatus = "OpenCode server reachable. Loaded " + ids.length + " providers from /config/providers.";
        }, function(err) {
            if (!openCodeToggle.checked) return;
            openCodeProviderCandidates = [];
            openCodeProviderModelMap = ({
            });
            openCodeModelCandidates = [];
            openCodeModelSearch = "";
            updateFilteredOpenCodeModels("");
            setOpenCodeProviderValue("");
            setOpenCodeModelValue("");
            discoveryStatus = "OpenCode server check failed: " + err;
        });
    }

    function probeOpenCodeModels(baseUrl, providerId) {
        var selectedProvider = providerId || activeOpenCodeProvider();
        if (!selectedProvider) {
            openCodeModelCandidates = [];
            openCodeModelSearch = "";
            updateFilteredOpenCodeModels("");
            if (openCodeToggle.checked) {
                discoveryStatus = "Select an OpenCode provider first.";
            }
            return ;
        }
        syncOpenCodeProviderSelection(selectedProvider, openCodeModelValueField.text);
        if (openCodeToggle.checked) {
            discoveryStatus = openCodeModelCandidates.length > 0 ? ("Loaded " + openCodeModelCandidates.length + " models for OpenCode provider " + selectedProvider + ".") : ("OpenCode provider " + selectedProvider + " has no models listed by /config/providers.");
        }
    }

    // Starts or stops (only ours) `opencode serve` on the configured port.
    function runOpenCodeServer(command) {
        var port = Number((/:(\d+)/.exec(String(openCodeUrlField.text || "").replace(/^[a-z]+:\/\//i, "")) || [0, 4096])[1]);
        var payload = Sec.base64Encode(JSON.stringify({"port": port}));
        discoveryStatus = command === "opencode_server_start" ? i18n("Starting OpenCode…") : i18n("Stopping OpenCode…"); // qmllint disable unqualified
        utilityDs.connectSource("python3 " + quoteForShell(getHelperPath()) + " " + command + " " + Sec.rawShellSnippetQuote(payload) + " #opencode-server");
    }

    function saveGeneralSettingsOnly() {
        if (!hasPlasmoidConfig)
            return;
        plasmoid.configuration.appearanceMode = appearanceModeCombo.currentIndex; // qmllint disable unqualified
        plasmoid.configuration.useOpenCode = openCodeToggle.checked; // qmllint disable unqualified
        plasmoid.configuration.usePi = piToggle.checked; // qmllint disable unqualified
        plasmoid.configuration.playNotificationSound = playSoundToggle.checked; // qmllint disable unqualified
        plasmoid.configuration.requestTimeout = requestTimeoutToggle.checked ? requestTimeoutSpinBox.value : 0; // qmllint disable unqualified
        plasmoid.configuration.openCodeUrl = openCodeUrlField.text; // qmllint disable unqualified
        plasmoid.configuration.openCodeProvider = openCodeProviderValueField.text; // qmllint disable unqualified
        plasmoid.configuration.openCodeModel = openCodeModelValueField.text; // qmllint disable unqualified
        plasmoid.configuration.piProvider = piProviderValueField.text; // qmllint disable unqualified
        plasmoid.configuration.piModel = piModelValueField.text; // qmllint disable unqualified
    }

    function resetToDefaults() {
        appearanceModeCombo.currentIndex = 0;
        openCodeToggle.checked = false;
        piToggle.checked = false;
        openCodeUrlField.text = "http://127.0.0.1:4096/v1";
        openCodeProviderValueField.text = "";
        openCodeModelValueField.text = "";
        piProviderValueField.text = "";
        piModelValueField.text = "";
        openCodeProviderCandidates = [];
        openCodeModelCandidates = [];
        openCodeProviderModelMap = ({});
        piProviderCandidates = [];
        piModelCandidates = [];
        piProviderModelMap = ({});
        requestTimeoutToggle.checked = true;
        requestTimeoutSpinBox.value = 60;
        discoveryStatus = i18n("Settings reset to defaults."); // qmllint disable unqualified
    }

    Component.onCompleted: {
        if (hasPlasmoidConfig && plasmoid.configuration.appearanceMode > 2) // qmllint disable unqualified
            plasmoid.configuration.appearanceMode = 0; // qmllint disable unqualified
        if (openCodeToggle.checked)
            refreshOpenCodeDiscovery();
        else if (piToggle.checked)
            refreshPiDiscovery();
        wallet.load();
        pageReady = true;
    }
    Component.onDestruction: saveGeneralSettingsOnly()

    P5Support.DataSource {
        id: utilityDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var out = (data["stdout"] || "").trim();
            var err = (data["stderr"] || "").trim();
            if (sourceName.indexOf("#opencode-server") >= 0) {
                var result = {};
                try { result = JSON.parse(out); } catch (e) { result = {"status": "error", "message": err || out}; }
                page.discoveryStatus = result.status === "started" ? "OpenCode started." : result.status === "already-running" ? "OpenCode is already running."
                    : result.status === "stopped" ? "OpenCode stopped." : (result.message || "OpenCode: " + result.status);
                if (result.status === "started" || result.status === "already-running")
                    page.refreshOpenCodeDiscovery();
            } else if (sourceName.indexOf("#pi_models_") >= 0) {
            try {
                var msg = JSON.parse(out);
                if (msg.providers && Array.isArray(msg.providers)) {
                    var providers = msg.providers;
                    var ids = [];
                    var modelsByProvider = {};
                    for (var i = 0; i < providers.length; i++) {
                        var provider = providers[i];
                        var providerId = provider && provider.id ? provider.id : "";
                        if (!providerId) continue;
                        if (ids.indexOf(providerId) < 0) ids.push(providerId);
                        var mods = [];
                        if (provider.models && Array.isArray(provider.models)) {
                            mods = provider.models;
                        }
                        modelsByProvider[providerId] = mods;
                    }
                    page.piProviderCandidates = ids;
                    page.piProviderModelMap = modelsByProvider;
                    if (ids.length === 0) {
                        page.piModelCandidates = [];
                        page.piModelSearch = "";
                        page.updateFilteredPiModels("");
                        piProviderValueField.text = "";
                        piModelValueField.text = "";
                        page.discoveryStatus = "Pi agent returned no models.";
                    } else {
                        var selectedProvider = piProviderValueField.text || "";
                        if (ids.indexOf(selectedProvider) < 0)
                            selectedProvider = ids[0];
                        var rememberedModel = piModelValueField.text || "";
                        page.syncPiProviderSelection(selectedProvider, rememberedModel);
                        page.discoveryStatus = "Pi models loaded successfully.";
                    }
                } else if (msg.status === "error" || msg.error) {
                    page.discoveryStatus = "Helper error: " + (msg.message || msg.error);
                }
            } catch(e) {
                page.discoveryStatus = "Error parsing Pi models: " + out;
            }
            } else {
                page.discoveryStatus = out !== "" ? out : (err !== "" ? err : "Command finished.");
            }
            disconnectSource(sourceName);
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.FormLayout {
            id: formLayout
            Layout.fillWidth: true
            wideMode: false
            property int fieldMaxWidth: Kirigami.Units.gridUnit * 36

            QQC2.ComboBox {
                id: appearanceModeCombo
                Kirigami.FormData.label: i18n("Appearance:") // qmllint disable unqualified
                Layout.maximumWidth: formLayout.fieldMaxWidth
                model: [i18n("Follow system"), i18n("Light mode"), i18n("Dark mode")] // qmllint disable unqualified
            }

            QQC2.CheckBox {
                id: playSoundToggle

                Kirigami.FormData.label: "Notification sound:"
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Play sound when AI finishes a response"
            }

            RowLayout {
                id: requestTimeoutLayout
                Kirigami.FormData.label: "Request timeout:"
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.CheckBox {
                    id: requestTimeoutToggle
                    text: "Enable timeout"
                    checked: page.hasPlasmoidConfig ? (plasmoid.configuration.requestTimeout > 0) : true // qmllint disable unqualified
                    onCheckedChanged: {
                        if (page.hasPlasmoidConfig && !checked) {
                            plasmoid.configuration.requestTimeout = 0; // qmllint disable unqualified
                        } else if (page.hasPlasmoidConfig && checked && requestTimeoutSpinBox.value === 0) {
                            requestTimeoutSpinBox.value = 60;
                        }
                    }
                }

                QQC2.SpinBox {
                    id: requestTimeoutSpinBox
                    visible: requestTimeoutToggle.checked
                    from: 1
                    to: 600
                    stepSize: 5
                    editable: true
                    value: page.hasPlasmoidConfig && plasmoid.configuration.requestTimeout > 0 ? plasmoid.configuration.requestTimeout : 60 // qmllint disable unqualified
                }
                QQC2.Label {
                    visible: requestTimeoutToggle.checked
                    text: "seconds"
                }
            }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Chat mode") // qmllint disable unqualified
            }

            QQC2.RadioButton {
                id: directModeRadio
                Kirigami.FormData.label: i18n("Send messages:") // qmllint disable unqualified
                text: i18n("Directly to a provider (your API key)") // qmllint disable unqualified
                checked: !openCodeToggle.checked && !piToggle.checked
                onToggled: if (checked) { openCodeToggle.checked = false; piToggle.checked = false; }
            }

            QQC2.CheckBox {
                id: openCodeToggle
                text: i18n("Through OpenCode (coding agent)") // qmllint disable unqualified
                onCheckedChanged: {
                    page.discoveryStatus = "";
                    if (checked) {
                        piToggle.checked = false;
                        if (page.pageReady)
                            page.refreshOpenCodeDiscovery();
                    }
                }
            }

            QQC2.CheckBox {
                id: piToggle
                text: i18n("Through the Pi coding agent") // qmllint disable unqualified
                onCheckedChanged: {
                    if (checked) {
                        openCodeToggle.checked = false;
                        page.refreshPiDiscovery();
                    }
                }
            }

            Kirigami.Separator {
                visible: openCodeToggle.checked
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: "OpenCode"
            }

            QQC2.TextField {
                id: openCodeUrlField

                visible: openCodeToggle.checked
                Kirigami.FormData.label: "OpenCode URL:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://127.0.0.1:4096/v1"
            }

            Flow {
                visible: openCodeToggle.checked
                Kirigami.FormData.label: "OpenCode server:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: i18n("Start server") // qmllint disable unqualified
                    enabled: !page.openCodeBusy
                    onClicked: page.runOpenCodeServer("opencode_server_start")
                }

                QQC2.Button {
                    text: "Check server"
                    enabled: !page.openCodeBusy
                    onClicked: page.probeOpenCodeProviders(openCodeUrlField.text)
                }

                QQC2.Button {
                    text: "Refresh"
                    enabled: !page.openCodeBusy
                    onClicked: page.refreshOpenCodeDiscovery()
                }

                QQC2.Button {
                    text: i18n("Stop server") // qmllint disable unqualified
                    enabled: !page.openCodeBusy
                    onClicked: page.runOpenCodeServer("opencode_server_stop")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Stops a server started by this widget. Servers you started yourself are left running.") // qmllint disable unqualified
                }

            }

            QQC2.BusyIndicator {
                visible: openCodeToggle.checked && page.openCodeBusy
                running: visible
                Kirigami.FormData.label: "Loading:"
            }

            QQC2.ComboBox {
                id: openCodeProvidersCombo

                visible: openCodeToggle.checked && page.openCodeProviderCandidates.length > 0
                Kirigami.FormData.label: "Providers:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                model: page.openCodeProviderCandidates
                onActivated: {
                    page.setOpenCodeProviderValue(currentText);
                    page.probeOpenCodeModels(openCodeUrlField.text, currentText);
                }
            }

            QQC2.Button {
                visible: openCodeToggle.checked
                Kirigami.FormData.label: "OpenCode models:"
                text: "Refresh models"
                onClicked: page.probeOpenCodeModels(openCodeUrlField.text, page.activeOpenCodeProvider())
            }

            QQC2.ComboBox {
                id: openCodeModelsCombo

                function syncText() {
                    var val = openCodeModelValueField.text || "";
                    var idx = page.openCodeModelCandidates.indexOf(val);
                    if (idx >= 0) {
                        currentIndex = idx;
                    } else {
                        currentIndex = -1;
                        editText = val;
                    }
                }

                visible: openCodeToggle.checked
                Kirigami.FormData.label: "Model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                editable: true
                model: page.openCodeModelCandidates
                Component.onCompleted: {
                    syncText();
                }
                onModelChanged: {
                    syncText();
                }
                onEditTextChanged: {
                    if (activeFocus)
                        page.setOpenCodeModelValue(editText);

                }
                onActivated: {
                    page.setOpenCodeModelValue(currentText);
                    editText = currentText;
                }
            }

            QQC2.TextField {
                visible: openCodeToggle.checked && (false)
                Kirigami.FormData.label: page.filteredOpenCodeModels.length > 0 ? "Custom model:" : "OpenCode model (optional):"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Enter your OpenCode model id"
                text: openCodeModelValueField.text
                onTextChanged: {
                    page.openCodeModelSearch = text;
                    page.updateFilteredOpenCodeModels(text);
                    page.setOpenCodeModelValue(text);
                }
            }

            Kirigami.Separator {
                visible: piToggle.checked
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: "Pi Agent Details"
            }

            QQC2.ComboBox {
                id: piProvidersCombo

                visible: piToggle.checked && page.piProviderCandidates.length > 0
                Kirigami.FormData.label: "Providers:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                model: page.piProviderCandidates
                onActivated: {
                    piProviderValueField.text = currentText;
                    page.syncPiProviderSelection(currentText, "");
                }
            }

            QQC2.Button {
                visible: piToggle.checked
                Kirigami.FormData.label: "Pi models:"
                text: "Refresh models"
                onClicked: page.refreshPiDiscovery()
            }

            QQC2.ComboBox {
                id: piModelsCombo

                function syncText() {
                    var val = piModelValueField.text || "";
                    var idx = page.piModelCandidates.indexOf(val);
                    if (idx >= 0) {
                        currentIndex = idx;
                    } else {
                        currentIndex = -1;
                        editText = val;
                    }
                }

                visible: piToggle.checked
                Kirigami.FormData.label: "Model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                editable: true
                model: page.piModelCandidates
                Component.onCompleted: syncText()
                onModelChanged: syncText()
                onEditTextChanged: {
                    if (activeFocus)
                        piModelValueField.text = editText;
                }
                onActivated: {
                    piModelValueField.text = currentText;
                }
                onAccepted: {
                    piModelValueField.text = editText;
                }
            }

            QQC2.TextField {
                id: piProviderValueField
                visible: false
                text: plasmoid.configuration.piProvider || "" // qmllint disable unqualified
            }

            QQC2.TextField {
                id: piModelValueField
                visible: false
                text: plasmoid.configuration.piModel || "" // qmllint disable unqualified
            }


            QQC2.TextField {
                id: openCodeProviderValueField

                visible: false
                text: plasmoid.configuration.openCodeProvider || "" // qmllint disable unqualified
            }

            QQC2.TextField {
                id: openCodeModelValueField

                visible: false
                text: plasmoid.configuration.openCodeModel || "" // qmllint disable unqualified
            }

            QQC2.Label {
                visible: page.discoveryStatus !== "" && (openCodeToggle.checked || piToggle.checked)
                Kirigami.FormData.label: i18n("Status:") // qmllint disable unqualified
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: page.discoveryStatus
                wrapMode: Text.Wrap
                opacity: 0.8
            }
        }

        Config.ProvidersPanel {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 40
            Layout.alignment: Qt.AlignHCenter
            visible: !openCodeToggle.checked && !piToggle.checked
            configuration: page.hasPlasmoidConfig ? plasmoid.configuration : null // qmllint disable unqualified
            wallet: page.wallet
        }
    }
}
