// Performance budget: streaming a 20k-token answer drops no frames.
//
// A fake server feeds backends/DirectBackend.js (the real SSE parser and
// <think> splitter) an OpenAI-style stream of 20,000 tokens at ~5 tokens
// per ms (far faster than any real provider), in network-sized chunks.
// Its events go through chat/StreamBuffer.qml, main.qml's real throttled
// path (FakeChat.applyDelta mirrors applyBackendEvent), into the real
// chat/ChatView.qml.
//
// What is measured:
// - Frame time: the interval between consecutive frames (frameSwapped)
//   while the reply streams. The streaming bubble's busy indicator
//   animates, so the window renders every frame; an interval over the
//   frame budget means the GUI thread was busy for longer than a frame
//   (event handling + bindings + layout + render), i.e. a dropped frame.
// - Flush cost: for each update of currentStreamText, the time from the
//   update until the next frame is swapped (the text change, the bubble's
//   relayout and the render).
// Growth: the flush cost at the end of the answer (~140,000 characters)
// compared with the start, to catch work that grows with the answer.
// Also printed: the time to render the finished reply as Markdown.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/backends/DirectBackend.js" as DirectBackend
import "PerfChat.js" as Perf

Item {
    id: root
    width: 520
    height: 640

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    Chat.ChatView {
        id: view
        anchors.fill: parent
        chat: chat
    }

    // The fake server: an XMLHttpRequest whose response grows on a timer.
    QtObject {
        id: server

        property int totalTokens: 20000
        property real tokensPerMs: 5
        property int sent: 0
        property real startedAt: 0
        property var xhr: null

        function token(i) {
            if (i % 400 === 399) return "\n```\n";
            if (i % 400 === 300) return "\n```js\n";
            return (i % 13 === 12 ? "\n" : "") + "word" + (i % 97) + " ";
        }

        function sse(text) {
            return "data: " + JSON.stringify({"choices": [{"delta": {"content": text}}]}) + "\n\n";
        }

        function makeXhr() {
            xhr = {
                "readyState": 0, "status": 0, "responseText": "",
                "onreadystatechange": null, "onerror": null, "ontimeout": null,
                "open": function() { this.readyState = 1; },
                "setRequestHeader": function() {},
                "send": function() { server.startedAt = Date.now(); feeder.start(); },
                "abort": function() { feeder.stop(); }
            };
            return xhr;
        }

        function feed() {
            var due = Math.min(totalTokens, Math.floor((Date.now() - startedAt) * tokensPerMs) + 1);
            if (due <= sent) return;
            var chunk = "";
            for (; sent < due; sent++) chunk += sse(token(sent));
            xhr.status = 200;
            xhr.responseText += chunk;
            xhr.readyState = 3;
            xhr.onreadystatechange();
            if (sent >= totalTokens) {
                feeder.stop();
                xhr.responseText += "data: [DONE]\n\n";
                xhr.readyState = 4;
                xhr.onreadystatechange();
            }
        }
    }

    Timer {
        id: feeder
        interval: 1
        repeat: true
        onTriggered: server.feed()
    }

    property bool recording: false
    property var frames: []
    property var updates: []   // {at, length, frame}
    property bool done: false

    Connections {
        target: root.Window.window
        function onFrameSwapped() {
            if (!root.recording) return;
            var now = Date.now();
            root.frames.push(now);
            for (var i = root.updates.length - 1; i >= 0 && root.updates[i].frame === 0; i--)
                root.updates[i].frame = now;
        }
    }

    Connections {
        target: chat
        function onCurrentStreamTextChanged() {
            if (root.recording)
                root.updates.push({"at": Date.now(), "length": chat.currentStreamText.length, "frame": 0});
        }
    }

    Component {
        id: streamingTextComponent
        Chat.StreamingText {
            width: 400
            chat: chat
        }
    }

    HarnessTestCase {
        name: "PerfStream"

        // The pieces of a StreamingText, top to bottom, joined back into one text.
        function shownText(stream) {
            stream.forceLayout();
            var parts = [];
            for (var i = 0; i < stream.children.length; i++)
                if (stream.children[i].getText !== undefined)
                    parts.push(stream.children[i]);
            parts.sort(function(a, b) { return a.y - b.y; });
            for (var k = 1; k < parts.length; k++)
                compare(parts[k].y, parts[k - 1].y + parts[k - 1].height, "pieces stack without gaps");
            return parts.map(function(p) { return p.getText(0, p.length).replace(/\u2029/g, "\n"); }).join("\n");
        }

        function test_0_streaming_text_shows_all_of_it() {
            var stream = streamingTextComponent.createObject(root);
            var text = "";
            for (var i = 0; i < 3000; i++) {
                text += server.token(i) + (i % 500 === 7 ? "x".repeat(2500) : "");
                if (i % 37 === 0) stream.text = text;
            }
            stream.text = text;
            compare(shownText(stream), text);
            verify(stream.frozenLength > 0 && text.length - stream.frozenLength < 4000, "only the end is in the last piece");
            stream.text = "A new reply\nwith two lines";
            compare(shownText(stream), "A new reply\nwith two lines");
            stream.text = "";
            compare(shownText(stream), "");
            stream.destroy();
        }

        readonly property real frameBudgetMs: 1000 / 60

        function intervalsOf(frames) {
            var out = [];
            for (var i = 1; i < frames.length; i++)
                out.push(frames[i] - frames[i - 1]);
            return out;
        }

        function test_stream_20k_tokens() {
            chat.messages = Perf.conversation(40).concat([
                {"id": "q", "role": "user", "content": "Write a very long answer"},
                {"id": "r", "role": "assistant", "content": "", "model": "test"}]);
            chat.currentStreamIndex = chat.messages.length - 1;
            chat.loading = true;
            tryVerify(() => !view.list.builder || !view.list.builder.running, 5000, "the buttons are built");
            wait(200);

            root.recording = true;
            DirectBackend.send({"type": "openai", "baseUrl": "http://fake", "model": "m", "messages": [],
                                "timeoutMs": 0, "xhrFactory": server.makeXhr,
                                "onEvent": function(event) {
                                    chat.applyDelta(event);
                                    if (event.type === "done") root.done = true;
                                }});
            tryVerify(() => root.done, 60000, "the stream finishes");
            wait(100);
            root.recording = false;
            screenshot(root, "perf-stream-20k");

            compare(server.sent, 20000);
            var answer = chat.currentStreamText;
            verify(answer.length > 100000, "the whole answer arrived: " + answer.length);
            verify(view.list.atYEnd, "the view followed the stream");

            var intervals = intervalsOf(root.frames);
            var costs = root.updates.filter(function(u) { return u.frame > 0; }).map(function(u) { return u.frame - u.at; });
            var part = Math.max(1, Math.floor(costs.length / 5));
            var early = Perf.median(costs.slice(0, part));
            var late = Perf.median(costs.slice(costs.length - part));
            var slow = intervals.filter(function(t) { return t > frameBudgetMs * 1.5; });
            var p95 = Perf.quantile(intervals, 0.95);
            console.log("PERF stream 20k tokens (" + answer.length + " chars) in " + (root.frames[root.frames.length - 1] - root.frames[0])
                        + " ms: " + root.frames.length + " frames, " + root.updates.length + " text updates");
            console.log("PERF frame interval ms: median " + Perf.median(intervals) + ", p95 " + p95
                        + ", p99 " + Perf.quantile(intervals, 0.99) + ", max " + Perf.max(intervals)
                        + "; over " + (frameBudgetMs * 1.5).toFixed(1) + " ms: " + slow.length + " [" + slow.slice(0, 20).join(", ") + "]");
            console.log("PERF update-to-frame ms: median " + Perf.median(costs) + ", p95 " + Perf.quantile(costs, 0.95)
                        + ", max " + Perf.max(costs) + "; first fifth median " + early + ", last fifth median " + late);

            // Finishing the reply: it becomes Markdown and code blocks, once.
            var finishedAt = Date.now();
            var frameCount = root.frames.length;
            root.recording = true;
            var copy = chat.messages.slice();
            copy[copy.length - 1] = Object.assign({}, copy[copy.length - 1], {"content": answer});
            chat.currentStreamIndex = -1;
            chat.messages = copy;
            chat.currentStreamText = "";
            chat.loading = false;
            tryVerify(() => root.frames.length > frameCount, 5000);
            var finishMs = root.frames[frameCount] - finishedAt;
            root.recording = false;
            console.log("PERF finishing the 20k-token reply (Markdown render): " + finishMs + " ms");
            screenshot(root, "perf-stream-20k-done");

            // The budget. The offscreen platform has no vsync: frames come
            // every ~10-12 ms while the busy indicator spins, and timer
            // jitter or a garbage collection (the fake server builds a
            // 1.4 MB response string) adds a few ms here and there. So 95%
            // of frames must be within the frame budget + 5 ms (before this
            // was optimised: 27-28 ms; now ~16), and at most 2% may take over
            // two frame budgets. A machine whose every core is busy with
            // other work misses this (measured: p95 24-27 ms); the local CI
            // runner runs one job at a time.
            var allowedP95 = frameBudgetMs + 5;
            var dropped = intervals.filter(function(t) { return t > frameBudgetMs * 2; });
            verify(p95 <= allowedP95, "95% of frames within " + allowedP95.toFixed(1) + " ms: p95 " + p95 + " ms");
            verify(dropped.length <= Math.max(2, intervals.length * 0.02), dropped.length + " frames over two budgets: " + dropped.join(", "));
            // Work per update must not grow with the answer (it did, from
            // ~8 to ~33 ms, when one TextEdit held the whole reply).
            verify(late <= early * 1.5 + 5, "update cost grew from " + early + " to " + late + " ms");
        }
    }
}
