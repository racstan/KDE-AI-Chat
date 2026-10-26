// Settings → Appearance: the panel icon's animation (mode, file check with
// the size limits, hover only, video only when QtMultimedia is there) and
// the "Buy Me a Coffee" link. The helper is a fake: no file is read.
import QtQuick
import QtTest

Item {
    id: root
    width: 820
    height: 1400

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    // Two names of the GIF fixture, shown in the preview; the other files are
    // only known to the fake helper.
    readonly property string fixtures: decodeURIComponent(String(Qt.resolvedUrl("../fixtures/")).replace(/^file:\/\//, ""))
    readonly property string robot: fixtures + "panel-icon.gif"
    readonly property string big: fixtures + "../fixtures/panel-icon.gif"

    // panel_icon_check replies, by path.
    property var files: {
        var out = {};
        out[robot] = {"ok": true, "exists": true, "size": 300 * 1024, "kind": "animated"};
        out[big] = {"ok": true, "exists": true, "size": 8 * 1024 * 1024, "kind": "animated"};
        return Object.assign(out, {
        "/home/me/huge.gif": {"ok": true, "exists": true, "size": 25 * 1024 * 1024, "kind": "animated"},
        "/home/me/clip.webm": {"ok": true, "exists": true, "size": 900 * 1024, "kind": "video"},
        "/home/me/gone.gif": {"ok": true, "exists": false, "size": 0, "kind": ""}
        });
    }
    property var calls: []
    property var opened: []

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    HarnessTestCase {
        id: testCase
        name: "ConfigAppearance"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null
        property var form: null

        function open(cfg) {
            var component = Qt.createComponent(uiDir + "ConfigAppearance.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({
                "width": root.width, "height": root.height,
                "cfg_customIcon": "dialog-messages", "cfg_appDisplayName": "", "cfg_playNotificationSound": false,
                "cfg_notifyOnReply": true, "cfg_notifyOnError": true, "cfg_notifyOnScheduled": true, "cfg_notifyOnInput": true,
                "cfg_panelIconMode": "icon", "cfg_panelIconFile": "", "cfg_panelIconHoverOnly": false,
                "runHelper": function(command, payload, onDone) {
                    root.calls.push(command + " " + payload.path);
                    onDone(JSON.stringify(root.files[payload.path] || {"ok": false, "error": "invalid path"}), 0, "");
                },
                "openUrl": function(url) { root.opened.push(url); }
            }, cfg || {}));
            verify(page !== null);
            form = findChild(page, "panelIconModeCombo").parent;
            while (form && !form.hasOwnProperty("videoAvailable"))
                form = form.parent;
            verify(form !== null, "PanelIconSettings");
            return page;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            root.calls = [];
            root.opened = [];
            wait(200);
        }
        function pickMode(value) {
            var combo = findChild(page, "panelIconModeCombo");
            combo.currentIndex = combo.indexOfValue(value);
            combo.activated(combo.currentIndex);
        }

        function test_normal_icon_hides_the_animation_rows() {
            open();
            compare(findChild(page, "panelIconModeCombo").currentText, "Normal icon");
            verify(!findChild(page, "panelIconFileRow").visible);
            verify(!findChild(page, "panelIconHoverOnly").visible);
            wait(300);
            screenshot(page, "config-appearance-icon");
        }

        function test_choosing_an_animated_gif() {
            open();
            pickMode("animated");
            compare(page.cfg_panelIconMode, "animated");
            verify(findChild(page, "panelIconFileRow").visible);
            compare(findChild(page, "panelIconFileName").text, "No file chosen");
            form.choose("file://" + root.robot);
            compare(root.calls.join(","), "panel_icon_check " + root.robot);
            compare(page.cfg_panelIconFile, root.robot);
            compare(findChild(page, "panelIconFileName").text, "panel-icon.gif");
            tryVerify(function() { return findChild(page, "panelIconPreview").visible; }, 3000);
            verify(!findChild(page, "panelIconMessage").visible, "no warning for a small file");
            var hover = findChild(page, "panelIconHoverOnly");
            verify(hover.visible);
            hover.toggle();
            hover.toggled();
            compare(page.cfg_panelIconHoverOnly, true);
        }

        function test_size_limits() {
            open({"cfg_panelIconMode": "animated", "cfg_panelIconFile": root.robot});
            form.choose("file:///home/me/huge.gif");
            compare(page.cfg_panelIconFile, root.robot, "over 20 MB: refused");
            var message = findChild(page, "panelIconMessage");
            verify(message.visible);
            compare(message.text, "This file is 25.0 MB. Choose one of 20 MB or less.");
            form.choose("file://" + root.big);
            compare(page.cfg_panelIconFile, root.big, "over 5 MB: taken, with a warning");
            compare(message.text, "This file is 8.0 MB. Big animations use more memory and power; a smaller one is better.");
            form.choose("file:///home/me/gone.gif");
            compare(page.cfg_panelIconFile, root.big);
            compare(message.text, "The file was not found.");
            wait(300);
            screenshot(page, "config-appearance-animated");
        }

        function test_wrong_kind_is_refused_and_mode_change_clears_the_file() {
            open({"cfg_panelIconMode": "animated", "cfg_panelIconFile": root.robot});
            form.choose("file:///home/me/clip.webm");
            compare(page.cfg_panelIconFile, root.robot);
            compare(findChild(page, "panelIconMessage").text, "This file is not an animated image.");
            form.videoAvailable = true;
            pickMode("video");
            compare(page.cfg_panelIconMode, "video");
            compare(page.cfg_panelIconFile, "", "a GIF is not kept for video");
            form.choose("file:///home/me/clip.webm");
            compare(page.cfg_panelIconFile, "/home/me/clip.webm");
        }

        function test_video_only_offered_with_qtmultimedia() {
            open();
            form.videoAvailable = false;
            var combo = findChild(page, "panelIconModeCombo");
            compare(combo.count, 2, "no video choice without QtMultimedia");
            form.videoAvailable = true;
            compare(combo.count, 3);
            compare(combo.model[2].text, "Short video");
        }

        function test_donate_link() {
            open();
            var button = findChild(page, "donateButton");
            verify(button !== null);
            compare(button.text, "Buy Me a Coffee");
            verify(findChild(page, "donateHelp").text.length > 20);
            button.clicked();
            compare(root.opened.join(","), "https://buymeacoffee.com/rachitasthana");
        }
    }
}
