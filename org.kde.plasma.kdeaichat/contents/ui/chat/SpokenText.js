.pragma library

// Where the words being read aloud are in a message as it is shown (the
// rendered Markdown, whose text differs from what the speech engine got:
// voice/TtsEngines.js speakableText). Used by chat/SpokenGlow.qml.
//
// A spoken chunk is matched by its words in order, whatever lies between
// them (punctuation, list marks, line breaks), case-insensitively.

// Letters (with their combining marks) and digits of any script; engines
// without Unicode property escapes get the common scripts.
var LETTERS = (function() {
    try {
        new RegExp("\\p{L}", "u");
        return "\\p{L}\\p{M}\\p{N}";
    } catch (e) {
        return "A-Za-z0-9\\u00C0-\\u024F\\u0300-\\u036F\\u0370-\\u03FF\\u0400-\\u04FF\\u0590-\\u06FF\\u0900-\\u097F\\u3040-\\u30FF\\u4E00-\\u9FFF";
    }
})();
var FLAGS = LETTERS.charAt(1) === "p" ? "u" : "";
var WORD = new RegExp("[" + LETTERS + "]+", "g" + FLAGS);
var GAP = "[^" + LETTERS + "]*?";

// The words of `text`, each {text, start, end}.
function words(text) {
    var out = [];
    var re = new RegExp(WORD.source, WORD.flags);
    var m;
    while ((m = re.exec(String(text || ""))) !== null)
        out.push({"text": m[0], "start": m.index, "end": m.index + m[0].length});
    return out;
}

function _escape(word) {
    return word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// {start, end} of `chunk` in `shown`, looking from `from` on first (the
// reading moves forward; the same sentence may also come earlier), then from
// the start. null when it isn't there.
function find(shown, chunk, from) {
    var list = words(chunk);
    if (list.length === 0)
        return null;
    var pattern = list.map(function(w) { return _escape(w.text); }).join(GAP);
    var re = new RegExp(pattern, "gi" + FLAGS);
    var text = String(shown || "");
    var starts = from > 0 && from < text.length ? [from, 0] : [0];
    for (var i = 0; i < starts.length; i++) {
        re.lastIndex = starts[i];
        var m = re.exec(text);
        if (m) {
            var end = m.index + m[0].length;
            while (end < text.length && /[.!?…。！？"'”’)]/.test(text.charAt(end)))
                end++;   // its closing punctuation glows too
            return {"start": m.index, "end": end};
        }
    }
    return null;
}

// The word the engine is saying, given as its place in the chunk
// (`wordStart`), mapped into `range` (find()'s result for that chunk):
// {start, end} in `shown`, or null.
function wordAt(shown, range, chunk, wordStart) {
    if (!range || wordStart < 0)
        return null;
    var spoken = words(chunk);
    var k = -1;
    for (var i = 0; i < spoken.length; i++) {
        if (spoken[i].start <= wordStart)
            k = i;
        else
            break;
    }
    if (k < 0)
        return null;
    var inRange = words(String(shown || "").slice(range.start, range.end));
    if (k >= inRange.length)
        return null;
    return {"start": range.start + inRange[k].start, "end": range.start + inRange[k].end};
}

// The sentence of `shown` around position `at` (a long chunk is shown one
// sentence at a time while its words are reported), within `range`.
function sentenceAround(shown, range, at) {
    var text = String(shown || "");
    var start = Math.max(range.start, at);
    var end = Math.min(range.end, at);
    while (start > range.start && !/[.!?。！？\n]/.test(text.charAt(start - 1)))
        start--;
    while (end < range.end && !/[.!?。！？\n]/.test(text.charAt(end)))
        end++;
    if (end < range.end)
        end++;   // the full stop goes with its sentence
    while (start < end && /\s/.test(text.charAt(start)))
        start++;
    return {"start": start, "end": end};
}

// When the whole chunk is not in `shown` (it spans several blocks of the message): the longest run of
// words around the one at `at` (its place in the chunk), within its sentence, that `shown` has.
// {range, text, offset}: where it is in `shown`, its text in the chunk and the word's place in that text;
// null when `shown` doesn't have the word's part of the sentence.
function phraseAround(shown, chunk, at, from) {
    var sentence = sentenceAround(chunk, {"start": 0, "end": chunk.length}, at);
    var list = words(chunk.slice(sentence.start, sentence.end));
    var k = -1;
    for (var n = 0; n < list.length; n++) {
        if (sentence.start + list[n].start <= at)
            k = n;
    }
    if (k < 0)
        return null;
    var text = function(i, j) { return chunk.slice(sentence.start + list[i].start, sentence.start + list[j].end); };
    if (!find(shown, text(k, k), from))
        return null;
    var i = k, j = k;
    while (j + 1 < list.length && find(shown, text(i, j + 1), from))
        j++;
    while (i > 0 && find(shown, text(i - 1, j), from))
        i--;
    var phrase = text(i, j);
    return {"range": find(shown, phrase, from), "text": phrase, "offset": at - (sentence.start + list[i].start)};
}
