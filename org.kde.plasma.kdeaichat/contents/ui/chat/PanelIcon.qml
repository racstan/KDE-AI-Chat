// The widget's panel icon (main.qml's compactRepresentation); a click opens
// or closes the chat. It shows, from Settings → Appearance:
//   - the normal icon: a theme icon or an image file (customIcon);
//   - an animated image (GIF, APNG, WebP) with AnimatedImage;
//   - a short muted looping video (chat/PanelVideo.qml, QtMultimedia, loaded
//     only in that mode, so a system without QtMultimedia never loads it).
// An animation runs only while the icon can be seen: the item and its panel
// window are visible and the screen isn't locked (org.freedesktop.ScreenSaver
// GetActive, asked every 15 s while animating), and with "animate only on
// hover" only while the pointer is on it. A file that is missing or can't be
// played falls back to the normal icon.
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus
import "PanelIcon.js" as Logic

MouseArea {
    id: icon

    // main.qml's root (expanded, plasmoid); tests pass a stand-in.
    property var chat: null
    readonly property var configuration: chat && chat.plasmoid ? chat.plasmoid.configuration : null

    readonly property string customIcon: configuration && configuration.customIcon ? String(configuration.customIcon) : Logic.DEFAULT_ICON
    readonly property string mode: Logic.effectiveMode(configuration ? configuration.panelIconMode : "icon",
                                                       configuration ? configuration.panelIconFile : "")
    readonly property string file: configuration ? String(configuration.panelIconFile || "") : ""
    readonly property bool hoverOnly: !!configuration && configuration.panelIconHoverOnly === true

    // Set when the animation can't be shown (missing file, decoding error).
    property bool failed: false
    property bool screenLocked: false
    readonly property bool shown: visible && width > 0 && height > 0 && (!Window.window || Window.window.visible)
    readonly property bool playing: Logic.shouldPlay({"mode": mode, "failed": failed, "visible": shown, "locked": screenLocked,
                                                      "hoverOnly": hoverOnly, "hovered": containsMouse})
    // What is on screen: "icon", "animated" or "video".
    readonly property string showing: mode !== "icon" && !failed ? mode : "icon"

    // Asks whether the screen is locked: done(bool). Tests replace it.
    property var lockQuery: function(done) {
        var reply;
        try {
            reply = DBus.SessionBus.asyncCall({"service": "org.freedesktop.ScreenSaver", "path": "/ScreenSaver",
                                               "iface": "org.freedesktop.ScreenSaver", "member": "GetActive", "arguments": []});
        } catch (e) {
            done(false);
            return;
        }
        reply.finished.connect(function() { done(!reply.isError && reply.value === true); });
    }

    onModeChanged: failed = false
    onFileChanged: failed = false

    hoverEnabled: true
    onClicked: if (chat) chat.expanded = !chat.expanded

    Timer {
        id: lockPoll
        interval: 15000
        repeat: true
        triggeredOnStart: true
        running: icon.mode !== "icon" && !icon.failed && icon.shown && !icon.hoverOnly
        onTriggered: icon.lockQuery(function(locked) { icon.screenLocked = locked; })
        onRunningChanged: if (!running) icon.screenLocked = false
    }

    readonly property real side: Math.min(width, height) * 0.8

    Image {
        objectName: "panelIconImage"
        anchors.centerIn: parent
        width: icon.side
        height: width
        visible: icon.showing === "icon" && Logic.isImageFile(icon.customIcon)
        source: visible ? Logic.fileUrl(icon.customIcon) : ""
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
    }

    Kirigami.Icon {
        objectName: "panelIconThemeIcon"
        anchors.centerIn: parent
        width: icon.side
        height: width
        visible: icon.showing === "icon" && !Logic.isImageFile(icon.customIcon)
        source: icon.customIcon
    }

    AnimatedImage {
        id: animation
        objectName: "panelIconAnimation"
        anchors.centerIn: parent
        width: icon.side
        height: width
        visible: icon.showing === "animated"
        source: icon.mode === "animated" ? Logic.fileUrl(icon.file) : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        playing: icon.playing
        // Back to the first frame when it stops on leaving the icon.
        onPlayingChanged: if (!playing && icon.hoverOnly && frameCount > 0) currentFrame = 0
        onStatusChanged: if (status === Image.Error) icon.failed = true
    }

    Loader {
        id: video
        objectName: "panelIconVideo"
        anchors.centerIn: parent
        width: icon.side
        height: width
        visible: icon.showing === "video"
        active: icon.mode === "video" && !icon.failed
        source: "PanelVideo.qml"
        onStatusChanged: if (status === Loader.Error) icon.failed = true
        onLoaded: {
            item.source = Qt.binding(function() { return Logic.fileUrl(icon.file); });
            item.playing = Qt.binding(function() { return icon.playing; });
            item.failed.connect(function() { icon.failed = true; });
        }
    }
}
