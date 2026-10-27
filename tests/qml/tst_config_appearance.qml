// Settings → Appearance, the one Icon setting: a theme icon or still image,
// an animated image (file check with the size limits, hover only) or a short
// video (only when QtMultimedia is there), reset; the support and terms links
// live on the About page. The helper is a fake: no file is read.
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
                }
            }, cfg || {}));
            verify(page !== null);
            form = findChild(page, "iconButton").parent;
            while (form && !form.hasOwnProperty("videoAvailable"))
                form = form.parent;
            verify(form !== null, "IconSettings");
            return page;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            root.calls = [];
            wait(200);
        }
        // The item of the Icon button's menu with this object name.
        function menuItem(name) {
            var menu = form.menu;
            for (var i = 0; i < menu.count; i++) {
                if (menu.itemAt(i).objectName === name)
                    return menu.itemAt(i);
            }
            fail("no menu item " + name);
            return null;
        }

        function test_one_icon_setting_and_no_panel_icon_combo() {
            open();
            verify(findChild(page, "panelIconModeCombo") === null, "the Panel icon combo is gone");
            verify(findChild(page, "panelIconFileRow") === null, "the File row is gone");
            verify(!findChild(page, "panelIconFileName").visible);
            verify(!findChild(page, "panelIconMessage").visible);
            verify(!findChild(page, "panelIconHoverOnly").visible, "hover only is for animations");
            compare(page.cfg_panelIconMode, "icon");
            wait(300);
            screenshot(page, "config-appearance-icon");
        }

        function test_menu_actions() {
            open();
            form.videoAvailable = false;
            compare(menuItem("chooseIconAction").text, "Choose Icon…");
            compare(menuItem("chooseImageAction").text, "Choose Image File…");
            compare(menuItem("chooseAnimatedAction").text, "Choose Animated Image…");
            verify(!menuItem("chooseVideoAction").enabled, "no video choice without QtMultimedia");
            form.videoAvailable = true;
            verify(menuItem("chooseVideoAction").enabled);
            compare(menuItem("chooseVideoAction").text, "Choose Short Video…");
            compare(menuItem("resetIconAction").text, "Reset to Default Icon");
        }

        function test_theme_icon_and_still_image_set_icon_mode() {
            open({"cfg_panelIconMode": "animated", "cfg_panelIconFile": root.robot});
            form.chooseIcon("bot-symbolic");
            compare(page.cfg_customIcon, "bot-symbolic");
            compare(page.cfg_panelIconMode, "icon");
            compare(page.cfg_panelIconFile, "");
            verify(!findChild(page, "panelIconHoverOnly").visible);
            form.choose("file://" + root.robot, "animated");
            compare(page.cfg_panelIconMode, "animated");
            form.chooseIcon(root.robot);
            compare(page.cfg_customIcon, root.robot);
            compare(page.cfg_panelIconMode, "icon");
            compare(page.cfg_panelIconFile, "");
        }

        function test_choosing_an_animated_gif() {
            open({"cfg_customIcon": "bot-symbolic"});
            form.choose("file://" + root.robot, "animated");
            compare(root.calls.join(","), "panel_icon_check " + root.robot);
            compare(page.cfg_panelIconMode, "animated");
            compare(page.cfg_panelIconFile, root.robot);
            compare(page.cfg_customIcon, "bot-symbolic", "the icon stays as the fallback");
            var name = findChild(page, "panelIconFileName");
            verify(name.visible);
            compare(name.text, "panel-icon.gif");
            tryVerify(function() { return findChild(page, "panelIconPreview").visible; }, 3000);
            verify(!findChild(page, "panelIconMessage").visible, "no warning for a small file");
            var hover = findChild(page, "panelIconHoverOnly");
            verify(hover.visible);
            hover.toggle();
            hover.toggled();
            compare(page.cfg_panelIconHoverOnly, true);
            wait(300);
            screenshot(page, "config-appearance-animated");
        }

        function test_size_limits() {
            open({"cfg_panelIconMode": "animated", "cfg_panelIconFile": root.robot});
            form.choose("file:///home/me/huge.gif", "animated");
            compare(page.cfg_panelIconFile, root.robot, "over 20 MB: refused");
            var message = findChild(page, "panelIconMessage");
            verify(message.visible);
            compare(message.text, "This file is 25.0 MB. Choose one of 20 MB or less.");
            form.choose("file://" + root.big, "animated");
            compare(page.cfg_panelIconFile, root.big, "over 5 MB: taken, with a warning");
            compare(message.text, "This file is 8.0 MB. Big animations use more memory and power; a smaller one is better.");
            form.choose("file:///home/me/gone.gif", "animated");
            compare(page.cfg_panelIconFile, root.big);
            compare(message.text, "The file was not found.");
            wait(300);
            screenshot(page, "config-appearance-animated-warning");
        }

        function test_wrong_kind_is_refused() {
            open({"cfg_panelIconMode": "animated", "cfg_panelIconFile": root.robot});
            form.choose("file:///home/me/clip.webm", "animated");
            compare(page.cfg_panelIconFile, root.robot);
            compare(page.cfg_panelIconMode, "animated");
            compare(findChild(page, "panelIconMessage").text, "This file is not an animated image.");
            form.choose("file://" + root.robot, "video");
            compare(page.cfg_panelIconFile, root.robot, "a GIF is not a video");
            compare(findChild(page, "panelIconMessage").text, "This file is not a video.");
        }

        function test_choosing_a_video() {
            open();
            form.videoAvailable = true;
            form.choose("file:///home/me/clip.webm", "video");
            compare(page.cfg_panelIconMode, "video");
            compare(page.cfg_panelIconFile, "/home/me/clip.webm");
            compare(findChild(page, "panelIconFileName").text, "clip.webm");
            verify(findChild(page, "panelIconHoverOnly").visible);
            wait(300);
            screenshot(page, "config-appearance-video");
        }

        function test_reset_goes_back_to_the_default_icon() {
            open({"cfg_customIcon": "bot-symbolic", "cfg_panelIconMode": "animated", "cfg_panelIconFile": root.robot});
            var reset = menuItem("resetIconAction");
            verify(reset.enabled);
            reset.triggered();
            compare(page.cfg_customIcon, "dialog-messages");
            compare(page.cfg_panelIconMode, "icon");
            compare(page.cfg_panelIconFile, "");
            verify(!reset.enabled, "nothing to reset now");
            verify(!findChild(page, "panelIconHoverOnly").visible);
        }

        function test_support_and_terms_links_moved_to_about() {
            open();
            verify(findChild(page, "donateButton") === null, "Buy Me a Coffee is on the About page now");
            verify(findChild(page, "termsButton") === null, "Read the terms is on the About page now");
            verify(findChild(page, "donateHelp") === null);
            verify(findChild(page, "termsHelp") === null);
        }
    }
}
