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

// Model errors in plain words
const nim404 = "Request to https://integrate.api.nvidia.com/v1/chat/completions failed (HTTP 404): Function '767b5b9a-1': Not found for account 'TSF5_x'";
let d = E.describe(nim404, "NVIDIA NIM");
assert.strictEqual(d.kind, "model");
assert.ok(d.text.startsWith("This model isn't available on your NVIDIA NIM account (it may be retired or not enabled)."), d.text);
assert.ok(d.text.includes("Settings \u2192 Connection"), d.text);
assert.ok(d.text.endsWith("\n\nFunction '767b5b9a-1': Not found for account 'TSF5_x'"), d.text);
assert.strictEqual(d.detail, nim404);
assert.strictEqual(d.settings, true);
assert.ok(E.describe(nim404).text.startsWith("This model isn't available on your account"));
d = E.describe("Request to https://integrate.api.nvidia.com/v1/chat/completions failed (HTTP 410): The model 'x/y' has reached its end of life on 2026-01-01 and is no longer available.", "NVIDIA NIM");
assert.strictEqual(d.kind, "model");
assert.ok(d.text.startsWith("This model has been retired and isn't available on your NVIDIA NIM account any more."), d.text);
assert.ok(d.text.includes("end of life"));
d = E.describe('Request to https://api.openai.com/v1/chat/completions failed (HTTP 404): {"error":{"message":"The model `gpt-9` does not exist","code":"model_not_found"}}', "OpenAI");
assert.strictEqual(d.kind, "model");
assert.ok(d.text.includes("your OpenAI account"));
assert.strictEqual(E.describe('Request to https://x failed (HTTP 400): {"error":{"code":"model_not_found"}}').kind, "model");
// A bare 404 (wrong URL) is not a model error: nothing says model or function.
d = E.describe("Request to https://x/v1/chatt failed (HTTP 404): Not Found");
assert.strictEqual(d.kind, "other");
// Keys still win, even when the body mentions the model.
assert.strictEqual(E.describe("Request to https://x failed (HTTP 401): Invalid API key for model gpt-4").kind, "auth");
assert.strictEqual(E.describe("Request to https://x failed (HTTP 403): no access to model foo, not found").kind, "auth");

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

// The image services' own messages are shown as they are, whatever words they contain.
for (const text of ["AI Horde needs kudos for this size. Pick a smaller picture or fewer steps in Settings \u2192 Connection, or add your own AI Horde key.",
                    "Pollinations free limit: try again in 12 s.",
                    "Pollinations says this key has no credit for this model. Pick a free model, or check your balance at pollinations.ai.",
                    "AI Horde can't be reached. Check your internet connection and try again.",
                    "Pollinations is limiting requests: try again in 7 s."]) {
    const r = plain(E.describe("\u26a0\ufe0f " + text, "OpenRouter"));
    assert.strictEqual(r.kind, "image", text);
    assert.strictEqual(r.text, text);
    assert.strictEqual(r.detail, "");
    assert.strictEqual(r.settings, /Settings/.test(text));
}
assert.strictEqual(plain(E.describe("The provider rejected the API key (HTTP 401). Check the key in Settings.")).kind, "auth", "other messages are unchanged");
console.log("PASS error_text");
