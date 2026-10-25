// Tests for chat/MessageContent.js (a user message as request content, with
// quotes), run by tests/test_message_content.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/MessageContent.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {build, makeQuote, canQuote, capQuote, quoteContext, quoteFirstLine, quoteRole, MAX_QUOTE_CHARS, MAX_QUOTES};", ctx);
const C = ctx.exports;
const plain = x => JSON.parse(JSON.stringify(x));

const tests = {
    no_quotes_leaves_the_text_unchanged() {
        assert.strictEqual(C.build("hello", [], "openai"), "hello");
        assert.strictEqual(C.build("hello", [], "openai", []), "hello");
        assert.strictEqual(C.build("hello", [], "openai", undefined), "hello");
        assert.strictEqual(C.build("hello", undefined, "anthropic", null), "hello");
        assert.strictEqual(C.quoteContext(undefined), "");
        assert.strictEqual(C.quoteContext([]), "");
    },
    one_quote_goes_in_front_as_a_block_quote_with_a_speaker() {
        const out = C.build("And in zsh?", [], "openai", [{id: "m-1", role: "assistant", text: "Use rsync.\nIt is faster."}]);
        assert.strictEqual(out, "> Quoted (assistant):\n> Use rsync.\n> It is faster.\n\nAnd in zsh?");
    },
    several_quotes_keep_their_order_and_are_separated() {
        const out = C.build("Compare", [], "openai", [
            {id: "a", role: "user", text: "first"},
            {id: "b", role: "assistant", text: "second\n\nwith a blank line"},
            {id: "c", role: "opencode_assistant", text: "third"}]);
        assert.strictEqual(out,
            "> Quoted (user):\n> first\n\n> Quoted (assistant):\n> second\n>\n> with a blank line\n\n> Quoted (assistant):\n> third\n\nCompare");
    },
    a_long_quote_is_cut_at_4000_characters_with_an_ellipsis() {
        const long = "x".repeat(5000);
        const out = C.build("q", [], "openai", [{role: "user", text: long}]);
        assert.strictEqual(out, "> Quoted (user):\n> " + "x".repeat(4000) + "…\n\nq");
        assert.strictEqual(C.MAX_QUOTE_CHARS, 4000);
        assert.strictEqual(C.capQuote("y".repeat(4000)), "y".repeat(4000), "exactly the cap: untouched");
        assert.strictEqual(C.capQuote("y".repeat(4001)).length, 4001, "cap plus the ellipsis");
    },
    empty_quotes_and_odd_entries_are_skipped_and_the_number_is_capped() {
        assert.strictEqual(C.build("t", [], "openai", [{role: "user", text: "  "}, null, {role: "user"}]), "t");
        const many = Array.from({length: 15}, (_, i) => ({role: "user", text: "n" + i}));
        const out = C.quoteContext(many);
        assert.strictEqual((out.match(/Quoted/g) || []).length, C.MAX_QUOTES);
        assert.ok(out.includes("> n9") && !out.includes("> n10"));
    },
    crlf_is_normalised() {
        assert.strictEqual(C.quoteContext([{role: "user", text: "a\r\nb"}]), "> Quoted (user):\n> a\n> b\n\n");
    },
    quotes_come_after_attached_files_and_before_the_text() {
        const att = [{type: "text", name: "n.txt", size: 10, content: "FILE"}];
        const out = C.build("question", att, "openai", [{role: "user", text: "earlier"}]);
        assert.ok(out.startsWith("[Attached File: n.txt"), out);
        assert.ok(out.indexOf("--- END OF FILE CONTENT ---") < out.indexOf("> Quoted (user):"), out);
        assert.ok(out.endsWith("> earlier\n\nquestion"), out);
    },
    quotes_with_images_are_in_the_text_part_in_both_api_formats() {
        const att = [{type: "image", mimeType: "image/png", content: "AAAA"}];
        const q = [{role: "assistant", text: "see this"}];
        const openai = C.build("what?", att, "openai", q);
        assert.strictEqual(openai[0].text, "> Quoted (assistant):\n> see this\n\nwhat?");
        assert.strictEqual(openai[1].type, "image_url");
        const anthropic = C.build("what?", att, "anthropic", q);
        assert.strictEqual(anthropic[0].text, "> Quoted (assistant):\n> see this\n\nwhat?");
        assert.strictEqual(anthropic[1].type, "image");
    },
    make_quote_takes_what_can_be_quoted() {
        assert.deepStrictEqual(plain(C.makeQuote({id: "m-7", role: "assistant", content: "  Hi  "})), {id: "m-7", role: "assistant", text: "Hi"});
        assert.deepStrictEqual(plain(C.makeQuote({id: "m-8", role: "queued", content: "later"})), {id: "m-8", role: "user", text: "later"});
        assert.strictEqual(C.makeQuote({role: "opencode_assistant", content: "x"}).role, "assistant");
        assert.strictEqual(C.makeQuote({role: "error", content: "boom"}), null);
        assert.strictEqual(C.makeQuote({role: "permission_request", content: "x"}), null);
        assert.strictEqual(C.makeQuote({role: "user", content: "   "}), null);
        assert.strictEqual(C.makeQuote(null), null);
        assert.strictEqual(C.makeQuote({role: "user", content: "no id"}).id, "");
        assert.strictEqual(C.makeQuote({role: "user", content: "z".repeat(9000)}).text.length, 4001);
        assert.strictEqual(C.canQuote({role: "user", content: "a"}), true);
        assert.strictEqual(C.canQuote({role: "error", content: "a"}), false);
    },
    first_line_for_a_chip() {
        assert.strictEqual(C.quoteFirstLine("\n  \n  Hello   world \nsecond"), "Hello world");
        assert.strictEqual(C.quoteFirstLine(""), "");
        assert.strictEqual(C.quoteFirstLine(undefined), "");
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); } catch (e) { failed++; console.error("FAIL " + name + "\n" + e.message); }
}
if (failed) process.exit(1);
console.log("message_content ok");
