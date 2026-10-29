// An avatar choice (Settings → Personality, one for you and one for the AI):
// a button showing the picture with a menu (a theme icon, an image file, an
// animated image, a short video if QtMultimedia is installed, none) and a line
// saying what is chosen or why a file was refused. `value` is a theme icon
// name or the absolute path of a file ("" = none; the kind comes from its
// extension); the page binds it to its cfg_ property. Animated images and
// videos are checked by the helper first (panel_icon_check, limits in
// chat/PanelIcon.js). Nothing here is secret.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes
import "../Security.js" as Sec
import "../chat/Personality.js" as Personality
import "../chat/PanelIcon.js" as Logic
import "../chat" as Chat

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

RowLayout {
    id: picker

    property string value: ""
    // Names the objects: <prefix>Button and <prefix>Status.
    property string prefix: "avatar"
    property string buttonName: i18n("Choose the avatar")
    property string dialogTitle: i18n("Choose a Picture")
    // Shown when a chosen file can't be used.
    property string error: ""
    readonly property var avatar: Personality.avatar({"aiAvatar": value})
    // Runs a helper command: run(command, payload, onDone(stdout, exitCode, stderr)).
    // Without one, animated files and videos are not checked.
    property var runHelper: null
    // Whether QtMultimedia can be loaded here (tests set it).
    property bool videoAvailable: detectVideo()
    // Set while the helper checks a file.
    property bool checking: false
    // "animated" or "video": what the open file dialog is for.
    property string pickKind: "animated"
    // A warning (not a refusal) about the chosen file, shown in the status line.
    property string warning: ""
    // The menu entry for videos (tests look at it).
    readonly property alias videoItem: videoItem
    readonly property alias menu: avatarMenu

    function detectVideo() {
        try {
            Qt.createQmlObject("import QtQuick; import QtMultimedia; QtObject {}", picker, "videoProbe").destroy();
            return true;
        } catch (e) {
            return false;
        }
    }

    // Takes a picked file if it is an image file with a safe path.
    function setFile(url) {
        var path = decodeURIComponent(String(url || "").replace(/^file:\/\//, ""));
        if (!Personality.isImagePath(path) || Sec.validateFilePath(path) === "") {
            error = i18n("Choose a PNG, JPEG, WebP, GIF, SVG or BMP image.");
            return;
        }
        error = "";
        value = path;
    }

    // Takes a picked animated image or video (`kind`): checked by the helper
    // (size, kind) when there is one, then saved as the path.
    function setMedia(url, kind) {
        var path = decodeURIComponent(String(url || "").replace(/^file:\/\//, ""));
        if (Sec.validateFilePath(path) === "" || path.charAt(0) !== "/" || Logic.fileKind(path) !== kind) {
            error = kind === "video" ? i18n("This file is not a video.") : i18n("This file is not an animated image.");
            return;
        }
        if (!runHelper) {
            error = "";
            value = path;
            return;
        }
        checking = true;
        runHelper("panel_icon_check", {"path": path}, function(stdout) {
            picker.checking = false;
            var info = null;
            try { info = JSON.parse(stdout); } catch (e) { info = null; }
            var verdict = Logic.verdict(info, kind);
            if (!verdict.ok) {
                picker.error = verdict.reason === "too-large"
                    ? i18n("This file is %1 MB. Choose one of 20 MB or less.", Logic.megabytes(info.size))
                    : verdict.reason === "kind"
                    ? (kind === "video" ? i18n("This file is not a video.") : i18n("This file is not an animated image."))
                    : verdict.reason === "missing" ? i18n("The file was not found.") : i18n("The file can't be read.");
                return;
            }
            picker.value = path;
            picker.warning = verdict.warn ? i18n("This file is %1 MB. Big animations use more memory and power; a smaller one is better.", Logic.megabytes(info.size)) : "";
        });
    }

    // A new choice (or none) ends the old complaint.
    onValueChanged: { error = ""; warning = ""; }

    spacing: Kirigami.Units.smallSpacing

    Component {
        id: iconDialogComponent
        KIconThemes.IconDialog {
            onIconNameChanged: function(iconName) {
                if (iconName) {
                    picker.error = "";
                    picker.value = iconName;
                }
            }
        }
    }
    property var iconDialog: null

    FileDialog {
        id: imageDialog
        title: picker.dialogTitle
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.webp *.gif *.svg *.svgz *.bmp)")]
        onAccepted: picker.setFile(selectedFile)
    }

    FileDialog {
        id: mediaDialog
        title: picker.pickKind === "video" ? i18n("Choose a Short Video") : i18n("Choose an Animated Image")
        fileMode: FileDialog.OpenFile
        nameFilters: picker.pickKind === "video" ? [i18n("Videos (*.mp4 *.webm *.mkv *.mov *.m4v *.ogv)")]
                                                 : [i18n("Animated images (*.gif *.png *.apng *.webp)")]
        onAccepted: picker.setMedia(selectedFile, picker.pickKind)
    }

    QQC2.Button {
        id: avatarButton
        objectName: picker.prefix + "Button"
        implicitWidth: Kirigami.Units.iconSizes.large + Kirigami.Units.largeSpacing * 2
        implicitHeight: implicitWidth
        onPressed: avatarMenu.opened ? avatarMenu.close() : avatarMenu.popup(avatarButton, 0, avatarButton.height)
        Accessible.name: picker.buttonName
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: picker.buttonName

        Chat.AvatarView {
            id: avatarView
            objectName: picker.prefix + "Preview"
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: width
            visible: valid
            kind: picker.avatar.kind
            source: picker.avatar.source
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: width
            visible: !avatarView.visible
            source: "user-identity"
            opacity: 0.35
        }

        QQC2.Menu {
            id: avatarMenu
            QQC2.MenuItem {
                text: i18n("Choose Icon…")
                icon.name: "document-open-folder"
                onTriggered: {
                    if (!picker.iconDialog)
                        picker.iconDialog = iconDialogComponent.createObject(picker);
                    picker.iconDialog.open();
                }
            }
            QQC2.MenuItem {
                text: i18n("Choose Image File…")
                icon.name: "image-x-generic"
                onTriggered: imageDialog.open()
            }
            QQC2.MenuItem {
                text: i18n("Choose Animated Image…")
                icon.name: "view-preview"
                enabled: !picker.checking
                onTriggered: {
                    picker.pickKind = "animated";
                    mediaDialog.open();
                }
            }
            QQC2.MenuItem {
                id: videoItem
                text: i18n("Choose Short Video…")
                icon.name: "video-x-generic"
                visible: picker.videoAvailable
                enabled: !picker.checking
                onTriggered: {
                    picker.pickKind = "video";
                    mediaDialog.open();
                }
            }
            QQC2.MenuItem {
                text: i18n("No Avatar")
                icon.name: "edit-clear"
                enabled: picker.value !== ""
                onTriggered: {
                    picker.error = "";
                    picker.value = "";
                }
            }
        }
    }

    QQC2.Label {
        textFormat: Text.PlainText
        objectName: picker.prefix + "Status"
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.Wrap
        color: picker.error !== "" || avatarView.failed ? Kirigami.Theme.negativeTextColor
            : picker.warning !== "" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.disabledTextColor
        text: picker.error !== "" ? picker.error
            : avatarView.failed ? (picker.avatar.kind === "video" ? i18n("This video can't be played; a plain icon is shown.") : i18n("This picture can't be read; no avatar is shown."))
            : picker.warning !== "" ? picker.warning
            : picker.checking ? i18n("Checking the file…")
            : picker.value === "" ? i18n("None")
            : picker.avatar.kind === "image" || picker.avatar.kind === "video" ? picker.value.substring(picker.value.lastIndexOf("/") + 1)
            : picker.value
    }
}
