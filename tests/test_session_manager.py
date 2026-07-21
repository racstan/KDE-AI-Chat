"""Test the SessionManager.js module.

Validates the new `isSessionOrderCorrect()` helper used by the
sidebar to short-circuit the cascading sort. Also covers the existing
`sortSessionsByUpdated()` comparator to lock in archived-first
ordering.
"""
import os
import re
import subprocess
import tempfile
import unittest

JS_PATH = os.path.join(
    os.path.dirname(__file__),
    "..", "org.kde.plasma.kdeaichat", "contents", "ui",
    "SessionManager.js",
)


def _strip_qml_directives(src: str) -> str:
    return re.sub(r"^\s*\.pragma\s+library\s*\n", "", src, count=1)


def _find_runner() -> str:
    for runner in ("node", "qjs6", "qjs"):
        if subprocess.run(["which", runner], capture_output=True).returncode == 0:
            return runner
    return ""


RUNNER = _find_runner()


@unittest.skipUnless(RUNNER, "No JavaScript runtime (node, qjs6, or qjs) available")
class TestSessionManagerSort(unittest.TestCase):
    """Cover `sortSessionsByUpdated` + `isSessionOrderCorrect`."""

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

    def test_is_correct_on_empty(self):
        out, err, rc = self._run_script("""
            console.log('empty=' + isSessionOrderCorrect([]));
            console.log('null=' + isSessionOrderCorrect(null));
            console.log('undef=' + isSessionOrderCorrect(undefined));
            console.log('one=' + isSessionOrderCorrect([{value:'a',updatedAt:1}]));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().split("\n"),
                         ["empty=true", "null=true", "undef=true", "one=true"])

    def test_is_correct_on_sorted(self):
        out, err, rc = self._run_script("""
            var s = [
                {value:'a', updatedAt: 30, archived: false},
                {value:'b', updatedAt: 20, archived: false},
                {value:'c', updatedAt: 10, archived: false},
            ];
            console.log('sorted=' + isSessionOrderCorrect(s));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip(), "sorted=true")

    def test_is_correct_on_unsorted(self):
        out, err, rc = self._run_script("""
            var s = [
                {value:'a', updatedAt: 10, archived: false},
                {value:'b', updatedAt: 20, archived: false},
            ];
            console.log('wrong=' + isSessionOrderCorrect(s));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip(), "wrong=false")

    def test_archived_goes_last(self):
        out, err, rc = self._run_script("""
            var s = [
                {value:'arc', updatedAt: 999, archived: true},
                {value:'new', updatedAt: 10, archived: false},
            ];
            console.log('arc-last=' + isSessionOrderCorrect(s));
            var s2 = [
                {value:'new', updatedAt: 10, archived: false},
                {value:'arc', updatedAt: 999, archived: true},
            ];
            console.log('arc-last2=' + isSessionOrderCorrect(s2));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().split("\n"),
                         ["arc-last=false", "arc-last2=true"])

    def test_falls_back_to_createdAt(self):
        out, err, rc = self._run_script("""
            var s = [
                {value:'a', createdAt: 30},
                {value:'b', createdAt: 20},
            ];
            console.log('fallback=' + isSessionOrderCorrect(s));
            var s2 = [
                {value:'a', createdAt: 10},
                {value:'b', createdAt: 20},
            ];
            console.log('fallback2=' + isSessionOrderCorrect(s2));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().split("\n"),
                         ["fallback=true", "fallback2=false"])

    def test_sort_produces_correct_order(self):
        out, err, rc = self._run_script("""
            var s = [
                {value:'a', updatedAt: 10, archived: false},
                {value:'b', updatedAt: 30, archived: false},
                {value:'c', updatedAt: 20, archived: false},
                {value:'d', updatedAt: 5, archived: true},
            ];
            var sorted = sortSessionsByUpdated(s);
            console.log(JSON.stringify(sorted.map(function(x){return x.value;})));
            console.log('now-correct=' + isSessionOrderCorrect(sorted));
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().split("\n"),
                         ["[\"b\",\"c\",\"a\",\"d\"]", "now-correct=true"])

    def test_sort_does_not_mutate_input(self):
        out, err, rc = self._run_script("""
            var s = [
                {value:'a', updatedAt: 10, archived: false},
                {value:'b', updatedAt: 30, archived: false},
            ];
            var sorted = sortSessionsByUpdated(s);
            console.log('orig=' + s[0].value);
            console.log('sorted=' + sorted[0].value);
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().split("\n"),
                         ["orig=a", "sorted=b"])


class TestUpdateSession(unittest.TestCase):
    """Cover the `updateSession()` helper."""

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

    def test_update_session_mutates_clone(self):
        out, err, rc = self._run_script("""
            var s = [
                {value:'a', text:'Old', updatedAt: 10},
                {value:'b', text:'Other', updatedAt: 20},
            ];
            var result = updateSession(s, 'a', function(clone) {
                clone.text = 'New';
                clone.updatedAt = 99;
            });
            console.log('a=' + result[0].text + ':' + result[0].updatedAt);
            console.log('b=' + result[1].text);
            console.log('orig=' + s[0].text);
            console.log('len=' + result.length);
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().split("\n"),
                         ["a=New:99", "b=Other", "orig=Old", "len=2"])

    def test_update_session_returns_same_for_missing_id(self):
        out, err, rc = self._run_script("""
            var s = [{value:'a', text:'X'}];
            var result = updateSession(s, 'missing', function(clone) {
                clone.text = 'Y';
            });
            console.log('same=' + (result === s));
            console.log('text=' + result[0].text);
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().split("\n"),
                         ["same=true", "text=X"])

    def test_update_session_preserves_other_sessions(self):
        out, err, rc = self._run_script("""
            var s = [
                {value:'a', text:'A'},
                {value:'b', text:'B'},
                {value:'c', text:'C'},
            ];
            var result = updateSession(s, 'b', function(clone) {
                clone.text = 'B2';
            });
            console.log('a=' + result[0].text + ' b=' + result[1].text + ' c=' + result[2].text);
            console.log('orig=' + s[0].text + ' ' + s[1].text + ' ' + s[2].text);
        """)
        self.assertEqual(rc, 0, msg=err)
        self.assertEqual(out.strip().split("\n"),
                         ["a=A b=B2 c=C", "orig=A B C"])


if __name__ == "__main__":
    unittest.main()
