import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support 2.0 as P5Support

import "Security.js" as Sec

KCM.SimpleKCM {
    id: configPage

    property alias cfg_appDisplayName: appDisplayNameField.text
    property alias cfg_schedulerEnabled: schedulerMasterSwitch.checked
    property alias cfg_schedulerAutoStart: schedAutoStartToggle.checked
    property alias cfg_executeMissedSchedules: executeMissedSchedulesToggle.checked
    property string cfg_preselectedChatId: ""
    property string cfg_preselectedChatName: ""
    property string cfg_chatSessionsJson: (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.chatSessionsJson || "[]") : "[]"
    property string cfg_promptTemplates: (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.promptTemplates || "[]") : "[]"
    property string cfg_uiLanguage: "en"

    // Configuration page readiness flag
    property bool pageReady: false

    // Scheduler state variables
    property bool schedulerDaemonRunning: false
    property string schedulerStatus: ""
    property var schedulerList: []
    property var schedulerArchivedList: []
    property var schedulerHistory: []
    property bool schedSaving: false
    property bool memRefreshing: false
    property int memScheduler: 0
    property int memOpenCode: 0
    property int memStt: 0
    property int memTts: 0
    property int memSttVram: 0
    property int memTtsVram: 0

    property string _lastSchedSetupPayload: ""

    function resetToDefaults() {
        appDisplayNameField.text = "KDE AI Chat";
        schedulerMasterSwitch.checked = false;
        schedAutoStartToggle.checked = false;
        executeMissedSchedulesToggle.checked = false;
    }

    readonly property bool showGuides: (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.showInteractiveGuides !== undefined ? plasmoid.configuration.showInteractiveGuides : true) : true

    // Paths
    readonly property string _rawDataDir: {
        let p = String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation));
        if (p.indexOf("file://") === 0)
            p = decodeURIComponent(p.substring(7));
        return p;
    }
    readonly property string dataDirPath: _rawDataDir + "/kdeaichat"
    readonly property string schedulesFilePath: dataDirPath + "/schedules.json"
    readonly property string schedulerScriptPath: dataDirPath + "/kde-ai-scheduler.py"

    // Helper functions
    function translate(text) {
        return i18n(text);
    }

    function getHelperPath() {
        let urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        let path = decodeURIComponent(urlStr);
        if (path.indexOf("/") === 0 && path.indexOf("/contents/ui/") !== -1)
            return path;
        return _rawDataDir + "/plasma/plasmoids/org.kde.plasma.kdeaichat/contents/ui/kde_ai_helper.py";
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
        if (payloadStr === configPage._lastSchedSetupPayload)
            return;
        configPage._lastSchedSetupPayload = payloadStr;
        let b64Payload = Sec.base64Encode(payloadStr);
        let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " setup_scheduler_service " + Sec.rawShellSnippetQuote(b64Payload);
        utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-auto-setup-" + Date.now());
    }

    function pollSchedulerState() {
        utilityDs.connectSource("sh -c 'pgrep -f kde-ai-scheduler.py > /dev/null 2>&1 && echo SCHED_RUNNING || echo SCHED_STOPPED' #sched-poll-" + Date.now());
    }

    function schedLoadSchedules() {
        if (schedSaving)
            return;
        let safePath = Sec.validateFilePath(schedulesFilePath);
        if (safePath === "")
            return;
        let cmd = "cat " + Sec.quoteForShell(safePath) + " 2>/dev/null || echo '{\"schedules\":[],\"history\":[]}'";
        utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-load-" + Date.now());
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
                "executeMissedSchedules": !!executeMissedSchedulesToggle.checked,
                "historyLimit": limit
            }
        };
        let b64Payload = Sec.base64Encode(JSON.stringify(payload));
        let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + " save_all_schedules " + Sec.rawShellSnippetQuote(b64Payload);
        utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-save-" + Date.now());
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
            return i18n("No schedule");
        let parts = expr.trim().split(/\s+/);
        if (parts.length !== 5)
            return expr;
        let min = parts[0], hr = parts[1], dom = parts[2], mon = parts[3], dow = parts[4];
        if (min === "0" && hr !== "*" && dom === "*" && mon === "*") {
            let h = parseInt(hr), ampm = h >= 12 ? "PM" : "AM", h12 = h % 12 || 12;
            let dayStr = dow === "*" ? i18n("every day") : dow === "1-5" ? i18n("weekdays") : dow === "6,0" || dow === "0,6" ? i18n("weekends") : i18n("on selected days");
            return i18n("Daily at %1:00 %2 %3").arg(h12).arg(ampm).arg(dayStr);
        }
        if (hr.indexOf && hr.indexOf("*/") === 0)
            return i18n("Every %1 hours").arg(hr.slice(2));
        return expr;
    }

    readonly property string schedulerGuideText: {
        if (!cfg_schedulerEnabled)
            return i18n("<b>Schedules Guide:</b><br/>" + "The scheduler runs in the background. At the time you choose, it automatically sends a message into your chat and the AI replies.<br/><br/>" + "• <b>Status: Stopped</b>.<br/>" + "• <b>Action:</b> Toggle the <b>Scheduler switch</b> below to <b>ON</b> to boot the background daemon.");
        if (!schedulerDaemonRunning)
            return i18n("<b>Schedules Guide:</b><br/>" + "• <b>Status: Starting up...</b><br/>" + "• The scheduler daemon is starting in the background. Once initialized, the status indicator will show <b>Active</b>.<br/>" + "• (Optional) Make sure to toggle <b>Auto-start at login</b> to <b>ON</b> if you want automated schedules to trigger even when you don't open settings.");
        let count = schedulerList.length;
        let enabledCount = 0;
        for (let i = 0; i < count; i++) {
            if (schedulerList[i] && schedulerList[i].enabled)
                enabledCount++;
        }
        if (count === 0)
            return i18n("<b>Schedules Guide:</b><br/>" + "• <b>Status: Active &amp; running!</b><br/>" + "• The scheduler is connected and monitoring. But you have <b>0 schedules configured</b>.<br/>" + "• <b>Action:</b> Click <b>Create Schedule</b> below to set up your first automated daily or one-time prompt!");
        return i18n("<b>Schedules Guide:</b><br/>• <b>Status: Active &amp; running!</b><br/>• You have <b>%1 schedule(s) configured</b> (%2 enabled).<br/>• The background service will run automatically. Click <b>Manage Schedules</b> to edit or delete tasks, view executed run history logs, and customize history retention limits.<br/>• <i>Pro-Tip:</i> You can also schedule prompts directly from the chat box by typing <code>/schedule</code>!").arg(count).arg(enabledCount);
    }

    ScheduleDialog {
        id: scheduleDialogObj
        page: configPage
    }

    QQC2.Dialog {
        id: templateDialog
        modal: true
        standardButtons: QQC2.Dialog.Close
        title: i18n("Prompt Templates")
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Kirigami.Units.gridUnit * 32
        height: Kirigami.Units.gridUnit * 28

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: i18n("Your saved prompt templates. Type /&lt;name&gt; in chat to use them.")
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: templateListView
                    model: {
                        try {
                            return JSON.parse(configPage.cfg_promptTemplates || "[]");
                        } catch(e) { return []; }
                    }
                    delegate: Rectangle {
                        width: templateListView.width
                        implicitHeight: templateItemLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: 4
                        color: index % 2 === 0 ? Kirigami.Theme.backgroundColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                        border.width: 1

                        ColumnLayout {
                            id: templateItemLayout
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing / 2

                            QQC2.Label {
                                text: "/" + (modelData.name || ("template-" + (index + 1)))
                                font.bold: true
                                font.family: "monospace"
                                color: Kirigami.Theme.highlightColor
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: modelData.prompt || ""
                                opacity: 0.8
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                            }
                        }

                        QQC2.ToolButton {
                            anchors { right: parent.right; top: parent.top; margins: Kirigami.Units.smallSpacing }
                            icon.name: "edit-delete"
                            QQC2.ToolTip.text: i18n("Delete template")
                            onClicked: {
                                let arr = JSON.parse(configPage.cfg_promptTemplates || "[]");
                                arr.splice(index, 1);
                                configPage.cfg_promptTemplates = JSON.stringify(arr);
                            }
                        }
                    }
                }
            }

            QQC2.Label {
                visible: templateListView.model.length === 0
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignCenter
                opacity: 0.5
                text: i18n("No templates yet. Create one above.")
                font: Kirigami.Theme.smallFont
            }
        }
    }

    readonly property alias scheduleDialog: scheduleDialogObj
    readonly property alias utilityDs: utilityDs

    P5Support.DataSource {
        id: utilityDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let out = data["stdout"] ? data["stdout"] : "";
            let err = data["stderr"] ? data["stderr"] : "";

            if (out.trim() === "" && err.trim() === "") {
                disconnectSource(sourceName);
                return;
            }

            if (sourceName.indexOf("sched-poll-") >= 0) {
                configPage.schedulerDaemonRunning = (out.trim() === "SCHED_RUNNING");
                if (!configPage.schedulerDaemonRunning && configPage.schedulerStatus === "Restarting…")
                    configPage.schedulerStatus = "Stopped";
            } else if (sourceName.indexOf("sched-start") >= 0) {
                configPage.schedulerStatus = "";
                Qt.callLater(pollSchedulerState);
            } else if (sourceName.indexOf("sched-stop") >= 0) {
                configPage.schedulerDaemonRunning = false;
                configPage.schedulerStatus = "Stopped";
                Qt.callLater(pollSchedulerState);
            } else if (sourceName.indexOf("sched-hup") >= 0) {
                configPage.schedulerStatus = "Schedules reloaded (SIGHUP sent).";
            } else if (sourceName.indexOf("mem-usage-") >= 0) {
                configPage.memRefreshing = false;
                try {
                    let memData = JSON.parse(out.trim());
                    configPage.memScheduler = memData.scheduler || 0;
                    configPage.memOpenCode = memData.opencode || 0;
                    configPage.memStt = memData.stt || 0;
                    configPage.memTts = memData.tts || 0;
                    configPage.memSttVram = memData.stt_vram || 0;
                    configPage.memTtsVram = memData.tts_vram || 0;
                } catch (e) {
                    console.warn("Failed to parse memory data:", e);
                }
            } else if (sourceName.indexOf("sched-enable") >= 0) {
                configPage.schedulerStatus = out.indexOf("SCHED_ENABLE_OK") >= 0 ? "Auto-start updated." : (err || out);
            } else if (sourceName.indexOf("sched-auto-setup") >= 0) {
                if (out.indexOf("AUTO_ENABLED") >= 0)
                    schedAutoStartToggle.checked = true;
                else if (out.indexOf("AUTO_DISABLED") >= 0)
                    schedAutoStartToggle.checked = false;
            } else if (sourceName.indexOf("sched-load") >= 0) {
                console.log("ConfigOther sched-load: sourceName =", sourceName, "stdout length =", out.length, "stderr =", err);
                if (out !== "") {
                    try {
                        console.log("ConfigOther sched-load raw stdout:", out);
                        let parsed = JSON.parse(out);
                        let allSchedules = parsed.schedules || [];
                        console.log("ConfigOther sched-load parsed schedules count:", allSchedules.length);
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
                        console.log("ConfigOther sched-load: active count =", active.length, "archived count =", archived.length);
                        configPage.schedulerList = active;
                        configPage.schedulerArchivedList = archived;
                        let hist = parsed.history || [];
                        let limit = configPage.getHistoryLimitValue();
                        if (hist.length > limit)
                            hist = hist.slice(hist.length - limit);

                        configPage.schedulerHistory = hist;
                    } catch (e) {
                        console.warn("Failed to parse schedules JSON:", e);
                    }
                }
            } else if (sourceName.indexOf("sched-save") >= 0) {
                configPage.schedSaving = false;
                configPage.schedulerStatus = "Schedules saved.";
                configPage.schedLoadSchedules();
            }

            disconnectSource(sourceName);
        }
    }

    Timer {
        id: schedPollTimer
        interval: 30000
        repeat: true
        running: schedulerMasterSwitch.checked
        onTriggered: {
            configPage.pollSchedulerState();
        }
    }

    Kirigami.FormLayout {
        id: formLayout
        wideMode: false
        property int fieldMaxWidth: Kirigami.Units.gridUnit * 35

        // ── Prompt Templates ──────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Prompt Templates")
        }

        Rectangle {
            visible: configPage.showGuides
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: templatesGuideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: templatesGuideLayout
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
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    color: Kirigami.Theme.textColor
                    text: "<b>Prompt Templates</b> are reusable snippets or instructions.<br><br>" +
                          "<b>How to use:</b><br>" +
                          "1. Create a template name (e.g. <i>review</i>) and a prompt.<br>" +
                          "2. In the chat interface, simply type <b>/review</b> to inject that prompt automatically.<br>" +
                          "3. Click <b>View</b> to manage your existing templates."
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: newTemplateName
                placeholderText: i18n("Name (e.g. review)")
                Layout.fillWidth: true
            }
            QQC2.TextField {
                id: newTemplatePrompt
                placeholderText: i18n("System prompt for template")
                Layout.fillWidth: true
            }
            QQC2.Button {
                text: i18n("Add")
                icon.name: "list-add"
                enabled: newTemplateName.text.trim().length > 0
                onClicked: {
                    if (!newTemplateName.text.trim()) return;
                    let arr = JSON.parse(configPage.cfg_promptTemplates || "[]");
                    arr.push({"name": newTemplateName.text.trim(), "prompt": newTemplatePrompt.text.trim()});
                    configPage.cfg_promptTemplates = JSON.stringify(arr);
                    newTemplateName.text = "";
                    newTemplatePrompt.text = "";
                }
            }
            QQC2.Button {
                text: i18n("View")
                icon.name: "view-list-details"
                onClicked: templateDialog.open()
            }
        }

        // ── Scheduler Daemon ──────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Scheduler Daemon")
        }

        RowLayout {
            visible: configPage.showGuides
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.gridUnit
            Kirigami.FormData.label: i18n("Schedules Guide:")

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
                        text: configPage.schedulerGuideText
                        wrapMode: Text.Wrap
                        textFormat: Text.RichText
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                        color: Kirigami.Theme.textColor
                    }
                }
            }
        }

        QQC2.Switch {
            id: schedulerMasterSwitch
            Kirigami.FormData.label: i18n("Scheduler:")
            text: checked ? i18n("ON — scheduler daemon configured") : i18n("OFF — scheduler daemon inactive")
            checked: false
            onCheckedChanged: {
                if (!configPage.pageReady)
                    return;

                if (checked) {
                    configPage.schedulerStatus = "Starting…";
                    let safeSchedulerScriptPath = Sec.validateFilePath(configPage.schedulerScriptPath);
                    let cmd = "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || " + "(pkill -f kde-ai-scheduler.py 2>/dev/null; sleep 0.5; " + "python3 " + Sec.quoteForShell(safeSchedulerScriptPath) + " &) ; " + "echo SCHED_START_OK";
                    configPage.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-start-" + Date.now());
                } else {
                    configPage.schedulerStatus = "Stopping…";
                    let cmd = "systemctl --user stop kde-ai-scheduler.service 2>/dev/null; pkill -f kde-ai-scheduler.py 2>/dev/null; echo SCHED_STOP_OK";
                    configPage.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-stop-" + Date.now());
                }
                schedPollTimer.restart();
                configPage.pollSchedulerState();
            }
        }

        QQC2.Switch {
            id: schedAutoStartToggle
            visible: schedulerMasterSwitch.checked
            Kirigami.FormData.label: i18n("Auto-start at login:")
            text: checked ? i18n("Scheduler starts automatically on session startup") : i18n("Off — must start manually")
            checked: false
            onCheckedChanged: {
                if (!configPage.pageReady)
                    return;
                let verb = checked ? "enable" : "disable";
                configPage.utilityDs.connectSource("sh -c 'systemctl --user " + verb + " kde-ai-scheduler.service 2>&1; echo SCHED_ENABLE_OK' #sched-enable-" + Date.now());
            }
        }

        QQC2.Switch {
            id: executeMissedSchedulesToggle
            visible: schedulerMasterSwitch.checked
            Kirigami.FormData.label: i18n("Missed schedules:")
            text: checked ? i18n("Execute missed runs on startup") : i18n("Ignore missed runs")
            checked: false
            onCheckedChanged: {
                if (!configPage.pageReady)
                    return;
                configPage.schedSaveAll();
            }
        }

        QQC2.Label {
            visible: schedulerMasterSwitch.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            textFormat: Text.RichText
            text: i18n("When the PC is turned off and then it restarts, if any schedule was missed in that period, should it execute one after another? <font color=\"#ff4444\"><b>(Highly not recommended)</b></font>")
            wrapMode: Text.Wrap
            opacity: 0.7
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
        }

        RowLayout {
            visible: schedulerMasterSwitch.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            Kirigami.FormData.label: i18n("Status:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                id: schedDotLabel
                text: configPage.schedulerDaemonRunning ? i18n("Active") : (configPage.schedulerStatus !== "" ? configPage.schedulerStatus : i18n("Stopped"))
                color: configPage.schedulerDaemonRunning ? Kirigami.Theme.positiveTextColor : (configPage.schedulerStatus === "Starting…" || configPage.schedulerStatus === "Restarting…" ? Kirigami.Theme.textColor : Kirigami.Theme.neutralTextColor)
                font.bold: true
            }

            QQC2.Button {
                text: configPage.schedulerDaemonRunning ? i18n("Restart") : i18n("Force Start")
                icon.name: configPage.schedulerDaemonRunning ? "view-refresh" : "media-playback-start"
                onClicked: {
                    configPage.schedulerStatus = configPage.schedulerDaemonRunning ? "Restarting…" : "Starting…";
                    configPage.schedulerDaemonRunning = false;
                    let safeSchedulerScriptPath = Sec.validateFilePath(configPage.schedulerScriptPath);
                    let cmd = "(systemctl --user is-active --quiet kde-ai-scheduler.service && systemctl --user restart kde-ai-scheduler.service) || " + "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || " + "(pkill -f kde-ai-scheduler.py; sleep 0.5; " + "nohup python3 " + Sec.quoteForShell(safeSchedulerScriptPath) + " >/dev/null 2>&1 &) ; " + "echo SCHED_START_OK";
                    configPage.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #sched-start-" + Date.now());
                    schedPollTimer.restart();
                }
            }

            QQC2.Button {
                text: i18n("Stop")
                icon.name: "media-playback-stop"
                onClicked: {
                    schedulerMasterSwitch.checked = false;
                }
            }
        }

        RowLayout {
            visible: schedulerMasterSwitch.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            Kirigami.FormData.label: i18n("Schedules:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Create Schedule")
                icon.name: "list-add"
                highlighted: true
                Layout.fillWidth: true
                onClicked: {
                    let now = new Date();
                    now.setMinutes(now.getMinutes() + 5);
                    now.setSeconds(0);
                    now.setMilliseconds(0);
                    let chats = configPage.scheduleDialog.getChatsList();
                    let firstChatId = (chats.length > 0) ? chats[0].id : "";
                    let firstChatName = (chats.length > 0) ? chats[0].name : "";
                    configPage.scheduleDialog.draft = {
                        "id": configPage.schedMakeUuid(),
                        "name": "",
                        "enabled": true,
                        "chatId": firstChatId,
                        "chatName": firstChatName,
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
                    configPage.scheduleDialog.editingIndex = -2;
                    configPage.scheduleDialog.open();
                }
            }

            QQC2.Button {
                text: i18n("Manage Schedules")
                icon.name: "appointment-new"
                Layout.fillWidth: true
                onClicked: {
                    configPage.scheduleDialog.editingIndex = -1;
                    configPage.scheduleDialog.open();
                }
            }

            QQC2.Button {
                text: i18n("Open Schedules File")
                icon.name: "document-open"
                Layout.fillWidth: true
                onClicked: {
                    let safeSchedPath = Sec.validateFilePath(configPage.schedulesFilePath);
                    if (safeSchedPath === "")
                        return;
                    configPage.utilityDs.connectSource("xdg-open " + Sec.quoteForShell(safeSchedPath) + " || kde-open " + Sec.quoteForShell(safeSchedPath) + " || kwrite " + Sec.quoteForShell(safeSchedPath) + " || kate " + Sec.quoteForShell(safeSchedPath) + " || nano " + Sec.quoteForShell(safeSchedPath) + " #open-sched-file");
                }
            }
        }

        // ── Misc Settings ──────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Other Settings")
        }

        QQC2.TextField {
            id: appDisplayNameField

            Kirigami.FormData.label: "App name:"
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            placeholderText: "KDE AI Chat"
            text: (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.appDisplayName || "") : ""
            onTextChanged: {
                if (pageReady && plasmoid && plasmoid.configuration && text !== (plasmoid.configuration.appDisplayName || "KDE AI Chat")) {
                    plasmoid.configuration.appDisplayName = text;
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            text: "Tip: After changing the app name, restart plasmashell."
            opacity: 0.8
        }

        QQC2.Button {
            text: i18n("Reset All Settings to Defaults")
            icon.name: "edit-clear-all-symbolic"
            onClicked: {
                let cmd = "python3 " + Sec.quoteForShell(configPage.getHelperPath()) + " reset_settings";
                configPage.utilityDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #reset-settings-" + Date.now());
                configPage.schedulerStatus = "Settings reset triggered. Restart plasmashell.";
            }
        }

        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: i18n("Resource & Memory Usage")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing
            Kirigami.FormData.label: i18n("Memory Usage:")

            QQC2.Button {
                text: configPage.memRefreshing ? i18n("Refreshing…") : i18n("Refresh")
                icon.name: "view-refresh"
                enabled: !configPage.memRefreshing
                onClicked: {
                    configPage.memRefreshing = true;
                    let cmd = "python3 " + Sec.quoteForShell(configPage.getHelperPath()) + " get_memory_usage";
                    configPage.utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());
                }
            }
        }

        Rectangle {
            visible: configPage.showGuides
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: memGuideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1

            RowLayout {
                id: memGuideLayout
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
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    color: Kirigami.Theme.textColor
                    text: "<b>Resource &amp; Memory Usage</b> displays the current RAM consumption of background processes.<br><br>" +
                          "<b>Voice Tools:</b> Aggregates STT (Speech-to-Text) and TTS (Text-to-Speech) engines.<br>" +
                          "<b>OpenCode:</b> Local AI endpoint process.<br>" +
                          "<b>Scheduler:</b> Background daemon that runs automated prompts.<br>" +
                          "<i>Click Refresh to update these metrics manually.</i>"
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: memGrid.implicitHeight + Kirigami.Units.gridUnit
            radius: 6
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
            border.width: 1

            GridLayout {
                id: memGrid
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                columns: 3
                columnSpacing: Kirigami.Units.gridUnit
                rowSpacing: Kirigami.Units.smallSpacing

                // Scheduler
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon { source: "appointment-new"; implicitWidth: 16; implicitHeight: 16 }
                    QQC2.Label { text: i18n("Scheduler Daemon") }
                }
                QQC2.Label {
                    text: configPage.memScheduler > 0 ? (configPage.memScheduler / 1024).toFixed(1) + " MB" : i18n("Not running")
                    color: configPage.memScheduler > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                    font.bold: configPage.memScheduler > 0
                }
                QQC2.Button {
                    id: killSchedBtn
                    icon.name: "application-exit"
                    text: i18n("Kill")
                    visible: configPage.memScheduler > 0
                    onClicked: {
                        configPage.utilityDs.connectSource("pkill -f kde-ai-scheduler.py #kill-sched-" + Date.now());
                        configPage.memRefreshing = true;
                        let cmd = "sleep 0.5 && python3 " + Sec.quoteForShell(configPage.getHelperPath()) + " get_memory_usage";
                        configPage.utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());
                    }
                }
                Item { visible: !killSchedBtn.visible }

                // OpenCode
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon { source: "utilities-terminal"; implicitWidth: 16; implicitHeight: 16 }
                    QQC2.Label { text: i18n("OpenCode") }
                }
                QQC2.Label {
                    text: configPage.memOpenCode > 0 ? (configPage.memOpenCode / 1024).toFixed(1) + " MB" : i18n("Not running")
                    color: configPage.memOpenCode > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                    font.bold: configPage.memOpenCode > 0
                }
                QQC2.Button {
                    id: killOpenCodeBtn
                    icon.name: "application-exit"
                    text: i18n("Kill")
                    visible: configPage.memOpenCode > 0
                    onClicked: {
                        configPage.utilityDs.connectSource("pkill -f opencode #kill-opencode-" + Date.now());
                        configPage.memRefreshing = true;
                        let cmd = "sleep 0.5 && python3 " + Sec.quoteForShell(configPage.getHelperPath()) + " get_memory_usage";
                        configPage.utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());
                    }
                }
                Item { visible: !killOpenCodeBtn.visible }

                // STT
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon { source: "audio-input-microphone"; implicitWidth: 16; implicitHeight: 16 }
                    QQC2.Label { text: i18n("Voice STT") }
                }
                QQC2.Label {
                    text: configPage.memStt > 0 ? (configPage.memStt / 1024).toFixed(1) + " MB" + (configPage.memSttVram > 0 ? " (VRAM: " + (configPage.memSttVram / 1024).toFixed(1) + " MB)" : "") : i18n("On-demand")
                    color: configPage.memStt > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                    font.bold: configPage.memStt > 0
                }
                QQC2.Button {
                    id: killSttBtn
                    icon.name: "application-exit"
                    text: i18n("Kill")
                    visible: configPage.memStt > 0
                    onClicked: {
                        configPage.utilityDs.connectSource("pkill -f 'voice_helper.py --stt-server' #kill-stt-" + Date.now());
                        configPage.memRefreshing = true;
                        let cmd = "sleep 0.5 && python3 " + Sec.quoteForShell(configPage.getHelperPath()) + " get_memory_usage";
                        configPage.utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());
                    }
                }
                Item { visible: !killSttBtn.visible }

                // TTS
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon { source: "audio-speakers"; implicitWidth: 16; implicitHeight: 16 }
                    QQC2.Label { text: i18n("Voice TTS") }
                }
                QQC2.Label {
                    text: configPage.memTts > 0 ? (configPage.memTts / 1024).toFixed(1) + " MB" + (configPage.memTtsVram > 0 ? " (VRAM: " + (configPage.memTtsVram / 1024).toFixed(1) + " MB)" : "") : i18n("On-demand")
                    color: configPage.memTts > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                    font.bold: configPage.memTts > 0
                }
                QQC2.Button {
                    id: killTtsBtn
                    icon.name: "application-exit"
                    text: i18n("Kill")
                    visible: configPage.memTts > 0
                    onClicked: {
                        configPage.utilityDs.connectSource("pkill -f 'voice_helper.py --tts-server' #kill-tts-" + Date.now());
                        configPage.memRefreshing = true;
                        let cmd = "sleep 0.5 && python3 " + Sec.quoteForShell(configPage.getHelperPath()) + " get_memory_usage";
                        configPage.utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());
                    }
                }
                Item { visible: !killTtsBtn.visible }

                // Total
                QQC2.Label { text: i18n("Total"); font.bold: true }
                QQC2.Label {
                    text: (configPage.memScheduler + configPage.memOpenCode + configPage.memStt + configPage.memTts) > 0 ? ((configPage.memScheduler + configPage.memOpenCode + configPage.memStt + configPage.memTts) / 1024).toFixed(1) + " MB" : "—"
                    font.bold: true
                    color: Kirigami.Theme.highlightColor
                }
                Item { Layout.fillWidth: true } // Empty cell for the 3rd column
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Advanced")
        }

        QQC2.ComboBox {
            id: uiLanguageCombo
            Kirigami.FormData.label: i18n("Interface Language (Beta):")
            model: [
                { text: i18n("English"), value: "en" },
                { text: i18n("Mandarin Chinese"), value: "zh" },
                { text: i18n("Hindi"), value: "hi" },
                { text: i18n("Spanish"), value: "es" },
                { text: i18n("French"), value: "fr" },
                { text: i18n("Russian"), value: "ru" },
                { text: i18n("Portuguese"), value: "pt" },
                { text: i18n("German"), value: "de" }
            ]
            textRole: "text"
            valueRole: "value"
            
            currentIndex: {
                for (let i = 0; i < count; i++) {
                    if (model[i].value === configPage.cfg_uiLanguage) {
                        return i;
                    }
                }
                return 0;
            }
            onActivated: {
                configPage.cfg_uiLanguage = model[currentIndex].value;
            }
        }

        QQC2.Button {
            Kirigami.FormData.label: i18n("Reset settings:")
            text: i18n("Reset to defaults")
            onClicked: configPage.resetToDefaults()
        }
    }

    Component.onCompleted: {
        schedLoadSchedules();
        schedAutoSetup();
        pollSchedulerState();
        
        let cmd = "python3 " + Sec.quoteForShell(configPage.getHelperPath()) + " get_memory_usage";
        configPage.utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());

        configPage.pageReady = true;
    }
}
