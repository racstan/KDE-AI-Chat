// One-off helper and shell commands: saving a chat export (privately), removing a
// deleted chat's schedules, stopping the pre-1.4.0 plasmashell watchdog, and
// desktop notifications. `chat` is the widget root (main.qml).
import QtQuick
import QtCore
import org.kde.plasma.plasma5support as P5Support
import "../Security.js" as Sec
import "../store" as Store

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

P5Support.DataSource {
    id: commands
    engine: "executable"
    connectedSources: []

    property var chat: null

    // Where payloads go to the helper (privately, store/HelperRunner.qml); tests replace both.
    property var runHelper: function(command, payload, onDone) {
        runner.helperPath = chat.getHelperPath();
        runner.run(command, payload, onDone);
    }
    // function(path): the desktop notification after a successful export.
    property var exportNotifier: function(path) {
        commands.connectSource("notify-send -i document-export " + Sec.quotePath("KDE AI Chat") + " "
            + Sec.quotePath(i18n("Chat session successfully exported to %1", path)) + " #export-notify-" + Date.now());
    }
    readonly property int maxExportChars: 20000000

    property QtObject runnerObject: Store.HelperRunner { id: runner }

    // Removes the schedules that target a deleted chat.
    function deleteSessionSchedules(sessionId) {
        runHelper("delete_session_schedules", {"sessionId": sessionId}, null);
    }

    // Saves export text (built by chat/ExportDialog.qml) through the helper; the text goes to it in a
    // private file, never on the command line. Errors show in the chat, the notification only on success.
    function writeExportFile(filePath, content) {
        var safePath = Sec.validateFilePath(filePath);
        if (!safePath) {
            chat.pushErrorMessage(i18n("Export cancelled: invalid destination."));
            return;
        }
        if (String(content).length > maxExportChars) {
            chat.pushErrorMessage(i18n("This chat is too large to export (over 20 MB of text). Remove older messages or export a shorter conversation."));
            return;
        }
        runHelper("export_chat", {"filePath": safePath, "content": String(content)}, function(stdout, exitCode, stderr) {
            if (exitCode !== 0)
                chat.pushErrorMessage(i18n("Export failed: %1", (stderr.trim() || stdout.trim() || i18n("the helper exited with code %1", exitCode))));
            else
                exportNotifier(safePath);
        });
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

    // Earlier versions ran their own speech models in systemd user units
    // (kde-ai-tts.service, kde-ai-stt.service, kde-ai-stt.socket). All speech now goes
    // through Speech Note, so those units are stopped and removed once
    // (kdeaichat/voice_legacy.py) if a file of them is still there. Their venvs
    // and models stay: Settings → Storage offers to delete them.
    function stopLegacyTtsService() {
        var helper = chat.getHelperPath();
        if (!helper)
            return;
        var dir = '"${KDEAICHAT_UNIT_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"';
        var cmd = "d=" + dir + "; if [ -e \"$d/kde-ai-tts.service\" ] || [ -e \"$d/kde-ai-stt.service\" ] || [ -e \"$d/kde-ai-stt.socket\" ]; then python3 "
            + Sec.quoteForShell(helper) + " voice_startup; fi";
        commands.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #voice-legacy-" + Date.now());
    }

    // Once at startup: what older versions left running.
    function cleanupLegacy() {
        stopLegacyWatchdog();
        stopLegacyTtsService();
    }

    onNewData: function(sourceName, data) {
        disconnectSource(sourceName);
    }
}
