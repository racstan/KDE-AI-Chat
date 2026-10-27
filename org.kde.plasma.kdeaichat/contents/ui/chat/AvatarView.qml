// One avatar picture, small: a theme icon, a still image, an animated image
// (GIF, APNG, WebP; plays only while visible) or a short muted looping video
// (chat/PanelVideo.qml, loaded on demand so the widget works without
// QtMultimedia; then, or when the file can't be played, a generic icon shows).
// `kind` and `source` are an avatar from chat/Personality.js; `valid` is
// whether something is shown, `failed` whether the file could not be used.
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import "PanelIcon.js" as Logic

Item {
    id: view

    property string kind: ""
    property string source: ""
    // Shown when a video can't be played.
    property string fallbackIcon: "video-x-generic"
    property bool failed: false

    // "icon", "image", "animated" or "video" ("" = nothing).
    readonly property string shape: kind === "image" && Logic.fileKind(source) === "animated" && Logic.extension(source) !== "png" ? "animated" : kind
    readonly property bool valid: shape === "icon" ? icon.valid
        : shape === "image" ? still.status === Image.Ready
        : shape === "animated" ? moving.status === Image.Ready
        : shape === "video" ? (!failed || icon.valid) : false
    // Animations run only while this is on screen (and not in a hidden popup).
    readonly property bool shown: visible && width > 0 && height > 0 && (!Window.window || Window.window.visible)

    onSourceChanged: failed = false
    onKindChanged: failed = false

    implicitWidth: Kirigami.Units.iconSizes.smallMedium
    implicitHeight: implicitWidth

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        visible: view.shape === "icon" || (view.shape === "video" && view.failed)
        source: view.shape === "icon" ? view.source : view.shape === "video" && view.failed ? view.fallbackIcon : ""
    }
    Image {
        id: still
        anchors.fill: parent
        visible: view.shape === "image"
        source: view.shape === "image" ? view.source : ""
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        onStatusChanged: if (status === Image.Error) view.failed = true
    }
    AnimatedImage {
        id: moving
        objectName: "avatarAnimation"
        anchors.fill: parent
        visible: view.shape === "animated"
        source: view.shape === "animated" ? view.source : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        playing: view.shown
        onStatusChanged: if (status === Image.Error) view.failed = true
    }
    Loader {
        id: video
        objectName: "avatarVideo"
        anchors.fill: parent
        visible: view.shape === "video" && !view.failed
        active: view.shape === "video" && !view.failed
        source: "PanelVideo.qml"
        onStatusChanged: if (status === Loader.Error) view.failed = true
    }
    // PanelVideo's type is only known once it loaded.
    Binding {
        target: video.item
        property: "source"
        value: view.source
        when: video.status === Loader.Ready
    }
    Binding {
        target: video.item
        property: "playing"
        value: view.shown
        when: video.status === Loader.Ready
    }
    Connections {
        target: video.item
        ignoreUnknownSignals: true
        function onFailed() { view.failed = true; }
    }
}
