"""Every interactive control in the widget's QML has a name a screen reader can
say: an Accessible.name, or (for buttons, checkboxes, switches, menu items) its
own text. Fields and drop-downs always need an explicit Accessible.name.

This reads the source of all files; tests/qml/tst_accessibility.qml walks the
running chat and settings pages as well.
"""
import re
from pathlib import Path

UI = Path(__file__).resolve().parent.parent / "org.kde.plasma.kdeaichat" / "contents" / "ui"

TEXT_NAMED = ("ToolButton", "Button", "CheckBox", "Switch", "RadioButton", "MenuItem", "ItemDelegate", "TabButton", "Chip")
NEEDS_NAME = ("ComboBox", "TextField", "TextArea", "SpinBox", "Slider", "SearchField", "PasswordField")
OPEN = re.compile(r"^(\s*)([A-Za-z0-9_.]*?(?:" + "|".join(TEXT_NAMED + NEEDS_NAME) + r"))\s*\{\s*$")

# "file:line-independent" objectNames of controls that are never shown to the user.
ALLOWLIST = {"buttonMetrics"}


def unnamed_controls():
    found = []
    for path in sorted(UI.rglob("*.qml")):
        lines = path.read_text().split("\n")
        for i, line in enumerate(lines):
            m = OPEN.match(line)
            if not m:
                continue
            kind = m.group(2).split(".")[-1]
            block, depth, j = [], 1, i + 1
            direct = []
            while j < len(lines) and depth > 0:
                if depth == 1:
                    direct.append(lines[j])
                block.append(lines[j])
                depth += lines[j].count("{") - lines[j].count("}")
                j += 1
            body = "\n".join(block)
            if "Accessible.name" in body:
                continue
            if kind.endswith(TEXT_NAMED) and re.search(r"^\s*(text|action)\s*:", "\n".join(direct), re.M):
                continue
            if any('objectName: "%s"' % name in body for name in ALLOWLIST):
                continue
            # A visible: false helper is never reached.
            if re.search(r"^\s*visible:\s*false\s*$", "\n".join(direct), re.M):
                continue
            found.append("%s:%d %s" % (path.relative_to(UI), i + 1, kind))
    return found


def test_every_control_has_an_accessible_name():
    assert unnamed_controls() == []
