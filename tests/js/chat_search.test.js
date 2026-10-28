// Tests for chat/ChatSearch.js (search across all chats), run by tests/test_chat_search.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/ChatSearch.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {search, snippet, patternFor, normalizeQuery, highlighted, escapeHtml, isIncognito, MAX_RESULTS, PER_CHAT};", ctx);
const S = ctx.exports;

const chats = [
    {value: "s-1", text: "Trip to Lisbon", updatedAt: 3000, messages: [
        {id: "m1", role: "user", content: "Where should I eat in Lisbon?", at: 1000},
        {id: "m2", role: "assistant", content: "Try the pastéis de nata near Belém.\nAlso the TIME OUT market.", at: 1100}]},
    {value: "s-2", text: "Taxes", archived: true, updatedAt: 2000, messages: [
        {id: "m3", role: "user", content: "How do I file taxes as a freelancer?", at: 900}]},
    {value: "s-3", text: "Work notes", projectId: "p-1", updatedAt: 1500, messages: [
        {id: "m4", role: "user", content: "Lisbon office move is in May", at: 800}]},
    {value: "s-incognito-1-1", text: "Secret Lisbon plans", incognito: true, messages: [
        {id: "m5", role: "user", content: "Lisbon surprise", at: 700}]},
];

const tests = {
    finds_titles_and_message_text_in_every_chat_but_incognito() {
        const out = S.search(chats, "lisbon");
        const keys = out.results.map(r => r.chatId + ":" + r.kind + ":" + r.messageId);
        assert.deepStrictEqual(Array.from(keys), ["s-1:title:", "s-1:message:m1", "s-3:message:m4"]);
        assert.strictEqual(out.more, false);
        assert.ok(S.isIncognito({value: "s-incognito-5-5"}));
        assert.ok(!S.isIncognito({value: "s-5"}));
    },
    archived_and_project_chats_are_found_and_labelled() {
        const taxes = S.search(chats, "freelancer").results;
        assert.strictEqual(taxes.length, 1);
        assert.strictEqual(taxes[0].archived, true);
        assert.strictEqual(taxes[0].messageIndex, 0);
        assert.strictEqual(taxes[0].at, 900);
        const office = S.search(chats, "office").results[0];
        assert.strictEqual(office.projectId, "p-1");
    },
    case_insensitive_literal_and_whitespace_tolerant() {
        const r = S.search(chats, "time   out").results;
        assert.strictEqual(r.length, 1);
        assert.strictEqual(r[0].match, "TIME OUT");
        assert.strictEqual(S.search(chats, "nata.near").results.length, 0, "the dot is literal");
        assert.strictEqual(S.search(chats, "((").results.length, 0);
        const multi = S.search(chats, "Belém. also").results;
        assert.strictEqual(multi.length, 1, "a line break matches a space");
        assert.strictEqual(multi[0].match, "Belém. Also");
    },
    short_queries_find_nothing() {
        assert.strictEqual(S.search(chats, "a").results.length, 0);
        assert.strictEqual(S.search(chats, "  ").results.length, 0);
        assert.strictEqual(S.patternFor(" x "), null);
    },
    snippets_show_no_markdown_marks() {
        const text = "Use `sort` and **uniq**:\n\n```bash\nsort names.txt | uniq -c\n```\nThat counts.";
        const sn = S.snippet(text, text.indexOf("uniq -c"), 7);
        assert.strictEqual(sn.before.indexOf("`"), -1, sn.before);
        assert.strictEqual(sn.before.indexOf("**"), -1, sn.before);
        assert.strictEqual(sn.before.indexOf("bash"), -1, "the fence's language is not text: " + sn.before);
        assert.ok(sn.before.indexOf("sort names.txt |") >= 0, sn.before);
        assert.strictEqual(sn.after.trim().indexOf("`"), -1, sn.after);
    },

    snippets_cut_the_context_at_words() {
        const text = "one two three four five six seven eight nine ten eleven twelve NEEDLE thirteen " + "x ".repeat(80);
        const sn = S.snippet(text, text.indexOf("NEEDLE"), 6);
        assert.strictEqual(sn.match, "NEEDLE");
        assert.ok(sn.before.startsWith("…"), sn.before);
        assert.ok(sn.after.endsWith("…"));
        assert.ok(sn.before.length <= 42);
        const whole = S.snippet("short NEEDLE here", 6, 6);
        assert.strictEqual(whole.before + whole.match + whole.after, "short NEEDLE here");
    },
    limits_per_chat_and_in_all() {
        const many = [{value: "s-many", text: "many", messages: Array.from({length: 20}, (_, i) => ({id: "x" + i, role: "user", content: "needle " + i}))}];
        const out = S.search(many, "needle");
        assert.strictEqual(out.results.length, S.PER_CHAT);
        assert.strictEqual(out.more, true);
        assert.strictEqual(out.results[0].messageId, "x19", "newest first");
        const lots = Array.from({length: 300}, (_, i) => ({value: "s-" + i, text: "chat " + i, messages: [{id: "m", role: "user", content: "needle"}]}));
        const all = S.search(lots, "needle");
        assert.strictEqual(all.results.length, S.MAX_RESULTS);
        assert.strictEqual(all.more, true);
    },
    highlight_escapes_markup() {
        const html = S.highlighted({before: "<b>a&", match: "x<y", after: "\"z\""}, "#3daee9");
        assert.ok(html.startsWith("&lt;b&gt;a&amp;"));
        assert.ok(html.includes("<b><font color=\"#3daee9\">x&lt;y</font></b>&quot;z&quot;"));
        assert.strictEqual(html.split("<b>").length, 2, "only the match is bold");
    },
    fast_with_hundreds_of_chats() {
        const words = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor".split(" ");
        const big = Array.from({length: 600}, (_, c) => ({value: "s-" + c, text: "Chat " + c, messages:
            Array.from({length: 80}, (_, m) => ({id: "m" + m, role: m % 2 ? "assistant" : "user",
                content: Array.from({length: 120}, (_, w) => words[(c + m + w) % words.length]).join(" ")}))}));
        const start = Date.now();
        const out = S.search(big, "zebra crossing");
        const took = Date.now() - start;
        assert.strictEqual(out.results.length, 0);
        assert.ok(took < 1500, "searching 48000 messages took " + took + " ms");
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try {
        fn();
        console.log("ok   " + name);
    } catch (e) {
        failed++;
        console.log("FAIL " + name + "\n" + e.stack);
    }
}
process.exit(failed ? 1 : 0);
