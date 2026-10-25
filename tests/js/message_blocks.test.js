// Tests for chat/MessageBlocks.js, run by tests/test_message_blocks.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/MessageBlocks.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {split, stripEmphasis};", ctx);
const plain = x => JSON.parse(JSON.stringify(x));
const split = s => plain(ctx.exports.split(s));

assert.deepStrictEqual(split(""), []);
assert.deepStrictEqual(split("hello"), [{type: "text", text: "hello"}]);
assert.deepStrictEqual(split("Run:\n```bash\nls -la\n```\nDone."), [
    {type: "text", text: "Run:\n"},
    {type: "code", language: "bash", text: "ls -la"},
    {type: "text", text: "\nDone."},
]);
assert.deepStrictEqual(split("```\nplain\n```"), [{type: "code", language: "code", text: "plain"}]);
assert.deepStrictEqual(split("Streaming:\n```py\nprint(1"), [
    {type: "text", text: "Streaming:\n"},
    {type: "code", language: "py", text: "print(1"},
]);
const strip = ctx.exports.stripEmphasis;
assert.strictEqual(strip(""), "");
assert.strictEqual(strip("The tide comes in with **quiet** hands"), "The tide comes in with quiet hands");
assert.strictEqual(strip("an **unclosed bold"), "an unclosed bold");
assert.strictEqual(strip("so *very* calm, *really*."), "so very calm, really.");
assert.strictEqual(strip("## Itinerary\n### Day 1"), "Itinerary\nDay 1");
assert.strictEqual(strip("ends with a star*"), "ends with a star");
assert.strictEqual(strip("* item one\n* item two"), "* item one\n* item two", "bullets are kept");
assert.strictEqual(strip("2 * 3 * 4"), "2 * 3 * 4", "multiplication is kept");
console.log("PASS message_blocks");
