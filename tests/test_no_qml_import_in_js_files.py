"""Regression test: ensure no QML `.import` directives leak into .js files.

`Security.js`, `ProviderService.js`, etc. are imported as aliases in
`main.qml` (e.g. `import "Security.js" as Sec`). When a JS helper file
like `MainNetwork.js` re-declares them with `.import "Security.js"
as Sec`, the .import directive is a QML-only construct and causes a
SyntaxError when the same file is loaded by a non-QML context — for
instance, when the plasmoid test runner (qmltestrunner), the QML
compiler (qmllint), or any tooling that evaluates the file under
plain JavaScript tries to parse it.

The previous fix (commit 4414f4d) explicitly removed these lines and
documented the rationale. A later lag-fix commit (bce6fc8) re-added
them by accident. This test guards against re-introduction.

Each of the four files known to have carried the regression at some
point must start with either `.pragma library`, a `//`-style comment,
or a top-level `function` / `var` / `let` / `const` declaration.
"""
import os
import re
import unittest

UI_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "org.kde.plasma.kdeaichat", "contents", "ui",
)

# The set of JS files known to have been affected by the regression.
# If a new file is added later, extend this list.
WATCHED_FILES = (
    "ChatEngine.js",
    "ConfigGeneralLogic.js",
)

# Top-of-file patterns that are legal in a plain .js file.
_LEGAL_HEADER = re.compile(
    r"^(?:\.pragma\s+library|//[^\n]*|/\*|\s*$|\s*(?:function|var|let|const|class)\b)"
)


class TestNoQmlImportInJsFiles(unittest.TestCase):
    """`.import` is a QML-only directive. Plain .js files must not
    contain it."""

    def test_watched_files_have_legal_header(self):
        for name in WATCHED_FILES:
            path = os.path.join(UI_DIR, name)
            with open(path) as f:
                first_line = f.readline().rstrip("\n")
            with self.subTest(file=name):
                self.assertFalse(
                    first_line.lstrip().startswith(".import"),
                    msg=(
                        f"{name} starts with a `.import` directive. "
                        "QML-only `.import` causes a SyntaxError when "
                        "the file is evaluated outside QML (qmllint, "
                        "qmltestrunner, plain node). The intended fix "
                        "(see commit 4414f4d) is to delete the line and "
                        "rely on the alias declared in the importing "
                        "QML file's `import` statement."
                    ),
                )
                self.assertRegex(
                    first_line,
                    _LEGAL_HEADER,
                    msg=(
                        f"{name} has an unexpected first line: {first_line!r}. "
                        "Expected `.pragma library`, a `//` comment, "
                        "or a top-level `function`/`var`/`let`/`const`."
                    ),
                )

    def test_no_qml_import_anywhere_in_watched_files(self):
        """No `.import` directive at the start of any line anywhere
        in the watched files."""
        for name in WATCHED_FILES:
            path = os.path.join(UI_DIR, name)
            with open(path) as f:
                contents = f.read()
            with self.subTest(file=name):
                self.assertNotRegex(
                    contents,
                    r"^\s*\.import\s+",
                    msg=f"{name} contains a `.import` directive (QML-only).",
                )


if __name__ == "__main__":
    unittest.main()
