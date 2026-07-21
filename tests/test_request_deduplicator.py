"""Test the RequestDeduplicator.js module.

Validates the basic in-flight tracking: claims succeed for new keys,
fail for duplicates, and release allows new claims to proceed.
"""
import os
import re
import subprocess
import tempfile
import unittest

JS_PATH = os.path.join(
    os.path.dirname(__file__),
    "..", "org.kde.plasma.kdeaichat", "contents", "ui",
    "RequestDeduplicator.js",
)


def _strip_qml_directives(src: str) -> str:
    """Strip the leading ``.pragma library`` line so plain Node can run it."""
    return re.sub(r"^\s*\.pragma\s+library\s*\n", "", src, count=1)


class TestRequestDeduplicatorFile(unittest.TestCase):
    """Test by loading the file (with QML directives stripped) under node."""

    @classmethod
    def setUpClass(cls):
        cls._runner = None
        for runner in ("node", "qjs6", "qjs"):
            if subprocess.run(["which", runner], capture_output=True).returncode == 0:
                cls._runner = runner
                break
        if cls._runner is None:
            raise unittest.SkipTest("No JavaScript runtime (node, qjs6, or qjs) available")
        if not os.path.exists(JS_PATH):
            raise unittest.SkipTest(f"Module not found: {JS_PATH}")

    def _run_script(self, driver: str):
        """Append driver code to the module file and run it."""
        with open(JS_PATH) as f:
            src = _strip_qml_directives(f.read())
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
            f.write(src)
            f.write("\n")
            f.write(driver)
            tmp = f.name
        try:
            r = subprocess.run([self._runner, tmp], capture_output=True, text=True, timeout=10)
            return r.stdout, r.stderr, r.returncode
        finally:
            os.unlink(tmp)

    def test_basic_claim(self):
        out, err, rc = self._run_script("""
            var k = key('openai', 'gpt-4', 'hello', 's-1');
            console.log('1=' + tryClaim(k));
            console.log('2=' + tryClaim(k));
            release(k);
            console.log('3=' + tryClaim(k));
            release(k);
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}")
        lines = out.strip().split("\n")
        self.assertEqual(lines, ["1=true", "2=false", "3=true"])

    def test_different_keys(self):
        out, err, rc = self._run_script("""
            var k1 = key('openai', 'gpt-4', 'hello', 's-1');
            var k2 = key('openai', 'gpt-4', 'world', 's-1');
            console.log('1=' + tryClaim(k1));
            console.log('2=' + tryClaim(k2));
            release(k1);
            release(k2);
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}")
        self.assertEqual(out.strip().split("\n"), ["1=true", "2=true"])

    def test_release_idempotent(self):
        out, err, rc = self._run_script("""
            var k = key('openai', 'gpt-4', 'hello', 's-1');
            tryClaim(k);
            release(k);
            release(k);
            release(k);
            console.log('count=' + inFlightCount());
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}")
        self.assertEqual(out.strip(), "count=0")

    def test_inflight_count(self):
        out, err, rc = self._run_script("""
            console.log('initial=' + inFlightCount());
            var k1 = key('a', 'b', 'c', 'd');
            var k2 = key('a', 'b', 'c', 'e');
            tryClaim(k1);
            tryClaim(k2);
            console.log('two=' + inFlightCount());
            release(k1);
            console.log('one=' + inFlightCount());
            release(k2);
            console.log('zero=' + inFlightCount());
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}")
        lines = out.strip().split("\n")
        self.assertEqual(lines, ["initial=0", "two=2", "one=1", "zero=0"])

    def test_clear_all(self):
        out, err, rc = self._run_script("""
            tryClaim(key('a', 'b', 'c', 'd'));
            tryClaim(key('a', 'b', 'c', 'e'));
            console.log('before=' + inFlightCount());
            clearAll();
            console.log('after=' + inFlightCount());
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}")
        lines = out.strip().split("\n")
        self.assertEqual(lines, ["before=2", "after=0"])

    def test_is_in_flight(self):
        out, err, rc = self._run_script("""
            var k = key('openai', 'gpt-4', 'hello', 's-1');
            console.log('before=' + isInFlight(k));
            tryClaim(k);
            console.log('after=' + isInFlight(k));
            release(k);
            console.log('released=' + isInFlight(k));
        """)
        self.assertEqual(rc, 0, msg=f"stderr: {err}")
        lines = out.strip().split("\n")
        self.assertEqual(lines, ["before=false", "after=true", "released=false"])


if __name__ == "__main__":
    unittest.main()
