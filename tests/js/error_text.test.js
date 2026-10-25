// Tests for chat/ErrorText.js and chat/PromptTemplates.js, run by tests/test_error_text.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

function load(name, exports) {
    const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat", name), "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/m, "");
    const ctx = {};
    vm.runInNewContext(src + "\nthis.exports = {" + exports + "};", ctx);
    return ctx.exports;
}
const plain = x => JSON.parse(JSON.stringify(x));
const E = load("ErrorText.js", "describe");
const T = load("PromptTemplates.js", "parse, expand, suggest");

const cases = [
    ["The provider rejected the API key (HTTP 401). Check the key in Settings. Incorrect API key", "auth", true],
    ["Request to https://api.x/v1/chat failed (HTTP 403): forbidden", "auth", true],
    ["⚠️ Cannot send message with OpenRouter. Missing: API key. Please open Widget Settings", "missing-key", true],
    ["⚠️ Cannot send message with Ollama. Missing: base URL, model. Please open Widget Settings", "setup", true],
    ["⚠️ The provider \"x\" isn't set up any more. Add it in Widget Settings", "setup", true],
    ["Request to https://openrouter.ai/api/v1 failed (HTTP 402): Insufficient credits", "credit", false],
    ["Request to https://x failed (HTTP 429): You exceeded your current quota, check billing", "credit", false],
    ["Request to https://x failed (HTTP 429): Rate limit reached for requests", "rate", false],
    ["Request to https://x failed (HTTP 429)", "rate", false],
    ["Request to https://x/v1/chat timed out after 120 seconds.", "timeout", false],
    ["Could not reach https://api.openai.com/v1/chat/completions. Check the server URL and your network.", "network", true],
    ["Request to https://x failed (HTTP 404): The model `gpt-9` does not exist", "model", true],
    ["Request to https://x failed (HTTP 503): upstream overloaded", "server", false],
    ["Request to https://x failed (HTTP 500): boom", "server", false],
    ["The model returned an empty response.", "empty", false],
    ["OpenCode isn't installed (no `opencode` command found).", "agent-missing", true],
    ["Pi isn't installed (no `pi` command found).", "agent-missing", true],
    ["OpenCode isn't reachable at http://127.0.0.1:4096.", "agent-offline", true],
    ["OpenCode isn't running at http://127.0.0.1:4096 and couldn't be started: x.", "agent-offline", true],
    ["Pi: the Pi bridge couldn't be started.", "agent-offline", true],
    ["Something odd happened", "other", false],
];
for (const [raw, k, settings] of cases) {
    const d = E.describe(raw);
    assert.strictEqual(d.kind, k, raw + " -> " + d.kind);
    assert.strictEqual(d.settings, settings, raw + " settings");
    assert.ok(d.text.length > 0 && !/[⚠️]/.test(d.text), "no warning sign in " + d.text);
}
assert.ok(E.describe("Pi isn't installed (no `pi` command found).").text.startsWith("Pi "));
assert.ok(E.describe("⚠️ Cannot send message with OpenRouter. Missing: API key.").text.includes("OpenRouter"));
// The original message stays available as detail (without the warning sign), unless it adds nothing.
assert.strictEqual(E.describe("⚠️ Cannot send message with Ollama. Missing: model.").detail.charAt(0), "C");
assert.strictEqual(E.describe("Something odd happened").detail, "");
assert.strictEqual(E.describe("").text, "Something went wrong.");
assert.strictEqual(E.describe(undefined).kind, "other");

// Prompt templates
const list = T.parse(JSON.stringify([{name: "fix", prompt: "Fix this code:"}, {name: "summarize", prompt: "Summarise:"}, {name: "", prompt: "x"}, {name: "bad"}]));
assert.deepStrictEqual(plain(list).map(t => t.name), ["fix", "summarize"]);
assert.deepStrictEqual(plain(T.parse("not json")), []);
assert.deepStrictEqual(plain(T.parse('{"a":1}')), []);
assert.strictEqual(T.expand("/fix my loop", list), "Fix this code:\n\nmy loop");
assert.strictEqual(T.expand("/fix", list), "Fix this code:");
assert.strictEqual(T.expand("/nope text", list), "/nope text");
assert.strictEqual(T.expand("hello", list), "hello");
assert.deepStrictEqual(plain(T.suggest("/", list)).map(t => t.name), ["fix", "summarize"]);
assert.deepStrictEqual(plain(T.suggest("/su", list)).map(t => t.name), ["summarize"]);
assert.deepStrictEqual(plain(T.suggest("/ix", list)).map(t => t.name), ["fix"], "contains also matches, after prefix matches");
assert.deepStrictEqual(plain(T.suggest("/fix ", list)), []);
assert.deepStrictEqual(plain(T.suggest("fix", list)), []);
console.log("PASS error_text");
