// A picture shown large over the chat, with its buttons. Click anywhere
// outside it, press Escape or Close to leave. The buttons are those of
// MessageImages.qml (the same actions), so they sit in one place.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QQC2.Popup {
    id: viewer

    property url source
    property string caption: ""
    property bool canRegenerate: false
    // Which image of the message is shown (for the buttons' signals).
    property int index: -1

    signal copyRequested()
    signal downloadRequested()
    signal regenerateRequested()

    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    width: parent ? Math.round(parent.width * 0.94) : 400
    height: parent ? Math.round(parent.height * 0.92) : 400
    modal: true
    focus: true
    dim: true
    padding: Kirigami.Units.smallSpacing
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Image {
            id: picture
            objectName: "viewerImage"
            Layout.fillWidth: true
            Layout.fillHeight: true
            source: viewer.visible ? viewer.source : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            // A very large picture is not decoded at full size just to be shown on screen.
            sourceSize.width: 2048
            sourceSize.height: 2048
        }

        QQC2.Label {
            objectName: "viewerCaption"
            Layout.fillWidth: true
            visible: viewer.caption !== ""
            text: viewer.caption
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font: Kirigami.Theme.smallFont
            opacity: 0.8
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                objectName: "viewerCopy"
                text: i18n("Copy image")
                icon.name: "edit-copy"
                onClicked: viewer.copyRequested()
            }
            QQC2.Button {
                objectName: "viewerDownload"
                text: i18n("Download")
                icon.name: "document-save"
                onClicked: viewer.downloadRequested()
            }
            QQC2.Button {
                objectName: "viewerRegenerate"
                visible: viewer.canRegenerate
                text: i18n("Regenerate")
                icon.name: "view-refresh"
                onClicked: { viewer.close(); viewer.regenerateRequested(); }
            }
            Item { Layout.fillWidth: true }
            QQC2.Button {
                objectName: "viewerClose"
                text: i18n("Close")
                icon.name: "dialog-close"
                onClicked: viewer.close()
            }
        }
    }
}
