// The pictures of a message: saved images (a model's or an image service's)
// with Enlarge, Copy image, Download and, for generated ones, Regenerate,
// and the images the reply links to as Markdown, which load only when you
// click (the widget never fetches an address a model chose by itself).
//
// The images are files in the chat's folder (chat/ImageStore.qml); `message.images`
// holds paths and notes, never the picture itself.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import "../Security.js" as Sec
import "ImageExtract.js" as ImageExtract
// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: gallery

    property var chat: null
    // chat/ImageStore.qml (a test can pass a fake).
    property var store: chat ? chat.imageStore : null
    property var message: ({})
    property bool alignRight: false

    readonly property var images: message.images || []
    // The Markdown image links in the reply that are not loaded yet: [{index, alt, url}].
    readonly property var links: pendingLinks(message.content, images)
    // The last thing a button did ("" when nothing to say) and its kind ("info" or "error").
    property string note: ""
    property string noteKind: "info"
    property string loadingLink: ""
    property int dialogImage: -1
    property alias saveDialog: saveDialogItem
    property alias viewer: viewerPopup   // the large picture's popup

    function pendingLinks(content, saved) {
        var found = ImageExtract.extractMarkdown(content, function(url) { return Sec.validateImageUrl(url) !== ""; }).links;
        var done = {};
        for (var i = 0; i < saved.length; i++) {
            if (saved[i].source === "link")
                done[saved[i].linkIndex] = true;
        }
        var out = [];
        for (var j = 0; j < found.length; j++) {
            if (!done[j])
                out.push({"index": j, "alt": found[j].alt, "url": found[j].url});
        }
        return out;
    }

    function hostOf(url) {
        var m = /^https:\/\/([^/:?#]+)/i.exec(String(url || ""));
        return m ? m[1] : "";
    }

    function captionOf(image) {
        var parts = [];
        if (image.prompt) parts.push(image.prompt);
        var facts = [];
        if (image.service) facts.push(image.service);
        if (image.model) facts.push(image.model);
        if (image.width && image.height) facts.push(image.width + "×" + image.height);
        if (image.seed !== undefined && image.seed !== "") facts.push(i18n("seed %1", image.seed));
        if (facts.length > 0) parts.push(facts.join(" · "));
        return parts.join("\n");
    }

    function say(text, kind) {
        note = text;
        noteKind = kind || "info";
        noteTimer.restart();
    }

    function copy(index) {
        gallery.store.copyImage(gallery.images[index].path, function(ok, text) {
            gallery.say(ok ? i18n("Image copied.") : text, ok ? "info" : "error");
        });
    }

    function download(index) {
        dialogImage = index;
        var path = String(gallery.images[index].path || "");
        saveDialogItem.currentFolder = StandardPaths.writableLocation(StandardPaths.PicturesLocation);
        saveDialogItem.currentFile = saveDialogItem.currentFolder + "/" + (path.split("/").pop() || "image.png");
        saveDialogItem.open();
    }

    function regenerate(index) {
        gallery.store.regenerate(gallery.message.id, index);
    }

    function loadLink(link) {
        loadingLink = link.url;
        gallery.store.loadLink(gallery.chat.currentSessionId, gallery.message.id, link.index, link, function(ok, error) {
            gallery.loadingLink = "";
            if (!ok)
                gallery.say(error, "error");
        });
    }

    spacing: Kirigami.Units.smallSpacing
    visible: images.length > 0 || links.length > 0

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        layoutDirection: gallery.alignRight ? Qt.RightToLeft : Qt.LeftToRight

        Repeater {
            model: gallery.images

            delegate: ColumnLayout {
                id: tile
                required property var modelData
                required property int index
                readonly property real wanted: gallery.images.length === 1 ? 360 : 220
                width: Math.max(80, Math.min(wanted, gallery.width))
                spacing: 2

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(picture.implicitHeight > 0 && picture.implicitWidth > 0
                        ? width * picture.implicitHeight / picture.implicitWidth : width * 0.7, 420)
                    radius: Kirigami.Units.cornerRadius
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
                    border.width: 1
                    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                    clip: true

                    Image {
                        id: picture
                        objectName: "messageImage"
                        anchors.fill: parent
                        anchors.margins: 1
                        source: gallery.store ? gallery.store.urlFor(tile.modelData.path) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize.width: 600
                        Accessible.name: tile.modelData.prompt ? i18n("Image: %1", tile.modelData.prompt) : i18n("Image")
                    }

                    QQC2.Label {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.largeSpacing * 2
                        visible: picture.status === Image.Error
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: i18n("This image file is missing or can't be shown.")
                        opacity: 0.7
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: gallery.openViewer(tile.index)
                        QQC2.ToolTip.visible: containsMouse && gallery.captionOf(tile.modelData) !== ""
                        QQC2.ToolTip.text: gallery.captionOf(tile.modelData)
                        hoverEnabled: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    QQC2.ToolButton {
                        objectName: "enlargeButton"
                        icon.name: "zoom-in"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Enlarge")
                        onClicked: gallery.openViewer(tile.index)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: text
                    }
                    QQC2.ToolButton {
                        objectName: "copyImageButton"
                        icon.name: "edit-copy"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Copy image")
                        onClicked: gallery.copy(tile.index)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: text
                    }
                    QQC2.ToolButton {
                        objectName: "downloadButton"
                        icon.name: "document-save"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Download")
                        onClicked: gallery.download(tile.index)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: text
                    }
                    QQC2.ToolButton {
                        objectName: "regenerateImageButton"
                        visible: !!tile.modelData.service && !!tile.modelData.prompt
                        icon.name: "view-refresh"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Regenerate")
                        onClicked: gallery.regenerate(tile.index)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18n("Regenerate: same prompt, a new image")
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    // Images the reply links to: nothing is fetched until you click.
    Repeater {
        model: gallery.links

        delegate: QQC2.Button {
            id: linkButton
            required property var modelData
            objectName: "imageLinkButton"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            enabled: gallery.loadingLink === ""
            icon.name: "image-x-generic"
            text: i18n("Show image from %1", gallery.hostOf(modelData.url))
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("The reply links to this picture. It is only loaded if you click. The website will see your connection.")
            onClicked: gallery.loadLink(modelData)
        }
    }

    QQC2.Label {
        textFormat: Text.PlainText
        objectName: "imageNote"
        Layout.fillWidth: true
        visible: gallery.note !== ""
        text: gallery.note
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        color: gallery.noteKind === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
    }

    Timer {
        id: noteTimer
        interval: 8000
        onTriggered: gallery.note = ""
    }

    function openViewer(index) {
        var image = gallery.images[index];
        viewerPopup.index = index;
        viewerPopup.source = gallery.store.urlFor(image.path);
        viewerPopup.caption = gallery.captionOf(image);
        viewerPopup.canRegenerate = !!image.service && !!image.prompt;
        viewerPopup.open();
    }

    ImageViewer {
        id: viewerPopup
        onCopyRequested: gallery.copy(viewerPopup.index)
        onDownloadRequested: gallery.download(viewerPopup.index)
        onRegenerateRequested: gallery.regenerate(viewerPopup.index)
    }

    FileDialog {
        id: saveDialogItem
        objectName: "saveImageDialog"
        title: i18n("Save image")
        fileMode: FileDialog.SaveFile
        nameFilters: [i18n("Images (*.png *.jpg *.webp *.gif)")]
        onAccepted: {
            var dest = decodeURIComponent(String(selectedFile).replace(/^file:\/\//, ""));
            var image = gallery.images[gallery.dialogImage];
            if (!image)
                return;
            // The saved file keeps the picture's own format, so the name ends in it.
            if (!/\.(png|jpe?g|webp|gif)$/i.test(dest))
                dest += "." + String(image.path).split(".").pop();
            gallery.store.exportImage(image.path, dest, function(ok, text) {
                gallery.say(ok ? i18n("Saved to %1", dest) : text, ok ? "info" : "error");
            });
        }
    }
}
