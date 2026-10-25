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

// Default exportedAt when missing is a valid date.
assert.ok(/- \*\*Exported:\*\* \d{4}-\d\d-\d\d \d\d:\d\d/.test(md({messages: []})));

console.log("chat_export ok");
