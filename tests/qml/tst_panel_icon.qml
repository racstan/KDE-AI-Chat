// chat/PanelIcon.qml, the panel icon: the normal icon (theme icon or image
// file), an animated GIF that plays only while it can be seen (not hidden,
// screen not locked, and with "only on hover" only while hovered), and the
// fallback to the normal icon when the animation file is missing.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 200
    height: 120

    readonly property string gif: decodeURIComponent(String(Qt.resolvedUrl("../fixtures/panel-icon.gif")).replace(/^file:\/\//, ""))
    readonly property string avatar: decodeURIComponent(String(Qt.resolvedUrl("../fixtures/avatar.png")).replace(/^file:\/\//, ""))

    // Stands in for main.qml's root.
    QtObject {
        id: fakeChat
        property bool expanded: false
        property QtObject plasmoid: QtObject {
            property QtObject configuration: QtObject {
                property string customIcon: "dialog-messages"
                property string panelIconMode: "icon"
                property string panelIconFile: ""
                property bool panelIconHoverOnly: false
            }
        }
    }
    readonly property var config: fakeChat.plasmoid.configuration

    property bool locked: false
    property int lockQueries: 0

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    Chat.PanelIcon {
        id: icon
        x: 10
        y: 10
        width: 48
        height: 48
        chat: fakeChat
        lockQuery: function(done) { root.lockQueries++; done(root.locked); }
    }

    HarnessTestCase {
        name: "PanelIcon"

        function init() {
            config.customIcon = "dialog-messages";
            config.panelIconMode = "icon";
            config.panelIconFile = "";
            config.panelIconHoverOnly = false;
            root.locked = false;
            root.lockQueries = 0;
            icon.visible = true;
            mouseMove(root, 190, 110);
        }

        function animated() {
            config.panelIconFile = root.gif;
            config.panelIconMode = "animated";
            var animation = findChild(icon, "panelIconAnimation");
            tryCompare(animation, "status", Image.Ready, 3000);
            return animation;
        }

        function test_normal_icon() {
            compare(icon.showing, "icon");
            verify(findChild(icon, "panelIconThemeIcon").visible);
            verify(!findChild(icon, "panelIconImage").visible);
            verify(!icon.playing);
            config.customIcon = root.avatar;
            verify(findChild(icon, "panelIconImage").visible, "an image file is shown as an image");
            verify(!findChild(icon, "panelIconThemeIcon").visible);
        }

        function test_a_click_opens_and_closes_the_chat() {
            mouseClick(icon);
            compare(fakeChat.expanded, true);
            mouseClick(icon);
            compare(fakeChat.expanded, false);
        }

        function test_animated_gif_plays_while_seen() {
            var animation = animated();
            compare(icon.showing, "animated");
            verify(animation.visible);
            verify(animation.frameCount > 1, "the fixture has frames");
            verify(icon.playing);
            verify(animation.playing);
            screenshot(root, "panel-icon-animated");
            icon.visible = false;
            verify(!animation.playing, "paused while the icon is hidden");
            icon.visible = true;
            verify(animation.playing);
        }

        function test_paused_while_the_screen_is_locked() {
            root.locked = true;
            animated();
            tryVerify(function() { return root.lockQueries > 0; }, 2000);
            compare(icon.screenLocked, true);
            verify(!icon.playing, "a locked screen pauses it");
        }

        function test_hover_only() {
            config.panelIconHoverOnly = true;
            var animation = animated();
            verify(!icon.playing, "still until pointed at");
            compare(animation.currentFrame, 0);
            mouseMove(icon, 20, 20);
            tryVerify(function() { return icon.playing; }, 1000);
            verify(animation.playing);
            compare(root.lockQueries, 0, "no lock polling for hover-only");
            mouseMove(root, 190, 110);
            tryVerify(function() { return !icon.playing; }, 1000);
            compare(animation.currentFrame, 0, "back to the first frame");
        }

        function test_missing_file_falls_back_to_the_icon() {
            ignoreWarning(/Error Reading Animated Image File/);
            config.panelIconMode = "animated";
            config.panelIconFile = "/nonexistent/folder/robot.gif";
            tryCompare(icon, "failed", true, 3000);
            compare(icon.showing, "icon");
            verify(findChild(icon, "panelIconThemeIcon").visible);
            verify(!icon.playing);
            config.panelIconFile = root.gif;
            compare(icon.failed, false, "a new file is tried again");
            tryCompare(findChild(icon, "panelIconAnimation"), "status", Image.Ready, 3000);
            compare(icon.showing, "animated");
        }

        function test_wrong_kind_of_file_shows_the_icon() {
            config.panelIconMode = "video";
            config.panelIconFile = root.gif;
            compare(icon.mode, "icon", "a GIF is not a video");
            compare(icon.showing, "icon");
            config.panelIconMode = "animated";
            config.panelIconFile = "";
            compare(icon.mode, "icon", "no file: the normal icon");
        }

        function test_missing_video_falls_back_to_the_icon() {
            config.panelIconMode = "video";
            config.panelIconFile = "/nonexistent/folder/clip.mp4";
            compare(icon.mode, "video");
            tryCompare(icon, "failed", true, 5000);
            compare(icon.showing, "icon");
            verify(findChild(icon, "panelIconThemeIcon").visible);
        }
    }
}
