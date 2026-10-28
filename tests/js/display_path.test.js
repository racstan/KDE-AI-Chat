// Tests for chat/DisplayPath.js, run by tests/test_display_path_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/DisplayPath.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.D = {tilde, plainPath, expand};", ctx);
const D = ctx.D;

assert.strictEqual(D.tilde("/home/sam/Projects/photos", "file:///home/sam"), "~/Projects/photos");
assert.strictEqual(D.tilde("/home/sam/.local/share/kdeaichat", "/home/sam/"), "~/.local/share/kdeaichat");
assert.strictEqual(D.tilde("/home/sam", "file:///home/sam"), "~");
assert.strictEqual(D.tilde("/home/samuel/x", "file:///home/sam"), "/home/samuel/x");   // not a prefix match
assert.strictEqual(D.tilde("/srv/data", "file:///home/sam"), "/srv/data");
assert.strictEqual(D.tilde("", "file:///home/sam"), "");
assert.strictEqual(D.tilde("/home/sam/x", ""), "/home/sam/x");
assert.strictEqual(D.expand("~/My Projects/a ", "file:///home/sam"), "/home/sam/My Projects/a ");   // spaces kept while typing
assert.strictEqual(D.tilde(D.expand("~/My ", "file:///home/sam"), "file:///home/sam"), "~/My ");
assert.strictEqual(D.expand("~", "/home/sam/"), "/home/sam");
assert.strictEqual(D.expand("/srv/x", "/home/sam"), "/srv/x");
assert.strictEqual(D.tilde("/x", "file:///"), "/x");
assert.strictEqual(D.tilde("/home/a b/x", "file:///home/a%20b"), "~/x");
console.log("ok");
