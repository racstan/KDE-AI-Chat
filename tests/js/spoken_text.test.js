// Tests for chat/SpokenText.js, run by tests/test_spoken_text.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/SpokenText.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {words, find, wordAt, sentenceAround};", ctx);
const S = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));
const at = (text, r) => r ? text.slice(r.start, r.end) : null;

// The speech engine got Markdown-free text; the message shows rendered text.
const shown = "Plan:\n• Buy milk, eggs.\n• Call Maya!\nThe end. Call Maya!";
assert.strictEqual(at(shown, S.find(shown, "Buy milk eggs.", 0)), "Buy milk, eggs.");
assert.strictEqual(at(shown, S.find(shown, "CALL maya", 0)), "Call Maya!", "case does not matter");
// Reading moves forward: a repeated sentence is found after the last one first.
const first = S.find(shown, "Call Maya!", 0);
const second = S.find(shown, "Call Maya!", first.end);
assert.ok(second.start > first.start);
assert.strictEqual(at(shown, second), "Call Maya!");
assert.deepStrictEqual(plain(S.find(shown, "Buy milk", second.end)), plain(S.find(shown, "Buy milk", 0)), "else from the start");
assert.strictEqual(S.find(shown, "Not here at all", 0), null);
assert.strictEqual(S.find(shown, "  ...  ", 0), null, "no words: nothing to light");

// Other scripts and accents are words too.
assert.strictEqual(at("Le café est prêt.", S.find("Le café est prêt.", "café est", 0)), "café est");
assert.strictEqual(at("नमस्ते दुनिया", S.find("नमस्ते दुनिया", "दुनिया", 0)), "दुनिया");

// The word being said, from its place in the chunk.
const chunk = "Buy milk, eggs.";
const range = S.find(shown, chunk, 0);
assert.strictEqual(at(shown, S.wordAt(shown, range, chunk, 0)), "Buy");
assert.strictEqual(at(shown, S.wordAt(shown, range, chunk, chunk.indexOf("eggs"))), "eggs");
assert.strictEqual(at(shown, S.wordAt(shown, range, chunk, chunk.indexOf(","))), "milk", "between words: the last one");
assert.strictEqual(S.wordAt(shown, range, chunk, -1), null);
assert.strictEqual(S.wordAt(shown, null, chunk, 0), null);

// A long chunk is lit one sentence at a time.
const para = "One two. Three four five? Six.";
const all = S.find(para, para, 0);
assert.strictEqual(at(para, S.sentenceAround(para, all, para.indexOf("four"))), "Three four five?");
assert.strictEqual(at(para, S.sentenceAround(para, all, 0)), "One two.");
assert.strictEqual(at(para, S.sentenceAround(para, all, para.indexOf("Six"))), "Six.");
console.log("ok");
