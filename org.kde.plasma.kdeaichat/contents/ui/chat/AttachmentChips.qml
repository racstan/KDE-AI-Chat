// A message's attachments as small chips; clicking one opens the file.
// Images show a thumbnail decoded at chip size, other files an icon.
import QtQuick
import QtCore
import "DisplayPath.js" as Paths
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../Security.js" as Sec

Flow {
    id: chips

    property var chat: null
    property var attachments: []
    // Your messages' chips sit at the right.
    property bool alignRight: false

    // The attachments with `stored`: the file:// address of their saved copy ("" when none).
    readonly property var shown: (attachments || []).map(function(att) { return Object.assign({"stored": chips.storedUrl(att)}, att); })

    // file:// address of the attachment's saved copy in the chat folder ("" when it has none).
    function storedUrl(att) {
        var dir = chips.chat && chips.chat.chatStore ? String(chips.chat.chatStore.directory || "") : "";
        return dir !== "" && att && /^attachments\/[A-Za-z0-9._-]+\/[0-9a-f]{64}\.[a-z0-9]{1,8}$/.test(String(att.file || ""))
            ? "file://" + encodeURI(dir + "/" + att.file) : "";
    }

    layoutDirection: alignRight ? Qt.RightToLeft : Qt.LeftToRight

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: chips.shown

        delegate: QQC2.AbstractButton {
            id: chip

            required property var modelData
            readonly property bool isImage: modelData.type === "image"

            implicitWidth: Math.min(Kirigami.Units.gridUnit * 10, row.implicitWidth + Kirigami.Units.smallSpacing * 2)
            implicitHeight: Kirigami.Units.gridUnit * 1.5
            hoverEnabled: true
            Accessible.name: i18n("Open %1", modelData.name || "")
            QQC2.ToolTip.visible: hovered && !!modelData.path
            QQC2.ToolTip.text: modelData.path ? Paths.tilde(modelData.path, StandardPaths.writableLocation(StandardPaths.HomeLocation)) : ""
            onClicked: {
                if (modelData.stored !== "") {
                    Qt.openUrlExternally(modelData.stored);
                    return;
                }
                var safe = Sec.validateFilePath(modelData.path || "");
                if (safe)
                    Qt.openUrlExternally(Sec.fileUrl(safe));
            }

            background: Rectangle {
                radius: Kirigami.Units.cornerRadius
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, chip.hovered ? 0.1 : 0.05)
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
            }

            contentItem: RowLayout {
                id: row
                spacing: Kirigami.Units.smallSpacing

                Image {
                    visible: chip.isImage
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    sourceSize.width: Kirigami.Units.iconSizes.small * 2
                    sourceSize.height: Kirigami.Units.iconSizes.small * 2
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    source: !chip.isImage ? "" : chip.modelData.content
                        ? "data:" + (chip.modelData.mimeType || "image/png") + ";base64," + chip.modelData.content
                        : (chip.modelData.stored !== "" ? chip.modelData.stored
                           : (chip.modelData.path ? "file://" + chip.modelData.path : ""))
                }

                Kirigami.Icon {
                    visible: !chip.isImage
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    source: chips.chat ? chips.chat.fileIconName(chip.modelData.name) : "text-x-generic"
                }

                PC3.Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: chip.modelData.name || ""
                    elide: Text.ElideMiddle
                    font: Kirigami.Theme.smallFont
                }
            }
        }
    }
}
