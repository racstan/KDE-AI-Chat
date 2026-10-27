// Tests for voice/SttConfig.js and voice/SttEngines.js, run by tests/test_stt_config_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const ui = path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/");
const load = (file, exportsList) => {
    const source = fs.readFileSync(path.join(ui, file), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
    const ctx = {};
    vm.runInNewContext(source + "\nthis.exports = {" + exportsList + "};", ctx);
    return ctx.exports;
};
const S = load("voice/SttConfig.js", "payload, migration, applyMigration, migratedEngine, KEYS, ENGINES");
const plain = x => JSON.parse(JSON.stringify(x));

// Defaults: dictation off, Speech Note (its own default model), auto language.
let p = plain(S.payload({}));
assert.strictEqual(p.sttEnabled, false);
assert.strictEqual(p.sttEngine, "speechnote");
assert.strictEqual(p.sttSpeechNoteModel, "");
assert.strictEqual(p.sttLanguage, "auto");
assert.strictEqual(p.sttRemoteModel, "whisper-1");
assert.deepStrictEqual(Object.keys(p).sort(), plain(S.KEYS).sort());
for (const gone of ["sttModel", "sttParakeetModel", "sttDevice", "sttCommand", "sttWhisperCppBinary", "sttWhisperCppModel",
                    "sttWhisperCppServer", "sttIdleMinutes", "venv"])
    assert.ok(!(gone in p), gone + " is no longer a dictation setting");

p = plain(S.payload({sttEnabled: true, sttEngine: "remote", sttRemoteUrl: "https://x/v1", voiceVenvPath: "/opt/venv"}));
assert.strictEqual(p.sttEnabled, true);
assert.strictEqual(p.sttEngine, "remote");
assert.strictEqual(p.sttRemoteUrl, "https://x/v1");
assert.ok(!("apiKey" in p) && !JSON.stringify(p).includes("key"), "no key in the payload");

// Only Speech Note and the speech server exist; a saved engine that was removed means Speech Note.
assert.deepStrictEqual(plain(S.ENGINES), ["speechnote", "remote"]);
for (const gone of ["parakeet", "faster-whisper", "whisper-cpp", "command", "", "nonsense", undefined, null]) {
    assert.strictEqual(S.migratedEngine(gone), "speechnote", String(gone));
    assert.strictEqual(plain(S.payload({sttEngine: gone})).sttEngine, "speechnote");
}
assert.strictEqual(S.migratedEngine("remote"), "remote");
assert.strictEqual(S.migratedEngine("speechnote"), "speechnote");

// The migration moves each removed engine to Speech Note, every start (and keeps the others).
for (const gone of ["parakeet", "faster-whisper", "whisper-cpp", "command"]) {
    const c = {sttEngine: gone, sttSettingsMigrated: true, sttEnabled: true};
    assert.deepStrictEqual(plain(S.applyMigration(c)), {sttEngine: "speechnote"}, gone);
    assert.strictEqual(c.sttEngine, "speechnote");
    assert.deepStrictEqual(plain(S.migration(c)), {}, "only once");
}
assert.deepStrictEqual(plain(S.migration({sttEngine: "remote", sttSettingsMigrated: true})), {});
assert.deepStrictEqual(plain(S.migration({sttEngine: "speechnote", sttSettingsMigrated: true})), {});

// Old voice settings carry over once; dictation stays on for people who had voice on. A Whisper model they
// had picked is no longer an engine: they get Speech Note.
let cfg = {voiceEnabled: true, voiceSttModel: "medium", voiceLanguage: "de", voiceGpuEnabled: true, sttSettingsMigrated: false,
           sttEngine: "faster-whisper"};
assert.deepStrictEqual(plain(S.applyMigration(cfg)),
    {sttEngine: "speechnote", sttSettingsMigrated: true, sttEnabled: true, sttLanguage: "de"});
assert.strictEqual(cfg.sttEnabled, true);
assert.deepStrictEqual(plain(S.migration(cfg)), {}, "only once");
// A fresh install: dictation stays off.
assert.deepStrictEqual(plain(S.migration({voiceEnabled: false})), {sttSettingsMigrated: true});
assert.deepStrictEqual(plain(S.migration({})), {sttSettingsMigrated: true});

// voice/SttEngines.js: the two engines the Voice page offers.
const E = load("voice/SttEngines.js", "engines, engine, defaultEngine, languages");
assert.deepStrictEqual(plain(E.engines.map(e => e.id)), ["speechnote", "remote"]);
assert.strictEqual(E.defaultEngine, "speechnote");
assert.strictEqual(E.engine("parakeet"), null);
assert.strictEqual(E.engine("command"), null);
const secret = E.engine("remote").options.filter(o => o.type === "secret")[0];
assert.strictEqual(secret.entry, "stt-remote");
assert.ok(!("key" in secret), "a key option has no settings key: it goes to KWallet");
assert.ok(E.engines.every(e => e.options.every(o => o.type !== "command" && o.type !== "file")), "no command or file option");
assert.deepStrictEqual(plain(E.engine("remote").options.map(o => o.key).filter(Boolean)), ["sttRemoteUrl", "sttRemoteModel"]);

console.log("stt_config ok");
