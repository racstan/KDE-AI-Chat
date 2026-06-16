"""Test that finishOpenCodeRequest is exception-safe.

Every error path in the network/OpenCode code calls
`finishOpenCodeRequest()` to clean up `root.loading`, the active XHR
reference, and the dedup key. If any of the cleanup steps throws (e.g.
`flushStreamingBuffer()` blowing up because a streaming message was
malformed), the `root.loading = false` assignment is never reached and
the widget is permanently stuck in the "Thinking..." state.

This test loads MainNetwork.js under node, stubs the QML globals, and
asserts that:

1. `root.loading` is reset to `false` even if `flushStreamingBuffer`
   throws.
2. `root.loading` is reset to `false` even if `saveCurrentSessionState`
   throws.
3. The cleanup chain is fault-tolerant: an exception in one step does
   not prevent subsequent steps from running.
4. The happy path (nothing throws) still sets all expected fields.
"""
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


GLOBAL_STUBS = """
var root = {
    loading: true,
    activeXhr: { abort: function() {} },
    openCodeActiveSessionId: "s-1",
    openCodeAssistantMessageIndex: 3,
    openCodeAssistantServerMessageId: "m-9",
    openCodeErrorShownForRequest: false,
    streamingResponse: true,
    streamingContent: "partial",
    messages: [],
    sessions: [],
    currentSessionId: "s-1",
    configOpenCodeAutoKill: false,
    userScrolledUp: false,
    _pendingStreamingText: "",
    reqDedupRelease: function() {},
    triggerTts: function() {},
};
var plasmoid = { configuration: { voiceEnabled: false } };
var MainDatabase = { triggerTts: function() {} };

// Bare-name stubs that mirror the real QML global imports
// main.qml does. Tests can override these by reassigning on root
// (e.g. root.flushStreamingBuffer = …) and our trampoline picks
// it up.
function __resolve(name) {
    if (typeof root[name] === "function") return root[name];
    if (typeof root["_" + name] === "function") return root["_" + name];
    return function() {};
}
function flushStreamingBuffer() { return __resolve("flushStreamingBuffer")(); }
function saveCurrentSessionState(t) { return __resolve("saveCurrentSessionState")(t); }
function triggerNotificationSound() { return __resolve("triggerNotificationSound")(); }
function resetOpenCodeIdleKillTimer() { return __resolve("resetOpenCodeIdleKillTimer")(); }
function processNextQueuedMessage() { return __resolve("processNextQueuedMessage")(); }
function scrollToBottom() {}
function nowTime(t) { return new Date(t || Date.now()).toISOString(); }

var Qt = {
    callLater: function(fn) { if (typeof fn === "function") fn(); }
};
var persistSessionsDebounce = { restart: function() {} };
var deferSaveStateTimer = { restart: function() {} };
var soundDs = { connectSource: function() {} };
"""


@unittest.skipUnless(RUNNER, "No JavaScript runtime available")
class TestFinishOpenCodeRequestRobustness(unittest.TestCase):
    """Verify finishOpenCodeRequest cannot leave root.loading = true."""

    def _run_script(self, driver: str):
        with open(JS_PATH) as f:
            src = _strip_qml_directives(f.read())
        cleaned = re.sub(r'^\s*\.import\s+"[^"]+"\s+as\s+\w+\s*\n', '', src, flags=re.MULTILINE)
        deps = []
        for dep in ("Security.js",):
            try:
                deps.append(_read_stripped(dep))
            except FileNotFoundError:
                pass
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
            f.write(GLOBAL_STUBS)
            f.write("\nvar __modules = {};\n")
            for i, d in enumerate(deps):
                f.write("__modules.m" + str(i) + " = (function(){\n")
                f.write(d)
                f.write("\nreturn { " + ", ".join(
                    re.findall(r"^function\s+(\w+)", d, flags=re.MULTILINE)
                ) + " };\n")
                f.write("})();\n")
            f.write("var Sec = __modules.m0;\n")
            f.write(cleaned)
            f.write("\n")
            f.write(driver)
            tmp = f.name
        try:
            r = subprocess.run([RUNNER, tmp], capture_output=True, text=True, timeout=20)
            return r.stdout, r.stderr, r.returncode
        finally:
            os.unlink(tmp)

    def test_happy_path_resets_all_fields(self):
        """When nothing throws, every required field is reset."""
        out, err, rc = self._run_script("""
            root.loading = true;
            root.activeXhr = { abort: function() { root._aborted = true; } };
            root.flushStreamingBuffer = function() {};
            root.saveCurrentSessionState = function() {};
            root.triggerNotificationSound = function() {};
            root.resetOpenCodeIdleKillTimer = function() {};
            root.processNextQueuedMessage = function() {};
            finishOpenCodeRequest();
            console.log("loading=" + root.loading);
            console.log("activeXhr=" + (root.activeXhr === null));
            console.log("ocActiveId=" + (root.openCodeActiveSessionId === ""));
            console.log("streaming=" + (root.streamingResponse === false));
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        self.assertEqual(out.strip().split("\n"),
                         ["loading=false", "activeXhr=true",
                          "ocActiveId=true", "streaming=true"])

    def test_loading_reset_even_if_flush_throws(self):
        """The fix: if flushStreamingBuffer throws, root.loading is
        still set to false. Pre-fix, the throw skipped the rest of the
        function and root.loading stayed true forever."""
        out, err, rc = self._run_script("""
            root.loading = true;
            root.flushStreamingBuffer = function() {
                throw new Error("simulated flush failure");
            };
            root.saveCurrentSessionState = function() {};
            root.triggerNotificationSound = function() {};
            root.resetOpenCodeIdleKillTimer = function() {};
            root.processNextQueuedMessage = function() {};
            var threw = false;
            try { finishOpenCodeRequest(); }
            catch (e) { threw = true; }
            console.log("loading=" + root.loading);
            console.log("threw=" + threw);
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        self.assertIn("loading=false", out.strip().split("\n"))

    def test_loading_reset_even_if_save_throws(self):
        """If saveCurrentSessionState throws, root.loading must still
        be set to false."""
        out, err, rc = self._run_script("""
            root.loading = true;
            root.flushStreamingBuffer = function() {};
            root.saveCurrentSessionState = function() {
                throw new Error("disk full");
            };
            root.triggerNotificationSound = function() {};
            root.resetOpenCodeIdleKillTimer = function() {};
            root.processNextQueuedMessage = function() {};
            var threw = false;
            try { finishOpenCodeRequest(); }
            catch (e) { threw = true; }
            console.log("loading=" + root.loading);
            console.log("threw=" + threw);
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        self.assertIn("loading=false", out.strip().split("\n"))

    def test_loading_reset_even_if_multiple_throws(self):
        """Multiple thrown errors in sequence must not skip the
        loading reset."""
        out, err, rc = self._run_script("""
            root.loading = true;
            root.flushStreamingBuffer = function() { throw new Error("a"); };
            root.saveCurrentSessionState = function() { throw new Error("b"); };
            root.triggerNotificationSound = function() { throw new Error("c"); };
            root.resetOpenCodeIdleKillTimer = function() {};
            root.processNextQueuedMessage = function() {};
            var threw = false;
            try { finishOpenCodeRequest(); }
            catch (e) { threw = true; }
            console.log("loading=" + root.loading);
            console.log("threw=" + threw);
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        self.assertIn("loading=false", out.strip().split("\n"))


if __name__ == "__main__":
    unittest.main()
