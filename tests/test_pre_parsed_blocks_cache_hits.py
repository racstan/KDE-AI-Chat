"""Test that pre-parse paths set lastParsedContent consistently.

`parseSessions`, `appendMessageToSession`, and `flushStreamingBuffer` all
pre-compute the `blocks` array on message objects so the per-delegate
Repeater in MessageContent.qml doesn't re-run `parseMessageBlocks()` on
every binding evaluation. The downstream `onMessagesChanged` guard in
main.qml checks:

    if (m.blocks === undefined || m.lastParsedContent !== m.content) {
        m.blocks = parseMessageBlocks(m.content);
        m.lastParsedContent = m.content;
    }

If a pre-parse path sets `blocks` but forgets `lastParsedContent`, the
second clause is always true and the optimization is defeated — every
loaded or appended message gets re-parsed on the very next
`onMessagesChanged` fire.

These tests load MainDatabase.js (with QML directives stripped) under
node, stub the QML/Plasma globals it references, and assert that the
output message objects have both `blocks` AND `lastParsedContent` set
on the pre-parse paths we can drive from JS.
"""
import json
import os
import re
import subprocess
import tempfile
import unittest

JS_PATH = os.path.join(
    os.path.dirname(__file__),
    "..", "org.kde.plasma.kdeaichat", "contents", "ui",
    "ChatEngine.js",
)
UI_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "org.kde.plasma.kdeaichat", "contents", "ui",
)


def _strip_qml_directives(src: str) -> str:
    """Strip the leading ``.pragma library`` line so plain Node can run it."""
    return re.sub(r"^\s*\.pragma\s+library\s*\n", "", src, count=1)


def _read_stripped(filename: str) -> str:
    with open(os.path.join(UI_DIR, filename)) as f:
        return _strip_qml_directives(f.read())


def _find_runner() -> str:
    for runner in ("node", "qjs6", "qjs"):
        if subprocess.run(["which", runner], capture_output=True).returncode == 0:
            return runner
    return ""


RUNNER = _find_runner()


# Stubs that make MainDatabase.js safe to evaluate in plain node.
# We need stubs for: Qt, plasmoid, root, StandardPaths, plus
# the helper modules it .imports (SessionManager, Security, etc.)
GLOBAL_STUBS = """
var plasmoid = { configuration: {} };
var root = {
    _markdownCache: { get: function() { return undefined; }, put: function() {} },
    _blocksCache: { get: function() { return undefined; }, put: function() {} },
    sessions: [],
    currentSessionId: "",
    currentSessionTitle: "",
    messages: [],
    expanded: false,
    historyOnlyMode: false,
    userScrolledUp: false,
    popupIsDark: false,
    streamingResponse: false,
    streamingContent: "",
    streamingModel: "",
    streamingContextItems: [],
    loading: false,
    visibleMessagesCount: 30,
    configOpenCodeAutoKillMinutes: 5,
    configOpenCodeAutoKill: false,
    openCodeMode: false,
    _pendingStreamingText: "",
    messagesChanged: function() {},
};
var StandardPaths = {
    writableLocation: function() { return "file:///tmp/"; }
};
var Qt = {
    resolvedUrl: function(p) { return "file:///tmp/" + p; },
    btoa: function(s) { return Buffer.from(s, "binary").toString("base64"); },
    atob: function(s) { return Buffer.from(s, "base64").toString("binary"); },
    createQmlObject: function() { return null; },
    callLater: function(fn) { if (typeof fn === "function") fn(); },
    formatDateTime: function() { return ""; },
};
var persistSessionsDebounce = { running: false, stop: function() {}, start: function() {}, restart: function() {} };
var deferSaveStateTimer = { restart: function() {} };
var openCodeIdleKillTimer = { stop: function() {}, restart: function() {} };
var soundDs = { connectSource: function() {} };
var customStorageDs = { connectSource: function() {} };
var fileReaderDs = { connectSource: function() {} };
var clipboardDs = { connectSource: function() {} };
var voiceDs = { connectSource: function() {} };
var opencodeTerminalDs = { connectSource: function() {} };
var schedulerDs = { connectSource: function() {} };
var opencodeServerDs = { connectSource: function() {} };
var kwalletStartupDs = { connectSource: function() {} };
var dataSources = null;
"""


@unittest.skipUnless(RUNNER, "No JavaScript runtime available")
class TestPreParseSetsLastParsedContent(unittest.TestCase):
    """parseSessions, appendMessageToSession, and the streaming flush
    path must set `lastParsedContent` whenever they pre-compute `blocks`.
    """

    def _run_script(self, driver: str):
        with open(JS_PATH) as f:
            src = _strip_qml_directives(f.read())
        # Strip the `.import "X.js" as Foo` lines (QML-only syntax).
        cleaned = re.sub(r'^\s*\.import\s+"[^"]+"\s+as\s+\w+\s*\n', '', src, flags=re.MULTILINE)
        deps = []
        for dep in ("SessionManager.js", "Security.js", "MarkdownRenderer.js"):
            try:
                deps.append(_read_stripped(dep))
            except FileNotFoundError:
                pass
        # Wrap each .js file in an IIFE so `let` declarations
        # don't collide at module scope (Node strict-mode would
        # otherwise refuse the second `let _ALLOWED_URL_SCHEMES`).
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
            f.write(GLOBAL_STUBS)
            f.write("\n")
            f.write("var __modules = {};\n")
            for i, d in enumerate(deps):
                f.write("__modules.m" + str(i) + " = (function(){\n")
                f.write(d)
                f.write("\nreturn { " + ", ".join(
                    re.findall(r"^function\s+(\w+)", d, flags=re.MULTILINE)
                ) + " };\n")
                f.write("})();\n")
            # Make the last module's exports available as the names
            # the driver code expects.
            f.write("var SessionManager = __modules.m0;\n")
            f.write("var Sec = __modules.m1;\n")
            f.write("var MarkdownRenderer = __modules.m2;\n")
            f.write("var parseMessageBlocks = MarkdownRenderer.parseMessageBlocks;\n")
            f.write("var convertMarkdownToHtml = MarkdownRenderer.convertMarkdownToHtml;\n")
            f.write(cleaned)
            f.write("\n")
            f.write(driver)
            tmp = f.name
        try:
            r = subprocess.run([RUNNER, tmp], capture_output=True, text=True, timeout=20)
            return r.stdout, r.stderr, r.returncode
        finally:
            os.unlink(tmp)

    # ── parseSessions ────────────────────────────────────────────────

    def test_parse_sessions_sets_last_parsed_content(self):
        """A session loaded from disk must end up with both `blocks` and
        `lastParsedContent` set on every message. The bug is that
        `blocks` was being set but `lastParsedContent` was not, defeating
        the onMessagesChanged guard."""
        out, err, rc = self._run_script("""
            var raw = JSON.stringify([{
                value: "s-1",
                text: "Chat",
                createdAt: 1000,
                updatedAt: 2000,
                archived: false,
                messages: [
                    { role: "user", content: "hello", at: 1000, time: "10:00" },
                    { role: "assistant", content: "hi there", at: 2000, time: "10:01" }
                ]
            }]);
            var arr = parseSessions(raw);
            precomputeBlocksForMessages(arr[0].messages);
            var m0 = arr[0].messages[0];
            var m1 = arr[0].messages[1];
            console.log("m0_has_blocks=" + (m0.blocks !== undefined));
            console.log("m0_has_lpc=" + (m0.lastParsedContent === m0.content));
            console.log("m0_lpc_eq=" + (m0.lastParsedContent === "hello"));
            console.log("m0_blocks_is_array=" + Array.isArray(m0.blocks));
            console.log("m1_has_blocks=" + (m1.blocks !== undefined));
            console.log("m1_has_lpc=" + (m1.lastParsedContent === m1.content));
            console.log("m1_lpc_eq=" + (m1.lastParsedContent === "hi there"));
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        lines = out.strip().split("\n")
        self.assertEqual(lines, [
            "m0_has_blocks=true",
            "m0_has_lpc=true",
            "m0_lpc_eq=true",
            "m0_blocks_is_array=true",
            "m1_has_blocks=true",
            "m1_has_lpc=true",
            "m1_lpc_eq=true",
        ])

    def test_parse_sessions_message_without_content_does_not_break(self):
        """An edge case: a stored message with no `content` field. The
        pre-parse should be skipped entirely; `lastParsedContent`
        should remain undefined (and the guard clause `m.blocks ===
        undefined` will short-circuit re-parsing)."""
        out, err, rc = self._run_script("""
            var raw = JSON.stringify([{
                value: "s-1", text: "Chat", createdAt: 1, updatedAt: 1,
                archived: false,
                messages: [
                    { role: "system", at: 1, time: "00:00" }
                ]
            }]);
            var arr = parseSessions(raw);
            var m = arr[0].messages[0];
            console.log("no_blocks=" + (m.blocks === undefined));
            console.log("no_lpc=" + (m.lastParsedContent === undefined));
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        self.assertEqual(out.strip().split("\n"),
                         ["no_blocks=true", "no_lpc=true"])

    # ── appendMessageToSession ───────────────────────────────────────

    def test_append_message_sets_last_parsed_content(self):
        """appendMessageToSession should set lastParsedContent in
        addition to blocks."""
        out, err, rc = self._run_script("""
            root.sessions = [{
                value: "s-1", text: "Chat", createdAt: 1, updatedAt: 1,
                archived: false, source: "provider", readCount: 0,
                messages: []
            }];
            root.currentSessionId = "s-1";
            appendMessageToSession("s-1", {
                role: "assistant",
                content: "world",
                at: 100,
                time: "10:00"
            });
            var m = root.sessions[0].messages[0];
            console.log("has_blocks=" + (m.blocks !== undefined));
            console.log("has_lpc=" + (m.lastParsedContent === m.content));
            console.log("lpc_eq=" + (m.lastParsedContent === "world"));
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        self.assertEqual(out.strip().split("\n"),
                         ["has_blocks=true", "has_lpc=true", "lpc_eq=true"])

    # ── flushStreamingBuffer ─────────────────────────────────────────

    def test_flush_streaming_buffer_sets_last_parsed_content(self):
        """The streaming commit must mark the new message as already
        parsed so onMessagesChanged doesn't redo the work."""
        out, err, rc = self._run_script("""
            root.streamingContent = "streamed reply";
            root.streamingModel = "gpt-4o-mini";
            root.streamingContextItems = [];
            root.messages = [];
            flushStreamingBuffer();
            var m = root.messages[root.messages.length - 1];
            console.log("has_blocks=" + (m.blocks !== undefined));
            console.log("has_lpc=" + (m.lastParsedContent === m.content));
            console.log("lpc_eq=" + (m.lastParsedContent === "streamed reply"));
            console.log("streaming_off=" + (root.streamingResponse === false));
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        self.assertEqual(out.strip().split("\n"),
                         ["has_blocks=true", "has_lpc=true", "lpc_eq=true",
                          "streaming_off=true"])


if __name__ == "__main__":
    unittest.main()
