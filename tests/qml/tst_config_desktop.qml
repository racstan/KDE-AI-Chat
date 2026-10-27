// Settings → Desktop integration (ConfigDesktop.qml): both switches off by default, each with its
// explanation; OK/Apply asks the helper to install or remove (desktop_sync) with the switches as they
// are; a bad prefix is replaced by "ai"; an error from the helper is shown. The helper is a stand-in.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami

Item {
    id: root
    width: 760
    height: 620

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    QtObject {
        id: helper
        property var calls: []
        property var errors: []
        function run(command, payload, onDone) {
            calls = calls.concat([{command: command, payload: payload}]);
            var on = command === "desktop_sync" ? payload : {krunner: false, dolphin: false};
            Qt.callLater(function() {
                onDone(JSON.stringify({"type": "desktop_status", "krunner": on.krunner, "dolphin": on.dolphin, "prefix": "ai",
                                       "errors": helper.errors}), 0, "");
            });
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    HarnessTestCase {
        id: tc
        name: "ConfigDesktop"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        function open() {
            var component = Qt.createComponent(uiDir + "ConfigDesktop.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, {"width": root.width, "height": root.height, "helperRunner": helper});
            verify(page !== null);
            tryVerify(() => page.status !== null, 3000);
            return page;
        }
        function init() { helper.calls = []; helper.errors = []; }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            wait(100);
        }

        function test_1_both_off_by_default_and_nothing_installed_by_opening() {
            open();
            compare(findChild(page, "krunnerSwitch").checked, false);
            compare(findChild(page, "dolphinSwitch").checked, false);
            compare(findChild(page, "krunnerPrefix").enabled, false, "no prefix to set while KRunner is off");
            compare(helper.calls.map(c => c.command), ["desktop_status"]);
            wait(200);
            screenshot(page, "config-desktop-off");
        }

        function test_2_apply_installs_what_is_switched_on() {
            open();
            findChild(page, "krunnerSwitch").checked = true;
            findChild(page, "dolphinSwitch").checked = true;
            findChild(page, "krunnerPrefix").text = "ask";
            page.saveConfig();
            tryVerify(() => helper.calls.length === 2, 3000);
            compare(helper.calls[1].command, "desktop_sync");
            compare(helper.calls[1].payload.krunner, true);
            compare(helper.calls[1].payload.dolphin, true);
            compare(helper.calls[1].payload.prefix, "ask");
            compare(helper.calls[1].payload.restart_krunner, true, "KRunner changed: it is told to look again");
            tryVerify(() => findChild(page, "desktopStatus").text.indexOf("KRunner yes, Dolphin yes") >= 0, 3000);
            wait(200);
            screenshot(page, "config-desktop-on");
        }

        function test_3_a_prefix_with_spaces_falls_back_to_ai() {
            open();
            findChild(page, "krunnerSwitch").checked = true;
            findChild(page, "krunnerPrefix").text = "two words";
            compare(page.cleanPrefix, "ai");
            page.saveConfig();
            tryVerify(() => helper.calls.length === 2, 3000);
            compare(helper.calls[1].payload.prefix, "ai");
        }

        function test_4_a_failure_is_shown_in_plain_words() {
            open();
            helper.errors = ["Dolphin: already exists and is not from KDE AI Chat"];
            findChild(page, "dolphinSwitch").checked = true;
            page.saveConfig();
            tryVerify(() => findChild(page, "desktopError").visible, 3000);
            verify(findChild(page, "desktopError").text.indexOf("Dolphin") >= 0);
        }
    }
}
