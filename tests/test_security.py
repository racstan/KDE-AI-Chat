"""Test the Security.js module.

Verifies the central shell-escape, URL-validation, and file-path-sanitize
helpers behave as expected for both safe inputs and the classes of
malicious inputs the audit flagged. Uses Node/qjs to actually evaluate
the QML module (with its `.pragma library` directive stripped) so the
real regexes and string ops are exercised.
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
        lines = [line for line in out.strip().splitlines() if line]
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

    def test_validate_path_keeps_ordinary_punctuation(self):
        # Shell characters are path data: quotePath() keeps them inside quotes.
        out, err, rc = self._run_script("""
            console.log("[" + validateFilePath("/tmp/Report (final).pdf") + "]");
            console.log("[" + validateFilePath("/tmp/Q&A; $2026.docx") + "]");
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.split("\n")[:2], ["[/tmp/Report (final).pdf]", "[/tmp/Q&A; $2026.docx]"])

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
class TestValidateFilePath(unittest.TestCase):
    """Path traversal protection in Security.validateFilePath."""

    def _run(self, driver: str):
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

    def test_rejects_dotdot(self):
        out, err, rc = self._run('console.log("[" + validateFilePath("../../etc/passwd") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_rejects_dotdot_in_middle(self):
        out, err, rc = self._run('console.log("[" + validateFilePath("/home/user/../secret") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_rejects_null_bytes(self):
        out, err, rc = self._run('console.log("[" + validateFilePath("file" + String.fromCharCode(0) + ".txt") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_rejects_newlines(self):
        out, err, rc = self._run('console.log("[" + validateFilePath("/tmp/a\\nb.txt") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_quoted_awkward_names_reach_the_program_unchanged(self):
        # Each name goes through quotePath() into a real sh -c, nested the
        # way chat/HelperCommands.qml nests it, and must come back intact.
        names = ["/tmp/Report (final).pdf", "/tmp/Q&A.docx", "/tmp/a;b|c<d>e", "/tmp/$(touch pwned)",
                 "/tmp/`id`.txt", "/tmp/it's \"here\".md", "/tmp/back\\slash", "/tmp/#hash ?.md"]
        driver = "var names = " + json.dumps(names) + ";\n" + """
            names.forEach(function(n) {
                var p = validateFilePath(n);
                if (p !== n) throw new Error("refused " + n);
                console.log("sh -c " + rawShellSnippetQuote("printf '%s\\\\0' " + quotePath(p)));
            });
        """
        out, err, rc = self._run(driver)
        self.assertEqual(rc, 0, msg=err)
        with tempfile.TemporaryDirectory() as cwd:
            for name, command in zip(names, out.strip().split("\n")):
                got = subprocess.run(["sh", "-c", command], cwd=cwd, capture_output=True, timeout=10)
                self.assertEqual(got.stdout.decode(), name + "\0", msg=command)
                self.assertEqual(os.listdir(cwd), [], msg="nothing may run: " + command)

    def test_file_url_escapes_hash_and_question_mark(self):
        out, err, rc = self._run('console.log(fileUrl("/tmp/a #1?.pdf"));')
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip(), "file:///tmp/a%20%231%3F.pdf")

    def test_accepts_safe_absolute(self):
        out, err, rc = self._run('console.log("[" + validateFilePath("/home/user/file.txt") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[/home/user/file.txt]", out)

    def test_accepts_safe_relative(self):
        out, err, rc = self._run('console.log("[" + validateFilePath("docs/readme.md") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[docs/readme.md]", out)

    def test_rejects_empty(self):
        out, err, rc = self._run('console.log("[" + validateFilePath("") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_rejects_null(self):
        out, err, rc = self._run('console.log("[" + validateFilePath(null) + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_rejects_undefined(self):
        out, err, rc = self._run('console.log("[" + validateFilePath(undefined) + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_rejects_tilde_expansion(self):
        out, err, rc = self._run('console.log("[" + validateFilePath("~/secret") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)


@unittest.skipUnless(RUNNER, "No JavaScript runtime available")
class TestValidateSessionId(unittest.TestCase):
    """Session ID validation for OpenCode remote sessions."""

    def _run(self, driver: str):
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

    def test_accepts_alphanumeric(self):
        out, err, rc = self._run('console.log("[" + validateSessionId("abc123") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[abc123]", out)

    def test_accepts_with_dash(self):
        out, err, rc = self._run('console.log("[" + validateSessionId("ses-abc-123") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[ses-abc-123]", out)

    def test_rejects_slash(self):
        out, err, rc = self._run('console.log("[" + validateSessionId("../etc") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_rejects_special_chars(self):
        out, err, rc = self._run('console.log("[" + validateSessionId("abc<script>") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_rejects_empty(self):
        out, err, rc = self._run('console.log("[" + validateSessionId("") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    def test_rejects_too_long(self):
        long_id = "a" * 300
        out, err, rc = self._run(f'console.log("[" + validateSessionId("{long_id}") + "]");')
        self.assertEqual(rc, 0, msg=err)
        self.assertIn("[]", out)

    # ---------- validateCommandTemplate ----------

    def test_command_template(self):
        out, err, rc = self._run(r"""
            console.log(JSON.stringify([
                validateCommandTemplate("  espeak-ng --stdin -w {output} "),
                validateCommandTemplate("say 'unbalanced"),
                validateCommandTemplate("a\nb"),
                validateCommandTemplate(""),
                validateCommandTemplate('tts --name "A \\" B" > x'),
                validateCommandTemplate("x".repeat(2001))]));
        """)
        self.assertEqual(rc, 0, err)
        self.assertEqual(out.strip(), r'["espeak-ng --stdin -w {output}","","","","tts --name \"A \\\" B\" > x",""]')


if __name__ == "__main__":
    unittest.main()
