// Removes the settings 1.4.0 no longer uses from this widget's group of
// Plasma's applet config, once per start, a while after the migrations have
// run (store/Storage.qml calls begin()). The helper's cleanup_old_settings
// (kdeaichat/config_cleanup.py) decides key by key from the same group: a
// migration-only key goes only once its migration is done; it backs the
// file up first and does nothing when there is nothing to remove.
import QtQuick

Timer {
    id: cleanup

    // store/HelperRunner.qml's run().
    property var runHelper: null
    // .../kdeaichat/chats/applet-<id>: the applet id is taken from it.
    property string chatDirectory: ""
    property bool done: false
    // What the helper answered, for the log and tests.
    property var result: null

    // Plasma writes changed settings to the file shortly after they change;
    // the wait lets the migrations' own writes land first.
    interval: 30000

    readonly property string appletId: {
        var match = /\/applet-([A-Za-z0-9._-]{1,64})\/?$/.exec(chatDirectory);
        return match ? match[1] : "";
    }

    function begin() {
        if (!done && appletId !== "" && runHelper)
            restart();
    }

    onTriggered: {
        if (done)
            return;
        done = true;
        runHelper("cleanup_old_settings", {"appletId": appletId}, function(stdout, exitCode) {
            try { cleanup.result = JSON.parse(String(stdout).trim().split("\n").pop()); } catch (e) { cleanup.result = {"status": "error"}; }
            if (cleanup.result.status === "removed")
                console.info("KDE AI Chat: removed old settings", cleanup.result.removed.join(", "), "(backup:", cleanup.result.backup + ")");
            else if (exitCode !== 0 || cleanup.result.status === "error" || cleanup.result.status === "busy")
                console.info("KDE AI Chat: old settings not cleaned up this time:", String(stdout).trim());
        });
    }
}
