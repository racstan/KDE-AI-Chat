// Tests for chat/ChatExport.js, run by tests/test_chat_export.py (TZ=UTC).
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");
const fixture = require("./chat_export_fixture.js");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/chat/ChatExport.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.exports = {build, resolveTarget, filterLabels, FORMATS};", ctx);
const X = ctx.exports;
const clone = x => JSON.parse(JSON.stringify(x));
const md = (chat, opts) => X.build("markdown", clone(chat), opts);
const txt = (chat, opts) => X.build("text", clone(chat), opts);
const json = (chat, opts) => JSON.parse(X.build("json", clone(chat), opts));

// Formats and target resolution.
assert.deepStrictEqual(Array.from(X.filterLabels()), ["Markdown files (*.md)", "Plain text files (*.txt)", "JSON files (*.json)"]);
assert.strictEqual(X.resolveTarget("/h/a/Chat_1.md", 2).path, "/h/a/Chat_1.json");
assert.strictEqual(X.resolveTarget("/h/a/Chat_1.md", 2).format, "json");
assert.strictEqual(X.resolveTarget("/h/a/Chat_1", 1).path, "/h/a/Chat_1.txt");
assert.strictEqual(X.resolveTarget("/h/a/notes.v2", 0).path, "/h/a/notes.v2.md");
assert.strictEqual(X.resolveTarget("/h/a/X.TXT", 0).path, "/h/a/X.md");
assert.strictEqual(X.resolveTarget("/h/a/.md", 1).path, "/h/a/chat.txt");
assert.strictEqual(X.resolveTarget("/h/a/x.md", 9).format, "markdown");

// Markdown.
const m = md(fixture);
assert.ok(m.startsWith("# Fix the backup script\n"), m);
assert.ok(m.includes("- **Exported:** 2026-10-25 14:12"), m);
assert.ok(m.includes("- **Created:** 2026-10-25 13:02"), m);
assert.ok(m.includes("- **Mode:** Pi"), m);
assert.ok(m.includes("- **Provider:** Anthropic"), m);
assert.ok(m.includes("- **Model:** claude-sonnet-4"), m);
assert.ok(m.includes("- **Messages:** 4"), m);  // user, assistant, error, queued
assert.ok(m.includes("## You · 2026-10-25 14:02"), m);
assert.ok(m.includes("## Assistant (claude-sonnet-4) · 2026-10-25 14:03"), m);
assert.ok(m.includes("## Error · 2026-10-25 14:05\n\n> Rate limit reached, try again later."), m);
assert.ok(m.includes("```bash\nfor f in \"$SRC\"/*; do\n  cp \"$f\" \"$DEST\"\ndone\n```"), m);
assert.ok(m.includes("**Attachments**\n\n- backup.sh (2 KB)"), m);
assert.ok(m.includes("- `read: /home/u/backup.sh [done]`\n  Result: #!/bin/bash (6 lines)"), m);
assert.ok(m.includes("- `edit: {\"path\":\"/home/u/backup.sh\"} [failed]`\n  Result: Permission denied"), m);
assert.ok(m.includes("**Files changed**\n\n- `/home/u/backup.sh`"), m);
assert.ok(!m.includes("SECRET-FILE-BODY"), "attachment bodies stay out");
assert.ok(!m.includes("Reasoning") && !m.includes("word-splits $f"), "reasoning is omitted by default");
assert.ok(!m.includes("permission") && !m.includes("<div"), m);
assert.ok(!m.includes("<think>") && !m.includes("\u0000"), m);
assert.ok(m.includes("Thanks, done"), m);
assert.ok(!/\n{3,}/.test(m) && m.endsWith("\n") && !m.endsWith("\n\n"));
// Reasoning on request, in a marked section.
assert.ok(md(fixture, {includeReasoning: true}).includes("**Reasoning**\n\n> The loop word-splits $f."));

// Plain text.
const t = txt(fixture);
assert.ok(t.startsWith("=".repeat(60) + "\nFix the backup script\n" + "=".repeat(60) + "\n"), t);
assert.ok(t.includes("Mode: Pi\n") && t.includes("Provider: Anthropic\n") && t.includes("Model: claude-sonnet-4\n"), t);
assert.ok(t.includes("You  [2026-10-25 14:02]\n" + "-".repeat(60) + "\nWhy does"), t);
assert.ok(t.includes("```bash\nfor f in"), t);
assert.ok(t.includes("Attachments: backup.sh"), t);
assert.ok(t.includes("Tool: read: /home/u/backup.sh [done]\n  Result: #!/bin/bash (6 lines)"), t);
assert.ok(t.includes("Error: Rate limit reached"), t);
assert.ok(!t.includes("**") && !t.includes("<div") && !t.includes("💬"), t);
assert.ok(txt(fixture, {includeReasoning: true}).includes("[Reasoning]\n  The loop word-splits $f."));

// JSON.
const j = json(fixture);
assert.strictEqual(j.format, "kdeaichat-chat");
assert.strictEqual(j.version, 1);
assert.strictEqual(j.title, "Fix the backup script");
assert.strictEqual(j.exportedAt, "2026-10-25T14:12:00.000Z");
assert.strictEqual(j.createdAt, "2026-10-25T13:02:00.000Z");
assert.strictEqual(j.mode, "pi");
assert.strictEqual(j.messages.length, 4);
assert.deepStrictEqual(j.messages.map(x => x.role), ["user", "assistant", "error", "user"]);
assert.strictEqual(j.messages[0].time, "2026-10-25T14:02:00.000Z");
assert.deepStrictEqual(j.messages[0].attachments, [{name: "backup.sh", type: "text", mimeType: "text/x-shellscript", size: 2048}]);
assert.strictEqual(j.messages[1].toolCalls.length, 2);
assert.strictEqual(j.messages[1].toolCalls[0].name, "read");
assert.strictEqual(j.messages[1].toolCalls[1].status, "error");
assert.deepStrictEqual(j.messages[1].tokens, {input: 412, output: 96});
assert.strictEqual(j.messages[1].reasoning, undefined);
assert.strictEqual(json(fixture, {includeReasoning: true}).messages[1].reasoning, "The loop word-splits $f.");
assert.ok(!JSON.stringify(j).includes("SECRET-FILE-BODY"));
assert.ok(!("loading" in j.messages[0].attachments[0]) && !("path" in j.messages[0].attachments[0]));

// Empty chat.
const empty = {title: "", messages: [], exportedAt: fixture.exportedAt};
assert.ok(md(empty).startsWith("# Untitled chat\n"));
assert.ok(md(empty).includes("*This chat has no messages.*"));
assert.ok(md(empty).includes("- **Mode:** Direct") && !md(empty).includes("Created") && !md(empty).includes("Provider"));
assert.ok(txt(empty).includes("(This chat has no messages.)"));
assert.deepStrictEqual(json(empty).messages, []);
assert.strictEqual(json(empty).createdAt, null);
assert.deepStrictEqual(clone(json({messages: null})).messages, []);

// Odd characters.
const odd = {title: "Tab\there *bold* `x`\nnew line", exportedAt: fixture.exportedAt, messages: [
    {role: "user", content: "emoji 🎉 \u202e RTL, \r\ncrlf, \u200bzero-width\u0007bell", time: "09:00"},
    {role: "assistant", content: "Open fence:\n```python\nprint(1)", time: "09:01", model: "m_1*"},
    {role: "assistant", content: "Nested:\n```md\n````\n```\n", time: "09:02", attachments: [{name: "a*b_c`.txt"}, {name: ""}, null]},
    {role: "weird", content: "x"}, null, "text"
]};
const om = md(odd);
assert.ok(om.startsWith("# Tab here *bold* `x` new line\n"), om);
assert.ok(om.includes("emoji 🎉") && !om.includes("\r") && !om.includes("\u200b") && !om.includes("\u0007"), om);
assert.ok(om.includes("## You · 09:00") && om.includes("## Assistant (m\\_1\\*) · 09:01"), om);
assert.ok(om.includes("```python\nprint(1)\n```"), "an open fence is closed:\n" + om);
assert.ok(om.includes("- a\\*b\\_c\\`.txt"), om);
assert.strictEqual(json(odd).messages.length, 3);
assert.strictEqual(json(odd).messages[2].attachments.length, 1);

// Quotes: Markdown block quotes above the message's text; text and JSON keep them too.
const quoted = {title: "Q", exportedAt: fixture.exportedAt, messages: [
    {role: "assistant", id: "m-1", model: "m", content: "Use rsync.\n\nIt is faster.", time: "09:00"},
    {role: "user", content: "Why?", time: "09:01", quotes: [
        {id: "m-1", role: "assistant", text: "Use rsync.\n\nIt is faster."},
        {id: "m-0", role: "user", text: "single line"},
        {id: "x", role: "user", text: "  "}, null]},
    {role: "assistant", content: "Answer", time: "09:02", quotes: [{role: "user", text: "ignored on a reply"}]}
]};
const qm = md(quoted);
assert.ok(qm.includes("## You · 09:01\n\n> **Assistant:** Use rsync.\n>\n> It is faster.\n\n> **You:** single line\n\nWhy?"), qm);
assert.ok(!qm.includes("ignored on a reply"), qm);
assert.ok(txt(quoted).includes("You  [09:01]\n" + "-".repeat(60) + "\n> Assistant: Use rsync.\n> \n> It is faster.\n\n> You: single line\n\nWhy?"), txt(quoted));
const qj = json(quoted).messages;
assert.deepStrictEqual(qj[1].quotes, [{role: "assistant", text: "Use rsync.\n\nIt is faster."}, {role: "user", text: "single line"}]);
assert.strictEqual(qj[0].quotes, undefined);
assert.strictEqual(qj[2].quotes, undefined);
assert.ok(!md(fixture).includes("**You:**"), "no quotes, nothing added");

// Default exportedAt when missing is a valid date.
assert.ok(/- \*\*Exported:\*\* \d{4}-\d\d-\d\d \d\d:\d\d/.test(md({messages: []})));

// A direct-mode reply that asked the user a question (ask_user): the question and the answer are exported
// with the reply; the question card message itself is left out.
const asked = {title: "Colours", messages: [
    {role: "user", content: "Pick a colour for me", at: 1000, time: "09:00"},
    {role: "assistant", content: "", model: "m1", at: 2000, time: "09:01",
     tools: {call_1: {name: "ask_user", status: "done", detail: "Which colour?", input: "{\"question\":\"Which colour?\"}", output: "Blue"}},
     toolRounds: [{text: "", calls: [{id: "call_1", name: "ask_user", args: {question: "Which colour?"}}]}]},
    {role: "question_request", status: "answered", questionId: "q1", questions: [{question: "Which colour?"}]},
    {role: "assistant", content: "Blue it is.", model: "m1", at: 3000, time: "09:02"}]};
const am = md(asked);
assert.ok(am.includes("ask_user") && am.includes("Which colour?") && am.includes("Blue"), am);
assert.ok(am.includes("Blue it is."), am);
assert.ok(!am.includes("question_request"), am);
assert.strictEqual(json(asked).messages.length, 3);

// Images: listed by their relative paths and notes; the markdown links them; no picture data is exported.
const pics = {title: "Pics", exportedAt: fixture.exportedAt, messages: [
    {role: "user", content: "/image a red fox", at: 1000, time: "09:00"},
    {role: "assistant", content: "", model: "Deliberate", at: 2000, time: "09:01", images: [
        {path: "images/s-1-2/m-9-0.webp", mime: "image/webp", bytes: 4100, source: "generated", prompt: "a red fox", service: "AI Horde",
         model: "Deliberate", width: 512, height: 512, seed: "77", b64: "SHOULD-NOT-APPEAR", url: "https://signed.example.com/x"},
        {path: "../../etc/passwd", mime: "image/png"}, {path: "images/s-1-2/a.svg"}, {path: "images/s-1-2/m-9-1.png", mime: "image/png", bytes: 10}]}]};
const pm = md(pics);
assert.ok(pm.includes("**Images**\n\n![a red fox](images/s-1-2/m-9-0.webp)\n*AI Horde, Deliberate, 512x512, seed 77, prompt: a red fox, m-9-0.webp*"), pm);
assert.ok(pm.includes("![m-9-1.png](images/s-1-2/m-9-1.png)"), pm);
assert.ok(!pm.includes("passwd") && !pm.includes("a.svg") && !pm.includes("SHOULD-NOT-APPEAR") && !pm.includes("signed.example"), pm);
assert.ok(txt(pics).includes("Image: images/s-1-2/m-9-0.webp (AI Horde, Deliberate, 512x512, seed 77, prompt: a red fox, m-9-0.webp)"), txt(pics));
const pj = json(pics).messages[1];
assert.strictEqual(pj.images.length, 2);
assert.deepStrictEqual(pj.images[0], {path: "images/s-1-2/m-9-0.webp", file: "m-9-0.webp", mime: "image/webp", bytes: 4100, source: "generated",
    prompt: "a red fox", service: "AI Horde", model: "Deliberate", width: 512, height: 512, seed: "77"});
assert.ok(!JSON.stringify(json(pics)).includes("SHOULD-NOT-APPEAR"));
assert.strictEqual(json(fixture).messages[0].images, undefined);

// Names from Settings → Personality: used for the speakers and quotes; none set = as before.
const named = Object.assign(clone(fixture), {userName: "Rachit", aiName: "Nova\nX"});
named.messages[0].quotes = [{role: "assistant", text: "Earlier answer"}];
const nm = md(named);
assert.ok(nm.includes("## Rachit · 2026-10-25"), nm);
assert.ok(nm.includes("## Nova X (claude-sonnet-4) · "), nm);
assert.ok(nm.includes("> **Nova X:** Earlier answer"), nm);
assert.ok(!nm.includes("## You") && !nm.includes("## Assistant"), nm);
assert.ok(txt(named).includes("Rachit  ["), txt(named));
assert.strictEqual(json(named).userName, "Rachit");
assert.strictEqual(json(named).aiName, "Nova X");
assert.ok(!("userName" in json(fixture)) && !("aiName" in json(fixture)), "no names: not in the file");
assert.strictEqual(md(Object.assign(clone(fixture), {userName: "  ", aiName: ""})), md(fixture), "blank names change nothing");

console.log("chat_export ok");
