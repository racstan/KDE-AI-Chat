// Tests for voice/SttConfig.js, run by tests/test_stt_config_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const source = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/voice/SttConfig.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(source + "\nthis.exports = {payload, migration, applyMigration, KEYS};", ctx);
const S = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));

// Defaults: dictation off, faster-whisper "small", auto device and language.
let p = plain(S.payload({}));
assert.strictEqual(p.sttEnabled, false);
assert.strictEqual(p.sttEngine, "faster-whisper");
assert.strictEqual(p.sttModel, "small");
assert.strictEqual(p.sttDevice, "auto");
assert.strictEqual(p.sttLanguage, "auto");
assert.strictEqual(p.venv, undefined);
assert.deepStrictEqual(Object.keys(p).sort(), plain(S.KEYS).sort());

p = plain(S.payload({sttEnabled: true, sttEngine: "remote", sttRemoteUrl: "https://x/v1", voiceVenvPath: "/opt/venv"}));
assert.strictEqual(p.sttEnabled, true);
assert.strictEqual(p.sttRemoteUrl, "https://x/v1");
assert.strictEqual(p.venv, "/opt/venv");
assert.ok(!("apiKey" in p) && !JSON.stringify(p).includes("key"), "no key in the payload");

// Old voice settings carry over once; dictation stays on for people who had voice on.
let cfg = {voiceEnabled: true, voiceSttModel: "medium", voiceLanguage: "de", voiceGpuEnabled: true, sttSettingsMigrated: false};
assert.deepStrictEqual(plain(S.applyMigration(cfg)),
    {sttSettingsMigrated: true, sttEnabled: true, sttModel: "medium", sttLanguage: "de", sttDevice: "cuda"});
assert.strictEqual(cfg.sttEnabled, true);
assert.deepStrictEqual(plain(S.migration(cfg)), {}, "only once");

cfg = {voiceEnabled: false, voiceSttModel: "small", voiceSttModelPath: "/m/ct2", voiceLanguage: "", voiceGpuEnabled: false};
assert.deepStrictEqual(plain(S.migration(cfg)), {sttSettingsMigrated: true, sttModel: "/m/ct2"});
// A fresh install: dictation stays off.
assert.deepStrictEqual(plain(S.migration({voiceEnabled: false})), {sttSettingsMigrated: true});

console.log("stt_config ok");
