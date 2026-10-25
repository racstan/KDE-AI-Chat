// A realistic chat for the export tests and the sample files.
"use strict";
const T = Date.UTC(2026, 9, 25, 14, 2, 0);
module.exports = {
    title: "Fix the backup script",
    createdAt: T - 3600000,
    exportedAt: T + 600000,
    mode: "pi",
    provider: "Anthropic",
    model: "claude-sonnet-4",
    messages: [
        {role: "user", content: "Why does backup.sh fail on spaces in paths? See the attached script.", time: "14:02", at: T,
         attachments: [{name: "backup.sh", path: "/home/u/backup.sh", type: "text", mimeType: "text/x-shellscript", size: 2048, content: "SECRET-FILE-BODY", loading: false}]},
        {role: "assistant", model: "claude-sonnet-4", time: "14:03", at: T + 60000,
         reasoning: "The loop word-splits $f.",
         content: "The loop word-splits unquoted variables. Quote them:\n\n```bash\nfor f in \"$SRC\"/*; do\n  cp \"$f\" \"$DEST\"\ndone\n```\n\nThat keeps names with spaces intact.",
         tools: {
             c1: {name: "read", detail: "/home/u/backup.sh", status: "done", input: "{\"path\":\"/home/u/backup.sh\"}", output: "#!/bin/bash\nSRC=$1\nDEST=$2\nfor f in $SRC/*; do\n  cp $f $DEST\ndone\n"},
             c2: {name: "edit", detail: "", status: "error", input: "{\"path\":\"/home/u/backup.sh\"}", output: "Permission denied"}
         },
         filesChanged: ["/home/u/backup.sh"], tokens: {input: 412, output: 96}},
        {role: "permission_request", status: "pending", content: "", model: "Pi"},
        {role: "assistant", content: "", reasoning: "", model: "claude-sonnet-4", at: T + 90000},
        {role: "error", content: "Rate limit reached, try again later.", time: "14:05", at: T + 180000},
        {role: "queued", content: "Thanks, <think>x</think>done\u0000", time: "14:06", at: T + 240000}
    ]
};
