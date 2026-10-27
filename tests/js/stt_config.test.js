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

// Defaults: dictation off, Speech Note (its own default model), Parakeet's default model (faster-whisper "small" when chosen), auto device and language.
let p = plain(S.payload({}));
assert.strictEqual(p.sttEnabled, false);
assert.strictEqual(p.sttEngine, "speechnote");
assert.strictEqual(p.sttSpeechNoteModel, "");
assert.strictEqual(p.sttParakeetModel, "parakeet-unified-en-0.6b");
assert.strictEqual(p.sttModel, "small");
assert.strictEqual(p.sttDevice, "auto");
assert.strictEqual(p.sttLanguage, "auto");
assert.strictEqual(p.venv, undefined);
assert.deepStrictEqual(Object.keys(p).sort(), plain(S.KEYS).sort());

p = plain(S.payload({sttEnabled: true, sttEngine: "remote", sttRemoteUrl: "https://x/v1", voiceVenvPath: "/opt/venv"}));
assert.strictEqual(p.sttEnabled, true);
assert.strictEqual(p.sttRemoteUrl, "https://x/v1");
assert.strictEqual(p.venv, undefined, "the venv folder is no longer a setting");
assert.ok(!("apiKey" in p) && !JSON.stringify(p).includes("key"), "no key in the payload");

// Old voice settings carry over once; dictation stays on for people who had voice on.
let cfg = {voiceEnabled: true, voiceSttModel: "medium", voiceLanguage: "de", voiceGpuEnabled: true, sttSettingsMigrated: false};
assert.deepStrictEqual(plain(S.applyMigration(cfg)),
    {sttSettingsMigrated: true, sttEnabled: true, sttModel: "medium", sttEngine: "faster-whisper", sttLanguage: "de",
     sttDevice: "cuda"});
assert.strictEqual(cfg.sttEnabled, true);
assert.deepStrictEqual(plain(S.migration(cfg)), {}, "only once");

cfg = {voiceEnabled: false, voiceSttModel: "small", voiceSttModelPath: "/m/ct2", voiceLanguage: "", voiceGpuEnabled: false};
assert.deepStrictEqual(plain(S.migration(cfg)), {sttSettingsMigrated: true, sttModel: "/m/ct2", sttEngine: "faster-whisper"});
// A fresh install: dictation stays off.
assert.deepStrictEqual(plain(S.migration({voiceEnabled: false})), {sttSettingsMigrated: true});

// voice/SttEngines.js: which engines can be picked, sizes, folders.
const enginesSource = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/voice/SttEngines.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ectx = {};
vm.runInNewContext(enginesSource + "\nthis.exports = {engines, split, size, isFolder, engine, defaultEngine, isLocal, devicesFor, deviceFor};", ectx);
const E = ectx.exports;
assert.deepStrictEqual(plain(E.engines.map(e => e.id)), ["speechnote", "parakeet", "faster-whisper", "whisper-cpp", "remote", "command"]);
assert.strictEqual(E.defaultEngine, "speechnote");
assert.ok(E.isLocal("parakeet") && E.isLocal("faster-whisper") && !E.isLocal("remote"));
assert.deepStrictEqual(plain(E.devicesFor("parakeet").map(d => d.value)), ["auto", "cpu", "gpu"]);
assert.deepStrictEqual(plain(E.devicesFor("faster-whisper").map(d => d.value)), ["auto", "cpu", "cuda"]);
assert.strictEqual(E.deviceFor("parakeet", "cuda"), "gpu");
assert.strictEqual(E.deviceFor("faster-whisper", "gpu"), "cuda");
assert.strictEqual(E.deviceFor("parakeet", ""), "auto");
assert.ok(E.isFolder("/home/u/models/p.gguf") && !E.isFolder("parakeet-unified-en-0.6b"));
const parts = plain(E.split([{id: "faster-whisper", available: false, selectable: true},
                             {id: "whisper-cpp", available: false, selectable: false, reason: "whisper-cli not found"},
                             {id: "remote", available: true}, {id: "nope", available: true}]));
assert.deepStrictEqual(parts.choices.map(r => r.id), ["faster-whisper", "remote"]);
assert.deepStrictEqual(parts.unavailable.map(r => r.id), ["whisper-cpp"]);
assert.strictEqual(E.size(484), "484 MB");
assert.strictEqual(E.size(1530), "1.5 GB");
assert.ok(E.isFolder("/home/u/models/x") && !E.isFolder("small"));
const secret = E.engine("remote").options.filter(o => o.type === "secret")[0];
assert.strictEqual(secret.entry, "stt-remote");
assert.ok(!("key" in secret), "a key option has no settings key: it goes to KWallet");

console.log("stt_config ok");
