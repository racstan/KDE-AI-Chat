import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "ProviderService.js" as ProviderService

// A non-modal right-side panel. It stays attached to the chat instead of
// covering the whole conversation, and owns a draft until Apply is pressed.
// In a narrow popup it overlays the chat instead of squeezing it.
Rectangle {
    id: page

    property var rootRef: null
    property Item hostItem: null
    property bool sidebarOpen: false
    // True when the panel is narrow enough that it covers the chat.
    readonly property bool overlaysChat: parent ? parent.width < Kirigami.Units.gridUnit * 38 : false
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
    property string _piProvider: ""
    property string _piModel: ""
    property var _piProviders: []
    property var _piModels: []
    property var _modelCandidates: []
    property int _generation: 0
    property bool _busy: false
    property string _status: ""
    // "information", "positive" or "error"; drives the status message type.
    property string _statusKind: "information"
    property bool _draftDirty: false
    property bool _loadingDraft: false
    readonly property string _defaultAgentText: i18n("(Default agent)")
    readonly property string _defaultProviderText: i18n("(Default provider)")
    readonly property string _defaultModelText: i18n("(Default model)")

    function _withoutSentinel(text, sentinel) {
        var t = String(text || "").trim();
        return t === sentinel ? "" : t;
    }

    function _get(key, fallback) {
        if (rootRef && typeof rootRef.getSessionProperty === "function")
            return rootRef.getSessionProperty(_sessionId, key, fallback);
        return fallback;
    }

    function _setStatus(text, kind) {
        _status = text || "";
        _statusKind = kind || "information";
    }

    function _invalidate() {
        _generation += 1;
        _busy = false;
        _setStatus("");
    }

    function _requestToken() {
        _busy = true;
        return { generation: _generation, sessionId: _sessionId };
    }

    function _current(token) {
        return token && token.generation === _generation && token.sessionId === _sessionId;
    }

    function _markDirty() {
        if (!_loadingDraft)
            _draftDirty = true;
    }

    function _providerEntries() {
        var cfg = rootRef && rootRef.plasmoid ? rootRef.plasmoid.configuration : null;
        var global = cfg ? (cfg.provider || "openai") : "openai";
        var result = [{ text: i18nc("@item:inlistbox %1 is the default provider", "Default (%1)", ProviderService.getProviderDisplayName(global, cfg)), value: "" }];
        var configured = ProviderService.getConfiguredProviders(cfg);
        var walletKeys = rootRef ? (rootRef.walletApiKeys || {}) : {};
        var supported = ProviderService.getSupportedProviders(cfg);
        for (var w = 0; w < supported.length; w++) {
            if (walletKeys[supported[w]] && configured.indexOf(supported[w]) < 0)
                configured.push(supported[w]);
        }
        for (var i = 0; i < configured.length; i++)
            result.push({ text: ProviderService.getProviderDisplayName(configured[i], cfg), value: configured[i] });
        return result;
    }

    // The first entry (sentinel) stands for "use the default".
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
        agentCombo.model = _names(rootRef ? rootRef.openCodeAgentsList : [], _defaultAgentText);
        agentCombo.editText = _ocAgent || _defaultAgentText;
        ocProviderCombo.model = _names(rootRef ? rootRef.openCodeProvidersList : [], _defaultProviderText);
        ocProviderCombo.editText = _ocProvider || _defaultProviderText;
        ocModelCombo.model = _names(rootRef ? rootRef.openCodeModelsList : [], _defaultModelText);
        ocModelCombo.editText = _ocModel || _defaultModelText;
    }

    function _load(sessionId) {
        _invalidate();
        _sessionId = sessionId || "";
        var source = _get("source", "");
        if (!source)
            source = rootRef && rootRef.openCodeMode ? "opencode" : "provider";
        _sessionTitle = rootRef ? rootRef.displayTitle(rootRef.currentSessionTitle) : "";
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
        var globalPiProvider = rootRef && rootRef.plasmoid ? (rootRef.plasmoid.configuration.piProvider || "") : "";
        var globalPiModel = rootRef && rootRef.plasmoid ? (rootRef.plasmoid.configuration.piModel || "") : "";
        _piProvider = _get("chatProvider", globalPiProvider);
        if (!_piProvider) _piProvider = globalPiProvider;
        _piModel = _get("chatModel", globalPiModel);
        if (!_piModel) _piModel = globalPiModel;
        _piProviders = rootRef ? (rootRef.piProviderCandidates || []) : [];
        _piModels = rootRef && rootRef.piProviderModelMap ? (rootRef.piProviderModelMap[_piProvider] || []) : [];
        _modelCandidates = [];
        _draftDirty = false;
        _loadingDraft = true;
        _applyLists();
        cwdField.text = _ocCwd;
        memoryCheck.checked = _memoryEnabled;
        memoryArea.text = _memory;
        systemCheck.checked = _systemEnabled;
        systemArea.text = _system;
        responseLengthCombo.currentIndex = _responseLength;
        _loadingDraft = false;
        // Always refresh the active source when opening. The old UI skipped
        // refreshes when a per-chat override was empty or keys loaded late.
        Qt.callLater(function() {
            if (_sessionId !== sessionId || !page.visible)
                return;
            if (_mode === "opencode")
                _refreshOpenCode(function() { _refreshAgents(); });
            else if (_mode === "pi")
                _refreshPi();
            else
                _refreshModels(false);
        });
    }

    function openForSession(sessionId) {
        if (!rootRef)
            return;
        _load(sessionId);
        open();
    }

    function open() {
        sidebarOpen = true;
        Qt.callLater(function() { modeProviderButton.forceActiveFocus(); });
    }

    // Closes without asking. Use requestClose() for user-initiated closing.
    function close() {
        sidebarOpen = false;
        if (rootRef)
            rootRef.focusInput();
    }

    // Asks what to do with unapplied changes before closing.
    function requestClose() {
        if (_draftDirty)
            unsavedDialog.open();
        else
            close();
    }

    function toggleForSession(sessionId) {
        if (visible && _sessionId === sessionId) {
            requestClose();
            return;
        }
        openForSession(sessionId);
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
            _setStatus(i18n("Loading models…"));
        // Keys stored in KWallet are only in memory, not in the config.
        var walletKey = rootRef.walletApiKeys ? String(rootRef.walletApiKeys[provider] || "") : "";
        ProviderService.fetchModelsForProvider(provider, rootRef.plasmoid.configuration,
            function(models) {
                if (!_current(token)) return;
                _busy = false;
                _modelCandidates = models || [];
                modelCombo.model = _modelCandidates;
                if (!_model && _modelCandidates.length > 0)
                    _model = _modelCandidates[0];
                modelCombo.editText = _model;
                if (_modelCandidates.length > 0)
                    _setStatus(showStatus ? i18np("Found %1 model.", "Found %1 models.", _modelCandidates.length) : "", "positive");
                else
                    _setStatus(i18n("The provider didn't list any models. You can still type a model name."), "information");
            },
            function(errorText) {
                if (!_current(token)) return;
                _busy = false;
                _setStatus(i18n("Couldn't load the model list: %1", errorText), "error");
            },
            walletKey);
    }

    function _refreshAgents() {
        if (_busy || !rootRef || typeof rootRef.fetchOpenCodeAgents !== "function")
            return;
        var token = _requestToken();
        _setStatus(i18n("Loading OpenCode agents…"));
        rootRef.fetchOpenCodeAgents(function() {
            if (!_current(token)) return;
            _busy = false;
            _applyLists();
            var count = (rootRef.openCodeAgentsList || []).length;
            if (count > 0)
                _setStatus(i18np("Found %1 agent.", "Found %1 agents.", count), "positive");
            else
                _setStatus(i18n("OpenCode didn't report any agents."), "information");
        });
    }

    function _refreshOpenCode(done) {
        if (_busy || !rootRef || typeof rootRef.fetchOpenCodeProvidersAndModels !== "function") {
            if (done) done();
            return;
        }
        var token = _requestToken();
        _setStatus(i18n("Loading OpenCode providers and models…"));
        rootRef.fetchOpenCodeProvidersAndModels(function() {
            if (!_current(token)) return;
            _busy = false;
            _applyLists();
            var providerCount = (rootRef.openCodeProvidersList || []).length;
            if (providerCount > 0)
                _setStatus("", "information");
            else
                _setStatus(i18n("OpenCode didn't report any providers or models. Is the OpenCode server running?"), "error");
            if (done) done();
        });
    }

    function _refreshPi() {
        if (_busy || !rootRef || typeof rootRef.fetchPiModels !== "function")
            return;
        var token = _requestToken();
        _setStatus(i18n("Loading Pi providers and models…"));
        rootRef.fetchPiModels(function(providers, modelMap) {
            if (!_current(token)) return;
            _piProviders = providers || [];
            var models = modelMap || {};
            _piModels = models[_piProvider] || [];
            _busy = false;
            if (_piProviders.length > 0)
                _setStatus("", "information");
            else
                _setStatus(i18n("Pi didn't report any providers. Is the pi command installed and set up?"), "error");
        });
    }

    function _save() {
        _invalidate();
        if (!rootRef || !_sessionId) {
            close();
            return;
        }
        var selected = _selectedProvider();
        var overrides = {
            source: _mode,
            chatProvider: _mode === "pi" ? _piProvider : (selected === (rootRef.plasmoid.configuration.provider || "openai") ? "" : selected),
            chatModel: _mode === "pi" ? _piModel : modelCombo.editText.trim(),
            openCodeAgent: _withoutSentinel(agentCombo.editText, _defaultAgentText),
            openCodeProvider: _withoutSentinel(ocProviderCombo.editText, _defaultProviderText),
            openCodeModel: _withoutSentinel(ocModelCombo.editText, _defaultModelText),
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
        _draftDirty = false;
        close();
    }

    function _discardChanges() {
        _invalidate();
        _load(_sessionId);
    }

    function _setMode(mode) {
        if (_mode === mode) return;
        _invalidate();
        _mode = mode;
        _modelCandidates = [];
        _markDirty();
        _applyLists();
        if (mode === "opencode")
            _refreshOpenCode(function() { _refreshAgents(); });
        else if (mode === "pi")
            _refreshPi();
        else if (mode === "provider")
            _refreshModels(false);
    }

    visible: sidebarOpen
    z: 1000
    anchors.top: parent ? parent.top : undefined
    anchors.right: parent ? parent.right : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    width: overlaysChat
        ? (parent ? parent.width : Kirigami.Units.gridUnit * 20)
        : Math.min(Kirigami.Units.gridUnit * 22, Math.max(Kirigami.Units.gridUnit * 18, (parent ? parent.width : Kirigami.Units.gridUnit * 40) * 0.44))
    color: Kirigami.Theme.backgroundColor
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
    border.width: 1
    radius: Kirigami.Units.cornerRadius || Kirigami.Units.smallSpacing
    focus: sidebarOpen
    Keys.onEscapePressed: page.requestClose()
    onSidebarOpenChanged: if (!sidebarOpen) page._invalidate()

    // A request that never answers must not leave Apply disabled forever.
    Timer {
        interval: 20000
        running: page._busy
        onTriggered: {
            page._busy = false;
            page._generation += 1;
            page._setStatus(i18n("No answer yet. Check the connection and try Refresh again."), "error");
        }
    }

    Connections {
        target: page.rootRef
        function onCurrentSessionIdChanged() {
            if (page.visible && page.rootRef && page.rootRef.currentSessionId !== page._sessionId) {
                if (page._draftDirty)
                    page.rootRef.showNotice(i18n("Unapplied Chat Settings changes for “%1” were discarded.", page._sessionTitle), "warning");
                page._load(page.rootRef.currentSessionId);
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: i18n("Choose OpenCode Workspace")
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.indexOf("file://") === 0) path = decodeURIComponent(path.substring(7));
            cwdField.text = path;
            page._markDirty();
        }
    }

    Kirigami.PromptDialog {
        id: unsavedDialog

        title: i18n("Apply Changes?")
        subtitle: i18n("You changed the settings for “%1” but haven't applied them.", page._sessionTitle)
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: i18n("Apply")
                icon.name: "dialog-ok-apply"
                onTriggered: {
                    unsavedDialog.close();
                    page._save();
                }
            },
            Kirigami.Action {
                text: i18n("Discard")
                icon.name: "edit-delete"
                onTriggered: {
                    unsavedDialog.close();
                    page._draftDirty = false;
                    page.close();
                }
            },
            Kirigami.Action {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onTriggered: unsavedDialog.close()
            }
        ]
    }

    // A checkable mode button whose checked state always follows
    // currentMode (clicking a checkable button would otherwise break the
    // binding).
    component ModeButton: PC3.Button {
        id: modeButton

        property string mode
        property string currentMode
        signal chosen(string mode)

        Layout.fillWidth: true
        checkable: true
        checked: currentMode === mode
        onClicked: {
            modeButton.chosen(mode);
            checked = Qt.binding(function() { return modeButton.currentMode === modeButton.mode; });
        }
    }

    // Caption above a field in this narrow panel.
    component FieldLabel: PC3.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        wrapMode: Text.Wrap
    }

    component Hint: PC3.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "document-properties"
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("Chat Settings")
                }

                PC3.Label {
                    Layout.fillWidth: true
                    text: page._sessionTitle
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    elide: Text.ElideRight
                }
            }

            PC3.ToolButton {
                text: i18n("Close")
                icon.name: "window-close"
                display: PC3.AbstractButton.IconOnly
                QQC2.ToolTip.text: i18nc("@info:tooltip %1 is an action name", "%1 (Esc)", text)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: page.requestClose()
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        PC3.ScrollView {
            id: settingsScroll

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth

            ColumnLayout {
                width: settingsScroll.availableWidth
                spacing: Kirigami.Units.smallSpacing

                Item {
                    implicitHeight: Kirigami.Units.smallSpacing
                }

                Kirigami.Heading {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    level: 5
                    text: i18n("Answer with")
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    ModeButton {
                        id: modeProviderButton
                        mode: "provider"
                        currentMode: page._mode
                        text: i18n("AI Provider")
                        onChosen: function(mode) { page._setMode(mode); }
                    }
                    ModeButton {
                        mode: "opencode"
                        currentMode: page._mode
                        text: i18n("OpenCode")
                        onChosen: function(mode) { page._setMode(mode); }
                    }
                    ModeButton {
                        mode: "pi"
                        currentMode: page._mode
                        text: i18n("Pi Agent")
                        onChosen: function(mode) { page._setMode(mode); }
                    }
                }

                // Provider
                ColumnLayout {
                    visible: page._mode === "provider"
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    FieldLabel {
                        text: i18n("Provider:")
                    }
                    PC3.ComboBox {
                        id: providerCombo
                        Layout.fillWidth: true
                        textRole: "text"
                        valueRole: "value"
                        Accessible.name: i18n("Provider")
                        onActivated: {
                            page._provider = currentValue || "";
                            page._model = "";
                            page._modelCandidates = [];
                            page._markDirty();
                            page._refreshModels(true);
                        }
                    }

                    FieldLabel {
                        text: i18n("Model:")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PC3.ComboBox {
                            id: modelCombo
                            Layout.fillWidth: true
                            editable: true
                            Accessible.name: i18n("Model")
                            onActivated: { page._model = currentText; page._markDirty(); }
                            onEditTextChanged: { if (activeFocus) { page._model = editText; page._markDirty(); } }
                        }
                        PC3.ToolButton {
                            text: i18n("Refresh Model List")
                            icon.name: "view-refresh"
                            display: PC3.AbstractButton.IconOnly
                            enabled: !page._busy
                            onClicked: page._refreshModels(true)
                            QQC2.ToolTip.text: text
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }
                    Hint {
                        text: i18n("Pick from the list or type a model name. Providers are set up under Configure KDE AI Chat.")
                    }
                }

                // OpenCode
                ColumnLayout {
                    visible: page._mode === "opencode"
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    FieldLabel {
                        text: i18n("Agent:")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PC3.ComboBox {
                            id: agentCombo
                            Layout.fillWidth: true
                            editable: true
                            Accessible.name: i18n("OpenCode agent")
                            onEditTextChanged: { page._ocAgent = editText; page._markDirty(); }
                        }
                        PC3.ToolButton {
                            text: i18n("Reload from OpenCode")
                            icon.name: "view-refresh"
                            display: PC3.AbstractButton.IconOnly
                            enabled: !page._busy
                            onClicked: page._refreshOpenCode(function() { page._refreshAgents(); })
                            QQC2.ToolTip.text: text
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }

                    FieldLabel {
                        text: i18n("Provider:")
                    }
                    PC3.ComboBox {
                        id: ocProviderCombo
                        Layout.fillWidth: true
                        editable: true
                        Accessible.name: i18n("OpenCode provider")
                        onEditTextChanged: { page._ocProvider = editText; page._markDirty(); }
                    }

                    FieldLabel {
                        text: i18n("Model:")
                    }
                    PC3.ComboBox {
                        id: ocModelCombo
                        Layout.fillWidth: true
                        editable: true
                        Accessible.name: i18n("OpenCode model")
                        onEditTextChanged: { page._ocModel = editText; page._markDirty(); }
                    }
                    Hint {
                        text: i18n("An agent with its own model in opencode.json uses that model.")
                    }

                    FieldLabel {
                        text: i18n("Workspace folder:")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PC3.TextField {
                            id: cwdField
                            Layout.fillWidth: true
                            maximumLength: 4096
                            placeholderText: i18n("Same as the default")
                            Accessible.name: i18n("Workspace folder")
                            onTextChanged: { page._ocCwd = text; page._markDirty(); }
                        }
                        PC3.ToolButton {
                            text: i18n("Choose Folder…")
                            icon.name: "document-open-folder"
                            display: PC3.AbstractButton.IconOnly
                            onClicked: folderDialog.open()
                            QQC2.ToolTip.text: text
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }
                }

                // Pi
                ColumnLayout {
                    visible: page._mode === "pi"
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    FieldLabel {
                        text: i18n("Provider:")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PC3.ComboBox {
                            id: piProviderCombo
                            Layout.fillWidth: true
                            model: page._piProviders
                            textRole: "text"
                            valueRole: "value"
                            Accessible.name: i18n("Pi provider")
                            currentIndex: {
                                for (var i = 0; i < model.length; i++) if (model[i].value === page._piProvider) return i;
                                return -1;
                            }
                            onActivated: {
                                page._piProvider = currentValue || currentText;
                                page._piModels = rootRef && rootRef.piProviderModelMap ? (rootRef.piProviderModelMap[page._piProvider] || []) : [];
                                page._piModel = page._piModels.length > 0 ? page._piModels[0] : "";
                                page._markDirty();
                            }
                        }
                        PC3.ToolButton {
                            text: i18n("Reload from Pi")
                            icon.name: "view-refresh"
                            display: PC3.AbstractButton.IconOnly
                            enabled: !page._busy
                            onClicked: page._refreshPi()
                            QQC2.ToolTip.text: text
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }

                    FieldLabel {
                        text: i18n("Model:")
                    }
                    PC3.ComboBox {
                        id: piModelCombo
                        Layout.fillWidth: true
                        editable: true
                        model: page._piModels
                        editText: page._piModel
                        Accessible.name: i18n("Pi model")
                        onActivated: { page._piModel = currentText; page._markDirty(); }
                        onEditTextChanged: { if (activeFocus) { page._piModel = editText; page._markDirty(); } }
                    }
                    Hint {
                        text: i18n("Applies to this chat only.")
                    }
                }

                RowLayout {
                    visible: page._busy || page._status.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    PC3.BusyIndicator {
                        visible: page._busy
                        running: page._busy
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: page._status.length > 0
                        text: page._status
                        type: page._statusKind === "error" ? Kirigami.MessageType.Error
                            : page._statusKind === "positive" ? Kirigami.MessageType.Positive
                            : Kirigami.MessageType.Information
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing
                }

                Kirigami.Heading {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    level: 5
                    text: i18n("Instructions for this chat")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    PC3.CheckBox {
                        id: systemCheck
                        visible: page._mode !== "opencode"
                        Layout.fillWidth: true
                        text: i18n("Use system instructions")
                        onCheckedChanged: { page._systemEnabled = checked; page._markDirty(); }
                    }
                    PC3.TextArea {
                        id: systemArea
                        visible: page._mode !== "opencode"
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                        maximumLength: 100000
                        enabled: systemCheck.checked
                        wrapMode: Text.WordWrap
                        placeholderText: i18n("Leave empty to use the instructions from Settings")
                        Accessible.name: i18n("System instructions")
                        onTextChanged: { page._system = text; page._markDirty(); }
                    }

                    PC3.CheckBox {
                        id: memoryCheck
                        Layout.fillWidth: true
                        text: i18n("Use memory")
                        onCheckedChanged: { page._memoryEnabled = checked; page._markDirty(); }
                    }
                    PC3.TextArea {
                        id: memoryArea
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                        maximumLength: 100000
                        enabled: memoryCheck.checked
                        wrapMode: Text.WordWrap
                        placeholderText: i18n("Facts the assistant should remember in this chat")
                        Accessible.name: i18n("Memory")
                        onTextChanged: { page._memory = text; page._markDirty(); }
                    }
                    Hint {
                        text: i18n("Instructions and memory are sent with every message in this chat. Don't put passwords here.")
                    }

                    RowLayout {
                        visible: page._mode !== "opencode"
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        PC3.Label {
                            Layout.fillWidth: true
                            text: i18n("Answer length:")
                        }
                        PC3.ComboBox {
                            id: responseLengthCombo
                            model: [i18nc("@item:inlistbox answer length", "Default"), i18nc("@item:inlistbox answer length", "Short"), i18nc("@item:inlistbox answer length", "Balanced"), i18nc("@item:inlistbox answer length", "Detailed"), i18nc("@item:inlistbox answer length", "Comprehensive")]
                            Accessible.name: i18n("Answer length")
                            onActivated: page._markDirty()
                        }
                    }
                }

                Item {
                    implicitHeight: Kirigami.Units.largeSpacing
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            PC3.Button {
                text: i18n("Discard Changes")
                icon.name: "edit-undo"
                enabled: page._draftDirty
                onClicked: page._discardChanges()
            }
            Item {
                Layout.fillWidth: true
            }
            PC3.Button {
                text: i18n("Apply")
                icon.name: "dialog-ok-apply"
                highlighted: true
                enabled: !page._busy
                onClicked: page._save()
            }
        }
    }
}
