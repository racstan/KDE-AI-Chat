// store/SettingsCleanup.qml: asks the helper once per start, after the
// migrations, to remove the dropped settings of this widget (its applet id
// from the chat folder). The helper is a fake; kdeaichat/config_cleanup.py
// itself is tested in tests/test_config_cleanup.py.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

TestCase {
    id: testCase
    name: "SettingsCleanup"

    property var calls: []

    function fakeRun(command, payload, done) {
        calls = calls.concat([{"command": command, "payload": payload}]);
        done(JSON.stringify({"status": "removed", "removed": ["useKWallet"], "backup": "/tmp/b"}), 0, "");
    }

    Component {
        id: cleanupComponent
        Store.SettingsCleanup {
            interval: 10
            runHelper: testCase.fakeRun
        }
    }

    function init() {
        calls = [];
    }

    function test_runs_once_for_this_applet() {
        var c = createTemporaryObject(cleanupComponent, testCase, {"chatDirectory": "/home/u/.local/share/kdeaichat/chats/applet-42"});
        compare(c.appletId, "42");
        c.begin();
        tryCompare(c, "done", true, 2000);
        compare(calls.length, 1);
        compare(calls[0].command, "cleanup_old_settings");
        compare(JSON.stringify(calls[0].payload), JSON.stringify({"appletId": "42"}));
        compare(c.result.status, "removed");
        c.begin();
        wait(50);
        compare(calls.length, 1, "only once per start");
    }

    function test_nothing_without_an_applet_id() {
        var c = createTemporaryObject(cleanupComponent, testCase, {"chatDirectory": "/home/u/.local/share/kdeaichat/chats"});
        compare(c.appletId, "");
        c.begin();
        wait(50);
        compare(calls.length, 0);
        verify(!c.running);
    }

    function test_waits_before_running() {
        verify(Qt.createComponent(Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/store/SettingsCleanup.qml"))
               .createObject(testCase).interval >= 10000, "Plasma's own writes land first");
    }
}
