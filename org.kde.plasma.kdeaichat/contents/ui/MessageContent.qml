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
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "Security.js" as Sec

Column {
    id: contentRoot

    property var messageData
    property var root
    property int messageIndex: -1

    visible: messageData && (root.editingMessageIndex !== messageIndex || messageData.role === "error")
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

    Repeater {
        visible: contentRoot.messageData && contentRoot.messageData.role !== "error" && contentRoot.messageData.role !== "schedules_list"
        width: parent.width
        model: contentRoot.messageData && contentRoot.messageData.role !== "error" && contentRoot.messageData.role !== "schedules_list"
            ? contentRoot.root.parseMessageBlocks(contentRoot.messageData.content || "")
            : []

        delegate: Item {
            required property var modelData

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
                text: contentRoot.root.convertMarkdownToHtml(modelData.content || "")
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
                    color: contentRoot.root.popupIsDark ? "#2d3139" : "#f0f2f5"
                    border.width: 1
                    border.color: contentRoot.root.popupIsDark ? "#3e4452" : "#d0d4dc"
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
                            color: contentRoot.root.popupIsDark ? "#5c6370" : "#a0a1a7"
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
                                if (contentRoot.root.clipboardHelper) {
                                    contentRoot.root.clipboardHelper.text = modelData.content;
                                    contentRoot.root.clipboardHelper.selectAll();
                                    contentRoot.root.clipboardHelper.copy();
                                }
                            }
                        }
                    }

                    Rectangle {
                        y: codeLangRow.height
                        width: parent.width
                        height: 1
                        color: contentRoot.root.popupIsDark ? "#3e4452" : "#d0d4dc"
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
                        color: contentRoot.root.popupIsDark ? "#abb2bf" : "#383a42"
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
                                let csv = contentRoot.root.tableMarkdownToCsv(modelData.content || "");
                                if (contentRoot.root.clipboardHelper) {
                                    contentRoot.root.clipboardHelper.text = csv;
                                    contentRoot.root.clipboardHelper.selectAll();
                                    contentRoot.root.clipboardHelper.copy();
                                }
                                if (contentRoot.root.customStorageDs) {
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
                                    contentRoot.root.customStorageDs.connectSource("bash -c " + Sec.quoteForShell("printf '%s' " + safeCsv + " > " + safePath + " && xdg-open " + safePath) + " #csv-export-" + ts);
                                }
                            }
                        }
                    }

                    TextEdit {
                        width: parent.width
                        wrapMode: Text.Wrap
                        textFormat: Text.RichText
                        text: contentRoot.root.convertMarkdownToHtml(modelData.content || "")
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
