// Settings → Appearance, the panel icon's animation: the normal icon, an
// animated image (GIF, APNG, WebP) or a short video (only offered when
// QtMultimedia is installed), the file, and "animate only on hover". A chosen
// file is checked by the helper first (panel_icon_check): files over 20 MB
// are refused, over 5 MB get a warning (limits in chat/PanelIcon.js). The
// page owns the saved values (cfg_panelIcon*); this form edits them.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../chat/PanelIcon.js" as Logic

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: settings

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

    function detectVideo() {
        try {
            Qt.createQmlObject("import QtQuick; import QtMultimedia; QtObject {}", settings, "videoProbe").destroy();
            return true;
        } catch (e) {
            return false;
        }
    }

    readonly property var modes: {
        var list = [{"value": "icon", "text": i18n("Normal icon")},
                    {"value": "animated", "text": i18n("Animated image (GIF, APNG, WebP)")}];
        if (videoAvailable || mode === "video")
            list.push({"value": "video", "text": videoAvailable ? i18n("Short video") : i18n("Short video (not available)")});
        return list;
    }

    function setMode(next) {
        if (next !== mode && Logic.fileKind(file) !== next)
            file = "";
        mode = next;
        message = "";
        messageKind = "";
    }

    // Checks a picked file, then takes it (or says why not).
    function choose(url) {
        var path = decodeURIComponent(String(url || "").replace(/^file:\/\//, ""));
        if (!runHelper) {
            file = path;
            return;
        }
        checking = true;
        message = "";
        runHelper("panel_icon_check", {"path": path}, function(stdout) {
            settings.checking = false;
            var info = null;
            try { info = JSON.parse(stdout); } catch (e) { info = null; }
            var verdict = Logic.verdict(info, settings.mode);
            if (!verdict.ok) {
                settings.messageKind = "error";
                settings.message = verdict.reason === "too-large"
                    ? i18n("This file is %1 MB. Choose one of 20 MB or less.", Logic.megabytes(info.size))
                    : verdict.reason === "kind"
                    ? (settings.mode === "video" ? i18n("This file is not a video.") : i18n("This file is not an animated image."))
                    : verdict.reason === "missing" ? i18n("The file was not found.") : i18n("The file can't be read.");
                return;
            }
            settings.file = path;
            settings.messageKind = verdict.warn ? "warn" : "";
            settings.message = verdict.warn ? i18n("This file is %1 MB. Big animations use more memory and power; a smaller one is better.", Logic.megabytes(info.size)) : "";
        });
    }

    FileDialog {
        id: fileDialog
        title: settings.mode === "video" ? i18n("Choose a Short Video") : i18n("Choose an Animated Image")
        fileMode: FileDialog.OpenFile
        nameFilters: settings.mode === "video" ? [i18n("Videos (*.mp4 *.webm *.mkv *.mov *.m4v *.ogv)")]
                                               : [i18n("Animated images (*.gif *.png *.apng *.webp)")]
        onAccepted: settings.choose(selectedFile)
    }

    QQC2.ComboBox {
        id: modeCombo
        objectName: "panelIconModeCombo"
        Kirigami.FormData.label: i18n("Panel icon:")
        textRole: "text"
        valueRole: "value"
        model: settings.modes
        currentIndex: Math.max(0, settings.modes.map(function(m) { return m.value; }).indexOf(settings.mode))
        onActivated: settings.setMode(currentValue)
    }

    SettingHelp {
        text: settings.videoAvailable
            ? i18n("What the widget shows in the panel: its icon, or a small animation or video of your choice. The animation is paused while the panel is hidden or the screen is locked.")
            : i18n("What the widget shows in the panel: its icon, or a small animation of your choice. Videos need the Qt Multimedia package, which is not installed. The animation is paused while the panel is hidden or the screen is locked.")
    }

    RowLayout {
        objectName: "panelIconFileRow"
        Kirigami.FormData.label: i18n("File:")
        visible: settings.mode !== "icon"
        spacing: Kirigami.Units.smallSpacing

        AnimatedImage {
            objectName: "panelIconPreview"
            visible: settings.mode === "animated" && settings.file !== "" && status === Image.Ready
            source: settings.mode === "animated" && settings.file !== "" ? Logic.fileUrl(settings.file) : ""
            Layout.preferredWidth: Kirigami.Units.iconSizes.large
            Layout.preferredHeight: Kirigami.Units.iconSizes.large
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            playing: visible
        }
        QQC2.Label {
            objectName: "panelIconFileName"
            Layout.maximumWidth: Kirigami.Units.gridUnit * 14
            elide: Text.ElideMiddle
            text: settings.file === "" ? i18n("No file chosen") : settings.file.substring(settings.file.lastIndexOf("/") + 1)
            opacity: settings.file === "" ? 0.7 : 1
        }
        QQC2.Button {
            objectName: "panelIconChoose"
            text: i18n("Choose…")
            icon.name: "document-open"
            enabled: !settings.checking
            onClicked: fileDialog.open()
        }
        QQC2.Button {
            icon.name: "edit-clear"
            visible: settings.file !== ""
            Accessible.name: i18n("Use no file")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: Accessible.name
            onClicked: { settings.file = ""; settings.message = ""; }
        }
    }

    QQC2.Label {
        objectName: "panelIconMessage"
        visible: settings.mode !== "icon" && settings.message !== ""
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 28
        wrapMode: Text.Wrap
        text: settings.message
        color: settings.messageKind === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.neutralTextColor
    }

    SettingHelp {
        visible: settings.mode !== "icon"
        text: i18n("A small file of up to 20 MB; a few seconds that repeat look best. If the file goes missing or can't be played, the normal icon is shown.")
    }

    QQC2.CheckBox {
        objectName: "panelIconHoverOnly"
        visible: settings.mode !== "icon"
        text: i18n("Animate only while the pointer is on it")
        checked: settings.hoverOnly
        onToggled: settings.hoverOnly = checked
    }

    SettingHelp {
        visible: settings.mode !== "icon"
        text: i18n("Keeps the panel calm and saves a little power: the animation stands still until you point at it.")
    }
}
