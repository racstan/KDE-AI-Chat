// A message's text. While the reply streams it's plain text that grows
// (StreamingText.qml); once done it's split into Markdown text and code blocks, built
// once per change of the message (not per streamed token).
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import "MessageBlocks.js" as MessageBlocks
import "ImageExtract.js" as ImageExtract

Column {
    id: body

    property var chat: null
    property int messageIndex: -1
    property string text: ""
    property bool streaming: false
    property bool isError: false
    // The width the text wraps at, set before the layout gives this its
    // width, so the height is right as soon as it's created.
    property real textWidth: width
    // For code blocks' copy buttons (see MessageActions.qml).
    property var builder: null
    property real buttonHeight: 0
    property bool alignRight: false

    signal selectionMade(string text)

    spacing: Kirigami.Units.smallSpacing

    readonly property var blocks: streaming ? [] : (isError ? [{"type": "text", "text": body.text}] : MessageBlocks.split(body.text))

    StreamingText {
        visible: body.streaming
        width: body.textWidth
        chat: body.chat
        messageIndex: body.messageIndex
        text: body.streaming ? body.text : ""
    }

    Repeater {
        model: body.blocks

        delegate: Loader {
            required property var modelData
            width: body.textWidth
            sourceComponent: modelData.type === "code" ? codeComponent : textComponent

            Component {
                id: textComponent
                MessageText {
                    chat: body.chat
                    messageIndex: body.messageIndex
                    alignRight: body.alignRight
                    // Markdown image links are never rendered (Qt would fetch them by itself):
                    // a placeholder shows, and MessageImages.qml offers to load the picture.
                    text: ImageExtract.extractMarkdown(modelData.text).text
                    onSelectionMade: (text) => body.selectionMade(text)
                }
            }

            Component {
                id: codeComponent
                CodeBlock {
                    chat: body.chat
                    buttonHeight: body.buttonHeight
                    builder: body.builder
                    language: modelData.language
                    code: modelData.text
                    onSelectionMade: (text) => body.selectionMade(text)
                }
            }
        }
    }
}
