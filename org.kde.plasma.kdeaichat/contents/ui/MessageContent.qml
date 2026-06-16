import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "Security.js" as Sec

Column {
    id: contentRoot

    property var messageData
    property var chatRoot
    property int messageIndex: -1

    visible: messageData && (chatRoot && chatRoot.editingMessageIndex !== messageIndex || messageData.role === "error" || messageData.isImage === true)
    width: parent ? parent.width : 0
    spacing: 4

    Text {
        visible: contentRoot.messageData && contentRoot.messageData.role === "error"
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: contentRoot.messageData ? (contentRoot.messageData.content || "") : ""
        color: Kirigami.Theme.negativeTextColor
        font: Kirigami.Theme.defaultFont
    }

    // Image generation display
    Column {
        visible: contentRoot.messageData && contentRoot.messageData.isImage === true
        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            text: {
                let prov = contentRoot.messageData ? (contentRoot.messageData.imageProvider || "") : "";
                let names = {"pollinations": "Pollinations.ai", "huggingface-image": "HuggingFace", "together-image": "Together AI"};
                return names[prov] || prov;
            }
            font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
            font.italic: true
            color: Kirigami.Theme.disabledTextColor
        }

        Rectangle {
            width: Math.min(parent.width, 512)
            height: chatImage.status === Image.Ready ? chatImage.implicitHeight : (chatImage.status === Image.Loading ? 300 : 0)
            radius: 6
            color: contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "#2d3139" : "#f0f2f5"
            border.width: 1
            border.color: contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "#3e4452" : "#d0d4dc"
            clip: true

            Image {
                id: chatImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                source: (contentRoot.messageData && contentRoot.messageData.isImage === true) ? (contentRoot.messageData.imageUrl || "") : ""
                asynchronous: true
                cache: true

                QQC2.BusyIndicator {
                    anchors.centerIn: parent
                    running: chatImage.status === Image.Loading
                    width: Kirigami.Units.gridUnit * 3
                    height: Kirigami.Units.gridUnit * 3
                }

                QQC2.Label {
                    anchors.centerIn: parent
                    visible: chatImage.status === Image.Error
                    text: contentRoot.chatRoot ? contentRoot.chatRoot.translate("Failed to load image") : "Failed to load image"
                    color: Kirigami.Theme.negativeTextColor
                }
            }
        }

        PC3.ToolButton {
            icon.name: "download"
            display: PC3.AbstractButton.TextBesideIcon
            flat: true
            text: contentRoot.chatRoot ? contentRoot.chatRoot.translate("Save image") : "Save image"
            visible: contentRoot.messageData && contentRoot.messageData.imageUrl !== ""
            onClicked: {
                if (contentRoot.chatRoot && contentRoot.chatRoot.msgListViewRef) {
                    let url = contentRoot.messageData.imageUrl || "";
                    if (url.indexOf("data:") === 0) {
                        let cmd = "python3 -c \"import base64,sys; d=sys.stdin.buffer.read(); open('/tmp/kdeaichat_img.png','wb').write(base64.b64decode(d.split(',')[1]))\" <<< '" + url.split(",")[1] + "'";
                        contentRoot.chatRoot.customStorageDs.connectSource(cmd + " #save-img-" + Date.now());
                    } else {
                        Qt.openUrlExternally(url);
                    }
                }
            }
        }
    }

    // Quoted message bubble (if present)
    Rectangle {
        visible: !!(contentRoot.messageData && contentRoot.messageData.quote)
        width: parent.width
        implicitHeight: quoteCol.implicitHeight + Kirigami.Units.smallSpacing * 2
        radius: 6
        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2)

        RowLayout {
            id: quoteCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "mail-reply-sender"
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                color: Kirigami.Theme.highlightColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                PC3.Label {
                    text: {
                        if (!contentRoot.messageData || !contentRoot.messageData.quote) return "";
                        let q = contentRoot.messageData.quote;
                        let sender = q.role === "assistant" ? (q.model || "Assistant") : "User";
                        return "Replying to @" + sender;
                    }
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
                    color: Kirigami.Theme.highlightColor
                }

                PC3.Label {
                    Layout.fillWidth: true
                    text: contentRoot.messageData && contentRoot.messageData.quote ? contentRoot.messageData.quote.content : ""
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.italic: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
                    opacity: 0.8
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (contentRoot.messageData && contentRoot.messageData.quote && contentRoot.messageData.quote.at) {
                    let targetAt = contentRoot.messageData.quote.at;
                    if (contentRoot.chatRoot) {
                        contentRoot.chatRoot.scrollToMessageByTimestamp(targetAt);
                    }
                }
            }
        }
    }

    // Main text content rendering as RichText
    Text {
        id: mainTextEdit

        visible: contentRoot.messageData
                 && contentRoot.messageData.role !== "error"
                 && contentRoot.messageData.role !== "schedules_list"
                 && contentRoot.messageData.isImage !== true
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.RichText
        text: {
            if (!visible) return "";
            let darkKey = contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "dark" : "light";
            if (contentRoot.messageData.contentHtmlCache && contentRoot.messageData.contentHtmlCache[darkKey] !== undefined) {
                return contentRoot.messageData.contentHtmlCache[darkKey];
            }
            if (contentRoot.chatRoot) {
                let html = contentRoot.chatRoot.convertMarkdownToHtml(contentRoot.messageData.content || "");
                if (!contentRoot.messageData.contentHtmlCache) {
                    contentRoot.messageData.contentHtmlCache = {};
                }
                contentRoot.messageData.contentHtmlCache[darkKey] = html;
                return html;
            }
            return contentRoot.messageData.content || "";
        }
        color: Kirigami.Theme.textColor
        font: Kirigami.Theme.defaultFont
        selectByMouse: true
        onLinkActivated: function(link) {
            let safe = Sec.validateUrl(link);
            if (safe !== "")
                Qt.openUrlExternally(safe);
        }
    }
}
