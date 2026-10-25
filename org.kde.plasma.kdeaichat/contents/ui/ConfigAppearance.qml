// Settings → Appearance: the widget's name and icon, which desktop
// notifications to show, and the sound played when a reply finishes. Colours always follow the Plasma colour scheme.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    // A KDE icon name, or the path of an image file (animated GIFs work).
    property string cfg_customIcon: "dialog-messages"
    property alias cfg_appDisplayName: nameField.text
    property alias cfg_playNotificationSound: soundCheck.checked
    property alias cfg_notifyOnReply: replyCheck.checked
    property alias cfg_notifyOnError: errorCheck.checked
    property alias cfg_notifyOnScheduled: scheduledCheck.checked

    readonly property string defaultIcon: "dialog-messages"

    function isCustomIconImage(value) {
        var v = String(value || "").trim().toLowerCase();
        if (v.indexOf("file://") === 0 || v.charAt(0) === "/")
            return true;
        return /\.(png|jpe?g|gif|webp|svgz?|bmp)$/.test(v);
    }

    function customIconImageSource(value) {
        var v = String(value || "").trim();
        return v === "" || v.indexOf("file://") === 0 ? v : "file://" + v;
    }

    Component {
        id: iconDialogComponent
        KIconThemes.IconDialog {
            onIconNameChanged: function(iconName) {
                if (iconName)
                    page.cfg_customIcon = iconName;
            }
        }
    }
    property var iconDialog: null

    FileDialog {
        id: imageDialog
        title: i18n("Choose an Image for the Widget")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.webp *.gif *.svg *.svgz *.bmp)")]
        onAccepted: page.cfg_customIcon = decodeURIComponent(String(selectedFile).replace(/^file:\/\//, ""))
    }

    Kirigami.FormLayout {
        QQC2.TextField {
            id: nameField
            Kirigami.FormData.label: i18n("Name:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            placeholderText: "KDE AI Chat"
        }

        QQC2.Button {
            id: iconButton
            Kirigami.FormData.label: i18n("Icon:")
            implicitWidth: Kirigami.Units.iconSizes.large + Kirigami.Units.largeSpacing * 2
            implicitHeight: implicitWidth
            onPressed: iconMenu.opened ? iconMenu.close() : iconMenu.popup(iconButton, 0, iconButton.height)
            Accessible.name: i18n("Choose the widget icon")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Choose the widget icon")

            Image {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                visible: page.isCustomIconImage(page.cfg_customIcon)
                source: visible ? page.customIconImageSource(page.cfg_customIcon) : ""
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                visible: !page.isCustomIconImage(page.cfg_customIcon)
                source: page.cfg_customIcon || page.defaultIcon
            }

            QQC2.Menu {
                id: iconMenu
                QQC2.MenuItem {
                    text: i18n("Choose Icon…")
                    icon.name: "document-open-folder"
                    onTriggered: {
                        if (!page.iconDialog)
                            page.iconDialog = iconDialogComponent.createObject(page);
                        page.iconDialog.open();
                    }
                }
                QQC2.MenuItem {
                    text: i18n("Choose Image File…")
                    icon.name: "image-x-generic"
                    onTriggered: imageDialog.open()
                }
                QQC2.MenuItem {
                    text: i18n("Reset to Default Icon")
                    icon.name: "edit-clear"
                    enabled: page.cfg_customIcon !== page.defaultIcon
                    onTriggered: page.cfg_customIcon = page.defaultIcon
                }
            }
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Notifications")
        }

        QQC2.CheckBox {
            id: replyCheck
            objectName: "notifyReplyCheck"
            Kirigami.FormData.label: i18n("Notify when:")
            text: i18n("A reply finishes while the chat is closed")
        }

        QQC2.CheckBox {
            id: errorCheck
            objectName: "notifyErrorCheck"
            text: i18n("A request fails while the chat is closed")
        }

        QQC2.CheckBox {
            id: scheduledCheck
            objectName: "notifyScheduledCheck"
            text: i18n("A scheduled task runs")
        }

        QQC2.CheckBox {
            id: soundCheck
            objectName: "soundCheck"
            Kirigami.FormData.label: i18n("Sound:")
            text: i18n("Play a sound when a reply is finished")
        }
    }
}
