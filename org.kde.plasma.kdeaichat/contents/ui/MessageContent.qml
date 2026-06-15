/**
 * MessageContent — render the body of a single chat message.
 *
 * Takes a message object and renders its text/code/table blocks. Used
 * inside the chat list delegate of main.qml. Keeping this in its own
 * file reduces the size of main.qml and makes the per-block rendering
 * (markdown, code, table) easier to test in isolation.
 *
 * Required caller properties (read via the `root` reference):
 *   - `convertMarkdownToHtml(string)` -> string
 *   - `parseMessageBlocks(string)`    -> Array<{type, content, lang}>
 *   - `tableMarkdownToCsv(string)`    -> string
 *   - `popupIsDark` (property)        -> bool
 *   - `clipboardHelper` (TextEdit)    -> used for the copy-code button
 *   - `customStorageDs` (DataSource)  -> used for the CSV export action
 *   - `translate(string)` (optional)  -> localized strings
 */
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

    TextEdit {
        visible: contentRoot.messageData && contentRoot.messageData.role === "error"
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: contentRoot.messageData ? (contentRoot.messageData.content || "") : ""
        color: Kirigami.Theme.negativeTextColor
        readOnly: true
        selectByMouse: true
        selectByKeyboard: true
        selectedTextColor: Kirigami.Theme.highlightedTextColor
        selectionColor: Kirigami.Theme.highlightColor
        font: Kirigami.Theme.defaultFont
    }

    // Image generation display
    Column {
        visible: contentRoot.messageData && contentRoot.messageData.isImage === true
        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            text: {
                let prov = contentRoot.messageData.imageProvider || "";
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
                source: contentRoot.messageData.imageUrl || ""
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
                    text: root.translate("Failed to load image")
                    color: Kirigami.Theme.negativeTextColor
                }
            }
        }

        PC3.ToolButton {
            icon.name: "download"
            display: PC3.AbstractButton.TextBesideIcon
            flat: true
            text: root.translate("Save image")
            visible: contentRoot.messageData.imageUrl !== ""
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

    Repeater {
        visible: contentRoot.messageData && contentRoot.messageData.role !== "error" && contentRoot.messageData.role !== "schedules_list"
        width: parent.width
        model: contentRoot.messageData && contentRoot.messageData.isImage !== true && contentRoot.messageData.role !== "error" && contentRoot.messageData.role !== "schedules_list"
            ? (contentRoot.messageData.blocks || (contentRoot.chatRoot ? contentRoot.chatRoot.parseMessageBlocks(contentRoot.messageData.content || "") : []))
            : []

        delegate: Item {
            required property var modelData
            onModelDataChanged: {
                if (htmlEdit) htmlEdit.htmlContent = "";
            }

            width: parent ? parent.width : 0
            implicitHeight: modelData.type === "code" ? codeLoader.implicitHeight
                : modelData.type === "table" ? tableBlock.implicitHeight
                : htmlEdit.implicitHeight

            TextEdit {
                id: htmlEdit

                visible: modelData.type === "text"
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                property string htmlContent: ""
                text: {
                    let darkKey = contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "dark" : "light";
                    if (modelData.contentHtmlCache && modelData.contentHtmlCache[darkKey] !== undefined) {
                        return modelData.contentHtmlCache[darkKey];
                    }
                    if (htmlContent !== "") {
                        return htmlContent;
                    }
                    parseHtmlTimer.restart();
                    return "<i>Loading...</i>";
                }

                Timer {
                    id: parseHtmlTimer
                    interval: 25
                    running: false
                    onTriggered: {
                        let darkKey = contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "dark" : "light";
                        if (contentRoot.chatRoot) {
                            let html = contentRoot.chatRoot.convertMarkdownToHtml(modelData.content || "");
                            if (!modelData.contentHtmlCache) {
                                modelData.contentHtmlCache = {};
                            }
                            modelData.contentHtmlCache[darkKey] = html;
                            htmlEdit.htmlContent = html;
                        }
                    }
                }
                color: Kirigami.Theme.textColor
                readOnly: true
                selectByMouse: true
                selectByKeyboard: true
                selectedTextColor: Kirigami.Theme.highlightedTextColor
                selectionColor: Kirigami.Theme.highlightColor
                font: Kirigami.Theme.defaultFont
                onLinkActivated: function(link) {
                    // Only open URLs with a safe scheme. Anything else
                    // (javascript:, data:, file:, custom schemes) is
                    // dropped here as well as in the markdown renderer.
                    let safe = Sec.validateUrl(link);
                    if (safe !== "")
                        Qt.openUrlExternally(safe);
                }
            }

            Item {
                id: codeLoader

                visible: modelData.type === "code"
                width: parent.width
                implicitHeight: codeContainer.implicitHeight + 2

                Rectangle {
                    id: codeContainer

                    width: parent.width
                    implicitHeight: codeLangRow.implicitHeight + codeBody.implicitHeight + Kirigami.Units.smallSpacing * 3
                    radius: 6
                    color: contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "#2d3139" : "#f0f2f5"
                    border.width: 1
                    border.color: contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "#3e4452" : "#d0d4dc"
                    clip: true

                    Row {
                        id: codeLangRow

                        width: parent.width
                        height: Math.max(langLabel.implicitHeight + Kirigami.Units.smallSpacing, copyCodeBtn.implicitHeight + Kirigami.Units.smallSpacing)
                        spacing: 0

                        PC3.Label {
                            id: langLabel

                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: Kirigami.Units.smallSpacing + 4
                            text: modelData.lang || "code"
                            font.pointSize: 8
                            font.bold: true
                            color: contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "#5c6370" : "#a0a1a7"
                            width: parent.width - copyCodeBtn.width - Kirigami.Units.smallSpacing
                        }

                        PC3.ToolButton {
                            id: copyCodeBtn

                            anchors.verticalCenter: parent.verticalCenter
                            icon.name: "edit-copy"
                            display: PC3.AbstractButton.IconOnly
                            flat: true
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: "Copy code"
                            onClicked: {
                                if (contentRoot.chatRoot && contentRoot.chatRoot.clipboardHelper) {
                                    contentRoot.chatRoot.clipboardHelper.text = modelData.content;
                                    contentRoot.chatRoot.clipboardHelper.selectAll();
                                    contentRoot.chatRoot.clipboardHelper.copy();
                                }
                            }
                        }
                    }

                    Rectangle {
                        y: codeLangRow.height
                        width: parent.width
                        height: 1
                        color: contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "#3e4452" : "#d0d4dc"
                    }

                    TextEdit {
                        id: codeBody

                        y: codeLangRow.height + 1
                        width: parent.width
                        leftPadding: Kirigami.Units.smallSpacing + 4
                        rightPadding: Kirigami.Units.smallSpacing + 4
                        topPadding: Kirigami.Units.smallSpacing
                        bottomPadding: Kirigami.Units.smallSpacing
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: modelData.content
                        color: contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "#abb2bf" : "#383a42"
                        font.family: "monospace"
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
                        readOnly: true
                        selectByMouse: true
                        selectByKeyboard: true
                        selectedTextColor: Kirigami.Theme.highlightedTextColor
                        selectionColor: Kirigami.Theme.highlightColor
                    }
                }
            }

            Item {
                id: tableBlock

                visible: modelData.type === "table"
                width: parent.width
                implicitHeight: tableOuterCol.implicitHeight

                Column {
                    id: tableOuterCol

                    width: parent.width
                    spacing: 2

                    Row {
                        width: parent.width
                        layoutDirection: Qt.RightToLeft

                        PC3.ToolButton {
                            icon.name: "document-export"
                            display: PC3.AbstractButton.IconOnly
                            flat: true
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: "Export table as CSV"
                            onClicked: {
                                let csv = contentRoot.chatRoot ? contentRoot.chatRoot.tableMarkdownToCsv(modelData.content || "") : "";
                                if (contentRoot.chatRoot && contentRoot.chatRoot.clipboardHelper) {
                                    contentRoot.chatRoot.clipboardHelper.text = csv;
                                    contentRoot.chatRoot.clipboardHelper.selectAll();
                                    contentRoot.chatRoot.clipboardHelper.copy();
                                }
                                if (contentRoot.chatRoot && contentRoot.chatRoot.customStorageDs) {
                                    let ts = new Date().getTime();
                                    // Use a sanitized timestamp inside a
                                    // hard-coded prefix; the path is then
                                    // routed through validateFilePath to
                                    // reject any unexpected characters.
                                    let path = "/tmp/kdeaichat-table-" + ts + ".csv";
                                    let safePath = Sec.validateFilePath(path);
                                    if (safePath === "")
                                        return;
                                    let safeCsv = Sec.sanitizeForShell(csv);
                                    contentRoot.chatRoot.customStorageDs.connectSource("bash -c " + Sec.quoteForShell("printf '%s' " + safeCsv + " > " + safePath + " && xdg-open " + safePath) + " #csv-export-" + ts);
                                }
                            }
                        }
                    }

                    TextEdit {
                        width: parent.width
                        wrapMode: Text.Wrap
                        textFormat: Text.RichText
                        text: {
                            let darkKey = contentRoot.chatRoot && contentRoot.chatRoot.popupIsDark ? "dark" : "light";
                            if (modelData.contentHtmlCache && modelData.contentHtmlCache[darkKey] !== undefined) {
                                return modelData.contentHtmlCache[darkKey];
                            }
                            if (contentRoot.chatRoot) {
                                let html = contentRoot.chatRoot.convertMarkdownToHtml(modelData.content || "");
                                if (!modelData.contentHtmlCache) {
                                    modelData.contentHtmlCache = {};
                                }
                                modelData.contentHtmlCache[darkKey] = html;
                                return html;
                            }
                            return "";
                        }
                        color: Kirigami.Theme.textColor
                        readOnly: true
                        selectByMouse: true
                        selectByKeyboard: true
                        selectedTextColor: Kirigami.Theme.highlightedTextColor
                        selectionColor: Kirigami.Theme.highlightColor
                        onLinkActivated: function(link) {
                            let safe = Sec.validateUrl(link);
                            if (safe !== "")
                                Qt.openUrlExternally(safe);
                        }
                    }
                }
            }
        }
    }
}
