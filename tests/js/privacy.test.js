// Tests for chat/Privacy.js, run by tests/test_privacy_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/Privacy.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.P = {placeOf, describe};", ctx);
const P = ctx.P;

// This computer.
for (const url of ["http://localhost:11434/v1", "http://127.0.0.1:1234/v1", "http://[::1]:8080/v1", "http://0.0.0.0:4000"])
    assert.strictEqual(P.placeOf(url), "here", url);
// The local network.
for (const url of ["http://192.168.1.20:11434/v1", "http://10.0.0.5/v1", "http://172.16.3.4:8000", "http://172.31.0.1",
                   "http://nas.local:11434/v1", "http://169.254.1.1", "http://[fd12:3456::1]:8080"])
    assert.strictEqual(P.placeOf(url), "network", url);
// Online.
for (const url of ["https://api.openai.com/v1", "https://openrouter.ai/api/v1", "http://172.32.0.1", "https://localhost.example.com",
                   "https://127.0.0.1.evil.com/v1", "", null, "not a url"])
    assert.strictEqual(P.placeOf(url), "cloud", String(url));

// Agents never claim "this computer" for the messages.
for (const mode of ["opencode", "pi"])
    assert.strictEqual(P.describe(mode, "http://localhost:1").place, "agent");
assert.strictEqual(P.describe("provider", "http://127.0.0.1:11434/v1").place, "here");
assert.strictEqual(P.describe("provider", "http://127.0.0.1:11434/v1").icon, "computer");
assert.strictEqual(P.describe("provider", "https://api.openai.com/v1").icon, "folder-cloud");
assert.strictEqual(P.describe("provider", "http://192.168.0.2").icon, "network-workgroup");
console.log("privacy.test.js: ok");
