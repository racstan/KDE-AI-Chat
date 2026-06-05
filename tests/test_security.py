"""Test the Security.js module.

Verifies the central shell-escape, URL-validation, and file-path-sanitize
helpers behave as expected for both safe inputs and the classes of
malicious inputs the audit flagged. Uses Node/qjs to actually evaluate
the QML module (with its `.pragma library` directive stripped) so the
real regexes and string ops are exercised.
"""
import os
import re
import subprocess
import tempfile
import unittest

JS_PATH = os.path.join(
    os.path.dirname(__file__),
    "..", "org.kde.plasma.kdeaichat", "contents", "ui",
    "Security.js",
)


def _strip_qml_directives(src: str) -> str:
    """Strip the leading ``.pragma library`` line so plain Node can run it."""
    return re.sub(r"^\s*\.pragma\s+library\s*\n", "", src, count=1)


def _find_runner() -> str:
    for runner in ("node", "qjs6", "qjs"):
        if subprocess.run(["which", runner], capture_output=True).returncode == 0:
            return runner
    return ""


RUNNER = _find_runner()


@unittest.skipUnless(RUNNER, "No JavaScript runtime (node, qjs6, or qjs) available")
class TestSecurityFile(unittest.TestCase):
    """Test by loading the file (with QML directives stripped) under node/qjs."""

    def _run_script(self, driver: str):
        with open(JS_PATH) as f:
            src = _strip_qml_directives(f.read())
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
            f.write(src)
            f.write("\n")
            f.write(driver)
            tmp = f.name
        try:
            r = subprocess.run([RUNNER, tmp], capture_output=True, text=True, timeout=10)
            return r.stdout, r.stderr, r.returncode
        finally:
            os.unlink(tmp)

    # ---------- sanitizeForShell ----------

    def test_sanitize_strips_command_substitution(self):
        out, err, rc = self._run_script("""
            console.log(JSON.stringify(sanitizeForShell("hello $(rm -rf /) world")));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertNotIn("$", out)
        self.assertNotIn("(", out)
        self.assertNotIn(")", out)

    def test_sanitize_strips_backticks(self):
        out, err, rc = self._run_script("""
            console.log(JSON.stringify(sanitizeForShell("a`id`b")));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertNotIn("`", out)

    def test_sanitize_strips_semicolons_and_pipes(self):
        out, err, rc = self._run_script("""
            console.log(JSON.stringify(sanitizeForShell("a; b | c & d < e > f")));
        """)
        self.assertEqual(rc, 0, msg=err)
        for ch in (";", "|", "&", "<", ">"):
            self.assertNotIn(ch, out, f"{ch!r} should be stripped")

    def test_sanitize_preserves_unicode(self):
        out, err, rc = self._run_script("""
            console.log(JSON.stringify(sanitizeForShell("héllo \u4e2d\u6587")));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("héllo", out)
        self.assertIn("中文", out)

    def test_sanitize_escapes_apostrophes(self):
        out, err, rc = self._run_script("""
            console.log(JSON.stringify(sanitizeForShell("it's a 'test'")));
        """)
        self.assertEqual(rc, 0, msg=err)
        # Each `'` becomes the close-quote / escape / open-quote sequence
        self.assertIn(r"'\\''", out)

    def test_sanitize_handles_null_and_undefined(self):
        out, err, rc = self._run_script("""
            console.log(JSON.stringify(sanitizeForShell(null)));
            console.log(JSON.stringify(sanitizeForShell(undefined)));
        """)
        self.assertEqual(rc, 0, msg=err)
        lines = [l for l in out.strip().splitlines() if l]
        self.assertEqual(lines, ['""', '""'])

    def test_sanitize_clamps_to_max_length(self):
        out, err, rc = self._run_script("""
            var s = "a".repeat(5000);
            var result = sanitizeForShell(s);
            console.log(result.length);
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip(), "4096")

    # ---------- validateUrl ----------

    def test_validate_url_allows_http(self):
        out, err, rc = self._run_script("""
            console.log(validateUrl("http://example.com"));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("http://example.com", out)

    def test_validate_url_allows_https(self):
        out, err, rc = self._run_script("""
            console.log(validateUrl("https://example.com/path?q=1"));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("https://example.com", out)

    def test_validate_url_allows_mailto(self):
        out, err, rc = self._run_script("""
            console.log(validateUrl("mailto:user@example.com"));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("mailto:user@example.com", out)

    def test_validate_url_rejects_javascript(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateUrl("javascript:alert(1)") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_validate_url_rejects_file_scheme(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateUrl("file:///etc/passwd") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_validate_url_rejects_data_scheme(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateUrl("data:text/html,<script>") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_validate_url_rejects_substring_match(self):
        # `xhttps:` should not be allowed even though `https:` is
        out, err, rc = self._run_script("""
            console.log("[" + validateUrl("xhttps://evil") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_validate_url_rejects_empty(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateUrl("") + "]");
            console.log("[" + validateUrl(null) + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    # ---------- safeHref ----------

    def test_safe_href_rejects_javascript(self):
        out, err, rc = self._run_script("""
            console.log("[" + safeHref("javascript:alert(1)") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_safe_href_strips_attr_breakers(self):
        out, err, rc = self._run_script("""
            console.log("[" + safeHref('https://example.com/\"onclick=alert(1)') + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertNotIn('"', out)

    # ---------- validateFilePath ----------

    def test_validate_path_allows_normal_paths(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateFilePath("/home/user/file.txt") + "]");
            console.log("[" + validateFilePath("relative/path-name_2.txt") + "]");
            console.log("[" + validateFilePath("/tmp/build-output.json") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[/home/user/file.txt]", out)
        self.assertIn("[relative/path-name_2.txt]", out)
        self.assertIn("[/tmp/build-output.json]", out)

    def test_validate_path_rejects_traversal(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateFilePath("/etc/../passwd") + "]");
            console.log("[" + validateFilePath("../etc/passwd") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)
        # Both inputs should produce []
        self.assertEqual(out.strip().count("[]"), 2)

    def test_validate_path_rejects_shell_metachars(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateFilePath("/tmp/a;b") + "]");
            console.log("[" + validateFilePath("/tmp/$(rm)") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().count("[]"), 2)

    def test_validate_path_rejects_empty(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateFilePath("") + "]");
            console.log("[" + validateFilePath(null) + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().count("[]"), 2)

    # ---------- validateSessionId ----------

    def test_session_id_accepts_valid(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateSessionId("sess-abc-123") + "]");
            console.log("[" + validateSessionId("550e8400-e29b-41d4-a716-446655440000") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[sess-abc-123]", out)
        self.assertIn("[550e8400-e29b-41d4-a716-446655440000]", out)

    def test_session_id_rejects_traversal(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateSessionId("../etc/passwd") + "]");
            console.log("[" + validateSessionId("foo/../bar") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().count("[]"), 2)

    def test_session_id_rejects_too_long(self):
        out, err, rc = self._run_script("""
            var s = "a".repeat(200);
            console.log("[" + validateSessionId(s) + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_session_id_rejects_special_chars(self):
        out, err, rc = self._run_script("""
            console.log("[" + validateSessionId("foo bar") + "]");
            console.log("[" + validateSessionId("foo;rm") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().count("[]"), 2)

    # ---------- quoteForShell ----------

    def test_quote_for_shell_wraps_in_single_quotes(self):
        out, err, rc = self._run_script("""
            console.log(quoteForShell("hello"));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("'hello'", out)

    def test_quote_for_shell_strips_then_quotes(self):
        out, err, rc = self._run_script("""
            var result = quoteForShell("a$(b)c");
            console.log("[" + result + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertNotIn("$", out)
        self.assertNotIn("(", out)
        # The metacharacters are stripped, then the result is single-quoted
        self.assertIn("'abc'", out)


@unittest.skipUnless(RUNNER, "No JavaScript runtime (node, qjs6, or qjs) available")
class TestMarkdownRendererFile(unittest.TestCase):
    """Test the sanitizeHref() helper inside MarkdownRenderer.js."""

    MD_PATH = os.path.join(
        os.path.dirname(__file__),
        "..", "org.kde.plasma.kdeaichat", "contents", "ui",
        "MarkdownRenderer.js",
    )

    def _run_script(self, driver: str):
        with open(self.MD_PATH) as f:
            src = _strip_qml_directives(f.read())
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
            f.write(src)
            f.write("\n")
            f.write(driver)
            tmp = f.name
        try:
            r = subprocess.run([RUNNER, tmp], capture_output=True, text=True, timeout=10)
            return r.stdout, r.stderr, r.returncode
        finally:
            os.unlink(tmp)

    def test_sanitize_href_allows_http(self):
        out, _, rc = self._run_script("console.log(sanitizeHref('http://example.com'));")
        self.assertEqual(rc, 0)
        self.assertIn("http://example.com", out)

    def test_sanitize_href_allows_https(self):
        out, _, rc = self._run_script("console.log(sanitizeHref('https://example.com/a?b=1'));")
        self.assertEqual(rc, 0)
        self.assertIn("https://example.com/a?b=1", out)

    def test_sanitize_href_allows_mailto(self):
        out, _, rc = self._run_script("console.log(sanitizeHref('mailto:user@example.com'));")
        self.assertEqual(rc, 0)
        self.assertIn("mailto:user@example.com", out)

    def test_sanitize_href_rejects_javascript(self):
        out, _, rc = self._run_script("console.log('[' + sanitizeHref('javascript:alert(1)') + ']');")
        self.assertEqual(rc, 0)
        self.assertIn("[]", out)

    def test_sanitize_href_rejects_data(self):
        out, _, rc = self._run_script("console.log('[' + sanitizeHref('data:text/html,<x>') + ']');")
        self.assertEqual(rc, 0)
        self.assertIn("[]", out)

    def test_sanitize_href_rejects_file(self):
        out, _, rc = self._run_script("console.log('[' + sanitizeHref('file:///etc/passwd') + ']');")
        self.assertEqual(rc, 0)
        self.assertIn("[]", out)

    def test_sanitize_href_strips_attribute_breakers(self):
        out, _, rc = self._run_script(
            "console.log('[' + sanitizeHref('https://e.com/\\\"x') + ']');"
        )
        self.assertEqual(rc, 0)
        self.assertNotIn('"', out)

    def test_markdown_link_inlines_safe_url(self):
        out, _, rc = self._run_script("""
            console.log(convertMarkdownToHtml('[Click](https://example.com)', false));
        """)
        self.assertEqual(rc, 0)
        self.assertIn('href="https://example.com"', out)
        self.assertIn(">Click</a>", out)

    def test_markdown_link_strips_javascript_href(self):
        out, _, rc = self._run_script("""
            console.log(convertMarkdownToHtml('[Click](javascript:alert(1))', false));
        """)
        self.assertEqual(rc, 0)
        self.assertNotIn("javascript:", out)
        self.assertNotIn('href="javascript:', out)
        # The label should still appear but without a working href
        self.assertIn("Click", out)


if __name__ == "__main__":
    unittest.main()
