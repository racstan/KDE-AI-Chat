// Tests for chat/MessageBlocks.js, run by tests/test_message_blocks.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/MessageBlocks.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {split};", ctx);
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
console.log("PASS message_blocks");
