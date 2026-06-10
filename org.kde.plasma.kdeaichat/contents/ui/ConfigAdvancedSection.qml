// LINKAGE RELATIONSHIPS:
// - ConfigAdvancedSection.qml: Contains advanced behavior configurations, system prompt customization, user memory, global context options, local cron-style schedules scheduler, database export/import, and memory usage tracking.
// - Parent: Instantiated inside ConfigGeneral.qml (the main KCM settings page).
// - Linked via properties:
//   - Exposes text areas, toggles, and text fields via aliases to the parent for configuration bindings (cfg_).
//   - Accesses parent properties (e.g. page.cfg_useOpenCode, page.cfg_showInteractiveGuides) and functions (e.g. page.pollSchedulerState, page.schedSaveAll) via the `page` reference.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import "Security.js" as Sec

Kirigami.FormLayout {
    id: advancedSection

    property var page: null

    // Expose fields via alias for configuration bindings in the parent KCM
    property alias systemPromptArea: systemPromptArea
    property alias memoryEnabledToggle: memoryEnabledToggle
    property alias userMemoryArea: userMemoryArea
    property alias globalContextEnabledToggle: globalContextEnabledToggle
    property alias globalContextLimitSpin: globalContextLimitSpin
    property alias globalContextAutoCompactToggle: globalContextAutoCompactToggle
    property alias globalContextCompactThresholdSpin: globalContextCompactThresholdSpin
    property alias schedulerMasterSwitch: schedulerMasterSwitch
    property alias schedAutoStartToggle: schedAutoStartToggle
    property alias executeMissedSchedulesToggle: executeMissedSchedulesToggle
    property alias appDisplayNameField: appDisplayNameField
    property alias customHistoryPathField: customHistoryPathField
    property alias storageModeCombo: storageModeCombo
    property alias walletNameField: walletNameField
    property alias kwalletAutoPromptCheck: kwalletAutoPromptCheck

    // Value aliases for config bindings to avoid double-nested aliases in parent
    property alias walletName: walletNameField.text
    property alias systemPrompt: systemPromptArea.text
    property alias memoryEnabled: memoryEnabledToggle.checked
    property alias userMemory: userMemoryArea.text
    property alias globalContextEnabled: globalContextEnabledToggle.checked
    property alias globalContextLimit: globalContextLimitSpin.value
    property alias globalContextAutoCompact: globalContextAutoCompactToggle.checked
    property alias globalContextCompactThreshold: globalContextCompactThresholdSpin.value
    property alias schedulerEnabled: schedulerMasterSwitch.checked
    property alias schedulerAutoStart: schedAutoStartToggle.checked
    property alias executeMissedSchedules: executeMissedSchedulesToggle.checked
    property alias appDisplayName: appDisplayNameField.text
    property alias customHistoryPath: customHistoryPathField.text

    // ── Behavior Section ──────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("Behavior") : "Behavior"
    }

    RowLayout {
        visible: page ? page.cfg_showInteractiveGuides : false
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        spacing: Kirigami.Units.gridUnit
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("Behavior Guide") : "Behavior Guide"

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: behaviorGuideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: behaviorGuideLayout
                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "help-hint"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                    Layout.alignment: Qt.AlignTop
                }

                QQC2.Label {
                    id: behaviorGuideLabel
                    Layout.fillWidth: true
                    text: advancedSection.behaviorGuideText
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }

    QQC2.ScrollView {
        id: systemPromptScrollView
        Kirigami.FormData.label: page ? page.translate("System prompt:") : "System prompt:"
        implicitHeight: Kirigami.Units.gridUnit * 5
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
        Layout.maximumHeight: Kirigami.Units.gridUnit * 5
        clip: true

        QQC2.TextArea {
            id: systemPromptArea
            width: systemPromptScrollView.availableWidth
            wrapMode: Text.Wrap
            placeholderText: "You are KDE AI Chat, a precise and helpful assistant."
            background: null
            padding: Kirigami.Units.smallSpacing + 2
        }

        background: Rectangle {
            color: Kirigami.Theme.backgroundColor
            radius: 4
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
            border.width: 1
        }
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: "Sets a default instruction sent to the AI at the start of every conversation. Leave blank for the built-in default."
    }

    QQC2.CheckBox {
        id: memoryEnabledToggle
        Kirigami.FormData.label: page ? page.translate("Global Memory:") : "Global Memory:"
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        text: memoryEnabledToggle.checked ? "Enabled — memory is injected into every prompt" : "Disabled"
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: "Write facts you want the AI to always remember — your name, preferences, context. Injected at the start of every prompt when enabled."
    }

    QQC2.ScrollView {
        id: userMemoryScrollView
        visible: memoryEnabledToggle.checked
        implicitHeight: Kirigami.Units.gridUnit * 6
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        Layout.preferredHeight: Kirigami.Units.gridUnit * 6
        Layout.maximumHeight: Kirigami.Units.gridUnit * 6
        clip: true

        QQC2.TextArea {
            id: userMemoryArea
            width: userMemoryScrollView.availableWidth
            wrapMode: Text.Wrap
            placeholderText: "E.g., My name is Alex. I use KDE Plasma 6. I prefer Python for scripting. Always be concise."
            background: null
            padding: Kirigami.Units.smallSpacing + 2
        }

        background: Rectangle {
            color: Kirigami.Theme.backgroundColor
            radius: 4
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
            border.width: 1
        }
    }

    QQC2.Label {
        visible: memoryEnabledToggle.checked
        Kirigami.FormData.label: ""
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: "Memory is saved with your settings (Apply/OK). It persists across sessions and is prepended to the system prompt."
    }

    QQC2.CheckBox {
        id: globalContextEnabledToggle
        Kirigami.FormData.label: page ? page.translate("Global Context:") : "Global Context:"
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        text: globalContextEnabledToggle.checked ? (page ? page.translate("Enabled — chat context will be sent to AI") : "Enabled") : (page ? page.translate("Disabled — AI will only see the current prompt") : "Disabled")
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("Each chat has the ability to modify the context settings for that chat. If nothing is specified there, then this global context default is used. When disabled, the AI only answers the immediate question without remembering previous messages.") : ""
    }

    RowLayout {
        id: globalContextLimitRow
        visible: globalContextEnabledToggle.checked
        spacing: Kirigami.Units.smallSpacing
        Kirigami.FormData.label: page ? page.translate("Context limit:") : "Context limit:"
        Layout.maximumWidth: advancedSection.fieldMaxWidth

        QQC2.SpinBox {
            id: globalContextLimitSpin
            from: 1
            to: 100
            value: 1
            editable: true
        }

        QQC2.Label {
            text: page ? page.translate("messages") : "messages"
        }
    }

    QQC2.Label {
        visible: globalContextEnabledToggle.checked
        Kirigami.FormData.label: ""
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("The maximum number of recent messages sent to the AI in each request to preserve token limit / memory.") : ""
    }

    QQC2.CheckBox {
        id: globalContextAutoCompactToggle
        visible: globalContextEnabledToggle.checked
        Kirigami.FormData.label: page ? page.translate("Context compacting:") : "Context compacting:"
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        text: page ? page.translate("Auto compact") : "Auto compact"
    }

    QQC2.Label {
        visible: globalContextEnabledToggle.checked
        Kirigami.FormData.label: ""
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("When enabled, older messages exceeding the threshold are automatically summarized in the background and replaced with a single summary message to preserve context window tokens.") : ""
    }

    RowLayout {
        id: globalContextCompactThresholdRow
        visible: globalContextEnabledToggle.checked && globalContextAutoCompactToggle.checked
        spacing: Kirigami.Units.smallSpacing
        Kirigami.FormData.label: page ? page.translate("Compacting threshold:") : "Compacting threshold:"
        Layout.maximumWidth: advancedSection.fieldMaxWidth

        QQC2.SpinBox {
            id: globalContextCompactThresholdSpin
            from: 5
            to: 100
            value: 10
            editable: true
        }

        QQC2.Label {
            text: page ? page.translate("messages") : "messages"
        }
    }

    QQC2.Label {
        visible: globalContextEnabledToggle.checked && globalContextAutoCompactToggle.checked
        Kirigami.FormData.label: ""
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("When the number of uncompacted messages exceeds this threshold, the widget automatically summarizes them in the background and replaces them with a single summary message to save context tokens.") : ""
    }

    // ── Scheduler Section ─────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("Scheduler") : "Scheduler"
    }

    RowLayout {
        visible: page ? page.cfg_showInteractiveGuides : false
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        spacing: Kirigami.Units.gridUnit
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("Schedules Guide") : "Schedules Guide"

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: schedGuideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: schedGuideLayout
                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "help-hint"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                    Layout.alignment: Qt.AlignTop
                }

                QQC2.Label {
                    id: schedGuideLabel
                    Layout.fillWidth: true
                    text: advancedSection.schedulerGuideText
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }

    QQC2.Switch {
        id: schedAutoStartToggle
        Kirigami.FormData.label: page ? page.translate("Auto-start at login:") : "Auto-start at login:"
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        text: schedAutoStartToggle.checked ? (page ? page.translate("Scheduler starts automatically when you log in") : "") : (page ? page.translate("Off — start manually each session") : "")
        checked: false
        onCheckedChanged: {
            if (!page || !page.pageReady)
                return ;

            let verb = checked ? "enable" : "disable";
            page.utilityDs.connectSource("sh -c 'systemctl --user " + verb + " kde-ai-scheduler.service 2>&1; echo SCHED_ENABLE_OK' #sched-enable");
        }
    }

    QQC2.Switch {
        id: executeMissedSchedulesToggle
        Kirigami.FormData.label: page ? page.translate("Missed schedules:") : "Missed schedules:"
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        text: page ? page.translate("Execute missed schedules") : ""
        checked: false
        onCheckedChanged: {
            if (!page || !page.pageReady)
                return ;
            page.schedSaveAll();
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        textFormat: Text.RichText
        text: page ? page.translate("When the PC is turned off and then it restarts, if any schedule was missed in that period, should it execute one after another? <font color=\"#ff4444\"><b>(Highly not recommended)</b></font>") : ""
        wrapMode: Text.Wrap
        opacity: 0.7
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
    }

    QQC2.Switch {
        id: schedulerMasterSwitch
        Kirigami.FormData.label: page ? page.translate("Scheduler:") : "Scheduler:"
        text: schedulerMasterSwitch.checked ? (page ? page.translate("ON — scheduler is running") : "") : (page ? page.translate("OFF — scheduler is stopped") : "")
        checked: false
        onCheckedChanged: {
            if (!page || !page.pageReady)
                return ;

            if (checked) {
                page.schedulerStatus = "Starting…";
                let safeSchedulerScriptPath = Sec.validateFilePath(page.schedulerScriptPath);
                let cmd = "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || " + "(pkill -f kde-ai-scheduler.py 2>/dev/null; sleep 0.5; " + "python3 " + Sec.quoteForShell(safeSchedulerScriptPath) + " &) ; " + "echo SCHED_START_OK";
                page.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-start-" + Date.now());
            } else {
                page.schedulerStatus = "Stopping…";
                let cmd = "systemctl --user stop kde-ai-scheduler.service 2>/dev/null; pkill -f kde-ai-scheduler.py 2>/dev/null; echo SCHED_STOP_OK";
                page.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-stop-" + Date.now());
            }
            schedPollTimer.restart();
            page.pollSchedulerState();
        }
    }

    RowLayout {
        visible: schedulerMasterSwitch.checked
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        Kirigami.FormData.label: page ? page.translate("Status:") : "Status:"
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            id: schedDotLabel
            text: page ? (page.schedulerDaemonRunning ? page.translate("Active") : (page.schedulerStatus !== "" ? page.translate(page.schedulerStatus) : page.translate("Stopped"))) : ""
            color: page ? (page.schedulerDaemonRunning ? Kirigami.Theme.positiveTextColor : (page.schedulerStatus === "Starting…" || page.schedulerStatus === "Restarting…" ? Kirigami.Theme.textColor : Kirigami.Theme.neutralTextColor)) : Kirigami.Theme.textColor
            font.bold: true
        }

        QQC2.Button {
            text: page ? (page.schedulerDaemonRunning ? page.translate("Restart") : page.translate("Force Start")) : ""
            icon.name: page ? (page.schedulerDaemonRunning ? "view-refresh" : "media-playback-start") : ""
            onClicked: {
                if (page) {
                    page.schedulerStatus = page.schedulerDaemonRunning ? "Restarting…" : "Starting…";
                    page.schedulerDaemonRunning = false;
                    let safeSchedulerScriptPath = Sec.validateFilePath(page.schedulerScriptPath);
                    let cmd = "(systemctl --user is-active --quiet kde-ai-scheduler.service && systemctl --user restart kde-ai-scheduler.service) || " + "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || " + "(pkill -f kde-ai-scheduler.py; sleep 0.5; " + "nohup python3 " + Sec.quoteForShell(safeSchedulerScriptPath) + " >/dev/null 2>&1 &) ; " + "echo SCHED_START_OK";
                    page.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-start-" + Date.now());
                    schedPollTimer.restart();
                }
            }
        }

        QQC2.Button {
            text: page ? page.translate("Stop") : "Stop"
            icon.name: "media-playback-stop"
            onClicked: {
                schedulerMasterSwitch.checked = false;
            }
        }
    }

    RowLayout {
        visible: schedulerMasterSwitch.checked
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        Kirigami.FormData.label: page ? page.translate("Schedules:") : "Schedules:"
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            text: page ? page.translate("Create Schedule") : "Create Schedule"
            icon.name: "list-add"
            highlighted: true
            Layout.fillWidth: true
            onClicked: {
                if (page) {
                    let now = new Date();
                    now.setMinutes(now.getMinutes() + 5);
                    page.scheduleDialog.draft = {
                        "id": page.schedMakeUuid(),
                        "name": "",
                        "enabled": true,
                        "chatId": "",
                        "chatName": "",
                        "message": "",
                        "taskType": "single",
                        "startDate": now.toISOString(),
                        "schedType": "days",
                        "schedEvery": 1,
                        "schedTime": "09:00",
                        "schedDays": [1],
                        "schedDayOfMonth": 1,
                        "limitEnabled": false,
                        "limitCount": 5,
                        "notify": true,
                        "createdAt": new Date().toISOString()
                    };
                    page.scheduleDialog.editingIndex = -2;
                    page.scheduleDialog.open();
                }
            }
        }

        QQC2.Button {
            text: page ? page.translate("Manage Schedules") : "Manage Schedules"
            icon.name: "appointment-new"
            Layout.fillWidth: true
            onClicked: {
                if (page) {
                    page.scheduleDialog.editingIndex = -1;
                    page.scheduleDialog.open();
                }
            }
        }

        QQC2.Button {
            text: page ? page.translate("Open Schedules File") : "Open Schedules File"
            icon.name: "document-open"
            Layout.fillWidth: true
            onClicked: {
                if (page) {
                    let safeSchedPath = Sec.validateFilePath(page.schedulesFilePath);
                    if (safeSchedPath === "")
                        return;
                    page.utilityDs.connectSource("xdg-open " + Sec.quoteForShell(safeSchedPath) + " || kde-open " + Sec.quoteForShell(safeSchedPath) + " || kwrite " + Sec.quoteForShell(safeSchedPath) + " || kate " + Sec.quoteForShell(safeSchedPath) + " || nano " + Sec.quoteForShell(safeSchedPath) + " #open-sched-file");
                }
            }
        }
    }

    Timer {
        id: schedPollTimer
        interval: 30000
        repeat: true
        running: schedulerMasterSwitch.checked
        onTriggered: {
            if (page) page.pollSchedulerState();
        }
    }

    // ── Prompt Templates ──────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("Prompt Templates") : "Prompt Templates"
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("Save frequently used prompts. Use /template in chat to apply them.") : ""
    }

    Repeater {
        model: {
            try {
                return JSON.parse(page ? page.cfg_promptTemplates || "[]" : "[]");
            } catch(e) { return []; }
        }
        delegate: RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: advancedSection.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: modelData.name || ("Template " + (index + 1))
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            QQC2.ToolButton {
                icon.name: "edit-delete"
                onClicked: {
                    if (!page) return;
                    let arr = JSON.parse(page.cfg_promptTemplates || "[]");
                    arr.splice(index, 1);
                    page.cfg_promptTemplates = JSON.stringify(arr);
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            id: newTemplateName
            placeholderText: page ? page.translate("Template name") : "Template name"
            Layout.fillWidth: true
        }
        QQC2.TextField {
            id: newTemplatePrompt
            placeholderText: page ? page.translate("System prompt") : "System prompt"
            Layout.fillWidth: true
        }
        QQC2.Button {
            text: page ? page.translate("Add") : "Add"
            onClicked: {
                if (!page || !newTemplateName.text.trim()) return;
                let arr = JSON.parse(page.cfg_promptTemplates || "[]");
                arr.push({"name": newTemplateName.text.trim(), "prompt": newTemplatePrompt.text.trim()});
                page.cfg_promptTemplates = JSON.stringify(arr);
                newTemplateName.text = "";
                newTemplatePrompt.text = "";
            }
        }
    }

    // ── API Key Storage ────────────────────────────────────────────────
    Kirigami.Separator {
        visible: page ? !page.cfg_useOpenCode : true
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("API Key Storage") : "API Key Storage"
    }

    QQC2.Label {
        visible: page ? !page.cfg_useOpenCode : true
        Kirigami.FormData.label: page ? page.translate("Storage mode:") : "Storage mode:"
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        text: page ? page.translate("Choose how your API keys are stored between sessions:") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.ComboBox {
        id: storageModeCombo
        visible: page ? !page.cfg_useOpenCode : true
        Kirigami.FormData.label: page ? page.translate("Storage mode:") : "Storage mode:"
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        model: ["🔒 Session only (forget keys on close)", "📄 Plain config (save to ~/.config/kdeaichatrc)", "🔑 KWallet (secure encrypted storage)"]
        currentIndex: page ? page.cfg_keyStorageMode : 1
        onCurrentIndexChanged: {
            if (!page || !page.pageReady)
                return;
            page.keyringStatus = "";
            if (currentIndex === 1) {
                page.syncKeysToDisk();
                page.keyringStatus = "Switched to Plain Config. Current keys synced to config file.";
            } else if (currentIndex === 2) {
                if (page.availableWalletNames.length === 0)
                    page.detectWallets();
            }
        }
    }

    RowLayout {
        visible: page ? (!page.cfg_useOpenCode && page.cfg_keyStorageMode === 1) : false
        Kirigami.FormData.label: page ? page.translate("Config actions:") : "Config actions:"
        Layout.fillWidth: true

        QQC2.Button {
            text: page ? page.translate("Reload from config file") : "Reload from config file"
            onClicked: { if (page) page.loadKeysFromPlainConfig(); }
        }

        QQC2.Button {
            text: page ? page.translate("Open config file") : "Open config file"
            onClicked: { if (page) page.writeKeysToDiskAndOpen(); }
        }
    }

    QQC2.Label {
        visible: page ? (!page.cfg_useOpenCode && page.cfg_keyStorageMode === 2) : false
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        text: page ? page.translate("Keys are encrypted and stored via DBus in your system KWallet. Recommended for shared or multi-user machines.") : ""
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    QQC2.ComboBox {
        visible: page ? (!page.cfg_useOpenCode && page.kwalletModeActive && page.availableWalletNames.length > 0) : false
        Kirigami.FormData.label: page ? page.translate("Wallet name:") : "Wallet name:"
        Layout.fillWidth: true
        model: page ? page.availableWalletNames : []
        currentIndex: page ? page.availableWalletNames.indexOf(page.kwalletName || "") : -1
        onActivated: {
            if (currentIndex >= 0 && page)
                page.cfg_kwalletName = currentText;
        }
    }

    QQC2.TextField {
        visible: page ? (!page.cfg_useOpenCode && page.kwalletModeActive && page.availableWalletNames.length === 0) : false
        Kirigami.FormData.label: page ? page.translate("Wallet name:") : "Wallet name:"
        Layout.fillWidth: true
        text: page ? page.cfg_kwalletName : ""
        placeholderText: "kdewallet"
        onTextChanged: { if (page) page.cfg_kwalletName = text; }
    }

    QQC2.CheckBox {
        id: kwalletAutoPromptCheck
        visible: page ? (!page.cfg_useOpenCode && page.kwalletModeActive) : false
        Kirigami.FormData.label: page ? page.translate("Auto-unlock:") : "Auto-unlock:"
        text: page ? page.translate("Automatically prompt for password") : "Automatically prompt for password"
        Layout.fillWidth: true
    }

    QQC2.Label {
        visible: page ? (!page.cfg_useOpenCode && page.kwalletModeActive) : false
        Kirigami.FormData.label: page ? page.translate("Wallet info:") : "Wallet info:"
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        text: page ? page.translate("KWallet controls wallet creation and password policy. A new wallet name may trigger KDE to create or unlock that wallet, depending on your system wallet settings.") : ""
        wrapMode: Text.Wrap
        opacity: 0.8
    }

    RowLayout {
        visible: page ? (!page.cfg_useOpenCode && page.kwalletModeActive) : false
        Kirigami.FormData.label: page ? page.translate("Wallet actions:") : "Wallet actions:"
        Layout.fillWidth: true

        QQC2.Button {
            text: page ? page.translate("Detect wallets") : "Detect wallets"
            enabled: page ? !page.keyringBusy : true
            onClicked: { if (page) page.detectWallets(); }
        }

        QQC2.Button {
            text: "Launch KWalletManager"
            onClicked: {
                if (page) page.utilityDs.connectSource("kwalletmanager6 || kwalletmanager5 || kwalletmanager #launch-kwallet");
            }
        }

        QQC2.Button {
            text: page ? page.translate("Create wallet") : "Create wallet"
            visible: page ? page.availableWalletNames.length === 0 : false
            enabled: page ? !page.keyringBusy : true
            onClicked: {
                if (page) {
                    page.cancelKeyringOps();
                    let walletName = page.effectiveWalletName();
                    page.keyringStatus = "Requesting wallet creation/open: " + walletName + "...";
                    page.utilityDs.connectSource(page.walletInitCommand(walletName) + " #kwallet-create");
                }
            }
        }
    }

    QQC2.Button {
        visible: page ? (!page.cfg_useOpenCode && page.kwalletModeActive) : false
        Kirigami.FormData.label: page ? page.translate("Wallet status:") : "Wallet status:"
        text: page ? page.translate("Check wallet status") : "Check wallet status"
        enabled: page ? !page.keyringBusy : true
        onClicked: {
            if (page) {
                page.cancelKeyringOps();
                page.keyringStatus = "Checking wallet status...";
                page.utilityDs.connectSource(page.walletStatusCommand(page.effectiveWalletName()) + " #kwallet-status-check");
            }
        }
    }

    RowLayout {
        visible: page ? (!page.cfg_useOpenCode && page.kwalletModeActive) : false
        Kirigami.FormData.label: page ? page.translate("KWallet sync:") : "KWallet sync:"
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth

        QQC2.Button {
            text: page ? page.translate("Refresh from KWallet") : "Refresh from KWallet"
            enabled: page ? !page.keyringBusy : true
            icon.name: "view-refresh"
            onClicked: {
                if (page) {
                    if (typeof page.resetKwalletFailState === "function") {
                        page.resetKwalletFailState();
                    }
                    page.kwalletLoadAll(true);
                }
            }
        }

        QQC2.Button {
            text: page ? page.translate("Sync to KWallet") : "Sync to KWallet"
            enabled: page ? !page.keyringBusy : true
            icon.name: "document-save"
            onClicked: { if (page) page.kwalletStoreAll(true); }
        }
    }

    // KWallet permanently-failed warning banner
    Rectangle {
        visible: {
            if (!page || !page.kwalletModeActive || page.cfg_useOpenCode) return false;
            return page.kwalletSyncPermanentlyFailed === true;
        }
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        Kirigami.FormData.label: ""
        implicitHeight: kwalletFailRow.implicitHeight + Kirigami.Units.gridUnit
        radius: 5
        color: Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.1)
        border.color: Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.4)
        border.width: 1

        RowLayout {
            id: kwalletFailRow
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "dialog-warning"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                Layout.alignment: Qt.AlignTop
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Kirigami.Theme.negativeTextColor
                font.bold: true
                text: page ? (page.kwalletSyncFailReason || "KWallet sync failed — possibly wrong password or wallet not unlocked. Click \"Refresh from KWallet\" above to retry.") : ""
            }
        }
    }

    QQC2.BusyIndicator {
        visible: page ? (!page.cfg_useOpenCode && page.kwalletModeActive && page.keyringBusy) : false
        running: visible
        Kirigami.FormData.label: page ? page.translate("Working:") : "Working:"
    }

    QQC2.Label {
        visible: page ? (!page.cfg_useOpenCode && page.keyringStatus !== "") : false
        Kirigami.FormData.label: page ? page.translate("Status:") : "Status:"
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        text: page ? page.keyringStatus : ""
        wrapMode: Text.Wrap
        opacity: 0.8
    }

    // ── Other settings ────────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("Other settings") : "Other settings"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Memory Usage (beta):") : "Memory Usage (beta):"
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            text: page ? (page.memRefreshing ? "Refreshing…" : "Refresh") : "Refresh"
            icon.name: "view-refresh"
            enabled: page ? !page.memRefreshing : true
            onClicked: {
                if (page) {
                    page.memRefreshing = true;
                    let cmd = "python3 " + Sec.quoteForShell(page.getHelperPath()) + " get_memory_usage";
                    page.utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        visible: true
        implicitHeight: memGrid.implicitHeight + Kirigami.Units.gridUnit
        radius: 6
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
        border.width: 1

        GridLayout {
            id: memGrid
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: Kirigami.Units.gridUnit * 0.6
            columns: 2
            columnSpacing: Kirigami.Units.gridUnit
            rowSpacing: Kirigami.Units.smallSpacing

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon { source: "appointment-new"; implicitWidth: 16; implicitHeight: 16 }
                QQC2.Label { text: "Scheduler Daemon" }
            }
            QQC2.Label {
                text: page ? (page.memScheduler > 0 ? (page.memScheduler / 1024).toFixed(1) + " MB" : "Not running") : ""
                color: page ? (page.memScheduler > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor) : Kirigami.Theme.textColor
                font.bold: page ? page.memScheduler > 0 : false
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon { source: "utilities-terminal"; implicitWidth: 16; implicitHeight: 16 }
                QQC2.Label { text: "OpenCode" }
            }
            QQC2.Label {
                text: page ? (page.memOpenCode > 0 ? (page.memOpenCode / 1024).toFixed(1) + " MB" : "Not running") : ""
                color: page ? (page.memOpenCode > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor) : Kirigami.Theme.textColor
                font.bold: page ? page.memOpenCode > 0 : false
            }

            QQC2.Label { text: "Total"; font.bold: true }
            QQC2.Label {
                text: page ? ((page.memScheduler + page.memOpenCode) > 0 ? ((page.memScheduler + page.memOpenCode) / 1024).toFixed(1) + " MB" : "—") : ""
                font.bold: true
                color: Kirigami.Theme.highlightColor
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.7
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
        text: "⚡ <b>Beta.</b> Shows live RAM (RSS) for each background component."
        textFormat: Text.RichText
    }

    RowLayout {
        visible: page ? page.cfg_showInteractiveGuides : false
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        spacing: Kirigami.Units.gridUnit
        Kirigami.FormData.label: page ? page.translate("Settings Guide") : "Settings Guide"

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: otherGuideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: otherGuideLayout
                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "help-hint"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                    Layout.alignment: Qt.AlignTop
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: advancedSection.otherSettingsGuideText
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }

    QQC2.TextField {
        id: appDisplayNameField
        Kirigami.FormData.label: page ? page.translate("App name:") : "App name:"
        placeholderText: "KDE AI Chat"
        onTextChanged: {
            if (page && text !== (plasmoid.configuration.appDisplayName || "KDE AI Chat"))
                page.discoveryStatus = "Tip: After changing the app name and pressing Apply/OK, restart plasmashell with: systemctl --user restart plasma-plasmashell.service";
        }
    }

    // ── Chat Storage Path ─────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("Chat Storage") : "Chat Storage"
    }

    RowLayout {
        Kirigami.FormData.label: page ? page.translate("Save chats to:") : "Save chats to:"
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            id: customHistoryPathField
            Layout.fillWidth: true
            placeholderText: "Default (~/.config)"
        }

        QQC2.Button {
            text: "Browse…"
            icon.name: "folder-open"
            onClicked: folderDialog.open()
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        visible: customHistoryPathField.text.trim() !== ""
        implicitHeight: storageInfoRow.implicitHeight + Kirigami.Units.smallSpacing * 2
        radius: 5
        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
        border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2)
        border.width: 1

        RowLayout {
            id: storageInfoRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "folder-sync"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                Layout.alignment: Qt.AlignVCenter
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
                text: {
                    let p = customHistoryPathField.text.trim();
                    if (p === "") return "";
                    if (p.indexOf("file://") === 0) {
                        p = decodeURIComponent(p.slice(7));
                    }
                    let file = p.endsWith("/") ? p + "kdeaichat_history.json" : p + "/kdeaichat_history.json";
                    return "Chats will be saved to: <b>" + file + "</b><br/>" +
                           "Your existing chats are <b>automatically exported</b> when you press Apply / OK.";
                }
                textFormat: Text.RichText
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        visible: customHistoryPathField.text.trim() !== ""
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            id: exportNowBtn
            text: page ? (page.storageExportStatus !== "" ? page.storageExportStatus : "Export Now") : "Export Now"
            icon.name: "document-export"
            enabled: page ? (customHistoryPathField.text.trim() !== "" && page.storageExportStatus === "") : false
            onClicked: {
                if (page) {
                    page.storageExportStatus = "Exporting…";
                    let dir = customHistoryPathField.text.trim();
                    if (dir.indexOf("file://") === 0) {
                        dir = decodeURIComponent(dir.slice(7));
                    }
                    let file = dir.endsWith("/") ? dir + "kdeaichat_history.json" : dir + "/kdeaichat_history.json";
                    let safeFile = Sec.validateFilePath(file);
                    if (safeFile === "") {
                        page.storageExportStatus = "Refusing to write to unsafe path.";
                        return;
                    }
                    let jsonStr = plasmoid.configuration.chatSessionsJson || "[]";
                    let b64 = Qt.btoa(unescape(encodeURIComponent(jsonStr)));
                    let cmd = "python3 -c \"import base64, os; path=os.path.expanduser(" + Sec.quoteForShell(safeFile) + "); os.makedirs(os.path.dirname(path), exist_ok=True); " +
                        "open(path, 'w', encoding='utf-8').write(base64.b64decode(" + Sec.quoteForShell(b64) + ").decode('utf-8')); print('OK')\"";
                    page.utilityDs.connectSource(cmd + " #storage-export-" + Date.now());
                    exportStatusTimer.restart();
                }
            }
        }

        QQC2.Button {
            text: "Open Folder"
            icon.name: "folder-open"
            visible: customHistoryPathField.text.trim() !== ""
            onClicked: {
                if (page) {
                    let dir = customHistoryPathField.text.trim();
                    if (dir.indexOf("file://") === 0) {
                        dir = decodeURIComponent(dir.slice(7));
                    }
                    let safeDir = Sec.validateFilePath(dir);
                    if (safeDir === "")
                        return;
                    page.utilityDs.connectSource("xdg-open " + Sec.quoteForShell(safeDir) + " #open-storage-dir");
                }
            }
        }

        QQC2.Button {
            text: "Clear Path"
            icon.name: "edit-clear"
            visible: customHistoryPathField.text.trim() !== ""
            onClicked: {
                customHistoryPathField.text = "";
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.7
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
        text: customHistoryPathField.text.trim() === ""
            ? "Chats are saved in the default KDE config location. Select a folder above to store them elsewhere (e.g. a synced cloud drive)."
            : "<b>Warning: Beta feature.</b> After changing this path, press <b>Apply</b> or <b>OK</b> — your chats will automatically be exported to the new location."
        textFormat: Text.RichText
    }

    Timer {
        id: exportStatusTimer
        interval: 2500
        repeat: false
        onTriggered: {
            if (page) page.storageExportStatus = "";
        }
    }

    RowLayout {
        visible: page ? page.discoveryStatus.indexOf("systemctl") >= 0 : false
        Kirigami.FormData.label: page ? page.translate("Next step:") : "Next step:"
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth

        QQC2.TextField {
            Layout.fillWidth: true
            readOnly: true
            text: "systemctl --user restart plasma-plasmashell.service"
            selectByMouse: true
        }

        QQC2.Button {
            text: "Copy"
            onClicked: {
                if (page) {
                    page.copyToClipboard("systemctl --user restart plasma-plasmashell.service");
                    page.discoveryStatus = "Command copied to clipboard!";
                }
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: advancedSection.fieldMaxWidth
        wrapMode: Text.Wrap
        text: "Settings are persisted automatically by KDE when you press Apply or OK."
        opacity: 0.8
    }

    QQC2.Button {
        Kirigami.FormData.label: page ? page.translate("Reset settings:") : "Reset settings:"
        text: "Reset to defaults"
        onClicked: {
            if (page) page.resetToDefaults();
        }
    }

    FolderDialog {
        id: folderDialog
        title: "Select Chat History Directory"
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            if (path.length > 1 && path.slice(-1) === "/")
                path = path.slice(0, -1);

            customHistoryPathField.text = path;
        }
    }

    // Helper functions/properties local or delegated to page
    readonly property string behaviorGuideText: page ? page.behaviorGuideText : ""
    readonly property string schedulerGuideText: page ? page.schedulerGuideText : ""
    readonly property string otherSettingsGuideText: page ? page.otherSettingsGuideText : ""
    readonly property real fieldMaxWidth: page ? page.fieldMaxWidth : Kirigami.Units.gridUnit * 28
}
