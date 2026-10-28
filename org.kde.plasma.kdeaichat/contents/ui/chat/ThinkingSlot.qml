// Above an assistant reply's text: the activity box (ActivityBox.qml) for direct
// and Pi replies, or OpenCode's own "Thinking" block (ReasoningBlock.qml). A chat
// never changes mode, so the open chat's mode decides.
import QtQuick
import "Activity.js" as Activity
// Properties of the components made here (and i18n()) are seen only at runtime.
// qmllint disable unqualified

Loader {
    id: slot

    property var chat: null
    property var message: ({})
    property bool streaming: false
    property bool editing: false

    // OpenCode's thinking: what streams, else what the message kept.
    readonly property string openCodeReasoning: streaming && chat.currentStreamReasoning ? chat.currentStreamReasoning : (message.reasoning || "")
    readonly property bool isAssistant: (message.role || "") === "assistant" && !editing
    readonly property bool activityBox: isAssistant && !chat.openCodeMode
        && (Activity.hasContent(message) || (streaming && chat.currentStreamReasoning !== ""))

    active: activityBox || (isAssistant && chat.openCodeMode && openCodeReasoning !== "")
    sourceComponent: activityBox ? boxComponent : reasoningComponent

    Component {
        id: boxComponent
        ActivityBox {
            message: slot.message
            streaming: slot.streaming
            streamReasoning: slot.streaming ? slot.chat.currentStreamReasoning : ""
            writing: slot.chat.currentStreamText !== ""
        }
    }

    Component {
        id: reasoningComponent
        ReasoningBlock {
            text: slot.openCodeReasoning
            streaming: slot.streaming && slot.chat.currentStreamText === ""
        }
    }
}
