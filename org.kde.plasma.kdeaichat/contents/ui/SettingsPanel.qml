import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support 2.0 as P5Support

import "Security.js" as Sec
import "api.js" as Api

Item {
    id: settingsPanel

    // Interface properties required by ScheduleDialog
    property bool pageReady: false
    property bool schedulerDaemonRunning: false
    property string schedulerStatus: ""
    property var schedulerList: []
    property var schedulerArchivedList: []
    property var schedulerHistory: []
    property bool schedSaving: false
    property bool memRefreshing: false
    property int memScheduler: 0
    property int memOpenCode: 0

    property string _lastSchedSetupPayload: ""

    // Bind configuration to/from plasmoid
    property bool cfg_schedulerEnabled: plasmoid.configuration.schedulerEnabled
    property bool cfg_schedulerAutoStart: plasmoid.configuration.schedulerAutoStart
    property bool cfg_executeMissedSchedules: plasmoid.configuration.executeMissedSchedules
    property string cfg_chatSessionsJson: plasmoid.configuration.chatSessionsJson || "[]"

    onCfg_schedulerEnabledChanged: {
        plasmoid.configuration.schedulerEnabled = cfg_schedulerEnabled
    }
    onCfg_schedulerAutoStartChanged: {
        plasmoid.configuration.schedulerAutoStart = cfg_schedulerAutoStart
    }
    onCfg_executeMissedSchedulesChanged: {
        plasmoid.configuration.executeMissedSchedules = cfg_executeMissedSchedules
    }

    // Paths
    readonly property string dataDirPath: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/kdeaichat"
    readonly property string schedulesFilePath: dataDirPath + "/schedules.json"
    readonly property string schedulerScriptPath: dataDirPath + "/kde-ai-scheduler.py"

    function translate(text) {
        return text;
    }

    function getHelperPath() {
        let urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        let path = decodeURIComponent(urlStr);
        if (path.indexOf("/") === 0 && path.indexOf("/contents/ui/") !== -1)
            return path;
        let localShare = StandardPaths.writableLocation(StandardPaths.GenericDataLocation);
        return localShare + "/plasma/plasmoids/org.kde.plasma.kdeaichat/contents/ui/kde_ai_helper.py";
    }

    function getDocExtractorPath() {
        let urlStr = String(Qt.resolvedUrl("doc_extractor.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        return decodeURIComponent(urlStr);
    }

    function schedAutoSetup() {
        let srcPath = String(Qt.resolvedUrl("../scripts/kde-ai-scheduler.py"));
        if (srcPath.indexOf("file://") === 0)
            srcPath = srcPath.substring(7);
        srcPath = decodeURIComponent(srcPath);

        let serviceContent = "[Unit]\nDescription=KDE AI Chat Scheduler Daemon\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=/usr/bin/python3 %h/.local/share/kdeaichat/kde-ai-scheduler.py\nRestart=on-failure\nRestartSec=30\nStandardOutput=journal\nStandardError=journal\nExecReload=/bin/kill -HUP $MAINPID\nKillMode=process\n\n[Install]\nWantedBy=default.target\n";
        
        let payload = {
            "srcPath": srcPath,
            "destPath": schedulerScriptPath,
            "serviceContent": serviceContent
        };
        let payloadStr = JSON.stringify(payload);
        if (payloadStr === settingsPanel._lastSchedSetupPayload)
            return;
        settingsPanel._lastSchedSetupPayload = payloadStr;
        let b64Payload = Sec.base64Encode(payloadStr);
        let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " setup_scheduler_service " + Sec.quoteForShell(b64Payload);
        utilityDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-auto-setup");
    }

    function pollSchedulerState() {
        utilityDs.connectSource("sh -c 'pgrep -f kde-ai-scheduler.py > /dev/null 2>&1 && echo SCHED_RUNNING || echo SCHED_STOPPED' #sched-poll-" + Date.now());
    }

    function schedLoadSchedules() {
        let safePath = Sec.validateFilePath(schedulesFilePath);
        if (safePath === "")
            return;
        let cmd = "cat " + Sec.quoteForShell(safePath) + " 2>/dev/null || echo '{\"schedules\":[],\"history\":[]}'";
        utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-load");
    }

    function schedSaveSchedules(items) {
        schedulerList = items;
        schedSaveAll();
    }

    function getHistoryLimitValue() {
        return 100;
    }

    function schedSaveAll() {
        schedSaving = true;
        let all = [];
        for (let i = 0; i < schedulerList.length; i++) {
            let s = Object.assign({}, schedulerList[i]);
            s.archived = false;
            all.push(s);
        }
        for (let j = 0; j < schedulerArchivedList.length; j++) {
            let sa = Object.assign({}, schedulerArchivedList[j]);
            sa.archived = true;
            all.push(sa);
        }
        let limit = getHistoryLimitValue();
        let hist = schedulerHistory || [];
        if (hist.length > limit) {
            hist = hist.slice(hist.length - limit);
            schedulerHistory = hist;
        }
        let payload = {
            "version": 1,
            "schedules": all,
            "history": hist,
            "settings": {
                "executeMissedSchedules": !!cfg_executeMissedSchedules,
                "historyLimit": limit
            }
        };
        let b64Payload = Sec.base64Encode(JSON.stringify(payload));
        let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " save_all_schedules " + Sec.quoteForShell(b64Payload);
        utilityDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-save");
    }

    function schedTriggerNow(index) {
        let copy = schedulerList.slice();
        if (index < 0 || index >= copy.length)
            return;
        let s = JSON.parse(JSON.stringify(copy[index]));
        s.triggerNow = true;
        copy[index] = s;
        schedulerList = copy;
        schedSaveAll();
    }

    function schedMakeUuid() {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
            let r = Math.random() * 16 | 0;
            return (c === "x" ? r : (r & 3 | 8)).toString(16);
        });
    }

    function schedHumanCron(expr) {
        if (!expr)
            return "No schedule";
        let parts = expr.trim().split(/\s+/);
        if (parts.length !== 5)
            return expr;
        let min = parts[0], hr = parts[1], dom = parts[2], mon = parts[3], dow = parts[4];
        if (min === "0" && hr !== "*" && dom === "*" && mon === "*") {
            let h = parseInt(hr), ampm = h >= 12 ? "PM" : "AM", h12 = h % 12 || 12;
            let dayStr = dow === "*" ? "every day" : dow === "1-5" ? "weekdays" : dow === "6,0" || dow === "0,6" ? "weekends" : "on selected days";
            return "Daily at " + h12 + ":00 " + ampm + " " + dayStr;
        }
        if (hr.indexOf && hr.indexOf("*/") === 0)
            return "Every " + hr.slice(2) + " hours";
        return expr;
    }

    readonly property string schedulerGuideText: {
        if (!cfg_schedulerEnabled)
            return "<b>Schedules Guide:</b><br/>The scheduler runs in the background. At the time you choose, it automatically sends a message into your chat and the AI replies.<br/><br/>• <b>Status: Stopped</b>.<br/>• <b>Action:</b> Toggle the <b>Scheduler switch</b> below to <b>ON</b> to boot the background daemon.";
        if (!schedulerDaemonRunning)
            return "<b>Schedules Guide:</b><br/>• <b>Status: Starting up...</b><br/>• The scheduler daemon is starting in the background. Once initialized, the status indicator will show <b>Active</b>.<br/>• (Optional) Make sure to toggle <b>Auto-start at login</b> to <b>ON</b> if you want automated schedules to trigger even when you don't open settings.";
        let count = schedulerList.length;
        let enabledCount = 0;
        for (let i = 0; i < count; i++) {
            if (schedulerList[i] && schedulerList[i].enabled)
                enabledCount++;
        }
        if (count === 0)
            return "<b>Schedules Guide:</b><br/>• <b>Status: Active &amp; running!</b><br/>• The scheduler is connected and monitoring. But you have <b>0 schedules configured</b>.<br/>• <b>Action:</b> Click <b>Create Schedule</b> below to set up your first automated daily or one-time prompt!";
        return "<b>Schedules Guide:</b><br/>• <b>Status: Active &amp; running!</b><br/>• You have <b>" + count + " schedule(s) configured</b> (" + enabledCount + " enabled).<br/>• The background service will run automatically. Click <b>Manage Schedules</b> to edit/trigger tasks.";
    }

    ScheduleDialog {
        id: scheduleDialogObj
        page: settingsPanel
    }

    readonly property alias scheduleDialog: scheduleDialogObj

    P5Support.DataSource {
        id: utilityDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let out = data["stdout"] ? data["stdout"] : "";
            let err = data["stderr"] ? data["stderr"] : "";

            if (out.trim() === "" && err.trim() === "") {
                return;
            }

            if (sourceName.indexOf("sched-poll-") >= 0) {
                settingsPanel.schedulerDaemonRunning = (out.trim() === "SCHED_RUNNING");
                if (!settingsPanel.schedulerDaemonRunning && settingsPanel.schedulerStatus === "Restarting…")
                    settingsPanel.schedulerStatus = "Stopped";
            } else if (sourceName.indexOf("sched-start") >= 0) {
                settingsPanel.schedulerStatus = "";
                Qt.callLater(pollSchedulerState);
            } else if (sourceName.indexOf("sched-stop") >= 0) {
                settingsPanel.schedulerDaemonRunning = false;
                settingsPanel.schedulerStatus = "Stopped";
                Qt.callLater(pollSchedulerState);
            } else if (sourceName.indexOf("sched-hup") >= 0) {
                settingsPanel.schedulerStatus = "Schedules reloaded (SIGHUP sent).";
            } else if (sourceName.indexOf("mem-usage-") >= 0) {
                settingsPanel.memRefreshing = false;
                try {
                    let memData = JSON.parse(out.trim());
                    settingsPanel.memScheduler = memData.scheduler || 0;
                    settingsPanel.memOpenCode = memData.opencode || 0;
                } catch (e) {
                    console.warn("Failed to parse memory data:", e);
                }
            } else if (sourceName.indexOf("sched-enable") >= 0) {
                settingsPanel.schedulerStatus = out.indexOf("SCHED_ENABLE_OK") >= 0 ? "Auto-start updated." : (err || out);
            } else if (sourceName.indexOf("sched-auto-setup") >= 0) {
                if (out.indexOf("AUTO_ENABLED") >= 0)
                    cfg_schedulerAutoStart = true;
                else if (out.indexOf("AUTO_DISABLED") >= 0)
                    cfg_schedulerAutoStart = false;
            } else if (sourceName.indexOf("sched-load") >= 0) {
                if (out !== "") {
                    try {
                        let parsed = JSON.parse(out);
                        let allSchedules = parsed.schedules || [];
                        let active = [];
                        let archived = [];
                        for (let i = 0; i < allSchedules.length; i++) {
                            if (allSchedules[i]) {
                                if (allSchedules[i].archived)
                                    archived.push(allSchedules[i]);
                                else
                                    active.push(allSchedules[i]);
                            }
                        }
                        settingsPanel.schedulerList = active;
                        settingsPanel.schedulerArchivedList = archived;
                        let hist = parsed.history || [];
                        let limit = settingsPanel.getHistoryLimitValue();
                        if (hist.length > limit)
                            hist = hist.slice(hist.length - limit);

                        settingsPanel.schedulerHistory = hist;
                    } catch (e) {
                        settingsPanel.schedulerList = [];
                        settingsPanel.schedulerArchivedList = [];
                        settingsPanel.schedulerHistory = [];
                    }
                }
            } else if (sourceName.indexOf("sched-save") >= 0) {
                settingsPanel.schedSaving = false;
                settingsPanel.schedulerStatus = "Schedules saved.";
            }

            disconnectSource(sourceName);
        }
    }

    Timer {
        id: schedPollTimer
        interval: 30000
        repeat: true
        running: cfg_schedulerEnabled
        onTriggered: {
            settingsPanel.pollSchedulerState();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            text: "Advanced Settings & Schedules"
            level: 2
            Layout.fillWidth: true
        }

        QQC2.ScrollView {
            id: mainScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: mainScroll.width - Kirigami.Units.gridUnit
                spacing: Kirigami.Units.largeSpacing

                // SECTION 1: Advanced AI Settings (System Prompt & Memory)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        text: "AI System Prompt & Memory"
                        level: 3
                        Layout.fillWidth: true
                    }

                    QQC2.Label {
                        text: "Configure custom instructions and memory for the AI assistant."
                        color: Kirigami.Theme.disabledTextColor
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    QQC2.Label {
                        text: "System Prompt Override:"
                        font.bold: true
                    }

                    QQC2.ScrollView {
                        id: spScroll
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                        Layout.maximumHeight: Kirigami.Units.gridUnit * 5
                        clip: true

                        QQC2.TextArea {
                            id: sysPromptInput
                            width: spScroll.width
                            text: plasmoid.configuration.systemPrompt
                            placeholderText: "Type custom system prompt instructions here..."
                            wrapMode: Text.Wrap
                            onTextChanged: {
                                plasmoid.configuration.systemPrompt = text
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.CheckBox {
                            id: memoryCheck
                            text: "Enable Persistent Memory"
                            checked: plasmoid.configuration.enableMemory
                            onCheckedChanged: {
                                plasmoid.configuration.enableMemory = checked
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: memoryCheck.checked
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: "User Memory Content:"
                            font.bold: true
                        }

                        QQC2.ScrollView {
                            id: memScroll
                            Layout.fillWidth: true
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                            Layout.maximumHeight: Kirigami.Units.gridUnit * 5
                            clip: true

                            QQC2.TextArea {
                                id: userMemoryInput
                                width: memScroll.width
                                text: plasmoid.configuration.userMemory
                                placeholderText: "Facts or preferences the AI should remember across chats..."
                                wrapMode: Text.Wrap
                                onTextChanged: {
                                    plasmoid.configuration.userMemory = text
                                }
                            }
                        }
                    }
                }

                // SECTION 2: Background Scheduler Daemon
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        text: "Background Scheduler Daemon"
                        level: 3
                        Layout.fillWidth: true
                    }

                    // Schedules Guide Banner
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: schedGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                        radius: 6
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
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.2
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
                                Layout.alignment: Qt.AlignTop
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                text: settingsPanel.schedulerGuideText
                                wrapMode: Text.Wrap
                                textFormat: Text.RichText
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                                color: Kirigami.Theme.textColor
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Switch {
                            id: schedulerMasterSwitch
                            text: checked ? "Scheduler Active" : "Scheduler Inactive"
                            checked: settingsPanel.cfg_schedulerEnabled
                            onCheckedChanged: {
                                if (!settingsPanel.pageReady) return;
                                settingsPanel.cfg_schedulerEnabled = checked;
                                if (checked) {
                                    settingsPanel.schedulerStatus = "Starting…";
                                    let safeSchedulerScriptPath = Sec.validateFilePath(settingsPanel.schedulerScriptPath);
                                    let cmd = "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || " + "(pkill -f kde-ai-scheduler.py 2>/dev/null; sleep 0.5; " + "python3 " + Sec.quoteForShell(safeSchedulerScriptPath) + " &) ; " + "echo SCHED_START_OK";
                                    settingsPanel.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-start-" + Date.now());
                                } else {
                                    settingsPanel.schedulerStatus = "Stopping…";
                                    let cmd = "systemctl --user stop kde-ai-scheduler.service 2>/dev/null; pkill -f kde-ai-scheduler.py 2>/dev/null; echo SCHED_STOP_OK";
                                    settingsPanel.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-stop-" + Date.now());
                                }
                                schedPollTimer.restart();
                                settingsPanel.pollSchedulerState();
                            }
                        }

                        QQC2.Switch {
                            id: schedAutoStartToggle
                            visible: schedulerMasterSwitch.checked
                            text: "Start daemon at login"
                            checked: settingsPanel.cfg_schedulerAutoStart
                            onCheckedChanged: {
                                if (!settingsPanel.pageReady) return;
                                settingsPanel.cfg_schedulerAutoStart = checked;
                                let status = checked ? "enable" : "disable";
                                let cmd = "systemctl --user " + status + " kde-ai-scheduler.service 2>&1 || echo SCHED_ENABLE_OK";
                                settingsPanel.utilityDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-enable-" + Date.now());
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: schedulerMasterSwitch.checked
                        QQC2.Switch {
                            id: executeMissedSchedulesToggle
                            text: "Execute missed schedules on boot"
                            checked: settingsPanel.cfg_executeMissedSchedules
                            onCheckedChanged: {
                                if (!settingsPanel.pageReady) return;
                                settingsPanel.cfg_executeMissedSchedules = checked;
                                settingsPanel.schedSaveAll();
                            }
                        }
                    }

                    QQC2.Label {
                        visible: settingsPanel.schedulerStatus !== ""
                        text: settingsPanel.schedulerStatus
                        color: Kirigami.Theme.highlightColor
                        font.italic: true
                    }

                    // Schedules management list
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: schedulerMasterSwitch.checked
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            QQC2.Label {
                                text: "Configured Schedules:"
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            QQC2.Button {
                                text: "Manage / Configure Schedules"
                                icon.name: "appointment-new"
                                onClicked: {
                                    settingsPanel.scheduleDialog.editingIndex = -1;
                                    settingsPanel.scheduleDialog.localActiveList = settingsPanel.schedulerList.slice();
                                    settingsPanel.scheduleDialog.localArchivedList = settingsPanel.schedulerArchivedList.slice();
                                    settingsPanel.scheduleDialog.open();
                                }
                            }
                        }

                        // Compact view of schedules inside panel
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            visible: settingsPanel.schedulerList.length > 0

                            Repeater {
                                model: settingsPanel.schedulerList
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: schedRow.implicitHeight + Kirigami.Units.smallSpacing
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
                                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                    border.width: 1
                                    radius: 4

                                    RowLayout {
                                        id: schedRow
                                        anchors.fill: parent
                                        anchors.margins: Kirigami.Units.smallSpacing / 2
                                        spacing: Kirigami.Units.smallSpacing

                                        Kirigami.Icon {
                                            source: modelData.enabled ? "appointment-new" : "appointment-missed"
                                            implicitWidth: 16
                                            implicitHeight: 16
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            QQC2.Label {
                                                text: modelData.name || "Untitled Schedule"
                                                font.bold: true
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            QQC2.Label {
                                                text: modelData.taskType === "single" ? "One-time at " + modelData.singleDateTime : settingsPanel.schedHumanCron(modelData.cron)
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                color: Kirigami.Theme.disabledTextColor
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        QQC2.Button {
                                            text: "Trigger"
                                            icon.name: "media-playback-start"
                                            QQC2.ToolTip.text: "Trigger this prompt immediately"
                                            QQC2.ToolTip.visible: hovered
                                            onClicked: {
                                                settingsPanel.schedTriggerNow(index);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        QQC2.Label {
                            text: "No schedules created yet."
                            color: Kirigami.Theme.disabledTextColor
                            visible: settingsPanel.schedulerList.length === 0
                        }
                    }
                }

                // SECTION 3: Resource & Memory Usage
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        text: "Resource & Memory Usage"
                        level: 3
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            text: "Monitor RSS memory usage of helper background daemons."
                            color: Kirigami.Theme.disabledTextColor
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        QQC2.Button {
                            text: settingsPanel.memRefreshing ? "Refreshing…" : "Refresh Stats"
                            icon.name: "view-refresh"
                            enabled: !settingsPanel.memRefreshing
                            onClicked: {
                                settingsPanel.memRefreshing = true;
                                let cmd = "python3 " + Sec.quoteForShell(settingsPanel.getHelperPath()) + " get_memory_usage";
                                settingsPanel.utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
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
                                text: settingsPanel.memScheduler > 0 ? (settingsPanel.memScheduler / 1024).toFixed(1) + " MB" : "Not running"
                                color: settingsPanel.memScheduler > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                font.bold: settingsPanel.memScheduler > 0
                            }

                            RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Icon { source: "utilities-terminal"; implicitWidth: 16; implicitHeight: 16 }
                                QQC2.Label { text: "OpenCode" }
                            }
                            QQC2.Label {
                                text: settingsPanel.memOpenCode > 0 ? (settingsPanel.memOpenCode / 1024).toFixed(1) + " MB" : "Not running"
                                color: settingsPanel.memOpenCode > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                font.bold: settingsPanel.memOpenCode > 0
                            }

                            QQC2.Label { text: "Total"; font.bold: true }
                            QQC2.Label {
                                text: (settingsPanel.memScheduler + settingsPanel.memOpenCode) > 0 ? ((settingsPanel.memScheduler + settingsPanel.memOpenCode) / 1024).toFixed(1) + " MB" : "—"
                                font.bold: true
                                color: Kirigami.Theme.highlightColor
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        settingsPanel.schedLoadSchedules();
        settingsPanel.schedAutoSetup();
        settingsPanel.pollSchedulerState();
        
        let cmd = "python3 " + Sec.quoteForShell(settingsPanel.getHelperPath()) + " get_memory_usage";
        settingsPanel.utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());

        settingsPanel.pageReady = true;
    }
}
