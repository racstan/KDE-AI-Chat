// The scheduler daemon and schedules.json, for Settings → Schedules.
//
// Also the `page` that ScheduleDialog.qml edits through: it reads
// schedulerList / schedulerArchivedList / schedulerHistory / chatIndexJson and
// calls schedLoadSchedules(), schedSaveAll(), schedMakeUuid() and translate().
import QtQuick
import QtCore
import org.kde.plasma.plasma5support as P5Support
import "../Security.js" as Sec
import "../store" as Store

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Item {
    id: service

    property string appletId: ""
    property var configuration: null     // plasmoid.configuration (read only)
    property bool executeMissed: false
    property bool polling: false         // checks the daemon every 30 s

    property bool running: false
    property string status: ""
    property bool saving: false
    property var schedulerList: []
    property var schedulerArchivedList: []
    property var schedulerHistory: []
    readonly property int historyLimit: 100

    // Emitted when setting up the service reports whether it starts at login.
    signal autoStartDetected(bool enabled)

    readonly property string dataDir: decodeURIComponent(String(StandardPaths.writableLocation(
        StandardPaths.GenericDataLocation)).replace(/^file:\/\//, "")) + "/kdeaichat"
    readonly property string schedulesFile: dataDir + "/schedules.json"
    readonly property string scriptPath: dataDir + "/kde-ai-scheduler.py"
    readonly property string helperPath: {
        var path = decodeURIComponent(String(Qt.resolvedUrl("../kde_ai_helper.py")).replace(/^file:\/\//, ""));
        return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
    }

    // The chat list for the schedule dialog, read from the chat store.
    readonly property Store.ChatStore chatIndexStore: Store.ChatStore {
        directory: service.appletId ? service.dataDir + "/chats/applet-" + service.appletId : ""
    }
    readonly property string chatIndexJson: chatIndexStore.indexJson()
        || (configuration ? (configuration.chatSessionsJson || "[]") : "[]")

    function translate(text) {
        return i18n(text);
    }

    // Runs `script` with sh and calls handle(tag, stdout, stderr). Tests set
    // runShell to keep commands off the real system.
    property var runShell: null

    function shell(script, tag) {
        if (runShell)
            runShell(script, tag);
        else
            ds.connectSource("sh -c " + Sec.rawShellSnippetQuote(script) + " #" + tag + "-" + Date.now());
    }

    // Copies the daemon script and writes its systemd user unit.
    function setup() {
        if (!helperPath) {
            status = i18n("The scheduler helper is missing.");
            return;
        }
        var source = decodeURIComponent(String(Qt.resolvedUrl("../../scripts/kde-ai-scheduler.py")).replace(/^file:\/\//, ""));
        var unit = "[Unit]\nDescription=KDE AI Chat Scheduler Daemon\nAfter=network-online.target\nWants=network-online.target\n\n"
            + "[Service]\nType=simple\nExecStart=/usr/bin/python3 %h/.local/share/kdeaichat/kde-ai-scheduler.py\nRestart=on-failure\n"
            + "RestartSec=30\nStandardOutput=journal\nStandardError=journal\nExecReload=/bin/kill -HUP $MAINPID\nKillMode=process\n\n"
            + "[Install]\nWantedBy=default.target\n";
        var payload = Sec.base64Encode(JSON.stringify({"srcPath": source, "destPath": scriptPath, "serviceContent": unit}));
        shell("python3 " + Sec.quoteForShell(helperPath) + " setup_scheduler_service " + Sec.rawShellSnippetQuote(payload), "sched-setup");
    }

    function poll() {
        shell("pgrep -f kde-ai-scheduler.py > /dev/null 2>&1 && echo SCHED_RUNNING || echo SCHED_STOPPED", "sched-poll");
    }

    function start() {
        status = i18n("Starting…");
        var script = Sec.quoteForShell(Sec.validateFilePath(scriptPath));
        shell("systemctl --user enable --now kde-ai-scheduler.service 2>&1 || (pkill -f kde-ai-scheduler.py 2>/dev/null; sleep 0.5; "
              + "python3 " + script + " &) ; echo SCHED_START_OK", "sched-start");
    }

    function restart() {
        status = i18n("Restarting…");
        running = false;
        var script = Sec.quoteForShell(Sec.validateFilePath(scriptPath));
        shell("(systemctl --user is-active --quiet kde-ai-scheduler.service && systemctl --user restart kde-ai-scheduler.service) || "
              + "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || (pkill -f kde-ai-scheduler.py; sleep 0.5; "
              + "nohup python3 " + script + " >/dev/null 2>&1 &) ; echo SCHED_START_OK", "sched-start");
    }

    function stop() {
        status = i18n("Stopping…");
        shell("systemctl --user stop kde-ai-scheduler.service 2>/dev/null; pkill -f kde-ai-scheduler.py 2>/dev/null; echo SCHED_STOP_OK", "sched-stop");
    }

    function setAutoStart(enabled) {
        shell("systemctl --user " + (enabled ? "enable" : "disable") + " kde-ai-scheduler.service 2>&1; echo SCHED_ENABLE_OK", "sched-enable");
    }

    function openFile() {
        var path = Sec.validateFilePath(schedulesFile);
        if (path)
            Qt.openUrlExternally("file://" + path);
    }

    function schedLoadSchedules() {
        if (saving)
            return;
        var path = Sec.validateFilePath(schedulesFile);
        if (path)
            shell("cat " + Sec.quoteForShell(path) + " 2>/dev/null || echo '{\"schedules\":[],\"history\":[]}'", "sched-load");
    }

    function schedSaveAll() {
        if (!helperPath) {
            status = i18n("The scheduler helper is missing.");
            return;
        }
        var all = schedulerList.map(function(s) { return Object.assign({}, s, {"archived": false}); })
            .concat(schedulerArchivedList.map(function(s) { return Object.assign({}, s, {"archived": true}); }));
        var history = (schedulerHistory || []).slice(-historyLimit);
        schedulerHistory = history;
        var payload = Sec.base64Encode(JSON.stringify({"version": 1, "schedules": all, "history": history,
            "settings": {"executeMissedSchedules": executeMissed, "historyLimit": historyLimit}}));
        if (payload.length > 900000) {
            status = i18n("Schedules are too large to save at once. Remove old history or shorten schedule messages.");
            return;
        }
        saving = true;
        shell("python3 " + Sec.quoteForShell(helperPath) + " save_all_schedules " + Sec.rawShellSnippetQuote(payload), "sched-save");
    }

    function schedMakeUuid() {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0;
            return (c === "x" ? r : (r & 3 | 8)).toString(16);
        });
    }

    function applyLoaded(text) {
        var parsed;
        try { parsed = JSON.parse(text); } catch (e) { return; }
        var all = parsed.schedules || [];
        schedulerList = all.filter(function(s) { return s && !s.archived; });
        schedulerArchivedList = all.filter(function(s) { return s && s.archived; });
        schedulerHistory = (parsed.history || []).slice(-historyLimit);
    }

    function handle(tag, out, err) {
        if (tag === "sched-poll") {
            running = out === "SCHED_RUNNING";
            if (running || status === i18n("Starting…") || status === i18n("Restarting…") || status === i18n("Stopping…"))
                status = "";
        } else if (tag === "sched-start" || tag === "sched-stop") {
            Qt.callLater(poll);
        } else if (tag === "sched-enable") {
            status = out.indexOf("SCHED_ENABLE_OK") >= 0 ? "" : (err || out);
        } else if (tag === "sched-setup") {
            if (out.indexOf("AUTO_ENABLED") >= 0) autoStartDetected(true);
            else if (out.indexOf("AUTO_DISABLED") >= 0) autoStartDetected(false);
        } else if (tag === "sched-load") {
            applyLoaded(out);
        } else if (tag === "sched-save") {
            saving = false;
            const ok = out.indexOf("SCHED_SAVE_OK") >= 0;
            status = ok ? i18n("Schedules saved.") : i18n("Could not save schedules: %1", err || out || i18n("no reply from the helper"));
            if (ok)
                schedLoadSchedules();
        }
    }

    P5Support.DataSource {
        id: ds
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName);
            var tag = sourceName.substring(sourceName.lastIndexOf("#") + 1).replace(/-\d+$/, "");
            service.handle(tag, String(data["stdout"] || "").trim(), String(data["stderr"] || "").trim());
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: service.polling
        onTriggered: service.poll()
    }
}
