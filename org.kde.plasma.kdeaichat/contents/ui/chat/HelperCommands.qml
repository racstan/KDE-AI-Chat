// One-off helper and shell commands: saving a chat export, removing a
// deleted chat's schedules, stopping the pre-1.4.0 plasmashell watchdog, and
// desktop notifications. `chat` is the widget root (main.qml).
import QtQuick
import QtCore
import org.kde.plasma.plasma5support as P5Support
import "../Security.js" as Sec

P5Support.DataSource {
    id: commands
    engine: "executable"
    connectedSources: []

    property var chat: null

    // Removes the schedules that target a deleted chat.
    function deleteSessionSchedules(sessionId) {
        var helper = chat.getHelperPath();
        if (helper) {
            let deletePayload = Sec.base64Encode(JSON.stringify({"sessionId": sessionId}));
            commands.connectSource("python3 " + Sec.quoteForShell(helper) + " delete_session_schedules " + Sec.rawShellSnippetQuote(deletePayload) + " #delete-session-schedules-" + Date.now());
        }
    }

    // Saves export text (built by chat/ExportDialog.qml) through the helper.
    function writeExportFile(filePath, content) {
        var safePath = Sec.validateFilePath(filePath);
        var helper = chat.getHelperPath();
        if (!safePath || !helper) {
            chat.pushErrorMessage("Export cancelled: invalid destination or helper unavailable.");
            return;
        }
        if (content.length > 500000) {
            chat.pushErrorMessage("This chat is too large to export in one operation. Remove older messages or export a shorter conversation.");
            return;
        }
        var payload = {
            "filePath": safePath,
            "b64Content": Sec.base64Encode(content)
        };
        var encoded = Sec.base64Encode(JSON.stringify(payload));
        if (encoded.length > 900000) {
            chat.pushErrorMessage("This chat is too large to export in one operation. Remove older messages or export a shorter conversation.");
            return;
        }
        var cmd = "python3 " + Sec.quoteForShell(helper) + " export_chat " + Sec.rawShellSnippetQuote(encoded)
            + " && (notify-send -i document-export " + Sec.quoteForShell("KDE AI Chat") + " "
            + Sec.quoteForShell("Chat session successfully exported to " + safePath) + " || true)";
        commands.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #export-chat-save");
    }

    // The plasmashell watchdog was removed in 1.4.0. A monitor started by an
    // older version keeps running across upgrades and would restart
    // plasmashell once heartbeats stop, so stop it once at startup if its
    // files are still there.
    function stopLegacyWatchdog() {
        var helper = chat.getHelperPath();
        if (!helper)
            return;
        var dataDir = String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)).replace(/^file:\/\//, "");
        var pidFile = decodeURIComponent(dataDir) + "/kdeaichat/plasmashell-watchdog.pid";
        var heartbeat = decodeURIComponent(dataDir) + "/kdeaichat/plasmashell-heartbeat";
        var cmd = "if [ -e " + Sec.quoteForShell(pidFile) + " ] || [ -e " + Sec.quoteForShell(heartbeat) + " ]; then python3 "
            + Sec.quoteForShell(helper) + " stop_legacy_watchdog; fi";
        commands.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #plasmashell-watchdog-" + Date.now());
    }

    onNewData: function(sourceName, data) {
        var exitCode = Number(data["exit code"]);
        if (isNaN(exitCode)) exitCode = 1;
        var stdout = data["stdout"] || "";
        var stderr = data["stderr"] || "";
        if (sourceName.indexOf("#export-chat-save") !== -1 && exitCode !== 0)
            chat.pushErrorMessage("Export failed: " + (stderr.trim() || stdout.trim() || ("helper exited with code " + exitCode)));
        disconnectSource(sourceName);
    }
}
