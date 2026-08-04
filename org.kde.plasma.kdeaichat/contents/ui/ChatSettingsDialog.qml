import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "ProviderService.js" as ProviderService

QQC2.Dialog {
    id: chatSettingsDialog

    title: targetSessionTitle ? ("Chat Settings - " + targetSessionTitle) : "Chat Settings"
    modal: true
    focus: true
    padding: Kirigami.Units.gridUnit
    standardButtons: QQC2.Dialog.NoButton

    property var rootRef: null
    property string targetSessionId: ""
    property string targetSessionTitle: ""

    // Session properties
    property string selectedMode: "provider" // "provider" or "opencode"
    property string selectedProvider: ""
    property string selectedModel: ""
    property string selectedOpenCodeAgent: ""
    property string selectedOpenCodeModel: ""
    property string selectedOpenCodeWorkspaceCwd: ""
    property bool chatMemoryEnabled: true
    property string chatMemoryText: ""
    property bool chatSystemPromptEnabled: true
    property string chatSystemPromptText: ""
    property int selectedResponseLength: 0

    property var modelCandidates: []
    property bool loadingModels: false
    property string statusText: ""

    width: Math.min(Screen.width ? Screen.width * 0.9 : 640, 600)
    height: Math.min(Screen.height ? Screen.height * 0.85 : 700, 660)

    function openForSession(sessionId) {
        if (!rootRef) return;
        targetSessionId = sessionId || rootRef.currentSessionId || "";
        targetSessionTitle = rootRef.currentSessionTitle || "Current Chat";

        if (typeof rootRef.getSessionProperty === "function") {
            var src = rootRef.getSessionProperty(targetSessionId, "source", "");
            if (!src) {
                src = (rootRef.openCodeMode ? "opencode" : "provider");
            }
            selectedMode = src;

            selectedProvider = rootRef.getSessionProperty(targetSessionId, "chatProvider", "");
            selectedModel = rootRef.getSessionProperty(targetSessionId, "chatModel", "");
            selectedOpenCodeAgent = rootRef.getSessionProperty(targetSessionId, "openCodeAgent", "");
            selectedOpenCodeModel = rootRef.getSessionProperty(targetSessionId, "openCodeModel", "");
            selectedOpenCodeWorkspaceCwd = rootRef.getSessionProperty(targetSessionId, "openCodeWorkspaceCwd", "");
            chatMemoryEnabled = rootRef.getSessionProperty(targetSessionId, "chatMemoryEnabled", true);
            chatMemoryText = rootRef.getSessionProperty(targetSessionId, "chatMemory", "");
            chatSystemPromptEnabled = rootRef.getSessionProperty(targetSessionId, "chatSystemPromptEnabled", true);
            chatSystemPromptText = rootRef.getSessionProperty(targetSessionId, "chatSystemPrompt", "");
            selectedResponseLength = rootRef.getSessionProperty(targetSessionId, "responseLength", 0);
        } else {
            selectedMode = rootRef.openCodeMode ? "opencode" : "provider";
            selectedProvider = "";
            selectedModel = "";
            selectedOpenCodeAgent = "";
            selectedOpenCodeModel = "";
            selectedOpenCodeWorkspaceCwd = "";
            chatMemoryEnabled = true;
            chatMemoryText = "";
            chatSystemPromptEnabled = true;
            chatSystemPromptText = "";
            selectedResponseLength = 0;
        }

        statusText = "";
        if (selectedMode === "provider") {
            refreshModelCandidates();
        } else {
            if (typeof rootRef.fetchOpenCodeAgents === "function") {
                rootRef.fetchOpenCodeAgents();
            }
            if (typeof rootRef.fetchOpenCodeProvidersAndModels === "function") {
                rootRef.fetchOpenCodeProvidersAndModels();
            }
        }
        open();
    }

    function refreshModelCandidates() {
        if (!rootRef || !rootRef.plasmoid) return;
        var prov = selectedProvider || rootRef.plasmoid.configuration.provider || "openai";
        loadingModels = true;
        statusText = "Fetching models for " + ProviderService.getProviderDisplayName(prov, rootRef.plasmoid.configuration) + "...";
        modelCandidates = [];

        ProviderService.fetchModelsForProvider(prov, rootRef.plasmoid.configuration, function(ids) {
            loadingModels = false;
            modelCandidates = ids;
            statusText = ids.length > 0 ? ("Loaded " + ids.length + " candidate models") : "No models returned from API endpoint";
        }, function(err) {
            loadingModels = false;
            statusText = "API query result: " + err;
        });
    }

    function saveSettings() {
        if (!rootRef || !targetSessionId) return;

        if (typeof rootRef.setSessionProperty === "function") {
            rootRef.setSessionProperty(targetSessionId, "source", selectedMode);
            rootRef.setSessionProperty(targetSessionId, "chatProvider", selectedProvider);
            rootRef.setSessionProperty(targetSessionId, "chatModel", selectedModel);
            rootRef.setSessionProperty(targetSessionId, "openCodeAgent", selectedOpenCodeAgent);
            rootRef.setSessionProperty(targetSessionId, "openCodeModel", selectedOpenCodeModel);
            rootRef.setSessionProperty(targetSessionId, "openCodeWorkspaceCwd", selectedOpenCodeWorkspaceCwd);
            rootRef.setSessionProperty(targetSessionId, "chatMemoryEnabled", chatMemoryEnabled);
            rootRef.setSessionProperty(targetSessionId, "chatMemory", chatMemoryText);
            rootRef.setSessionProperty(targetSessionId, "chatSystemPromptEnabled", chatSystemPromptEnabled);
            rootRef.setSessionProperty(targetSessionId, "chatSystemPrompt", chatSystemPromptText);
            rootRef.setSessionProperty(targetSessionId, "responseLength", selectedResponseLength);
        }

        if (targetSessionId === rootRef.currentSessionId) {
            rootRef.openCodeMode = (selectedMode === "opencode");
            if (selectedOpenCodeAgent) rootRef.openCodeAgent = selectedOpenCodeAgent;
            if (selectedOpenCodeWorkspaceCwd) rootRef.openCodeWorkspaceCwd = selectedOpenCodeWorkspaceCwd;
        }

        if (typeof rootRef.saveCurrentSessionState === "function") {
            rootRef.saveCurrentSessionState(true);
        }
        close();
    }

    function resetDefaults() {
        selectedMode = rootRef && rootRef.plasmoid && rootRef.plasmoid.configuration.useOpenCode ? "opencode" : "provider";
        selectedProvider = "";
        selectedModel = "";
        selectedOpenCodeAgent = "";
        selectedOpenCodeModel = "";
        selectedOpenCodeWorkspaceCwd = "";
        chatMemoryEnabled = true;
        chatMemoryText = "";
        chatSystemPromptEnabled = true;
        chatSystemPromptText = "";
        selectedResponseLength = 0;
        statusText = "Reset chat properties to global defaults.";
        if (selectedMode === "provider") {
            refreshModelCandidates();
        }
    }

    FolderDialog {
        id: dirDialog
        title: "Select OpenCode Workspace Directory"
        currentFolder: selectedOpenCodeWorkspaceCwd ? ("file://" + selectedOpenCodeWorkspaceCwd) : ""
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.indexOf("file://") === 0) path = path.substring(7);
            selectedOpenCodeWorkspaceCwd = path;
        }
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.mediumSpacing

        // Main Scrollable Area
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.mediumSpacing

                // Mode Selector Card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: modeLayout.implicitHeight + Kirigami.Units.gridUnit
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.3)
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        id: modeLayout
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing * 1.5
                        spacing: Kirigami.Units.smallSpacing

                        PC3.Label {
                            text: "Chat Execution Mode"
                            font.bold: true
                            color: Kirigami.Theme.textColor
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.mediumSpacing

                            PC3.RadioButton {
                                id: modeNormalRadio
                                text: "🌐 Normal AI Provider Mode"
                                checked: chatSettingsDialog.selectedMode !== "opencode"
                                onClicked: {
                                    chatSettingsDialog.selectedMode = "provider";
                                    chatSettingsDialog.refreshModelCandidates();
                                }
                            }

                            PC3.RadioButton {
                                id: modeOpenCodeRadio
                                text: "💻 OpenCode Mode"
                                checked: chatSettingsDialog.selectedMode === "opencode"
                                onClicked: {
                                    chatSettingsDialog.selectedMode = "opencode";
                                    if (chatSettingsDialog.rootRef && typeof chatSettingsDialog.rootRef.fetchOpenCodeAgents === "function") {
                                        chatSettingsDialog.rootRef.fetchOpenCodeAgents();
                                    }
                                    if (chatSettingsDialog.rootRef && typeof chatSettingsDialog.rootRef.fetchOpenCodeProvidersAndModels === "function") {
                                        chatSettingsDialog.rootRef.fetchOpenCodeProvidersAndModels();
                                    }
                                }
                            }
                        }

                        PC3.Label {
                            text: chatSettingsDialog.selectedMode === "opencode" ?
                                  "OpenCode Mode routes messages to local/remote OpenCode assistant engine with workspace tools." :
                                  "Normal AI Mode uses configured AI model APIs directly (OpenAI, Anthropic, Gemini, Groq, Ollama, etc.)."
                            font.pointSize: 8.5
                            opacity: 0.75
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                // Normal Mode Settings: Provider & Model Card
                Rectangle {
                    visible: chatSettingsDialog.selectedMode !== "opencode"
                    Layout.fillWidth: true
                    implicitHeight: providerCardLayout.implicitHeight + Kirigami.Units.gridUnit
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        id: providerCardLayout
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing * 1.5
                        spacing: Kirigami.Units.smallSpacing

                        PC3.Label {
                            text: "Provider & Model Overrides (Configured APIs Only)"
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PC3.Label {
                                text: "Provider:"
                                Layout.preferredWidth: 100
                            }

                            QQC2.ComboBox {
                                id: providerCombo
                                Layout.fillWidth: true
                                textRole: "text"
                                valueRole: "value"

                                model: {
                                    var cfg = chatSettingsDialog.rootRef ? chatSettingsDialog.rootRef.plasmoid.configuration : null;
                                    var list = [{
                                        "text": "Default (Global: " + ProviderService.getProviderDisplayName(cfg ? (cfg.provider || "openai") : "openai", cfg) + ")",
                                        "value": ""
                                    }];
                                    var configured = ProviderService.getConfiguredProviders(cfg);
                                    for (var i = 0; i < configured.length; i++) {
                                        list.push({
                                            "text": ProviderService.getProviderDisplayName(configured[i], cfg),
                                            "value": configured[i]
                                        });
                                    }
                                    return list;
                                }

                                currentIndex: {
                                    var cur = chatSettingsDialog.selectedProvider;
                                    for (var i = 0; i < model.length; i++) {
                                        if (model[i].value === cur) return i;
                                    }
                                    return 0;
                                }

                                onActivated: {
                                    var val = model[currentIndex].value;
                                    chatSettingsDialog.selectedProvider = val;
                                    chatSettingsDialog.refreshModelCandidates();
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PC3.Label {
                                text: "Model:"
                                Layout.preferredWidth: 100
                            }

                            QQC2.ComboBox {
                                id: modelCombo
                                Layout.fillWidth: true
                                editable: true

                                model: {
                                    var list = ["Default (Global Model)"];
                                    for (var i = 0; i < chatSettingsDialog.modelCandidates.length; i++) {
                                        list.push(chatSettingsDialog.modelCandidates[i]);
                                    }
                                    if (chatSettingsDialog.selectedModel && list.indexOf(chatSettingsDialog.selectedModel) < 0) {
                                        list.push(chatSettingsDialog.selectedModel);
                                    }
                                    return list;
                                }

                                editText: chatSettingsDialog.selectedModel

                                onEditTextChanged: {
                                    chatSettingsDialog.selectedModel = editText;
                                }

                                onActivated: {
                                    if (currentIndex === 0) {
                                        chatSettingsDialog.selectedModel = "";
                                        editText = "";
                                    } else {
                                        chatSettingsDialog.selectedModel = currentText;
                                    }
                                }
                            }

                            PC3.ToolButton {
                                id: refreshModelsBtn
                                icon.name: "view-refresh"
                                onClicked: chatSettingsDialog.refreshModelCandidates()

                                QQC2.ToolTip {
                                    text: "Fetch available candidate models live from API endpoint"
                                    visible: refreshModelsBtn.hovered
                                    z: 9999
                                }
                            }
                        }

                        PC3.Label {
                            text: chatSettingsDialog.statusText
                            font.pointSize: 8.5
                            opacity: 0.8
                            color: Kirigami.Theme.highlightColor
                            visible: chatSettingsDialog.statusText !== ""
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                // OpenCode Mode Settings Card
                Rectangle {
                    visible: chatSettingsDialog.selectedMode === "opencode"
                    Layout.fillWidth: true
                    implicitHeight: openCodeCardLayout.implicitHeight + Kirigami.Units.gridUnit
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        id: openCodeCardLayout
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing * 1.5
                        spacing: Kirigami.Units.smallSpacing

                        PC3.Label {
                            text: "OpenCode Engine Properties"
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PC3.Label {
                                text: "Agent Profile:"
                                Layout.preferredWidth: 100
                            }

                            QQC2.ComboBox {
                                Layout.fillWidth: true
                                editable: true
                                model: {
                                    var agents = chatSettingsDialog.rootRef ? chatSettingsDialog.rootRef.openCodeAgentsList : [];
                                    var list = ["(default agent from opencode)"];
                                    for (var i = 0; i < agents.length; i++) {
                                        var aItem = agents[i];
                                        var aName = (typeof aItem === "string") ? aItem : (aItem.name || aItem.text || "");
                                        if (aName && list.indexOf(aName) < 0) list.push(aName);
                                    }
                                    if (chatSettingsDialog.selectedOpenCodeAgent && list.indexOf(chatSettingsDialog.selectedOpenCodeAgent) < 0) {
                                        list.push(chatSettingsDialog.selectedOpenCodeAgent);
                                    }
                                    return list;
                                }
                                editText: chatSettingsDialog.selectedOpenCodeAgent
                                onEditTextChanged: chatSettingsDialog.selectedOpenCodeAgent = editText
                                onActivated: {
                                    if (currentIndex === 0) {
                                        chatSettingsDialog.selectedOpenCodeAgent = "";
                                        editText = "";
                                    } else {
                                        chatSettingsDialog.selectedOpenCodeAgent = currentText;
                                    }
                                }
                            }

                            PC3.ToolButton {
                                id: refreshAgentsBtn
                                icon.name: "view-refresh"
                                onClicked: {
                                    if (chatSettingsDialog.rootRef && typeof chatSettingsDialog.rootRef.fetchOpenCodeAgents === "function") {
                                        chatSettingsDialog.rootRef.fetchOpenCodeAgents();
                                        chatSettingsDialog.statusText = "Refreshed OpenCode agents list.";
                                    }
                                }

                                QQC2.ToolTip {
                                    text: "Refresh active agents list from OpenCode server / opencode.json"
                                    visible: refreshAgentsBtn.hovered
                                    z: 9999
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PC3.Label {
                                text: "Model / Provider:"
                                Layout.preferredWidth: 100
                            }

                            QQC2.ComboBox {
                                Layout.fillWidth: true
                                editable: true
                                model: {
                                    var list = ["(default model from opencode)"];
                                    var mList = chatSettingsDialog.rootRef ? chatSettingsDialog.rootRef.openCodeModelsList : [];
                                    for (var i = 0; i < mList.length; i++) {
                                        if (list.indexOf(mList[i]) < 0) list.push(mList[i]);
                                    }
                                    if (chatSettingsDialog.selectedOpenCodeModel && list.indexOf(chatSettingsDialog.selectedOpenCodeModel) < 0) {
                                        list.push(chatSettingsDialog.selectedOpenCodeModel);
                                    }
                                    return list;
                                }
                                editText: chatSettingsDialog.selectedOpenCodeModel
                                onEditTextChanged: chatSettingsDialog.selectedOpenCodeModel = editText
                                onActivated: {
                                    if (currentIndex === 0) {
                                        chatSettingsDialog.selectedOpenCodeModel = "";
                                        editText = "";
                                    } else {
                                        chatSettingsDialog.selectedOpenCodeModel = currentText;
                                    }
                                }
                            }

                            PC3.ToolButton {
                                id: refreshOpenCodeModelsBtn
                                icon.name: "view-refresh"
                                onClicked: {
                                    if (chatSettingsDialog.rootRef && typeof chatSettingsDialog.rootRef.fetchOpenCodeProvidersAndModels === "function") {
                                        chatSettingsDialog.rootRef.fetchOpenCodeProvidersAndModels();
                                        chatSettingsDialog.statusText = "Refreshed OpenCode providers and models.";
                                    }
                                }

                                QQC2.ToolTip {
                                    text: "Refresh providers & models from OpenCode /provider API"
                                    visible: refreshOpenCodeModelsBtn.hovered
                                    z: 9999
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PC3.Label {
                                text: "Workspace Cwd:"
                                Layout.preferredWidth: 100
                            }

                            QQC2.TextField {
                                Layout.fillWidth: true
                                placeholderText: "Default global workspace directory"
                                text: chatSettingsDialog.selectedOpenCodeWorkspaceCwd
                                onTextChanged: chatSettingsDialog.selectedOpenCodeWorkspaceCwd = text
                            }

                            PC3.ToolButton {
                                id: browseDirBtn
                                icon.name: "folder"
                                onClicked: dirDialog.open()

                                QQC2.ToolTip {
                                    text: "Browse workspace directory folder"
                                    visible: browseDirBtn.hovered
                                    z: 9999
                                }
                            }
                        }
                    }
                }

                // Per-Chat Memory Card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: memoryCardLayout.implicitHeight + Kirigami.Units.gridUnit
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        id: memoryCardLayout
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing * 1.5
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label {
                                text: "Per-Chat Memory"
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            PC3.CheckBox {
                                text: "Enable Chat Memory"
                                checked: chatSettingsDialog.chatMemoryEnabled
                                onClicked: chatSettingsDialog.chatMemoryEnabled = checked
                            }
                        }

                        PC3.Label {
                            text: "Notes, facts, and context items retained specifically for this session:"
                            font.pointSize: 8.5
                            opacity: 0.75
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        QQC2.TextArea {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 70
                            enabled: chatSettingsDialog.chatMemoryEnabled
                            wrapMode: Text.WordWrap
                            placeholderText: "e.g. User prefers Python 3.12 syntax and strict typing for code snippets in this session."
                            text: chatSettingsDialog.chatMemoryText
                            onTextChanged: chatSettingsDialog.chatMemoryText = text
                        }
                    }
                }

                // Per-Chat System Instructions Card (Normal Mode)
                Rectangle {
                    visible: chatSettingsDialog.selectedMode !== "opencode"
                    Layout.fillWidth: true
                    implicitHeight: sysPromptCardLayout.implicitHeight + Kirigami.Units.gridUnit
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        id: sysPromptCardLayout
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing * 1.5
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label {
                                text: "Per-Chat System Instructions"
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            PC3.CheckBox {
                                text: "Enable System Context"
                                checked: chatSettingsDialog.chatSystemPromptEnabled
                                onClicked: chatSettingsDialog.chatSystemPromptEnabled = checked
                            }
                        }

                        PC3.Label {
                            text: "Custom system prompt additions for this chat (extends global system prompt):"
                            font.pointSize: 8.5
                            opacity: 0.75
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        QQC2.TextArea {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 70
                            enabled: chatSettingsDialog.chatSystemPromptEnabled
                            wrapMode: Text.WordWrap
                            placeholderText: "e.g. Act as a senior Linux kernel software engineer..."
                            text: chatSettingsDialog.chatSystemPromptText
                            onTextChanged: chatSettingsDialog.chatSystemPromptText = text
                        }
                    }
                }

                // Response Length Preference Card (Normal Mode)
                Rectangle {
                    visible: chatSettingsDialog.selectedMode !== "opencode"
                    Layout.fillWidth: true
                    implicitHeight: respLenCardLayout.implicitHeight + Kirigami.Units.gridUnit
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        id: respLenCardLayout
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing * 1.5
                        spacing: Kirigami.Units.smallSpacing

                        PC3.Label {
                            text: "Response Length Preference"
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PC3.Label {
                                text: "Length:"
                                Layout.preferredWidth: 100
                            }

                            QQC2.ComboBox {
                                Layout.fillWidth: true
                                model: ["Default (Global)", "Short (~256 tokens)", "Balanced (~1024 tokens)", "Detailed (~4096 tokens)", "Comprehensive (~8192 tokens)"]
                                currentIndex: chatSettingsDialog.selectedResponseLength
                                onActivated: chatSettingsDialog.selectedResponseLength = currentIndex
                            }
                        }
                    }
                }
            }
        }

        // Bottom Action Buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.Button {
                text: "Reset Defaults"
                icon.name: "edit-clear-all"
                onClicked: chatSettingsDialog.resetDefaults()
            }

            Item {
                Layout.fillWidth: true
            }

            PC3.Button {
                text: "Cancel"
                icon.name: "dialog-cancel"
                onClicked: chatSettingsDialog.close()
            }

            PC3.Button {
                text: "Save Settings"
                icon.name: "dialog-ok-apply"
                highlighted: true
                onClicked: chatSettingsDialog.saveSettings()
            }
        }
    }
}
