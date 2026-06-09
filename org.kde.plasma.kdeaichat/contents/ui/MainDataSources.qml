import QtQuick
import org.kde.plasma.plasma5support as P5Support
import QtQuick.Dialogs
import "MainDatabase.js" as MainDatabase
import "MainNetwork.js" as MainNetwork
import "MainScheduler.js" as MainScheduler
import "MainOpenCode.js" as MainOpenCode
import "Security.js" as Sec

/*
 * MainDataSources.qml — KDE AI Chat DataSources & Timers Container
 *
 * LINKAGE & INTEGRATION:
 * 1. Instantiated in `main.qml` as a child component (id: dataSources).
 * 2. Objects declared here (such as soundDs, schedulerDs, customStorageDs) are exposed
 *    to the global QML/JS namespace via property aliases on the root element of `main.qml`.
 * 3. JavaScript logic files (MainDatabase.js, MainNetwork.js, MainScheduler.js, MainOpenCode.js)
 *    reference these DataSources and Timers by ID directly to execute commands, fetch
 *    data, and coordinate background work.
 * 4. Accepts a `root` property referencing the main app container for dynamic data updates.
 */
Item {
    id: dataSourcesContainer

    required property var root

    // Expose internal components to the parent via properties/aliases
    property alias soundDs: soundDs
    property alias clipboardDs: clipboardDs
    property alias schedulerDs: schedulerDs
    property alias openCodeReconnectTimer: openCodeReconnectTimer
    property alias persistSessionsDebounce: persistSessionsDebounce
    property alias streamingBatchTimer: streamingBatchTimer
    property alias openCodeIdleKillTimer: openCodeIdleKillTimer
    property alias openCodeStartPollTimer: openCodeStartPollTimer
    property alias schedulerPollTimer: schedulerPollTimer
    property alias autoStartOpenCodeTimer: autoStartOpenCodeTimer
    property alias opencodeServerDs: opencodeServerDs
    property alias fileReaderDs: fileReaderDs
    property alias customStorageDs: customStorageDs
    property alias fileDialog: fileDialog
    property alias exportFileDialog: exportFileDialog
    property alias clipboardHelper: clipboardHelper
    property alias kwalletStartupDs: kwalletStartupDs
    property alias opencodeTerminalDs: opencodeTerminalDs
    property alias openCodePollTimer: openCodePollTimer

    P5Support.DataSource {
        id: soundDs

        engine: "executable"
        connectedSources: []
    }

    P5Support.DataSource {
        id: clipboardDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName);
        }
    }

    function copyToClipboard(textValue) {
        return MainDatabase.copyToClipboard(textValue);
    }

    P5Support.DataSource {
        id: schedulerDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = (data["stdout"] || "").trim();
            disconnectSource(sourceName);
            if (sourceName.indexOf("#sched-poll") >= 0)
                root.schedPolling = false;

            if (sourceName.indexOf("#sched-delete") >= 0 || sourceName.indexOf("#sched-save") >= 0 || sourceName.indexOf("#sched-toggle") >= 0)
                schedulerPollTimer.triggered();

            if (stdout !== "") {
                try {
                    let parsed = JSON.parse(stdout);
                    // 1. Sync schedulesList
                    if (parsed && Array.isArray(parsed.schedules))
                        root.schedulesList = parsed.schedules;

                    // 2. Handle pending triggers
                    let triggers = (parsed && parsed.pending) || [];
                    if (Array.isArray(triggers) && triggers.length > 0) {
                        for (let i = 0; i < triggers.length; i++) {
                            let t = triggers[i];
                            if (t && t.message) {
                                let cid = t.chatId || "";
                                if (cid === "" || cid === "new") {
                                    // Create a new session first
                                    root.createSession(true);
                                    cid = root.currentSessionId;
                                }
                                root.injectScheduledMessage(cid, t.message, t.notify, t.id, t.name);
                            }
                        }
                    }
                } catch (e) {
                    debugLog("[KAI-DEBUG] Failed to parse poll data:", e);
                }
            }
        }
    }

    Timer {
        id: openCodeReconnectTimer

        interval: 5000
        repeat: false
        onTriggered: {
            if (root.openCodeMode)
                root.ensureOpenCodeEventStream();

        }
    }

    // Debounce timer for `persistSessions()`. Every state mutation
    // (message add, edit, archive, label change) calls
    // `persistSessions()`, which used to run the full JSON.stringify
    // + config write + Python helper pipeline on every keystroke.
    // The wrapper now schedules a single 1-Hz flush per burst of
    // changes. `flushPersistSessions()` forces an immediate flush
    // for code paths that need synchronous persistence (close,
    // settings save, manual refresh).
    Timer {
        id: persistSessionsDebounce
        interval: 1000
        repeat: false
        onTriggered: root.flushPersistSessions()
    }

    // Audit 5.1: batch streaming token updates to avoid full model
    // resets on every chunk. Tokens are buffered in `_pendingStreamingText`
    // and flushed at ~30 Hz instead of per-token. `flushStreamingBuffer()`
    // forces an immediate flush (used on stream end, cancel, and
    // session switch).
    Timer {
        id: streamingBatchTimer
        interval: 150
        repeat: false
        onTriggered: root.flushStreamingBuffer()
    }

    Timer {
        id: openCodeIdleKillTimer

        interval: 300000 // 5 minutes
        repeat: false
        onTriggered: {
            if (root.openCodeMode && plasmoid.configuration.autoStartOpenCodeServer && root.configOpenCodeAutoKill) {
                let stopCmd = (plasmoid.configuration.openCodeStopCommand || "pkill -f opencode >/dev/null 2>&1 && echo ok").trim();
                let envPrefix = "export PATH=\"$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/local/bin:$HOME/.opencode/bin\"; ";
                opencodeServerDs.connectSource("sh -c '" + envPrefix + stopCmd.replace(/'/g, "'\\''") + "' #autokill-opencode");
                debugLog("[KAI-DEBUG] OpenCode server auto-killed due to idleness/chat switch.");
            }
        }
    }

    Timer {
        id: openCodeStartPollTimer

        property var successCb
        property var failureCb
        property int retriesLeft: 0

        interval: 1000
        repeat: false
        onTriggered: {
            retriesLeft--;
            let checkUrl = root.openCodeBaseUrl() + "/config/providers";
            let xhr = new XMLHttpRequest();
            xhr.open("GET", checkUrl, true);
            xhr.timeout = 1000;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                if (xhr.status >= 200 && xhr.status < 300) {
                    if (successCb)
                        successCb();
                } else {
                    if (retriesLeft > 0) {
                        openCodeStartPollTimer.start();
                    } else {
                        if (failureCb)
                            failureCb("OpenCode server failed to start (HTTP " + xhr.status + ")");
                    }
                }
            };
            xhr.onerror = function() {
                if (retriesLeft > 0) {
                    openCodeStartPollTimer.start();
                } else {
                    if (failureCb)
                        failureCb("OpenCode server failed to start (Connection refused)");
                }
            };
            xhr.ontimeout = function() {
                if (retriesLeft > 0) {
                    openCodeStartPollTimer.start();
                } else {
                    if (failureCb)
                        failureCb("OpenCode server failed to start (Timeout)");
                }
            };
            try {
                xhr.send();
            } catch (e) {
                if (retriesLeft > 0) {
                    openCodeStartPollTimer.start();
                } else {
                    if (failureCb)
                        failureCb(e.toString());
                }
            }
        }
    }

    Timer {
        id: schedulerPollTimer

        interval: 3000
        repeat: true
        running: root.expanded
        triggeredOnStart: true
        onTriggered: {
            if (root.schedPolling)
                return ;

            root.schedPolling = true;
            let cmd = "python3 " + Sec.quoteForShell(root.getHelperPath()) + " poll_pending_triggers";
            schedulerDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #sched-poll-" + Date.now());
        }
    }

    // Fires after a short delay on startup when autoStartOpenCodeServer is enabled,
    // so session loading completes before we spawn the server process.
    Timer {
        id: autoStartOpenCodeTimer

        interval: 1500
        repeat: false
        onTriggered: {
            let cmd = (plasmoid.configuration.openCodeStartCommand || "logf=\"${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log\"; nohup opencode serve --port 4096 --hostname 127.0.0.1 >\"$logf\" 2>&1 & echo ok").trim();
            let envPrefix = "export PATH=\"$PATH:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/local/bin:$HOME/.opencode/bin\"; ";
            opencodeServerDs.connectSource("sh -c '" + envPrefix + cmd.replace(/'/g, "'\\''") + "' #autostart-opencode");
        }
    }

    P5Support.DataSource {
        id: opencodeServerDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: fileReaderDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let exitCode = data["exit code"];
            let stdout = data["stdout"] || "";
            let stderr = data["stderr"] || "";
            if (sourceName.indexOf("--clipboard") !== -1) {
                if (exitCode === 0 && stderr.trim() === "") {
                    try {
                        let res = JSON.parse(stdout);
                        if (res.status === "success") {
                            let currentFiles = root.attachedFiles.slice();
                            if (res.mode === "files" && res.files) {
                                for (let f = 0; f < res.files.length; f++) {
                                    let fInfo = res.files[f];
                                    let exists = false;
                                    for (let idx = 0; idx < currentFiles.length; idx++) {
                                        if (currentFiles[idx].path === fInfo.path) {
                                            exists = true;
                                            break;
                                        }
                                    }
                                    if (!exists)
                                        currentFiles.push({
                                        "name": fInfo.filename || fInfo.name,
                                        "path": fInfo.path,
                                        "type": fInfo.type,
                                        "content": fInfo.content,
                                        "mimeType": fInfo.mimeType,
                                        "size": fInfo.size,
                                        "loading": false,
                                        "error": ""
                                    });

                                }
                            } else if (res.mode === "image" && res.file) {
                                let fInfo = res.file;
                                  let exists = false;
                                for (let idx = 0; idx < currentFiles.length; idx++) {
                                    if (currentFiles[idx].path === fInfo.path) {
                                        exists = true;
                                        break;
                                    }
                                }
                                if (!exists)
                                    currentFiles.push({
                                    "name": fInfo.name,
                                    "path": fInfo.path,
                                    "type": fInfo.type,
                                    "content": fInfo.content,
                                    "mimeType": fInfo.mimeType,
                                    "size": fInfo.size,
                                    "loading": false,
                                    "error": ""
                                });

                            }
                            root.attachedFiles = currentFiles;
                        }
                    } catch (e) {
                        root.reportParseFailure("Failed to parse clipboard data", e);
                    }
                }
                disconnectSource(sourceName);
                return ;
            }
            let matchedIndex = -1;
            let files = root.attachedFiles.slice();
            for (let i = 0; i < files.length; i++) {
                let filePath = files[i].path;
                if (sourceName.indexOf(filePath) !== -1) {
                    matchedIndex = i;
                    break;
                }
            }
            if (matchedIndex === -1) {
                disconnectSource(sourceName);
                return ;
            }
            let fileObj = Object.assign({
            }, files[matchedIndex]);
            fileObj.loading = false;
            if (exitCode !== 0 || stderr.trim() !== "") {
                fileObj.error = stderr.trim() || ("Command exited with code " + exitCode);
            } else {
                try {
                    let res = JSON.parse(stdout);
                    if (res.status === "success") {
                        fileObj.type = res.type;
                        fileObj.content = res.content;
                        fileObj.mimeType = res.mimeType;
                        fileObj.size = res.size;
                    } else {
                        fileObj.error = res.message || "Failed to extract file contents";
                    }
                } catch (e) {
                    fileObj.error = "Failed to parse extractor output: " + e;
                }
            }
            files[matchedIndex] = fileObj;
            root.attachedFiles = files;
            disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: customStorageDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let exitCode = data["exit code"];
            let stdout = data["stdout"] || "";
            if (sourceName.indexOf("#custom-history-read-") !== -1) {
                if (exitCode === 0 && stdout.trim() !== "") {
                    try {
                        let jsonStr = root.base64Decode(stdout.trim());
                        let arr = JSON.parse(jsonStr);
                        if (Array.isArray(arr)) {
                            root.sessions = root.parseSessions(arr);
                            if (root.sessions.length === 0)
                                root.createSession(true);

                            let preferred = plasmoid.configuration.lastSessionId || "";
                            let idx = root.sessionIndexById(preferred);
                            if (idx < 0)
                                idx = 0;

                            root.currentSessionId = root.sessions[idx].value;
                            root.currentSessionTitle = root.sessions[idx].text;
                            root.messages = root.sessions[idx].messages || [];
                            if (root.sessions[idx])
                                root.openCodeMode = (root.sessions[idx].source === "opencode");

                            root.sortSessionsByUpdated();
                            root.checkAndMarkCurrentSessionAsRead();
                            disconnectSource(sourceName);
                            return ;
                        }
                    } catch (e) {
                        root.reportParseFailure("Failed to parse custom history", e);
                    }
                }
                // Fallback & Seamless Migration:
                let oldJson = plasmoid.configuration.chatSessionsJson || "";
                if (oldJson !== "" && oldJson !== "[]") {
                    root.loadSessions();
                    root.persistSessions();
                } else {
                    root.loadSessions();
                }
                root.checkAndMarkCurrentSessionAsRead();
            } else if (sourceName.indexOf("#migrate-history") !== -1) {
                if (exitCode === 0 && stdout.trim() !== "") {
                    try {
                        let jsonRaw = root.base64Decode(stdout.trim());
                        let res = JSON.parse(jsonRaw);
                        if (res.status === "ok") {
                            if (res.action === "load" && res.content) {
                                let arrVal = JSON.parse(root.base64Decode(res.content));
                                if (Array.isArray(arrVal)) {
                                    root.sessions = root.parseSessions(arrVal);
                                    if (root.sessions.length === 0)
                                        root.createSession(true);

                                    let pref = plasmoid.configuration.lastSessionId || "";
                                    let idxVal = root.sessionIndexById(pref);
                                    if (idxVal < 0)
                                        idxVal = 0;

                                    root.currentSessionId = root.sessions[idxVal].value;
                                    root.currentSessionTitle = root.sessions[idxVal].text;
                                    root.messages = root.sessions[idxVal].messages || [];
                                    if (root.sessions[idxVal])
                                        root.openCodeMode = (root.sessions[idxVal].source === "opencode");

                                    root.sortSessionsByUpdated();
                                    root.checkAndMarkCurrentSessionAsRead();
                                    root.persistSessions();
                                }
                            } else if (res.action === "write_current" || res.action === "copied" || res.action === "exported") {
                                root.persistSessions();
                            }
                        } else {
                            console.warn("Migration failed: " + res.message);
                        }
                    } catch (e) {
                        console.error("Failed to parse migration output: " + e);
                    }
                }
            }
            disconnectSource(sourceName);
        }
    }

    FileDialog {
        id: fileDialog

        title: "Attach Files"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["All supported files (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.pdf *.csv *.docx *.txt *.md *.json)", "Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)", "Documents (*.pdf *.docx *.csv *.txt *.md *.json)", "All files (*)"]
        onAccepted: {
            for (let i = 0; i < selectedFiles.length; i++) {
                root.attachFile(selectedFiles[i]);
            }
        }
    }

    FileDialog {
        id: exportFileDialog

        title: "Export Chat Session"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Markdown files (*.md)", "Plain text files (*.txt)"]
        onAccepted: {
            let path = selectedFile.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            root.performExportChat(path);
        }
    }

    // Invisible text editor acting as helper to interact with OS text clipboard (copy / paste)
    TextEdit {
        id: clipboardHelper

        visible: false
    }

    P5Support.DataSource {
        id: kwalletStartupDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = data["stdout"] || "";
            if (sourceName.indexOf("kwallet-startup-load") >= 0) {
                let lines = stdout.split(/\r?\n/);
                let openFailed = false;
                let openFailedMsg = "KWallet open failed.";
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line.indexOf("__KAI_BULK__:OPEN_FAILED") === 0) {
                        openFailed = true;
                        openFailedMsg = "KWallet open failed.";
                    } else if (line.indexOf("__KAI_BULK__:NO_WALLET") === 0) {
                        openFailed = true;
                        openFailedMsg = "Configured KWallet not found.";
                    } else if (line.indexOf("__KAI_SECRET__:") === 0) {
                        let rest = line.slice("__KAI_SECRET__:".length);
                        let sep = rest.indexOf(":");
                        if (sep > 0) {
                            let targetId = rest.slice(0, sep);
                            let secretValue = rest.slice(sep + 1);
                            root.applyKWalletKeyToMemory(targetId, secretValue);
                        }
                    }
                }
                if (openFailed) {
                    root.kwalletKeysLoaded = false;
                    root.kwalletOpenAttempts++;
                    debugLog("[KAI-DEBUG] KWallet open failed (attempt " + root.kwalletOpenAttempts + " of 3)");
                    root.triggerKWalletCallbacks(false, openFailedMsg);
                } else {
                    root.kwalletOpenAttempts = 0;
                    root.kwalletKeysLoaded = true;
                    root.triggerKWalletCallbacks(true);
                }
            }
            disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: opencodeTerminalDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = data["stdout"] || "";
            let stderr = data["stderr"] || "";
            let exitCode = data["exit code"];
            if (sourceName.indexOf("opencode-cli-") >= 0) {
                let output = stdout || stderr;
                // Detect opencode not installed
                if (exitCode !== undefined && (output.indexOf("not found") >= 0 || output.indexOf("No such file") >= 0 || output === "")) {
                    root.loading = false;
                    root.finishOpenCodeRequest();
                    root.pushErrorMessage("**OpenCode is not installed or not in PATH.**\nInstall it with:\n```\nnpm install -g opencode-ai\n```\nor visit https://opencode.ai for instructions.");
                    disconnectSource(sourceName);
                    return ;
                }
                if (output !== "")
                    root.updateAssistantStreamingContent(output, "OpenCode CLI");

                if (exitCode !== undefined) {
                    root.loading = false;
                    root.finishOpenCodeRequest();
                    disconnectSource(sourceName);
                }
            } else {
                disconnectSource(sourceName);
            }
        }
    }

    Timer {
        id: openCodePollTimer

        property int retriesLeft: 0

        function startPolling() {
            retriesLeft = 15;
            start();
        }

        function checkServerStatus() {
            let xhr = new XMLHttpRequest();
            xhr.open("GET", root.openCodeBaseUrl() + "/", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return ;

                if (xhr.status >= 200 && xhr.status < 300) {
                    openCodePollTimer.stop();
                    root.pushInfoMessage("OpenCode server is online. Resuming thread...");
                    root.removeLastErrorMessages();
                    root.retryLastFailedMessage();
                }
            };
            xhr.onerror = function() {
            };
            try {
                xhr.send();
            } catch (e) {
            }
        }

        interval: 1000
        repeat: true
        onTriggered: {
            retriesLeft--;
            if (retriesLeft <= 0) {
                stop();
                root.pushErrorMessage("OpenCode server failed to start in time. Check logs in ${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log");
                return ;
            }
            checkServerStatus();
        }
    }
}
