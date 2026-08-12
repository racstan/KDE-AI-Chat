import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "ProviderService.js" as ProviderService

// A deliberately small, state-owned editor.  The dialog never binds a
// ComboBox property to mutable session data: it loads a draft, performs
// bounded asynchronous refreshes, then commits the draft once.
QQC2.Popup {
    id: page

    property var rootRef: null
    property string _sessionId: ""
    property string _sessionTitle: ""
    property string _mode: "provider"
    property string _provider: ""
    property string _model: ""
    property string _ocAgent: ""
    property string _ocProvider: ""
    property string _ocModel: ""
    property string _ocCwd: ""
    property bool _memoryEnabled: true
    property string _memory: ""
    property bool _systemEnabled: true
    property string _system: ""
    property int _responseLength: 0
    property var _modelCandidates: []
    property int _generation: 0
    property bool _busy: false
    property string _status: ""

    function _get(key, fallback) {
        if (rootRef && typeof rootRef.getSessionProperty === "function")
            return rootRef.getSessionProperty(_sessionId, key, fallback);
        return fallback;
    }

    function _invalidate() {
        _generation += 1;
        _busy = false;
        _status = "";
    }

    function _requestToken() {
        _busy = true;
        return { generation: _generation, sessionId: _sessionId };
    }

    function _current(token) {
        return token && token.generation === _generation && token.sessionId === _sessionId;
    }

    function _providerEntries() {
        var cfg = rootRef && rootRef.plasmoid ? rootRef.plasmoid.configuration : null;
        var global = cfg ? (cfg.provider || "openai") : "openai";
        var result = [{ text: "Default · " + ProviderService.getProviderDisplayName(global, cfg), value: "" }];
        var configured = ProviderService.getConfiguredProviders(cfg);
        for (var i = 0; i < configured.length; i++)
            result.push({ text: ProviderService.getProviderDisplayName(configured[i], cfg), value: configured[i] });
        return result;
    }

    function _names(items, sentinel) {
        var result = [sentinel];
        for (var i = 0; i < (items || []).length; i++) {
            var item = items[i];
            var value = typeof item === "string" ? item : (item && (item.value || item.id || item.name || item.text));
            if (value && result.indexOf(value) < 0)
                result.push(value);
        }
        return result;
    }

    function _applyLists() {
        providerCombo.model = _providerEntries();
        providerCombo.currentIndex = 0;
        for (var i = 0; i < providerCombo.model.length; i++) {
            if (providerCombo.model[i].value === _provider) {
                providerCombo.currentIndex = i;
                break;
            }
        }
        modelCombo.model = _modelCandidates;
        modelCombo.editText = _model;
        agentCombo.model = _names(rootRef ? rootRef.openCodeAgentsList : [], "(default agent)");
        agentCombo.editText = _ocAgent || "";
        ocProviderCombo.model = _names(rootRef ? rootRef.openCodeProvidersList : [], "(default provider)");
        ocProviderCombo.editText = _ocProvider || "";
        ocModelCombo.model = _names(rootRef ? rootRef.openCodeModelsList : [], "(default model)");
        ocModelCombo.editText = _ocModel || "";
    }

    function _load(sessionId) {
        _invalidate();
        _sessionId = sessionId || "";
        var source = _get("source", "");
        if (!source)
            source = rootRef && rootRef.openCodeMode ? "opencode" : "provider";
        _sessionTitle = rootRef && rootRef.currentSessionTitle ? rootRef.currentSessionTitle : "Current Chat";
        _mode = source;
        _provider = _get("chatProvider", "");
        _model = _get("chatModel", "");
        _ocAgent = _get("openCodeAgent", "");
        _ocProvider = _get("openCodeProvider", "");
        _ocModel = _get("openCodeModel", "");
        _ocCwd = _get("openCodeWorkspaceCwd", "");
        _memoryEnabled = _get("chatMemoryEnabled", true);
        _memory = _get("chatMemory", "");
        _systemEnabled = _get("chatSystemPromptEnabled", true);
        _system = _get("chatSystemPrompt", "");
        _responseLength = _get("responseLength", 0) || 0;
        _modelCandidates = [];
        _applyLists();
        cwdField.text = _ocCwd;
        memoryCheck.checked = _memoryEnabled;
        memoryArea.text = _memory;
        systemCheck.checked = _systemEnabled;
        systemArea.text = _system;
        responseLengthCombo.currentIndex = _responseLength;
        Qt.callLater(function() {
            if (_sessionId !== sessionId)
                return;
            if (_mode === "opencode") {
                _refreshOpenCode(function() { _refreshAgents(); });
            } else if (_provider || (rootRef && rootRef.plasmoid && rootRef.plasmoid.configuration.apiKey)) {
                _refreshModels(false);
            }
        });
    }

    function openForSession(sessionId) {
        if (!rootRef)
            return;
        _load(sessionId);
        open();
    }

    function _selectedProvider() {
        if (providerCombo.currentIndex > 0 && providerCombo.model)
            return providerCombo.model[providerCombo.currentIndex].value || "";
        return rootRef && rootRef.plasmoid ? (rootRef.plasmoid.configuration.provider || "openai") : "openai";
    }

    function _refreshModels(showStatus) {
        if (_busy || !rootRef || !rootRef.plasmoid)
            return;
        var provider = _selectedProvider();
        var token = _requestToken();
        if (showStatus)
            _status = "Fetching models…";
        ProviderService.fetchModelsForProvider(provider, rootRef.plasmoid.configuration,
            function(models) {
                if (!_current(token)) return;
                _busy = false;
                _modelCandidates = models || [];
                if (!_model && _modelCandidates.length > 0)
                    _model = _modelCandidates[0];
                modelCombo.model = _modelCandidates;
                modelCombo.editText = _model;
                _status = _modelCandidates.length > 0 ? ("Loaded " + _modelCandidates.length + " models") : "No models returned";
            },
            function(errorText) {
                if (!_current(token)) return;
                _busy = false;
                _status = "Model refresh failed: " + errorText;
            });
    }

    function _refreshAgents() {
        if (_busy || !rootRef || typeof rootRef.fetchOpenCodeAgents !== "function")
            return;
        var token = _requestToken();
        _status = "Fetching OpenCode agents…";
        rootRef.fetchOpenCodeAgents(function() {
            if (!_current(token)) return;
            _busy = false;
            _applyLists();
            _status = (rootRef.openCodeAgentsList || []).length > 0 ? "OpenCode agents loaded" : "No agents reported by OpenCode";
        });
    }

    function _refreshOpenCode(done) {
        if (_busy || !rootRef || typeof rootRef.fetchOpenCodeProvidersAndModels !== "function") {
            if (done)
                done();
            return;
        }
        var token = _requestToken();
        _status = "Fetching OpenCode providers…";
        rootRef.fetchOpenCodeProvidersAndModels(function() {
            if (!_current(token)) return;
            _busy = false;
            _applyLists();
            _status = "OpenCode providers and models loaded";
            if (done)
                done();
        });
    }

    function _save() {
        _invalidate();
        if (!rootRef || !_sessionId) {
            close();
            return;
        }
        var agent = agentCombo.editText.trim();
        var ocProvider = ocProviderCombo.editText.trim();
        var ocModel = ocModelCombo.editText.trim();
        if (agent === "(default agent)") agent = "";
        if (ocProvider === "(default provider)") ocProvider = "";
        if (ocModel === "(default model)") ocModel = "";
        var overrides = {
            source: _mode,
            chatProvider: _selectedProvider() === (rootRef.plasmoid.configuration.provider || "openai") ? "" : _selectedProvider(),
            chatModel: modelCombo.editText.trim(),
            openCodeAgent: agent,
            openCodeProvider: ocProvider,
            openCodeModel: ocModel,
            openCodeWorkspaceCwd: cwdField.text.trim(),
            chatMemoryEnabled: memoryCheck.checked,
            chatMemory: memoryArea.text,
            chatSystemPromptEnabled: systemCheck.checked,
            chatSystemPrompt: systemArea.text,
            responseLength: responseLengthCombo.currentIndex
        };
        if (typeof rootRef.setSessionOverrides === "function")
            rootRef.setSessionOverrides(_sessionId, overrides);
        else if (typeof rootRef.setSessionProperty === "function") {
            for (var key in overrides)
                rootRef.setSessionProperty(_sessionId, key, overrides[key]);
        }
        close();
    }

    function _reset() {
        _invalidate();
        _mode = rootRef && rootRef.plasmoid && rootRef.plasmoid.configuration.usePi ? "pi" : (rootRef && rootRef.plasmoid && rootRef.plasmoid.configuration.useOpenCode ? "opencode" : "provider");
        _provider = ""; _model = ""; _ocAgent = ""; _ocProvider = ""; _ocModel = ""; _ocCwd = "";
        _memoryEnabled = true; _memory = ""; _systemEnabled = true; _system = ""; _responseLength = 0;
        _modelCandidates = [];
        _applyLists();
        memoryCheck.checked = true; memoryArea.text = ""; systemCheck.checked = true; systemArea.text = "";
        responseLengthCombo.currentIndex = 0;
    }

    function _setMode(mode) {
        _invalidate();
        _mode = mode;
    }

    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    onClosed: page._invalidate()
    width: Math.max(380, Math.min(700, parent ? parent.width - 24 : 700))
    height: Math.max(480, Math.min(760, parent ? parent.height - 24 : 760))

    FolderDialog {
        id: folderDialog
        title: "Select OpenCode workspace"
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.indexOf("file://") === 0) path = path.substring(7);
            cwdField.text = path;
        }
    }

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        radius: 12
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.35)
    }

    contentItem: ColumnLayout {
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 58
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.13)
            RowLayout {
                anchors.fill: parent; anchors.margins: 14; spacing: 10
                Kirigami.Icon { source: "preferences-other"; implicitWidth: 24; implicitHeight: 24 }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    PC3.Label { text: "Chat settings"; font.bold: true; font.pointSize: 11 }
                    PC3.Label { text: page._sessionTitle; opacity: 0.65; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                PC3.ToolButton { icon.name: "window-close"; onClicked: page.close() }
            }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            ColumnLayout {
                width: Math.max(0, page.width - 24); spacing: 12
                Item { implicitHeight: 4 }
                PC3.Label { text: "Choose how this chat responds"; font.bold: true; Layout.leftMargin: 12 }
                RowLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; spacing: 10
                    PC3.RadioButton { text: "Normal provider"; checked: page._mode === "provider"; onClicked: page._setMode("provider") }
                    PC3.RadioButton { text: "OpenCode"; checked: page._mode === "opencode"; onClicked: page._setMode("opencode") }
                    PC3.RadioButton { text: "Pi Agent"; checked: page._mode === "pi"; onClicked: page._setMode("pi") }
                }

                Rectangle {
                    visible: page._mode === "provider"; Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                    implicitHeight: normalColumn.implicitHeight + 24; radius: 10; color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.035)
                    ColumnLayout {
                        id: normalColumn; anchors.fill: parent; anchors.margins: 12; spacing: 9
                        PC3.Label { text: "Provider and model"; font.bold: true }
                        QQC2.ComboBox {
                            id: providerCombo; Layout.fillWidth: true; textRole: "text"; valueRole: "value"
                            onActivated: { page._provider = currentValue || ""; page._model = ""; page._modelCandidates = []; page._refreshModels(true); }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            QQC2.ComboBox { id: modelCombo; Layout.fillWidth: true; editable: true }
                            PC3.Button { text: page._busy ? "Loading…" : "Refresh"; enabled: !page._busy; onClicked: page._refreshModels(true) }
                        }
                        PC3.Label { text: "Models are loaded from the selected provider API. Select one before saving."; wrapMode: Text.WordWrap; opacity: 0.65; Layout.fillWidth: true }
                    }
                }

                Rectangle {
                    visible: page._mode === "opencode"; Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                    implicitHeight: openCodeColumn.implicitHeight + 24; radius: 10; color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.035)
                    ColumnLayout {
                        id: openCodeColumn; anchors.fill: parent; anchors.margins: 12; spacing: 9
                        PC3.Label { text: "OpenCode connection"; font.bold: true }
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Provider"; Layout.preferredWidth: 76 }
                            QQC2.ComboBox {
                                id: ocProviderCombo
                                Layout.fillWidth: true
                                editable: true
                            }
                            PC3.Button {
                                text: "Refresh"
                                enabled: !page._busy
                                onClicked: page._refreshOpenCode()
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Model"; Layout.preferredWidth: 76 }
                            QQC2.ComboBox {
                                id: ocModelCombo
                                Layout.fillWidth: true
                                editable: true
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Agent"; Layout.preferredWidth: 76 }
                            QQC2.ComboBox {
                                id: agentCombo
                                Layout.fillWidth: true
                                editable: true
                            }
                            PC3.Button {
                                text: "Refresh"
                                enabled: !page._busy
                                onClicked: page._refreshAgents()
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label { text: "Workspace"; Layout.preferredWidth: 76 }
                            QQC2.TextField {
                                id: cwdField
                                Layout.fillWidth: true
                            }
                            PC3.ToolButton {
                                icon.name: "folder"
                                onClicked: folderDialog.open()
                            }
                        }
                        PC3.Label { text: "OpenCode agents and models come only from its API/configuration."; wrapMode: Text.WordWrap; opacity: 0.65; Layout.fillWidth: true }
                        PC3.Label { text: "For workspace, enter absolute path or leave empty."; wrapMode: Text.WordWrap; opacity: 0.65; Layout.fillWidth: true }
                    }
                }

                Rectangle {
                    visible: page._mode === "pi"; Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                    implicitHeight: piColumn.implicitHeight + 24; radius: 10; color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.035)
                    ColumnLayout {
                        id: piColumn; anchors.fill: parent; anchors.margins: 12; spacing: 9
                        PC3.Label { text: "Pi Agent configuration"; font.bold: true }
                        PC3.Label { text: "Pi mode uses your global Pi configuration. It communicates directly via CLI."; wrapMode: Text.WordWrap; opacity: 0.65; Layout.fillWidth: true }
                    }
                }

                PC3.Label { text: page._status; visible: text.length > 0; color: Kirigami.Theme.highlightColor; wrapMode: Text.WordWrap; Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.fillWidth: true }

                Rectangle {
                    Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; implicitHeight: memoryColumn.implicitHeight + 24; radius: 10; color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.035)
                    ColumnLayout { id: memoryColumn; anchors.fill: parent; anchors.margins: 12; spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label { text: "Chat memory"; font.bold: true; Layout.fillWidth: true }
                            QQC2.CheckBox {
                                id: memoryCheck
                                text: "Enable"
                                onCheckedChanged: page._memoryEnabled = checked
                            }
                        }
                        QQC2.TextArea {
                            id: memoryArea
                            Layout.fillWidth: true
                            Layout.preferredHeight: 72
                            enabled: memoryCheck.checked
                            wrapMode: Text.WordWrap
                            placeholderText: "Notes retained for this chat"
                            onTextChanged: page._memory = text
                        }
                    }
                }
                Rectangle {
                    visible: page._mode !== "opencode"; Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; implicitHeight: systemColumn.implicitHeight + 24; radius: 10; color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.035)
                    ColumnLayout { id: systemColumn; anchors.fill: parent; anchors.margins: 12; spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label { text: "System instructions"; font.bold: true; Layout.fillWidth: true }
                            QQC2.CheckBox {
                                id: systemCheck
                                text: "Enable"
                                onCheckedChanged: page._systemEnabled = checked
                            }
                        }
                        QQC2.TextArea {
                            id: systemArea
                            Layout.fillWidth: true
                            Layout.preferredHeight: 88
                            enabled: systemCheck.checked
                            wrapMode: Text.WordWrap
                            placeholderText: "Instructions for this chat"
                            onTextChanged: page._system = text
                        }
                    }
                }
                RowLayout {
                    visible: page._mode !== "opencode"
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    QQC2.Label { text: "Response length"; Layout.fillWidth: true }
                    QQC2.ComboBox {
                        id: responseLengthCombo
                        model: ["Default", "Short", "Balanced", "Detailed", "Comprehensive"]
                    }
                }
                Item { implicitHeight: 8 }
            }
        }

        Rectangle {
            Layout.fillWidth: true; implicitHeight: 58; color: Kirigami.Theme.backgroundColor
            RowLayout { anchors.fill: parent; anchors.margins: 12; spacing: 8
                PC3.Button { text: "Reset"; icon.name: "edit-clear-all"; onClicked: page._reset() }
                Item { Layout.fillWidth: true }
                PC3.Button { text: "Cancel"; onClicked: page.close() }
                PC3.Button { text: "Save"; highlighted: true; enabled: !page._busy; onClicked: page._save() }
            }
        }
    }
}
