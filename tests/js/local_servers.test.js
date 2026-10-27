// Tests for config/LocalServers.js, run by tests/test_local_servers_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/config/LocalServers.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.L = {parse, loopbackPort, isAdded, defaultModel, providerFor};", ctx);
const L = ctx.L;
const plain = x => JSON.parse(JSON.stringify(x));

const ollama = {id: "ollama-11434", kind: "ollama", name: "Ollama", port: 11434, baseUrl: "http://127.0.0.1:11434/v1",
                models: ["nomic-embed-text:latest", "qwen3:8b"], count: 2, needsKey: false, provider: "ollama"};
const generic = {id: "openai-1337", kind: "openai", name: "OpenAI-compatible server", port: 1337, baseUrl: "http://127.0.0.1:1337/v1",
                 models: [], count: 0, needsKey: false, provider: "custom"};

// parse
assert.strictEqual(L.parse("", 1), null);
assert.strictEqual(L.parse("not json", 0), null);
assert.strictEqual(L.parse('{"servers": 3}', 0), null);
assert.deepStrictEqual(plain(L.parse(JSON.stringify({servers: [ollama, null, {id: 1}]}), 0)), [ollama]);
assert.deepStrictEqual(plain(L.parse('{"servers": []}\n', 0)), []);

// loopbackPort
assert.strictEqual(L.loopbackPort("http://localhost:11434/v1"), "11434");
assert.strictEqual(L.loopbackPort("http://127.0.0.1:1234"), "1234");
assert.strictEqual(L.loopbackPort("http://[::1]:8080/v1"), "8080");
assert.strictEqual(L.loopbackPort("http://example.com:11434/v1"), "");
assert.strictEqual(L.loopbackPort("http://127.0.0.1.evil.com:11434/v1"), "");
assert.strictEqual(L.loopbackPort(""), "");

// isAdded: a chat provider on that loopback port; a picture service or another port doesn't count
const list = [{id: "a", type: "openai-compat", baseUrl: "http://localhost:11434/v1"},
              {id: "b", type: "image", baseUrl: "http://localhost:1337"},
              {id: "c", type: "openai-compat", baseUrl: "https://api.openai.com/v1"}];
assert.strictEqual(L.isAdded(ollama, list), true);
assert.strictEqual(L.isAdded(generic, list), false);
assert.strictEqual(L.isAdded(ollama, []), false);
assert.strictEqual(L.isAdded(ollama, null), false);

// defaultModel skips embedding models
assert.strictEqual(L.defaultModel(ollama.models), "qwen3:8b");
assert.strictEqual(L.defaultModel(["nomic-embed-text"]), "nomic-embed-text");
assert.strictEqual(L.defaultModel([]), "");

// providerFor
assert.deepStrictEqual(plain(L.providerFor(ollama)), {presetId: "ollama", overrides: {baseUrl: "http://127.0.0.1:11434/v1", model: "qwen3:8b"}, needsKey: false});
assert.deepStrictEqual(plain(L.providerFor(generic)),
    {presetId: "custom", overrides: {baseUrl: "http://127.0.0.1:1337/v1", model: "", name: "OpenAI-compatible server (local)"}, needsKey: false});
// a LiteLLM proxy that asks for its key: the litellm preset, no models, the editor asks for the key first
const lite = {id: "litellm-4000", kind: "litellm", name: "LiteLLM proxy", port: 4000, baseUrl: "http://127.0.0.1:4000/v1",
              models: [], count: 0, needsKey: true, provider: "litellm"};
assert.deepStrictEqual(plain(L.providerFor(lite)), {presetId: "litellm", overrides: {baseUrl: "http://127.0.0.1:4000/v1", model: ""}, needsKey: true});
assert.strictEqual(L.providerFor(ollama).needsKey, false);
console.log("ok");
