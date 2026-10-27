// Tests for voice/TtsEngines.js and chat/ReadAloudAction.js, run by tests/test_tts_engines_js.py.
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
const E = load("voice/TtsEngines.js", ["engines", "engine", "optionKeys", "settingsFor", "valueOfType", "speakableText", "chunks", "clampUnit", "clampSpeed", "defaultEngine",
                                         "fallbackEngine", "sentenceChunks", "chunksFor", "plainVoice"]);
const A = load("chat/ReadAloudAction.js", ["toggle", "shortcutTarget"]);

function same(a, b, msg) { assert.strictEqual(JSON.stringify(a), JSON.stringify(b), msg); }

const tests = {
    every_engine_has_unique_keys_and_a_known_kind() {
        const seen = {};
        E.engines.forEach(e => {
            assert.ok(e.kind === "qt" || e.kind === "file", e.id);
            e.options.forEach(o => {
                if (o.type === "choice") assert.ok(o.choices.some(c => c.value === o.def), o.key + " default is a choice");
                if (o.type === "secret") { assert.ok(o.entry && !o.key, "a secret is never a setting"); return; }
                assert.ok(/^voiceTts[A-Z]\w+$/.test(o.key), o.key);
                assert.ok(!seen[o.key], "duplicate " + o.key);
                seen[o.key] = true;
            });
        });
        assert.strictEqual(E.defaultEngine, "neural", "the natural voice is the default");
        assert.strictEqual(E.engines[0].id, "neural", "and first in the list");
        assert.strictEqual(E.fallbackEngine, "system");
        assert.strictEqual(E.engine("system").plugin, "speechd");
        assert.strictEqual(E.engine("system").options.filter(o => o.type === "rate" || o.type === "pitch").every(o => o.def === 0), true);
    },
    main_xml_declares_every_key_with_its_default() {
        const xml = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/config/main.xml"), "utf8");
        const keys = E.optionKeys();
        Object.keys(keys).concat(["voiceTtsEngine"]).forEach(k => {
            const m = new RegExp('<entry name="' + k + '" type="(\\w+)">\\s*<default>([^<]*)</default>').exec(xml);
            assert.ok(m, "main.xml lacks " + k);
            if (k !== "voiceTtsEngine")
                assert.strictEqual(String(m[2]), String(keys[k]), k + " default");
            else
                assert.strictEqual(m[2], E.defaultEngine, "main.xml's engine default");
        });
    },
    settings_fall_back_to_defaults() {
        const s = E.settingsFor("remote", {voiceTtsRemoteVoice: "nova"});
        assert.strictEqual(s.voiceTtsRemoteVoice, "nova");
        assert.strictEqual(s.voiceTtsRemoteModel, "tts-1");
        assert.strictEqual(E.valueOfType("system", {voiceTtsSystemVoice: ""}, "voice", "x"), "");
        assert.strictEqual(E.valueOfType("system", {voiceTtsSystemRate: 0.5}, "rate", 0), 0.5);
        assert.strictEqual(E.valueOfType("flite", {}, "language", "none"), "none");
    },
    markdown_is_made_speakable() {
        const t = E.speakableText("# Title\n\n**Bold** and *it* with `code`.\n\n```js\nx()\n```\n- [a link](https://x.y) here\n> quoted\nSee https://example.com/a");
        assert.strictEqual(t, "Title\nBold and it with code.\n(code block)\na link here\nquoted\nSee link");
        assert.strictEqual(E.speakableText("<think>hmm</think>Answer"), "Answer");
    },
    chunks_split_at_sentences_within_the_limit() {
        const text = "One. Two! Three? " + "word ".repeat(100);
        const c = E.chunks(text, 60);
        assert.strictEqual(c[0], "One. Two! Three?");
        c.forEach(x => assert.ok(x.length <= 60, x));
        assert.strictEqual(c.join(" ").replace(/\s+/g, " "), text.trim());
        same(E.chunks("  "), []);
    },
    sentence_engines_read_one_sentence_at_a_time() {
        const c = E.sentenceChunks("Hi. This is the first real sentence here. Note: it goes on! And on?\nA list item\nAnother");
        same(c, ["Hi. This is the first real sentence here.", "Note: it goes on!", "And on? A list item", "Another"]);
        const long = "word ".repeat(120).trim() + ".";
        E.sentenceChunks(long).forEach(x => assert.ok(x.length <= 240, x.length));
        same(E.chunksFor(E.engine("neural"), "**The first one.** The second one."), ["The first one.", "The second one."]);
        const qt = E.chunksFor(E.engine("system"), "One. Two. Three.");
        same(qt, ["One. Two. Three."], "a Qt engine says a normal reply in one go");
        assert.ok(E.chunksFor(E.engine("system"), "Sentence here. ".repeat(200)).every(x => x.length <= 1000));
        same(E.chunksFor(E.engine("neural"), "```\ncode\n```"), ["(code block)"]);
    },
    espeak_variants_are_hidden_unless_chosen() {
        assert.strictEqual(E.plainVoice("English (America)"), true);
        assert.strictEqual(E.plainVoice("English (Caribbean)+Linda"), false);
        assert.strictEqual(E.plainVoice("English (Caribbean)+Linda", "English (Caribbean)+Linda"), true);
    },
    clamps() {
        assert.strictEqual(E.clampUnit(3), 1);
        assert.strictEqual(E.clampUnit("x"), 0);
        assert.strictEqual(E.clampSpeed(0), 1);
        assert.strictEqual(E.clampSpeed(9), 2);
    },
    toggle_reads_and_stops() {
        const calls = [];
        const voice = {isPlaying: false, playTTS(t) { calls.push(["play", t]); this.isPlaying = true; }, stopTTS() { calls.push(["stop"]); this.isPlaying = false; }};
        const chat = {voiceManagerRef: voice, playingMessageIndex: -1};
        assert.strictEqual(A.toggle(chat, 2, "part of it"), true);
        assert.strictEqual(chat.playingMessageIndex, 2);
        assert.strictEqual(A.toggle(chat, 2, "part of it"), false, "the same message again stops");
        assert.strictEqual(chat.playingMessageIndex, -1);
        voice.isPlaying = true; chat.playingMessageIndex = 1;
        assert.strictEqual(A.toggle(chat, 3, "other"), true, "another message replaces it");
        same(calls, [["play", "part of it"], ["stop"], ["play", "other"]]);
        assert.strictEqual(A.toggle(chat, 4, "  "), false);
        assert.strictEqual(A.toggle({}, 1, "x"), false);
    },
    shortcut_target_prefers_the_selection() {
        const msgs = [{content: "q"}, {content: "picked"}, {content: "last"}];
        same(A.shortcutTarget({selectedText: "bit", messageIndex: 1}, msgs, -1, 2), {text: "bit", index: 1});
        same(A.shortcutTarget({selectedText: "typed"}, msgs, 1, 2), {text: "typed", index: -1});
        same(A.shortcutTarget({selectedText: ""}, msgs, 1, 2), {text: "picked", index: 1});
        same(A.shortcutTarget(null, msgs, -1, 2), {text: "last", index: 2});
        assert.strictEqual(A.shortcutTarget(null, [], -1, -1), null);
    }
};

let failed = 0;
for (const name of Object.keys(tests)) {
    try { tests[name](); console.log("ok", name); }
    catch (e) { failed++; console.log("FAIL", name, e.message); }
}
process.exit(failed ? 1 : 0);
