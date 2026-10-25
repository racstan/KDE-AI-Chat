// Builds the parts of messages that can wait (the Plasma tool buttons, a
// few ms each) after the frame that shows the messages, a few at a time,
// so opening a long chat doesn't wait for them and no frame takes long.
//
// A part has buildStep(), which builds one more piece and returns false
// when the part is complete, and calls remove() when it's destroyed. Parts are built in the order they were added
// (the chat view creates the newest messages first).
import QtQuick

Timer {
    id: builder

    // Building time per turn, in ms (a frame is ~16 ms).
    property int sliceMs: 6
    property var queue: []

    function add(part) {
        queue.push(part);
        if (!running)
            start();
    }

    // From the part's Component.onDestruction (a message scrolled away).
    function remove(part) {
        var at = queue.indexOf(part);
        if (at >= 0)
            queue.splice(at, 1);
    }

    interval: 1
    repeat: true
    onTriggered: {
        var start = Date.now();
        while (queue.length > 0 && Date.now() - start < sliceMs) {
            if (!queue[0].buildStep())
                queue.shift();
        }
        if (queue.length === 0)
            stop();
    }
}
