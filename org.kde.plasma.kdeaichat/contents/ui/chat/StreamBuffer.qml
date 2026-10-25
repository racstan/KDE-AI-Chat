// Holds a streamed reply's deltas and adds them to the chat's
// currentStreamText / currentStreamReasoning at most every `interval` ms,
// so the chat view updates ~30 times a second however fast tokens arrive.
// flush() before reading the stream's text (done, error, reset).
import QtQuick

QtObject {
    id: buffer

    // The chat root (main.qml): has currentStreamText and currentStreamReasoning.
    property var target: null
    property int maxChars: 2000000
    property alias interval: flushTimer.interval

    property string text: ""
    property string reasoning: ""

    property Timer _timer: Timer {
        id: flushTimer
        interval: 33
        onTriggered: buffer.flush()
    }

    // kind: "text" or "reasoning".
    function add(kind, delta) {
        if (kind === "reasoning")
            reasoning += delta;
        else
            text += delta;
        if (!flushTimer.running)
            flushTimer.start();
    }

    function _append(current: string, more: string): string {
        var joined = current + more;
        return joined.length > maxChars ? joined.substring(0, maxChars) : joined;
    }

    function flush() {
        flushTimer.stop();
        if (text)
            target.currentStreamText = _append(target.currentStreamText, text);
        if (reasoning)
            target.currentStreamReasoning = _append(target.currentStreamReasoning, reasoning);
        text = "";
        reasoning = "";
    }

    // Drops what's waiting (a new reply or chat).
    function clear() {
        flushTimer.stop();
        text = "";
        reasoning = "";
    }
}
