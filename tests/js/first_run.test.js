// Tests for chat/FirstRun.js, run by tests/test_first_run_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/FirstRun.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.F = {cloudChoices, isUsable, wanted, makeEntry, upsert, pickModel, CLOUD_IDS, TERMS_URL};", ctx);
const F = ctx.F;
const plain = x => JSON.parse(JSON.stringify(x));

const local = e => /localhost|127\.0\.0\.1/.test(e.baseUrl);
const cloud = {id: "openai", name: "OpenAI", type: "openai-compat", baseUrl: "https://api.openai.com/v1", model: "gpt-4o"};
const ollama = {id: "ollama", name: "Ollama", type: "openai-compat", baseUrl: "http://localhost:11434/v1", model: "qwen3:8b"};

// isUsable
assert.strictEqual(F.isUsable(cloud, {openai: "k"}, local), true);
assert.strictEqual(F.isUsable(cloud, {}, local), false, "a cloud provider needs its key");
assert.strictEqual(F.isUsable(cloud, {openai: "  "}, local), false);
assert.strictEqual(F.isUsable(Object.assign({}, cloud, {model: ""}), {openai: "k"}, local), false, "a model is needed");
assert.strictEqual(F.isUsable(ollama, {}, local), true, "local needs no key");
assert.strictEqual(F.isUsable({id: "h", type: "image", model: "x", baseUrl: "http://localhost:1"}, {}, local), false);
assert.strictEqual(F.isUsable(null, {}, local), false);

// wanted
const base = {providers: [], keys: {}, isLocal: local, dismissed: false, agentMode: false, walletStatus: "ready"};
const w = o => F.wanted(Object.assign({}, base, o));
assert.strictEqual(w({}), true, "fresh install");
assert.strictEqual(w({walletStatus: "unknown"}), false, "keys not read yet");
assert.strictEqual(w({walletStatus: "unavailable"}), true, "no providers at all");
assert.strictEqual(w({dismissed: true}), false);
assert.strictEqual(w({agentMode: true}), false);
assert.strictEqual(w({providers: [Object.assign({}, cloud, {model: ""})]}), true, "the placeholder default");
assert.strictEqual(w({providers: [cloud]}), true, "no key");
assert.strictEqual(w({providers: [cloud], keys: {openai: "k"}}), false);
assert.strictEqual(w({providers: [ollama]}), false);
assert.strictEqual(w({providers: [cloud], walletStatus: "denied"}), false, "cannot tell without the wallet");

// cloudChoices
const presets = {openai: {id: "openai", name: "OpenAI", keyUrl: "https://k"}, groq: {id: "groq", name: "Groq"}};
const rows = F.cloudChoices(id => presets[id] || null);
assert.deepStrictEqual(plain(rows.map(r => r.id)), ["openai", "groq"]);
assert.strictEqual(rows[1].keyUrl, "");

// makeEntry / upsert / pickModel
assert.deepStrictEqual(plain(F.makeEntry({name: "OpenRouter", type: "openai-compat", baseUrl: "u", model: "auto", headers: {a: "b"}}, "openrouter", "m1")),
    {id: "openrouter", name: "OpenRouter", type: "openai-compat", baseUrl: "u", model: "m1", headers: {a: "b"}});
assert.strictEqual(F.makeEntry({name: "X", baseUrl: "u"}, "x", "", {baseUrl: "http://127.0.0.1:1/v1", model: "q"}).model, "q");
assert.deepStrictEqual(plain(F.upsert([{id: "a", model: ""}, {id: "b"}], {id: "a", model: "m"})), [{id: "a", model: "m"}, {id: "b"}]);
assert.deepStrictEqual(plain(F.upsert([{id: "b"}], {id: "a"})), [{id: "b"}, {id: "a"}]);
assert.strictEqual(F.pickModel(["x", "y"], "y"), "y");
assert.strictEqual(F.pickModel(["x", "y"], "z"), "x");
assert.strictEqual(F.pickModel([], "z"), "z");
assert.ok(/^https:\/\/github\.com\/racstan\/KDE-AI-Chat\/blob\/master\/TERMS\.md$/.test(F.TERMS_URL));
console.log("ok");
