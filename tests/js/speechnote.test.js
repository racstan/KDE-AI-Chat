// Tests for voice/SpeechNote.js and the Speech Note entries of voice/TtsEngines.js and
// voice/SttEngines.js, run by tests/test_speechnote_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

function load(rel, names) {
    const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui", rel), "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/m, "");
    const ctx = {};
    vm.runInNewContext(src + "\nthis.exports = {" + names.join(", ") + "};", ctx);
    return ctx.exports;
}
const plain = x => JSON.parse(JSON.stringify(x));
const N = load("voice/SpeechNote.js", ["ERRORS", "errorText", "parse", "isError", "modelChoices", "withSaved", "KEEPALIVE_MS",
                                       "FLATHUB_URL", "GITHUB_URL"]);
const T = load("voice/TtsEngines.js", ["engines", "engine", "optionKeys", "settingsFor", "chunksFor", "defaultEngine", "fallbackEngine"]);
const S = load("voice/SttEngines.js", ["engines", "engine", "defaultEngine"]);

const tests = {
    every_helper_error_code_has_a_plain_message() {
        for (const code of ["not_installed", "service_failed_to_start", "not_configured", "timeout", "busy", "bus_error",
                            "bad_request", "mic_error", "engine_error"])
            assert.ok(N.ERRORS[code], code);
        assert.strictEqual(N.errorText("not_installed"), "Speech Note is not installed — see Settings → Voice");
        assert.strictEqual(N.errorText("mic_error"), "Speech Note could not use the microphone");
        assert.strictEqual(N.errorText("not_configured"), "Speech Note has no speech model yet — add one in Speech Note");
        assert.strictEqual(N.errorText("nonsense"), "Speech Note failed");
    },
    the_keepalive_is_well_inside_speech_notes_ten_seconds() {
        assert.ok(N.KEEPALIVE_MS <= 8000 && N.KEEPALIVE_MS >= 1000);
    },
    links_point_at_flathub_and_github() {
        assert.strictEqual(N.FLATHUB_URL, "https://flathub.org/apps/net.mkiol.SpeechNote");
        assert.strictEqual(N.GITHUB_URL, "https://github.com/mkiol/dsnote");
    },
    parse_takes_the_last_typed_line() {
        assert.strictEqual(N.parse('noise\n{"type":"speechnote_listening","task":3}\n', 0, "").task, 3);
        const bad = plain(N.parse("not json", 1, "boom"));
        assert.deepStrictEqual([bad.type, bad.code, bad.error], ["speechnote_error", "bus_error", "boom"]);
        assert.strictEqual(N.isError(N.parse('{"type":"speechnote_error","code":"timeout","error":"x"}', 0, "")), true);
        assert.strictEqual(N.isError(null), false);
    },
    model_pickers_start_with_the_default_and_show_the_language() {
        const rows = plain(N.modelChoices([{id: "a", name: "Whisper Base / English", lang: "en"}, {id: "b", name: "Piper Amy", lang: "de"}], "Default"));
        assert.deepStrictEqual(rows, [{value: "", text: "Default"}, {value: "a", text: "Whisper Base / English"},
                                      {value: "b", text: "Piper Amy (de)"}]);
        assert.deepStrictEqual(plain(N.modelChoices([], "Default")), [{value: "", text: "Default"}]);
    },
    a_saved_model_that_is_gone_stays_visible() {
        const rows = N.modelChoices([{id: "a", name: "A", lang: ""}], "Default");
        assert.strictEqual(N.withSaved(rows, "zz").length, 3);
        assert.strictEqual(N.withSaved(rows, "a").length, 2);
        assert.strictEqual(N.withSaved(rows, "").length, 2);
    },
    read_aloud_defaults_to_speech_note_with_the_system_voice_as_fallback() {
        assert.strictEqual(T.defaultEngine, "speechnote");
        assert.strictEqual(T.engines[0].id, "speechnote");
        assert.strictEqual(T.fallbackEngine, "system");
        assert.strictEqual(T.engine("speechnote").kind, "speechnote");
        assert.strictEqual(plain(T.optionKeys()).voiceTtsSpeechNoteModel, "");
        assert.strictEqual(T.settingsFor("speechnote", {voiceTtsSpeechNoteModel: "m1"}).voiceTtsSpeechNoteModel, "m1");
        assert.strictEqual(T.settingsFor("speechnote", {}).voiceTtsSpeechNoteModel, "");
    },
    speech_note_gets_the_whole_reply_in_one_piece() {
        const text = "First sentence. Second one!\n\nA third, with `code`.";
        const pieces = plain(T.chunksFor(T.engine("speechnote"), text));
        assert.strictEqual(pieces.length, 1);
        assert.ok(pieces[0].indexOf("First sentence.") === 0 && pieces[0].indexOf("A third, with code.") > 0);
        assert.deepStrictEqual(plain(T.chunksFor(T.engine("speechnote"), "   ")), []);
        assert.ok(T.chunksFor(T.engine("remote"), text).length >= 1, "the other engines split themselves");
    },
    dictation_defaults_to_speech_note_and_lists_it_first() {
        assert.strictEqual(S.defaultEngine, "speechnote");
        assert.strictEqual(S.engines[0].id, "speechnote");
        assert.deepStrictEqual(plain(S.engines.map(e => e.id)), ["speechnote", "remote"], "and the speech server is the only other");
    }
};

let failed = 0;
for (const name of Object.keys(tests)) {
    try { tests[name](); console.log("ok", name); }
    catch (e) { failed++; console.log("FAIL", name, e.message); }
}
process.exit(failed ? 1 : 0);
