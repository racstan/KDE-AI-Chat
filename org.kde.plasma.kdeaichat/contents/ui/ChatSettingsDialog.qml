import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "ProviderService.js" as ProviderService

// ChatSettingsDialog — per-chat settings panel
// DESIGN RULES (to prevent binding loops & hangs):
//   1. No declarative property bindings on ComboBox.editText or ComboBox.currentIndex
//   2. All state is stored in plain JS vars (d.*) and pushed to controls manually via open()
//   3. No network calls on open — only on explicit button press
//   4. All XHR done inside ProviderService which has a 5s timeout

QQC2.Popup {
    id: chatSettingsDialog

    // ── public API ──────────────────────────────────────────────────
    property var rootRef: null

    function openForSession(sessionId) {
        if (!rootRef) return;
        _load(sessionId);
        open();
    }

    // ── private state (plain object, never declaratively bound) ─────
    property var _d: ({})

    function _load(sessionId) {
        var r = rootRef;
        var get = (k, def) =>
            (typeof r.getSessionProperty === "function")
                ? r.getSessionProperty(sessionId, k, def)
                : def;

        var src = get("source", "");
        if (!src) src = r.openCodeMode ? "opencode" : "provider";

        _d = {
            sessionId:   sessionId,
            sessionTitle: r.currentSessionTitle || "Current Chat",
            mode:        src,
            provider:    get("chatProvider",            ""),
            model:       get("chatModel",               ""),
            ocAgent:     get("openCodeAgent",           ""),
            ocModel:     get("openCodeModel",           ""),
            ocCwd:       get("openCodeWorkspaceCwd",    ""),
            memEnabled:  get("chatMemoryEnabled",       true),
            memText:     get("chatMemory",              ""),
            sysEnabled:  get("chatSystemPromptEnabled", true),
            sysText:     get("chatSystemPrompt",        ""),
            respLen:     get("responseLength",          0),
        };

        // push to controls now that _d is ready
        _applyToControls();
    }

    function _applyToControls() {
        var d = _d;
        titleLabel.text = "Chat Settings: " + d.sessionTitle;
        modeNormalBtn.checked    = (d.mode !== "opencode");
        modeOpenCodeBtn.checked  = (d.mode === "opencode");
        normalCard.visible       = (d.mode !== "opencode");
        openCodeCard.visible     = (d.mode === "opencode");
        statusLabel.text         = "";

        // provider combo — find index by value
        var cfg = rootRef ? rootRef.plasmoid.configuration : null;
        var provList = _buildProviderModel(cfg);
        providerCombo.model = provList;
        providerCombo.currentIndex = 0;
        for (var i = 0; i < provList.length; i++) {
            if (provList[i].value === d.provider) { providerCombo.currentIndex = i; break; }
        }

        // model field — plain text
        modelField.text = d.model;

        // opencode agent combo
        var agentList = _buildAgentModel();
        agentCombo.model = agentList;
        agentCombo.currentIndex = 0;
        for (var j = 0; j < agentList.length; j++) {
            if (agentList[j] === d.ocAgent) { agentCombo.currentIndex = j; break; }
        }
        agentCombo.editText = d.ocAgent || "";

        // opencode model combo
        var ocModelList = _buildOcModelModel();
        ocModelCombo.model = ocModelList;
        ocModelCombo.currentIndex = 0;
        for (var k = 0; k < ocModelList.length; k++) {
            if (ocModelList[k] === d.ocModel) { ocModelCombo.currentIndex = k; break; }
        }
        ocModelCombo.editText = d.ocModel || "";

        // other fields
        cwdField.text              = d.ocCwd;
        memCheck.checked           = d.memEnabled;
        memArea.text               = d.memText;
        memArea.enabled            = d.memEnabled;
        sysCheck.checked           = d.sysEnabled;
        sysArea.text               = d.sysText;
        sysArea.enabled            = d.sysEnabled;
        respLenCombo.currentIndex  = d.respLen || 0;
    }

    function _buildProviderModel(cfg) {
        var globalProv = cfg ? (cfg.provider || "openai") : "openai";
        var list = [{ text: "Default (Global: " + ProviderService.getProviderDisplayName(globalProv, cfg) + ")", value: "" }];
        var providers = ProviderService.getConfiguredProviders(cfg);
        for (var i = 0; i < providers.length; i++) {
            list.push({ text: ProviderService.getProviderDisplayName(providers[i], cfg), value: providers[i] });
        }
        return list;
    }

    function _buildAgentModel() {
        var agents = rootRef ? rootRef.openCodeAgentsList : [];
        var list = ["(default agent)"];
        for (var i = 0; i < agents.length; i++) {
            var name = (typeof agents[i] === "string") ? agents[i] : (agents[i].name || "");
            if (name && list.indexOf(name) < 0) list.push(name);
        }
        return list;
    }

    function _buildOcModelModel() {
        var models = rootRef ? rootRef.openCodeModelsList : [];
        var list = ["(default model)"];
        for (var i = 0; i < models.length; i++) {
            if (models[i] && list.indexOf(models[i]) < 0) list.push(models[i]);
        }
        return list;
    }

    function _readFromControls() {
        _d.provider   = (providerCombo.currentIndex > 0 && providerCombo.model)
                         ? (providerCombo.model[providerCombo.currentIndex].value || "") : "";
        _d.model      = modelField.text.trim();
        _d.ocAgent    = (agentCombo.currentIndex > 0) ? agentCombo.currentText : agentCombo.editText;
        _d.ocModel    = (ocModelCombo.currentIndex > 0) ? ocModelCombo.currentText : ocModelCombo.editText;
        _d.ocCwd      = cwdField.text.trim();
        _d.memEnabled = memCheck.checked;
        _d.memText    = memArea.text;
        _d.sysEnabled = sysCheck.checked;
        _d.sysText    = sysArea.text;
        _d.respLen    = respLenCombo.currentIndex;
    }

    function _saveAndClose() {
        if (!rootRef || !_d.sessionId) { close(); return; }
        _readFromControls();
        var d = _d;
        var set = (k, v) => { if (typeof rootRef.setSessionProperty === "function") rootRef.setSessionProperty(d.sessionId, k, v); };
        set("source",                 d.mode);
        set("chatProvider",           d.provider);
        set("chatModel",              d.model);
        set("openCodeAgent",          d.ocAgent);
        set("openCodeModel",          d.ocModel);
        set("openCodeWorkspaceCwd",   d.ocCwd);
        set("chatMemoryEnabled",      d.memEnabled);
        set("chatMemory",             d.memText);
        set("chatSystemPromptEnabled",d.sysEnabled);
        set("chatSystemPrompt",       d.sysText);
        set("responseLength",         d.respLen);

        if (d.sessionId === rootRef.currentSessionId) {
            rootRef.openCodeMode = (d.mode === "opencode");
            if (d.ocAgent) rootRef.openCodeAgent = d.ocAgent;
            if (d.ocCwd)   rootRef.openCodeWorkspaceCwd = d.ocCwd;
        }
        if (typeof rootRef.saveCurrentSessionState === "function")
            rootRef.saveCurrentSessionState(true);
        close();
    }

    function _resetDefaults() {
        var r = rootRef;
        var useOC = r && r.plasmoid && r.plasmoid.configuration.useOpenCode;
        _d.mode      = useOC ? "opencode" : "provider";
        _d.provider  = ""; _d.model  = "";
        _d.ocAgent   = ""; _d.ocModel = ""; _d.ocCwd = "";
        _d.memEnabled = true;  _d.memText = "";
        _d.sysEnabled = true;  _d.sysText = "";
        _d.respLen   = 0;
        _applyToControls();
    }

    function _switchMode(mode) {
        _d.mode = mode;
        normalCard.visible    = (mode !== "opencode");
        openCodeCard.visible  = (mode === "opencode");
        modeNormalBtn.checked   = (mode !== "opencode");
        modeOpenCodeBtn.checked = (mode === "opencode");
    }

    // ── popup geometry ───────────────────────────────────────────────
    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    width: 580
    height: 600
    x: parent ? (parent.width  - width)  / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0

    // ── FolderDialog ─────────────────────────────────────────────────
    FolderDialog {
        id: dirDialog
        title: "Select OpenCode Workspace Directory"
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.startsWith("file://")) path = path.substring(7);
            cwdField.text = path;
        }
    }

    // ── main content ─────────────────────────────────────────────────
    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                              Kirigami.Theme.highlightColor.g,
                              Kirigami.Theme.highlightColor.b, 0.4)
        border.width: 1
        radius: 10
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── header ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                           Kirigami.Theme.highlightColor.g,
                           Kirigami.Theme.highlightColor.b, 0.12)
            radius: 10
            // square bottom corners
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 10; color: parent.color }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Kirigami.Icon {
                    source: "preferences-other"
                    implicitWidth: 22; implicitHeight: 22
                    color: Kirigami.Theme.highlightColor
                }

                PC3.Label {
                    id: titleLabel
                    text: "Chat Settings"
                    font.bold: true
                    font.pointSize: 11
                    Layout.fillWidth: true
                }

                PC3.ToolButton {
                    icon.name: "window-close"
                    onClicked: chatSettingsDialog.close()
                    flat: true
                }
            }
        }

        // ── scrollable body ──
        QQC2.ScrollView {
            id: sv
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: sv.width

            ColumnLayout {
                width: sv.width - 2
                spacing: 10

                Item { height: 8 }

                // ── Mode selector ──────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                    implicitHeight: modeRow.implicitHeight + 24
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                   Kirigami.Theme.highlightColor.g,
                                   Kirigami.Theme.highlightColor.b, 0.07)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                          Kirigami.Theme.highlightColor.g,
                                          Kirigami.Theme.highlightColor.b, 0.25)
                    border.width: 1; radius: 8

                    ColumnLayout {
                        id: modeRow
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        PC3.Label { text: "Chat Mode"; font.bold: true }

                        RowLayout {
                            spacing: 20
                            PC3.RadioButton {
                                id: modeNormalBtn
                                text: "🌐 Normal AI Provider"
                                onClicked: chatSettingsDialog._switchMode("provider")
                            }
                            PC3.RadioButton {
                                id: modeOpenCodeBtn
                                text: "💻 OpenCode Engine"
                                onClicked: chatSettingsDialog._switchMode("opencode")
                            }
                        }
                    }
                }

                // ── Normal Mode card ───────────────────────────────
                Rectangle {
                    id: normalCard
                    Layout.fillWidth: true
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                    implicitHeight: normalLayout.implicitHeight + 24
                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                   Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                          Kirigami.Theme.textColor.g,
                                          Kirigami.Theme.textColor.b, 0.12)
                    border.width: 1; radius: 8

                    ColumnLayout {
                        id: normalLayout
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        PC3.Label { text: "Provider & Model"; font.bold: true }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            PC3.Label { text: "Provider:"; Layout.preferredWidth: 90 }
                            QQC2.ComboBox {
                                id: providerCombo
                                Layout.fillWidth: true
                                textRole: "text"; valueRole: "value"
                                // model set imperatively in _applyToControls
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            PC3.Label { text: "Model:"; Layout.preferredWidth: 90 }
                            QQC2.TextField {
                                id: modelField
                                Layout.fillWidth: true
                                placeholderText: "Leave blank to use global model"
                                // text set imperatively in _applyToControls
                            }
                            PC3.ToolButton {
                                id: refreshModelsBtn
                                icon.name: "view-refresh"
                                enabled: !chatSettingsDialog._fetching
                                onClicked: {
                                    var r = chatSettingsDialog.rootRef;
                                    if (!r || !r.plasmoid) return;
                                    var prov = (providerCombo.currentIndex > 0 && providerCombo.model)
                                               ? providerCombo.model[providerCombo.currentIndex].value
                                               : r.plasmoid.configuration.provider || "openai";
                                    chatSettingsDialog._fetching = true;
                                    statusLabel.text = "Fetching models…";
                                    ProviderService.fetchModelsForProvider(prov, r.plasmoid.configuration,
                                        function(ids) {
                                            chatSettingsDialog._fetching = false;
                                            statusLabel.text = ids.length > 0
                                                ? ("✓ " + ids.length + " models loaded")
                                                : "No models returned";
                                            // repopulate model field if it was blank
                                            if (!modelField.text && ids.length > 0)
                                                modelField.placeholderText = ids[0] + " (first result)";
                                        },
                                        function(err) {
                                            chatSettingsDialog._fetching = false;
                                            statusLabel.text = "⚠ " + err;
                                        });
                                }
                                QQC2.ToolTip.text: "Fetch available models from provider API (5s timeout)"
                                QQC2.ToolTip.visible: hovered
                            }
                        }

                        PC3.Label {
                            id: statusLabel
                            text: ""
                            visible: text !== ""
                            font.pointSize: 8.5; opacity: 0.8
                            color: Kirigami.Theme.highlightColor
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                // ── OpenCode card ──────────────────────────────────
                Rectangle {
                    id: openCodeCard
                    Layout.fillWidth: true
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                    implicitHeight: ocLayout.implicitHeight + 24
                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                   Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                          Kirigami.Theme.textColor.g,
                                          Kirigami.Theme.textColor.b, 0.12)
                    border.width: 1; radius: 8

                    ColumnLayout {
                        id: ocLayout
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        PC3.Label { text: "OpenCode Engine"; font.bold: true }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            PC3.Label { text: "Agent:"; Layout.preferredWidth: 90 }
                            QQC2.ComboBox {
                                id: agentCombo
                                Layout.fillWidth: true
                                editable: true
                                // model & index set imperatively in _applyToControls
                            }
                            PC3.ToolButton {
                                icon.name: "view-refresh"
                                onClicked: {
                                    var r = chatSettingsDialog.rootRef;
                                    if (r && typeof r.fetchOpenCodeAgents === "function") {
                                        r.fetchOpenCodeAgents();
                                        // rebuild combo after agents arrive (delayed)
                                        Qt.callLater(function() {
                                            var list = chatSettingsDialog._buildAgentModel();
                                            var prev = agentCombo.editText;
                                            agentCombo.model = list;
                                            agentCombo.editText = prev;
                                        });
                                    }
                                }
                                QQC2.ToolTip.text: "Refresh agent list from OpenCode server"
                                QQC2.ToolTip.visible: hovered
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            PC3.Label { text: "Model:"; Layout.preferredWidth: 90 }
                            QQC2.ComboBox {
                                id: ocModelCombo
                                Layout.fillWidth: true
                                editable: true
                                // model & index set imperatively in _applyToControls
                            }
                            PC3.ToolButton {
                                icon.name: "view-refresh"
                                onClicked: {
                                    var r = chatSettingsDialog.rootRef;
                                    if (r && typeof r.fetchOpenCodeProvidersAndModels === "function") {
                                        r.fetchOpenCodeProvidersAndModels();
                                        Qt.callLater(function() {
                                            var list = chatSettingsDialog._buildOcModelModel();
                                            var prev = ocModelCombo.editText;
                                            ocModelCombo.model = list;
                                            ocModelCombo.editText = prev;
                                        });
                                    }
                                }
                                QQC2.ToolTip.text: "Refresh model list from OpenCode /provider API"
                                QQC2.ToolTip.visible: hovered
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            PC3.Label { text: "Workspace:"; Layout.preferredWidth: 90 }
                            QQC2.TextField {
                                id: cwdField
                                Layout.fillWidth: true
                                placeholderText: "Use global workspace directory"
                            }
                            PC3.ToolButton {
                                icon.name: "folder"
                                onClicked: dirDialog.open()
                                QQC2.ToolTip.text: "Browse for workspace folder"
                                QQC2.ToolTip.visible: hovered
                            }
                        }
                    }
                }

                // ── Chat Memory ────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                    implicitHeight: memLayout.implicitHeight + 24
                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                   Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                          Kirigami.Theme.textColor.g,
                                          Kirigami.Theme.textColor.b, 0.12)
                    border.width: 1; radius: 8

                    ColumnLayout {
                        id: memLayout
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label { text: "Per-Chat Memory"; font.bold: true; Layout.fillWidth: true }
                            PC3.CheckBox {
                                id: memCheck
                                text: "Enable"
                                onClicked: memArea.enabled = checked
                            }
                        }

                        PC3.Label {
                            text: "Notes retained for this session:"
                            font.pointSize: 8.5; opacity: 0.7
                            Layout.fillWidth: true
                        }

                        QQC2.TextArea {
                            id: memArea
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            wrapMode: Text.WordWrap
                            placeholderText: "e.g. User prefers Python 3.12..."
                        }
                    }
                }

                // ── System Context (Normal mode only) ──────────────
                Rectangle {
                    visible: _d.mode !== "opencode"
                    Layout.fillWidth: true
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                    implicitHeight: sysLayout.implicitHeight + 24
                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                   Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                          Kirigami.Theme.textColor.g,
                                          Kirigami.Theme.textColor.b, 0.12)
                    border.width: 1; radius: 8

                    ColumnLayout {
                        id: sysLayout
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label { text: "System Instructions"; font.bold: true; Layout.fillWidth: true }
                            PC3.CheckBox {
                                id: sysCheck
                                text: "Enable"
                                onClicked: sysArea.enabled = checked
                            }
                        }

                        QQC2.TextArea {
                            id: sysArea
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            wrapMode: Text.WordWrap
                            placeholderText: "Custom system prompt for this chat..."
                        }
                    }
                }

                // ── Response length (Normal mode only) ────────────
                Rectangle {
                    visible: _d.mode !== "opencode"
                    Layout.fillWidth: true
                    Layout.leftMargin: 12; Layout.rightMargin: 12
                    implicitHeight: respLayout.implicitHeight + 24
                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                   Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                          Kirigami.Theme.textColor.g,
                                          Kirigami.Theme.textColor.b, 0.12)
                    border.width: 1; radius: 8

                    RowLayout {
                        id: respLayout
                        anchors { fill: parent; margins: 12 }
                        spacing: 8
                        PC3.Label { text: "Response Length:"; font.bold: true }
                        QQC2.ComboBox {
                            id: respLenCombo
                            Layout.fillWidth: true
                            model: ["Default (Global)", "Short (~256 tokens)",
                                    "Balanced (~1024 tokens)", "Detailed (~4096 tokens)",
                                    "Comprehensive (~8192 tokens)"]
                        }
                    }
                }

                Item { height: 8 }
            }
        }

        // ── footer buttons ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: footerRow.implicitHeight + 20
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                           Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, 1)
            radius: 10
            // square top corners
            Rectangle { anchors.top: parent.top; width: parent.width; height: 10; color: parent.color }
            // separator
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1;
                         color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                        Kirigami.Theme.textColor.b, 0.1) }

            RowLayout {
                id: footerRow
                anchors { fill: parent; margins: 12 }
                spacing: 8

                PC3.Button {
                    text: "Reset Defaults"
                    icon.name: "edit-clear-all"
                    onClicked: chatSettingsDialog._resetDefaults()
                }

                Item { Layout.fillWidth: true }

                PC3.Button {
                    text: "Cancel"
                    icon.name: "dialog-cancel"
                    onClicked: chatSettingsDialog.close()
                }

                PC3.Button {
                    text: "Save"
                    icon.name: "dialog-ok-apply"
                    highlighted: true
                    onClicked: chatSettingsDialog._saveAndClose()
                }
            }
        }
    }

    // internal flag for fetch-in-progress
    property bool _fetching: false
}
