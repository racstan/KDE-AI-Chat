// Tests for config/SetupChecks.js, run by tests/test_setup_checks_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/config/SetupChecks.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.S = {MESSAGES, ACTIONS, directChecks, helperPayload, message, counts, parseHelper};", ctx);
const S = ctx.S;
const plain = x => JSON.parse(JSON.stringify(x));
const codes = rows => plain(rows).map(r => r.status + ":" + r.code);

if (process.argv[2] === "--codes") {
    console.log(JSON.stringify(Object.keys(S.MESSAGES)));
    process.exit(0);
}

const or = {id: "openrouter", name: "OpenRouter", baseUrl: "https://openrouter.ai/api/v1", model: "openrouter/auto", local: false};
const nim = {id: "nvidia", name: "NVIDIA NIM", baseUrl: "https://integrate.api.nvidia.com/v1", model: "", local: false};
const ollama = {id: "ollama", name: "Ollama", baseUrl: "http://localhost:11434/v1", model: "qwen3", local: true};
const cf = {id: "cloudflare", name: "Cloudflare", baseUrl: "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1", model: "m", local: false};
const bad = {id: "custom_1", name: "Mine", baseUrl: "localhost:8080", model: "m", local: false};

// No providers at all.
assert.deepStrictEqual(codes(S.directChecks([], "ready", {})), ["error:no-providers"]);
// Wallet ready: a missing key is an error, a provider without a model a warning; local ones need no key.
assert.deepStrictEqual(codes(S.directChecks([or, nim, ollama], "ready", {openrouter: "x"})),
    ["ok:wallet-ready", "ok:provider-ok", "error:key-missing"]);
assert.deepStrictEqual(codes(S.directChecks([or, nim], "ready", {openrouter: "x", nvidia: "y"}, "nvidia")),
    ["ok:wallet-ready", "ok:provider-ok", "warn:model-missing"]);
// Only the default provider's missing model is mentioned: chats pick their own.
assert.deepStrictEqual(codes(S.directChecks([or, nim], "ready", {openrouter: "x", nvidia: "y"}, "openrouter")),
    ["ok:wallet-ready", "ok:provider-ok", "ok:provider-ok"]);
// Wallet off or locked: one row says so; keys aren't reported missing one by one.
for (const [status, code] of [["disabled", "error:wallet-disabled"], ["denied", "error:wallet-denied"],
                              ["unavailable", "error:wallet-unavailable"], ["unknown", "warn:wallet-unknown"]]) {
    assert.deepStrictEqual(codes(S.directChecks([or], status, {})), [code, "ok:provider-ok"], status);
}
// Only local providers: KWallet isn't needed, so it isn't mentioned.
assert.deepStrictEqual(codes(S.directChecks([ollama], "disabled", {})), []);
// Bad addresses.
assert.deepStrictEqual(codes(S.directChecks([cf, bad], "ready", {cloudflare: "k", custom_1: "k"})),
    ["ok:wallet-ready", "error:url-placeholder", "error:url-bad"]);
assert.deepStrictEqual(plain(S.directChecks([bad], "ready", {}))[1].args, ["Mine", "localhost:8080"]);

// The helper's payload: settings only, the local providers as endpoints, never a key.
const cfg = {useOpenCode: false, openCodeUrl: "http://127.0.0.1:4096/v1", sttEnabled: true, sttEngine: "remote",
             sttRemoteUrl: "http://x/v1", voiceTtsEnabled: false, voiceTtsEngine: "piper", openRouterApiKey: "sk-secret",
             providersJson: "[...]"};
let p = plain(S.helperPayload("direct", cfg, [or, ollama, Object.assign({}, ollama, {id: "x", baseUrl: "nope"})]));
assert.deepStrictEqual(p.endpoints, [{id: "ollama", name: "Ollama", url: "http://localhost:11434/v1"}]);
assert.strictEqual(p.mode, "direct");
assert.strictEqual(p.stt.sttEnabled, true);
assert.strictEqual(p.stt.sttEngine, "remote");
assert.strictEqual(p.tts.voiceTtsEnabled, false);
assert.ok(!JSON.stringify(p).includes("sk-secret") && !JSON.stringify(p).includes("providersJson"));
p = plain(S.helperPayload("opencode", cfg, [ollama], "http://127.0.0.1:5000"));
assert.deepStrictEqual(p.endpoints, []);
assert.strictEqual(p.openCodeUrl, "http://127.0.0.1:5000");
assert.strictEqual(plain(S.helperPayload("pi", cfg, [])).openCodeUrl, "http://127.0.0.1:4096/v1");

// Messages: every code has a text; problems have a fix; placeholders are numbered from 1.
for (const [code, [text, fix]] of Object.entries(S.MESSAGES)) {
    assert.ok(text.length > 0, code);
    for (const t of [text, fix]) {
        const ns = (t.match(/%(\d)/g) || []).map(m => +m[1]);
        assert.ok(ns.every(n => n >= 1 && n <= 3), code);
    }
}
assert.deepStrictEqual(plain(S.message({code: "nope", args: []})), ["nope %1 %2", ""]);
assert.strictEqual(S.ACTIONS["sched-timers-missing"], "sync-schedules");
assert.deepStrictEqual(plain(S.counts([{status: "ok"}, {status: "error"}, {status: "error"}])), {ok: 1, warn: 0, error: 2});

// Reading the helper's answer.
assert.deepStrictEqual(codes(S.parseHelper('{"checks":[{"id":"a","area":"x","status":"ok","code":"pdf-ok","args":[]}]}\n', 0)),
    ["ok:pdf-ok"]);
assert.deepStrictEqual(codes(S.parseHelper("Error executing setup_check: boom", 1)), ["warn:check-failed"]);
assert.deepStrictEqual(codes(S.parseHelper("", 1)), ["warn:check-failed"]);
console.log("PASS setup_checks");
