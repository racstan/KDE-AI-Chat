// The glow behind the words being read aloud, in one block of message text
// (chat/MessageText.qml, its parent): the sentence being read, and the word
// being said where the speech engine reports words (System voices). It moves
// along as the reading goes on. Drawn under the text, so the user's own
// selection stays as it is. Matching: chat/SpokenText.js.
import QtQuick
import org.kde.kirigami as Kirigami
import "SpokenText.js" as SpokenText

Item {
    id: glow

    required property TextEdit textItem
    // VoiceManager.qml (currentPlayingChunk, currentPlayingWordStart).
    property var voice: null
    // This message is the one being read.
    property bool reading: false

    // Shown as [{x, y, w, h}], one per line.
    property var sentenceRects: []
    property var wordRects: []
    readonly property bool shown: sentenceRects.length > 0

    property var _chunkRange: null
    property var _sentence: null
    // Where the last chunk ended: the next one is looked for after it.
    property int _from: 0

    anchors.fill: parent
    z: -1

    onReadingChanged: {
        glow._from = 0;
        glow.update();
    }

    function _clear() {
        _chunkRange = null;
        _sentence = null;
        sentenceRects = [];
        wordRects = [];
    }

    // A new chunk: find it in the text as shown.
    function update() {
        if (!reading || !voice || !voice.currentPlayingChunk) {
            if (!reading)
                _clear();
            return;   // between chunks the last one stays lit
        }
        var shownText = textItem.getText(0, textItem.length);
        var range = SpokenText.find(shownText, voice.currentPlayingChunk, _from);
        _chunkRange = range;
        _sentence = null;
        if (range)
            _from = range.end;
        else
            sentenceRects = wordRects = [];
        updateWord();
    }

    // The word moved on (or the chunk changed): the word, and the sentence around it.
    function updateWord() {
        var shownText = textItem.getText(0, textItem.length);
        var chunk = voice ? voice.currentPlayingChunk : "";
        var at = voice ? voice.currentPlayingWordStart : -1;
        var word = null, sentence = null;
        if (_chunkRange) {
            word = SpokenText.wordAt(shownText, _chunkRange, chunk, at);
            sentence = word ? SpokenText.sentenceAround(shownText, _chunkRange, word.start) : _chunkRange;
        } else if (reading && chunk && at >= 0) {
            // The chunk is not all in this block (a reply with a code block is several blocks, and
            // System voices get the whole reply): its sentence being said, where this block has it.
            var phrase = SpokenText.phraseAround(shownText, chunk, at, _from);
            sentence = phrase ? phrase.range : null;
            word = phrase ? SpokenText.wordAt(shownText, sentence, phrase.text, phrase.offset) : null;
            if (sentence)
                _from = sentence.start;   // the next words are in it too; the next sentence comes after
        }
        if (!sentence) {
            _sentence = null;
            sentenceRects = wordRects = [];
            return;
        }
        if (!_sentence || _sentence.start !== sentence.start || _sentence.end !== sentence.end) {
            _sentence = sentence;
            sentenceRects = rectsFor(sentence.start, sentence.end);
        }
        wordRects = word ? rectsFor(word.start, word.end) : [];
    }

    // The text from `start` to `end` as one box per line.
    function rectsFor(start, end) {
        var rects = [];
        var line = null;
        for (var i = start; i < end; i++) {
            var r = textItem.positionToRectangle(i);
            var next = textItem.positionToRectangle(i + 1);
            var right = Math.abs(next.y - r.y) < 1 ? next.x : r.x;
            if (!line || Math.abs(r.y - line.y) >= 1) {
                line = {"x": r.x, "y": r.y, "w": 0, "h": r.height};
                rects.push(line);
            }
            line.x = Math.min(line.x, r.x, right);
            line.w = Math.max(line.w, Math.max(r.x, right) - line.x);
        }
        return rects.filter(function(l) { return l.w > 0; });
    }

    // The text was laid out again (new width, or more of a streamed reply).
    function _relayout() {
        if (_sentence) {
            sentenceRects = rectsFor(_sentence.start, _sentence.end);
            _sentence = null;
            updateWord();
        }
    }

    Connections {
        target: glow.voice
        ignoreUnknownSignals: true
        function onCurrentPlayingChunkChanged() { glow.update(); }
        function onCurrentPlayingWordStartChanged() { glow.updateWord(); }
    }

    Connections {
        target: glow.textItem
        function onWidthChanged() { glow._relayout(); }
        function onContentHeightChanged() { glow._relayout(); }
    }

    component Box: Rectangle {
        required property var modelData
        property real strength: 0.22
        x: modelData.x - 2
        y: modelData.y
        width: modelData.w + 4
        height: modelData.h
        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(Kirigami.Theme.highlightColor, strength)
        NumberAnimation on opacity {
            from: 0
            to: 1
            duration: Kirigami.Units.shortDuration
        }
    }

    Repeater {
        objectName: "spokenSentence"
        model: glow.sentenceRects
        delegate: Box {}
    }

    Repeater {
        objectName: "spokenWord"
        model: glow.wordRects
        delegate: Box {
            strength: 0.45
        }
    }
}
