// Settings → Appearance, the widget's icon: ONE choice for what the panel
// shows. A theme icon or a still image (customIcon, mode "icon"), an animated
// image (GIF, APNG, WebP: mode "animated") or a short video (mode "video",
// only offered when QtMultimedia is installed) from `file`. The theme icon
// stays as the fallback if the file goes missing. A chosen animation or video
// is checked by the helper first (panel_icon_check): files over 20 MB are
// refused, over 5 MB get a warning (limits in chat/PanelIcon.js). The page
// owns the saved values (cfg_customIcon, cfg_panelIcon*); this form edits them.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes
import "../chat/PanelIcon.js" as Logic

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: settings

    // A KDE icon name, or the path of a still image file.
    property string customIcon: Logic.DEFAULT_ICON
    property string mode: "icon"
    property string file: ""
    property bool hoverOnly: false
    // Runs a helper command: run(command, payload, onDone(stdout, exitCode, stderr)).
    property var runHelper: null
    // Whether QtMultimedia can be loaded here (tests set it).
    property bool videoAvailable: detectVideo()

    // What the last check said: "" or a message; kind "error", "warn" or "".
    property string message: ""
    property string messageKind: ""
    property bool checking: false

    // What the panel shows: the animation or video only with a file of its kind.
    readonly property string shown: Logic.effectiveMode(mode, file)
    readonly property bool animating: mode !== "icon" && file !== ""
    // The Icon button's menu (tests read its items).
    readonly property var menu: iconMenu
    readonly property bool stillImage: shown === "icon" && Logic.isImageFile(customIcon)

    function detectVideo() {
        try {
            Qt.createQmlObject("import QtQuick; import QtMultimedia; QtObject {}", settings, "videoProbe").destroy();
            return true;
        } catch (e) {
            return false;
        }
    }

    function clearFile() {
        file = "";
        message = "";
        messageKind = "";
    }

    // A theme icon or a still image: the panel shows it as it is.
    function chooseIcon(value) {
        customIcon = value;
        mode = "icon";
        clearFile();
    }

    function resetIcon() {
        chooseIcon(Logic.DEFAULT_ICON);
    }

    // Checks a picked animated image ("animated") or video ("video"), then
    // takes it (or says why not).
    function choose(url, kind) {
        var path = decodeURIComponent(String(url || "").replace(/^file:\/\//, ""));
        if (!runHelper) {
            file = path;
            mode = kind;
            return;
        }
        checking = true;
        message = "";
        runHelper("panel_icon_check", {"path": path}, function(stdout) {
            settings.checking = false;
            var info = null;
            try { info = JSON.parse(stdout); } catch (e) { info = null; }
            var verdict = Logic.verdict(info, kind);
            if (!verdict.ok) {
                settings.messageKind = "error";
                settings.message = verdict.reason === "too-large"
                    ? i18n("This file is %1 MB. Choose one of 20 MB or less.", Logic.megabytes(info.size))
                    : verdict.reason === "kind"
                    ? (kind === "video" ? i18n("This file is not a video.") : i18n("This file is not an animated image."))
                    : verdict.reason === "missing" ? i18n("The file was not found.") : i18n("The file can't be read.");
                return;
            }
            settings.file = path;
            settings.mode = kind;
            settings.messageKind = verdict.warn ? "warn" : "";
            settings.message = verdict.warn ? i18n("This file is %1 MB. Big animations use more memory and power; a smaller one is better.", Logic.megabytes(info.size)) : "";
        });
    }

    Component {
        id: iconDialogComponent
        KIconThemes.IconDialog {
            onIconNameChanged: function(iconName) {
                if (iconName)
                    settings.chooseIcon(iconName);
            }
        }
    }
    property var iconDialog: null

    FileDialog {
        id: imageDialog
        title: i18n("Choose an Image for the Widget")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.webp *.gif *.svg *.svgz *.bmp)")]
        onAccepted: settings.chooseIcon(decodeURIComponent(String(selectedFile).replace(/^file:\/\//, "")))
    }

    FileDialog {
        id: animationDialog
        property string kind: "animated"
        title: kind === "video" ? i18n("Choose a Short Video") : i18n("Choose an Animated Image")
        fileMode: FileDialog.OpenFile
        nameFilters: kind === "video" ? [i18n("Videos (*.mp4 *.webm *.mkv *.mov *.m4v *.ogv)")]
                                      : [i18n("Animated images (*.gif *.png *.apng *.webp)")]
        onAccepted: settings.choose(selectedFile, kind)
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Icon:")
        spacing: Kirigami.Units.largeSpacing

        QQC2.Button {
            id: iconButton
            objectName: "iconButton"
            implicitWidth: Kirigami.Units.iconSizes.large + Kirigami.Units.largeSpacing * 2
            implicitHeight: implicitWidth
            enabled: !settings.checking
            onPressed: iconMenu.opened ? iconMenu.close() : iconMenu.popup(iconButton, 0, iconButton.height)
            Accessible.name: i18n("Choose the widget icon")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Choose the widget icon")

            AnimatedImage {
                objectName: "panelIconPreview"
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                visible: settings.shown === "animated" && status === Image.Ready
                source: settings.shown === "animated" ? Logic.fileUrl(settings.file) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                playing: visible
            }
            Image {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                visible: settings.stillImage
                source: visible ? Logic.fileUrl(settings.customIcon) : ""
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                visible: !settings.stillImage && settings.shown !== "animated"
                source: settings.shown === "video" ? "video-x-generic" : (settings.customIcon || Logic.DEFAULT_ICON)
            }

            QQC2.Menu {
                id: iconMenu
                objectName: "iconMenu"
                QQC2.MenuItem {
                    objectName: "chooseIconAction"
                    text: i18n("Choose Icon…")
                    icon.name: "document-open-folder"
                    onTriggered: {
                        if (!settings.iconDialog)
                            settings.iconDialog = iconDialogComponent.createObject(settings);
                        settings.iconDialog.open();
                    }
                }
                QQC2.MenuItem {
                    objectName: "chooseImageAction"
                    text: i18n("Choose Image File…")
                    icon.name: "image-x-generic"
                    onTriggered: imageDialog.open()
                }
                QQC2.MenuItem {
                    objectName: "chooseAnimatedAction"
                    text: i18n("Choose Animated Image…")
                    icon.name: "image-x-generic"
                    onTriggered: { animationDialog.kind = "animated"; animationDialog.open(); }
                }
                QQC2.MenuItem {
                    objectName: "chooseVideoAction"
                    text: i18n("Choose Short Video…")
                    icon.name: "video-x-generic"
                    enabled: settings.videoAvailable
                    visible: settings.videoAvailable
                    height: visible ? implicitHeight : 0
                    onTriggered: { animationDialog.kind = "video"; animationDialog.open(); }
                }
                QQC2.MenuItem {
                    objectName: "resetIconAction"
                    text: i18n("Reset to Default Icon")
                    icon.name: "edit-clear"
                    enabled: settings.customIcon !== Logic.DEFAULT_ICON || settings.mode !== "icon"
                    onTriggered: settings.resetIcon()
                }
            }
        }

        QQC2.Label {
            objectName: "panelIconFileName"
            visible: settings.animating
            Layout.maximumWidth: Kirigami.Units.gridUnit * 14
            elide: Text.ElideMiddle
            text: settings.file.substring(settings.file.lastIndexOf("/") + 1)
        }
    }

    SettingHelp {
        text: settings.videoAvailable
            ? i18n("What the widget shows in the panel. Choose a picture from your theme or a still image of your own, or a small animated image (GIF, APNG, WebP) or short video that plays in the panel. The animation is paused while the panel is hidden or the screen is locked. If an animation or video goes missing or can't be played, the picture is shown instead.")
            : i18n("What the widget shows in the panel. Choose a picture from your theme or a still image of your own, or a small animated image (GIF, APNG, WebP) that plays in the panel. Videos need the Qt Multimedia package, which is not installed. The animation is paused while the panel is hidden or the screen is locked. If an animation goes missing or can't be played, the picture is shown instead.")
    }

    QQC2.Label {
        objectName: "panelIconMessage"
        visible: settings.animating && settings.message !== ""
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 28
        wrapMode: Text.Wrap
        text: settings.message
        color: settings.messageKind === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.neutralTextColor
    }

    SettingHelp {
        visible: settings.animating
        text: i18n("A small file of up to 20 MB; a few seconds that repeat look best.")
    }

    QQC2.CheckBox {
        objectName: "panelIconHoverOnly"
        visible: settings.animating
        text: i18n("Animate only while the pointer is on it")
        checked: settings.hoverOnly
        onToggled: settings.hoverOnly = checked
    }

    SettingHelp {
        visible: settings.animating
        text: i18n("Keeps the panel calm and saves a little power: the animation stands still until you point at it.")
    }
}
