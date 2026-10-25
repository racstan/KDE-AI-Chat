// A message's text. While the reply streams it's one plain-text block that
// grows; once done it's split into Markdown text and code blocks, built
// once per change of the message (not per streamed token).
import QtQuick
import org.kde.kirigami as Kirigami
import "MessageBlocks.js" as MessageBlocks

Column {
    id: body

    property var chat: null
    property int messageIndex: -1
    property string text: ""
    property bool streaming: false
    property bool isError: false

    signal selectionMade(string text)

    spacing: Kirigami.Units.smallSpacing

    readonly property var blocks: streaming ? [] : (isError ? [{"type": "text", "text": body.text}] : MessageBlocks.split(body.text))

    MessageText {
        visible: body.streaming
        width: body.width
        chat: body.chat
        messageIndex: body.messageIndex
        plain: true
        text: body.streaming ? body.text : ""
    }

    Repeater {
        model: body.blocks

        delegate: Loader {
            required property var modelData
            width: body.width
            sourceComponent: modelData.type === "code" ? codeComponent : textComponent

            Component {
                id: textComponent
                MessageText {
                    chat: body.chat
                    messageIndex: body.messageIndex
                    isError: body.isError
                    text: modelData.text
                    onSelectionMade: (text) => body.selectionMade(text)
                }
            }

            Component {
                id: codeComponent
                CodeBlock {
                    chat: body.chat
                    language: modelData.language
                    code: modelData.text
                    onSelectionMade: (text) => body.selectionMade(text)
                }
            }
        }
    }
}
