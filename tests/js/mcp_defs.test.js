// Tests for mcp/McpDefs.js and config/McpForm.js (run by tests/test_mcp_defs.py).
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const ui = path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/");
function load(file, names) {
    const src = fs.readFileSync(path.join(ui, file), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
    const ctx = {};
    vm.runInNewContext(src + "\nthis.exports = {" + names + "};", ctx);
    return ctx.exports;
}
const D = load("mcp/McpDefs.js", "walletEntry, isRemote, secretNames, resolve, fingerprint, entries, chosen, shortError, makeId");
const F = load("config/McpForm.js", "parseLines, pairs, build, fromCandidate, approvalLabel");
const plain = x => JSON.parse(JSON.stringify(x));

const tests = {
    secrets_are_found_and_resolved() {
        const def = {id: "a", enabled: true, url: "https://x", headers: {Authorization: {secret: "TOK"}, "X-Plain": "p"}};
        assert.deepStrictEqual(plain(D.secretNames(def)), ["TOK"]);
        const r = D.resolve(def, {TOK: "abc"});
        assert.deepStrictEqual(plain(r.definition), {id: "a", url: "https://x", headers: {Authorization: "abc", "X-Plain": "p"}});
        assert.deepStrictEqual(plain(r.missing), []);
        assert.strictEqual(D.walletEntry("a"), "mcp-a");
        const m = D.resolve(def, {});
        assert.deepStrictEqual(plain(m.missing), ["TOK"]);
        assert.strictEqual(m.definition.headers.Authorization, undefined);
    },
    entries_become_runner_tools() {
        const e = D.entries("files", [{name: "echo", description: "E", inputSchema: {type: "object"}}, {name: ""}, null]);
        assert.strictEqual(e.length, 1);
        assert.strictEqual(e[0].source, "mcp:files");
        assert.strictEqual(e[0].server, "files");
        assert.strictEqual(e[0].risk, "change");
        assert.deepStrictEqual(plain(e[0].schema), {type: "object"});
    },
    a_chat_uses_all_enabled_servers_unless_it_chooses() {
        const servers = [{id: "a"}, {id: "b", enabled: false}, {id: "c", enabled: true}];
        assert.deepStrictEqual(D.chosen(servers, null).map(s => s.id), ["a", "c"]);
        assert.deepStrictEqual(D.chosen(servers, undefined).map(s => s.id), ["a", "c"]);
        assert.deepStrictEqual(D.chosen(servers, ["c", "b"]).map(s => s.id), ["c"]);
        assert.deepStrictEqual(D.chosen(servers, []).map(s => s.id), []);
    },
    ids_are_made_from_names() {
        assert.strictEqual(D.makeId("My Files!", []), "my-files");
        assert.strictEqual(D.makeId("files", ["files"]), "files-2");
        assert.strictEqual(D.makeId("???", []), "server");
        assert.ok(D.makeId("x".repeat(80), []).length <= 40);
    },
    form_builds_a_command_server_with_secret_placeholders() {
        const r = F.build({name: "GH", kind: "command", command: "npx", args: "-y\n\n gh \n", cwd: "",
            env: [{name: "TOKEN", value: "v", secret: true}, {name: "MODE", value: "ro", secret: false}, {name: "", value: ""}]}, [], D.makeId);
        assert.ok(r.ok);
        assert.strictEqual(r.id, "gh");
        assert.deepStrictEqual(plain(r.definition), {id: "gh", enabled: true, command: "npx", args: ["-y", "gh"], env: {TOKEN: {secret: "TOKEN"}, MODE: "ro"}});
        assert.deepStrictEqual(plain(r.secrets), {TOKEN: "v"});
        assert.ok(JSON.stringify(r.definition).indexOf('"v"') < 0);
    },
    form_builds_a_url_server_and_checks_input() {
        const r = F.build({name: "R", kind: "url", url: " https://a.b/mcp ", headers: [{name: "Authorization", value: "Bearer t", secret: true}]}, ["r"], D.makeId);
        assert.ok(r.ok);
        assert.strictEqual(r.id, "r-2");
        assert.strictEqual(r.definition.url, "https://a.b/mcp");
        assert.deepStrictEqual(plain(r.secrets), {Authorization: "Bearer t"});
        assert.ok(!F.build({name: "", kind: "url"}, [], D.makeId).ok);
        assert.ok(!F.build({name: "x", kind: "url", url: "ftp://x"}, [], D.makeId).ok);
        assert.ok(!F.build({name: "x", kind: "command", command: " "}, [], D.makeId).ok);
        assert.ok(!F.build({name: "x", kind: "command", command: "a", env: [{name: "bad name", value: "1"}]}, [], D.makeId).ok);
        assert.ok(!F.build({name: "x", kind: "command", command: "a", env: [{name: "K", value: "", secret: true}]}, [], D.makeId).ok);
    },
    import_candidates_keep_secrets_out_of_the_definition() {
        const r = F.fromCandidate({id: "gh", enabled: false, command: "npx", args: ["-y", "gh"],
            env: {GITHUB_TOKEN: {secret: "GITHUB_TOKEN", value: "ghp"}, MODE: "ro"}});
        assert.deepStrictEqual(plain(r.definition), {id: "gh", enabled: false, command: "npx", args: ["-y", "gh"],
            env: {GITHUB_TOKEN: {secret: "GITHUB_TOKEN"}, MODE: "ro"}});
        assert.deepStrictEqual(plain(r.secrets), {GITHUB_TOKEN: "ghp"});
        assert.strictEqual(JSON.stringify(r.definition).indexOf("ghp"), -1);
    },
    approval_labels() {
        assert.strictEqual(F.approvalLabel("mcp:files:echo"), "echo (files)");
        assert.strictEqual(F.approvalLabel("workspace:/w:write_file"), "workspace:/w:write_file");
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try {
        fn();
    } catch (e) {
        failed++;
        console.error("FAIL " + name + ": " + e.message);
    }
}
process.exit(failed ? 1 : 0);
