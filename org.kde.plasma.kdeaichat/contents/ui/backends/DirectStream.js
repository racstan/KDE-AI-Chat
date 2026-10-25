.pragma library

// Splits a direct reply's text stream into answer and <think> reasoning.
// DirectBackend.send takes it as options.thinkFactory (backends are self-contained: no imports).

// Splits a text stream into answer and <think>…</think> reasoning, even when a
// tag is cut across chunks. emit(kind, text) with kind "text" or "reasoning".
function createThinkSplitter(emit) {
    var OPEN = "<think>", CLOSE = "</think>";
    var inside = false;
    var pending = "";

    function partialTagAt(text, tag) {
        // Length of the longest suffix of `text` that is a prefix of `tag`.
        for (var n = Math.min(tag.length - 1, text.length); n > 0; n--) {
            if (text.substring(text.length - n) === tag.substring(0, n))
                return n;
        }
        return 0;
    }

    return {
        "push": function(chunk) {
            var text = pending + chunk;
            pending = "";
            while (text.length > 0) {
                var tag = inside ? CLOSE : OPEN;
                var at = text.indexOf(tag);
                if (at < 0) {
                    var keep = partialTagAt(text, tag);
                    var out = text.substring(0, text.length - keep);
                    if (out) emit(inside ? "reasoning" : "text", out);
                    pending = text.substring(text.length - keep);
                    return;
                }
                if (at > 0) emit(inside ? "reasoning" : "text", text.substring(0, at));
                text = text.substring(at + tag.length);
                inside = !inside;
            }
        },
        "end": function() {
            if (pending) emit(inside ? "reasoning" : "text", pending);
            pending = "";
        }
    };
}
