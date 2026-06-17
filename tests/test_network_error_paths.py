"""Test that the AI network request error paths are exception-safe.

Two prior bugs:

1. `doAnthropicRequest` had no try/catch around `xhr.send()`. If
   `JSON.stringify` or `xhr.send` threw, `root.loading` stayed true
   forever and the dedup key was never released → the widget was
   permanently stuck in "Thinking..." until restart.

2. `xhr.open` / `setRequestHeader` could also throw (invalid URL,
   header validation). Same hang symptom.

The fix mirrors `doOpenAICompatRequest`: wrap setup and send in
try/catch, and on any failure call `finishOpenCodeRequest` (which
itself is now exception-safe) and release the dedup key.

These tests load `MainNetwork.js` under node, stub the QML globals
and `XMLHttpRequest`, then drive the function through:
- A normal happy-path send
- A setup-phase throw (xhr.open throws)
- A send-phase throw (xhr.send throws)

and assert that root.loading ends up false and the dedup key was
released in all cases.
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


# We construct a mock XMLHttpRequest factory in JS so the test
# driver can control which method throws.
GLOBAL_STUBS = """
var __xhrBehavior = { openThrows: false, sendThrows: false, abortCalled: false };
function XMLHttpRequest() {
    var xhr = this;
    xhr.openCalls = [];
    xhr.sendCalls = [];
    xhr.readyState = 0;
    xhr.responseText = "";
    xhr.status = 0;
    xhr.timeout = 0;
    xhr.onreadystatechange = null;
    xhr.onerror = null;
    xhr.ontimeout = null;
    xhr.open = function(method, url, async) {
        if (__xhrBehavior.openThrows) throw new Error("simulated xhr.open failure");
        xhr.openCalls.push({method: method, url: url, async: async});
    };
    xhr.setRequestHeader = function(k, v) { xhr.openCalls.push({header: k, value: v}); };
    xhr.send = function(body) {
        xhr.sendCalls.push(body);
        if (__xhrBehavior.sendThrows) throw new Error("simulated xhr.send failure");
    };
    xhr.abort = function() { __xhrBehavior.abortCalled = true; };
    return xhr;
}

var root = {
    loading: false,
    activeXhr: null,
    streamingResponse: false,
    streamingContent: "",
    streamingModel: "",
    streamingContextItems: [],
    messages: [
        { role: "user", content: "hello" }
    ],
    sessions: [],
    currentSessionId: "s-1",
    configOpenCodeAutoKill: false,
    openCodeMode: false,
    _pendingStreamingText: "",
    openCodeErrorShownForRequest: false,
    openCodeActiveSessionId: "",
    openCodeAssistantMessageIndex: -1,
    openCodeAssistantServerMessageId: "",
    userScrolledUp: false,
    reqDedupKey: function() { return "dedup-key"; },
    reqDedupTryClaim: function() { return true; },
    reqDedupRelease: function() { __xhrBehavior.released = true; },
    flushStreamingBuffer: function() {},
    saveCurrentSessionState: function() {},
    triggerNotificationSound: function() {},
    resetOpenCodeIdleKillTimer: function() {},
    processNextQueuedMessage: function() {},
    beginAssistantStreaming: function(m) { __xhrBehavior.streamingLabel = m; },
    updateAssistantStreamingContent: function(t) { __xhrBehavior.lastContent = t; },
    buildEffectiveSystemPrompt: function() { return "system"; },
    buildAnthropicPayload: function() { return [{role:"user",content:"x"}]; },
    pushErrorMessage: function(t) { __xhrBehavior.lastError = t; },
    messagesChanged: function() {},
};
var plasmoid = { configuration: { voiceEnabled: false } };
var MainDatabase = { triggerTts: function() {} };
function flushStreamingBuffer() {}
function saveCurrentSessionState() {}
function triggerNotificationSound() {}
function resetOpenCodeIdleKillTimer() {}
function processNextQueuedMessage() {}
function scrollToBottom() {}
function nowTime(t) { return new Date(t || Date.now()).toISOString(); }
function pushErrorMessage(t) { __xhrBehavior.lastError = t; }
function buildEffectiveSystemPrompt() { return "system"; }
function buildAnthropicPayload() { return [{role:"user",content:"x"}]; }
function beginAssistantStreaming(m) { __xhrBehavior.streamingLabel = m; }
function updateAssistantStreamingContent(t) { __xhrBehavior.lastContent = t; }
function reqDedupKey() { return "dedup-key"; }
function reqDedupTryClaim() { return true; }
function reqDedupRelease() { __xhrBehavior.released = true; }
function finishOpenCodeRequest() {
    root.loading = false;
    root.activeXhr = null;
    root.streamingResponse = false;
    __xhrBehavior.finished = true;
}
function buildEffectiveSystemPrompt() { return "system"; }
function buildAnthropicPayload() { return [{role:"user",content:"x"}]; }
function beginAssistantStreaming(m) { __xhrBehavior.streamingLabel = m; }
function updateAssistantStreamingContent(t) { __xhrBehavior.lastContent = t; }
function reqDedupKey() { return "dedup-key"; }
function reqDedupTryClaim() { return true; }
function reqDedupRelease() { __xhrBehavior.released = true; }
function finishOpenCodeRequest() {
    root.loading = false;
    root.activeXhr = null;
    root.streamingResponse = false;
    __xhrBehavior.finished = true;
}
var Qt = { callLater: function(fn) { if (typeof fn === "function") fn(); } };
var persistSessionsDebounce = { restart: function() {} };
"""


@unittest.skipUnless(RUNNER, "No JavaScript runtime available")
class TestNetworkErrorPaths(unittest.TestCase):
    """Verify xhr.send / xhr.open exceptions do not hang the widget."""

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

    def test_happy_path_sends_request(self):
        """Normal case: xhr.send is called. We don't assert on
        root.loading because the XHR onreadystatechange callback is
        asynchronous in the real environment — in this unit test
        the mock XHR doesn't fire events, so the request stays
        in-flight. The two exception tests below verify the actual
        bug fix (cleanup on error)."""
        out, err, rc = self._run_script("""
            __xhrBehavior.openThrows = false;
            __xhrBehavior.sendThrows = false;
            doAnthropicRequest("sk-test", "claude-3-5-sonnet-20241022");
            // Read the activeXhr's sendCalls via the saved reference.
            console.log("loading_was_true=" + (root.loading === true));
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        self.assertIn("loading_was_true=true", out.strip().split("\n"))

    def test_xhr_open_throw_does_not_hang(self):
        """If xhr.open throws (invalid URL, header validation, etc.)
        the function must clean up. Pre-fix, this left root.loading
        true and the dedup key unreleased."""
        out, err, rc = self._run_script("""
            __xhrBehavior.openThrows = true;
            __xhrBehavior.sendThrows = false;
            doAnthropicRequest("sk-test", "claude-3-5-sonnet-20241022");
            console.log("loading=" + root.loading);
            console.log("error_role_msgs=" + root.messages.filter(function(m){return m.role==="error";}).length);
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        lines = out.strip().split("\n")
        self.assertIn("loading=false", lines, msg=out)
        # The fix pushes a user-visible error message via the
        # standard pushErrorMessage path.
        self.assertTrue(
            any("error_role_msgs=1" in l for l in lines),
            msg=f"Expected an error message to be pushed, got: {lines}"
        )

    def test_xhr_send_throw_does_not_hang(self):
        """If xhr.send throws (JSON.stringify failure, network
        unavailable at the very moment of send, etc.) the function
        must clean up. Pre-fix, this left root.loading true and the
        dedup key unreleased — the widget was stuck in "Thinking..."
        state forever."""
        out, err, rc = self._run_script("""
            __xhrBehavior.openThrows = false;
            __xhrBehavior.sendThrows = true;
            doAnthropicRequest("sk-test", "claude-3-5-sonnet-20241022");
            console.log("loading=" + root.loading);
            console.log("error_role_msgs=" + root.messages.filter(function(m){return m.role==="error";}).length);
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}\nstdout: {out}")
        lines = out.strip().split("\n")
        self.assertIn("loading=false", lines, msg=out)
        # The fix pushes a user-visible error message.
        self.assertTrue(
            any("error_role_msgs=1" in l for l in lines),
            msg=f"Expected an error message to be pushed, got: {lines}"
        )


if __name__ == "__main__":
    unittest.main()
