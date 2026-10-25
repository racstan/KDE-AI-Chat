// Tests for chat/Commands.js, run by tests/test_commands.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/Commands.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {parse, resolve, suggest, find, COMMANDS, MODES};", ctx);
const C = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));
const templates = [{name: "fix", prompt: "Fix this:"}, {name: "modeling", prompt: "Model it"}, {name: "new-year", prompt: "Hi"}];
const names = list => Array.from(list.map(e => e.kind + ":" + e.name));

// parse
assert.deepStrictEqual(plain(C.parse("/model gpt-4")), {name: "model", arg: "gpt-4", spaced: true});
assert.deepStrictEqual(plain(C.parse("/new")), {name: "new", arg: "", spaced: false});
assert.strictEqual(C.parse("hello"), null);
assert.strictEqual(C.parse("/"), null);
assert.strictEqual(C.parse("/new\nmore"), null);

// resolve: only built-ins, one line
assert.strictEqual(C.resolve("/new").command.name, "new");
assert.strictEqual(C.resolve("  /mode pi ").arg, "pi");
assert.strictEqual(C.resolve("/etc/hosts?"), null);
assert.strictEqual(C.resolve("/fix this"), null);
assert.strictEqual(C.resolve("/new\nand more text"), null);
assert.strictEqual(C.resolve("hello /new"), null);
assert.deepStrictEqual(plain(C.resolve("/image a red fox in the snow").arg), "a red fox in the snow");
assert.strictEqual(C.resolve("/image").command.name, "image");
assert.strictEqual(C.resolve("/image").arg, "");
assert.strictEqual(C.resolve("/image a fox\nand more"), null);

// "/" lists commands first, then templates; /variant only with variants
assert.deepStrictEqual(names(C.suggest("/", templates, {})), ["command:model", "command:new", "command:mode", "command:image", "template:fix", "template:modeling", "template:new-year"]);
assert.ok(names(C.suggest("/", templates, {hasVariants: true})).indexOf("command:variant") === 1);
assert.deepStrictEqual(names(C.suggest("/mo", templates, {})), ["command:model", "command:mode", "template:modeling"]);
assert.deepStrictEqual(names(C.suggest("/new", templates, {})), ["command:new", "template:new-year"]);
assert.deepStrictEqual(names(C.suggest("/im", templates, {})), ["command:image"]);
assert.strictEqual(C.suggest("/im", [], {})[0].insert, "/image ");
assert.strictEqual(C.suggest("/im", [], {})[0].usage, "<prompt>");
assert.strictEqual(C.suggest("hello", templates, {}).length, 0);
assert.strictEqual(C.suggest("/zzz", templates, {}).length, 0);

// completion text
assert.strictEqual(C.suggest("/mod", [], {})[0].insert, "/model ");
assert.strictEqual(C.suggest("/ne", [], {})[0].insert, "/new");
assert.strictEqual(C.suggest("/fi", templates, {})[0].insert, "/fix ");

// arguments
const ctx2 = {models: ["gpt-4", "gpt-4o", "claude-3"], variants: ["default", "high"], hasVariants: true};
assert.deepStrictEqual(names(C.suggest("/model gpt", [], ctx2)), ["option:gpt-4", "option:gpt-4o"]);
assert.deepStrictEqual(names(C.suggest("/model 4o", [], ctx2)), ["option:gpt-4o"]);
assert.strictEqual(C.suggest("/model gpt", [], ctx2)[0].insert, "/model gpt-4");
assert.deepStrictEqual(names(C.suggest("/model gpt-4o", [], ctx2)), ["option:gpt-4o"]);
assert.deepStrictEqual(names(C.suggest("/variant h", [], ctx2)), ["option:high"]);
assert.deepStrictEqual(names(C.suggest("/mode p", [], ctx2)), ["option:pi", "option:opencode"]);
assert.deepStrictEqual(names(C.suggest("/mode ", [], ctx2)), ["option:direct", "option:opencode", "option:pi"]);
assert.strictEqual(C.suggest("/new x", [], ctx2).length, 0);
assert.strictEqual(C.suggest("/image a fox", [], ctx2).length, 0, "the prompt is free text");
assert.strictEqual(C.suggest("/fix some text", templates, ctx2).length, 0);
console.log("ok");
