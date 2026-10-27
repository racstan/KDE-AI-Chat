// An avatar choice (Settings → Personality, one for you and one for the AI):
// a button showing the picture with a menu (a theme icon, an image file, none)
// and a line saying what is chosen or why a file was refused. `value` is a
// theme icon name or the absolute path of an image file ("" = none); the page
// binds it to its cfg_ property. Nothing here is secret.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes
import "../Security.js" as Sec
import "../chat/Personality.js" as Personality

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

    // A new choice (or none) ends the old complaint.
    onValueChanged: error = ""

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

    QQC2.Button {
        id: avatarButton
        objectName: picker.prefix + "Button"
        implicitWidth: Kirigami.Units.iconSizes.large + Kirigami.Units.largeSpacing * 2
        implicitHeight: implicitWidth
        onPressed: avatarMenu.opened ? avatarMenu.close() : avatarMenu.popup(avatarButton, 0, avatarButton.height)
        Accessible.name: picker.buttonName
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: picker.buttonName

        Image {
            id: avatarImage
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: width
            visible: picker.avatar.kind === "image" && status === Image.Ready
            source: picker.avatar.kind === "image" ? picker.avatar.source : ""
            sourceSize.width: width
            sourceSize.height: height
            fillMode: Image.PreserveAspectFit
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: width
            visible: !avatarImage.visible
            source: picker.avatar.kind === "icon" ? picker.avatar.source : "user-identity"
            opacity: picker.avatar.kind === "icon" ? 1 : 0.35
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
        objectName: picker.prefix + "Status"
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        wrapMode: Text.Wrap
        color: picker.error !== "" || avatarImage.status === Image.Error ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
        text: picker.error !== "" ? picker.error
            : avatarImage.status === Image.Error ? i18n("This picture can't be read; no avatar is shown.")
            : picker.value === "" ? i18n("None")
            : picker.avatar.kind === "image" ? picker.value.substring(picker.value.lastIndexOf("/") + 1)
            : picker.value
    }
}
