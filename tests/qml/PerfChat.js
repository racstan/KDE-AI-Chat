.pragma library

// Test data and timing helpers for the tst_perf_*.qml performance tests.

// A deterministic chat of `n` messages: user questions and assistant
// answers in Markdown (lists, bold, inline code, fenced code blocks); every
// tenth answer is long (~4,000 characters, several code blocks).
function conversation(n) {
    var msgs = [];
    for (var i = 0; i < n; i++) {
        var t = "10:" + (i % 60 < 10 ? "0" : "") + (i % 60);
        if (i % 2 === 0) {
            msgs.push({"id": "u" + i, "role": "user", "time": t,
                       "content": i % 14 === 0 ? longQuestion(i) : "Question number " + i + ": how do I sort a list in Python?"});
            continue;
        }
        var content = i % 10 === 5 ? longAnswer(i)
            : "Answer **" + i + "**: use `sorted()`.\n\n- returns a new list\n- `list.sort()` sorts in place\n\n"
              + "```python\nitems = sorted(items, key=len)\n```\n\nThat's all.";
        msgs.push({"id": "a" + i, "role": "assistant", "model": "openrouter/auto", "time": t, "content": content,
                   "tokens": {"input": 1200 + i, "output": 300 + i}});
    }
    return msgs;
}

function longQuestion(i) {
    var s = "Here is a long question " + i + ".\n";
    for (var k = 0; k < 12; k++) s += "Line " + k + " of the pasted log: ERROR something failed at step " + k + "\n";
    return s;
}

function longAnswer(i) {
    var s = "## Answer " + i + "\n\n";
    for (var p = 0; p < 4; p++) {
        s += "Paragraph " + p + " explains *why* this works. ";
        for (var w = 0; w < 30; w++) s += "word" + w + " ";
        s += "\n\n1. first step\n2. second step with `inline code`\n3. third step\n\n";
        s += "```js\nfunction step" + p + "(items) {\n";
        for (var l = 0; l < 8; l++) s += "    items.push(" + l + "); // line " + l + "\n";
        s += "    return items;\n}\n```\n\n";
    }
    return s + "> A closing note, quoted.\n";
}

// Sorted copy, and the value at fraction q (0..1).
function quantile(values, q) {
    if (values.length === 0) return 0;
    var sorted = values.slice().sort(function(a, b) { return a - b; });
    return sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))];
}

function median(values) { return quantile(values, 0.5); }

function max(values) { return values.length ? Math.max.apply(null, values) : 0; }
