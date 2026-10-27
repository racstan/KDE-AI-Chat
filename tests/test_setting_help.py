"""Every setting has a plain explanation (config/SettingHelp.qml).

The settings pages, their sub-forms and the per-chat settings are read as QML
and checked:

* In a Kirigami.FormLayout, every "setting row" is followed by a SettingHelp
  before the next setting row or section (or has one inside it). A setting
  row is a direct child of the form that has a Kirigami.FormData.label, is an
  input control (check box, switch, drop-down, spin box, text field, slider),
  or holds a control that a cfg_ property is bound to. Plain labels and
  labelled rows with nothing to change (information, status) and sections
  are not settings.
  A row that shares the explanation of the next one says so with the comment
  `// help: next` inside it.
* A component whose root is a form row (config/TtsOption.qml) has a
  SettingHelp inside.
* The per-chat settings use SettingField, which must be given `help:`.
* The voice engines' options (voice/TtsEngines.js, voice/SttEngines.js) each
  have a `help` text.

So a new setting can't be added without its explanation.
"""
import json
import os
import re
import subprocess
import sys

import pytest

ROOT = os.path.join(os.path.dirname(__file__), "..")
UI = os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui")

# The settings pages and every form they are built from, and the per-chat settings.
FILES = [
    "ConfigConnection.qml", "ConfigChat.qml", "ConfigPersonality.qml", "ConfigMemory.qml",
    "ConfigSchedules.qml", "ConfigVoice.qml", "ConfigAppearance.qml",
    "config/ModeChooser.qml", "config/RequestOptions.qml", "config/ProviderEditor.qml",
    "config/OpenCodeSettings.qml", "config/PiSettings.qml", "config/ImageProviderEditor.qml",
    "config/ScheduleEditor.qml", "config/ScheduleOptions.qml", "config/DictationSettings.qml",
    "config/SpeechNotePanel.qml", "config/TtsOption.qml", "config/PanelIconSettings.qml",
    "config/ChatLookSettings.qml", "config/LayoutSettings.qml", "config/BehaviourSettings.qml",
    "ChatSettingsDialog.qml", "chat/ChatOverridesForm.qml", "chat/PiChatSettings.qml", "chat/SettingField.qml",
    "chat/OwnModelCheck.qml",
]

# Settings laid out in a plain column (the Chat info panel): their root is checked like a form.
COLUMN_FORMS = {"chat/ChatOverridesForm.qml", "chat/PiChatSettings.qml"}

INPUT_TYPES = {"CheckBox", "Switch", "ComboBox", "SpinBox", "TextField", "PasswordField", "Slider", "TextArea", "RadioButton"}
LABEL_TYPES = {"Label", "Heading", "SettingHelp", "Separator", "InlineMessage"}
# Types that show something but can't be changed.
PASSIVE_TYPES = LABEL_TYPES | {"RowLayout", "ColumnLayout", "Item", "BusyIndicator", "ProgressBar", "Image", "Icon"}

TYPE_RE = re.compile(r"(?:^|[\s;:\[,])((?:[A-Za-z_]\w*\.)*[A-Z]\w*)\s*$")


class Element:
    def __init__(self, type_name, start, parent):
        self.type = type_name
        self.short = type_name.split(".")[-1]
        self.start = start
        self.end = None
        self.parent = parent
        self.children = []
        self.own = ""          # its text without the children's

    def walk(self):
        yield self
        for child in self.children:
            yield from child.walk()

    def has_help_property(self):
        return re.search(r"(?m)^\s*help:\s*\S", self.own) is not None

    def contains_help(self):
        return any(e.short == "SettingHelp" or (e.short == "SettingField" and e.has_help_property())
                   for e in self.walk())


def _blank(source):
    """Comments and string contents become spaces (offsets stay)."""
    out = []
    i, n = 0, len(source)
    while i < n:
        c = source[i]
        if source.startswith("//", i):
            j = source.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif source.startswith("/*", i):
            j = source.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", source[i:j]))
            i = j
        elif c in "\"'`":
            j = i + 1
            while j < n and source[j] != c:
                j += 2 if source[j] == "\\" else 1
            out.append(c + re.sub(r"[^\n]", " ", source[i + 1:j]) + c)
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def parse(path):
    """The QML object tree of a file (JS blocks are skipped)."""
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    text = _blank(raw)
    root = Element("<file>", 0, None)
    stack = [root]   # Elements, or None for a JS / object-literal block
    for i, c in enumerate(text):
        if c == "{":
            match = TYPE_RE.search(text[max(0, i - 200):i])
            parent = next(e for e in reversed(stack) if e is not None)
            if match and not re.search(r"\b(function|if|else|for|while|switch|try|catch|return)\b[^{]*$", text[max(0, i - 200):i].split("\n")[-1]) \
                    and stack[-1] is not None:
                element = Element(match.group(1), i, parent)
                parent.children.append(element)
                stack.append(element)
            else:
                stack.append(None)
        elif c == "}":
            top = stack.pop()
            if top is not None:
                top.end = i + 1
    for element in root.walk():
        if element is root:
            continue
        pieces, pos = [], element.start
        for child in element.children:
            pieces.append(text[pos:child.start])
            pos = child.end
        pieces.append(text[pos:element.end])
        element.own = "".join(pieces)
        element.raw = raw[element.start:element.end]
    return root, text, raw


def _ids(element):
    return {m.group(1) for e in element.walk() for m in re.finditer(r"(?m)^\s*id:\s*(\w+)", e.own)}


def _is_section(element):
    return re.search(r"FormData\.isSection:\s*true", element.own) is not None


def _labelled(element):
    return "FormData.label:" in element.own


def _is_setting_row(element, cfg_targets):
    if element.short in LABEL_TYPES or _is_section(element):
        return False
    row = element
    if element.short == "Repeater":
        delegates = [c for c in element.children]
        if not delegates:
            return False
        row = delegates[0]
        if row.short in LABEL_TYPES:
            return False
    if row.short in INPUT_TYPES or row.short in ("SettingField", "OwnModelCheck") or _ids(row) & cfg_targets:
        return True
    # A labelled row with nothing to change in it is information (a status line).
    return _labelled(row) and any(e.short not in PASSIVE_TYPES for e in row.walk())


def problems_in(rel):
    path = os.path.join(UI, rel)
    root, text, raw = parse(path)
    cfg_targets = set(re.findall(r"property alias cfg_\w+:\s*(\w+)\.", raw))
    found = []

    def where(element):
        return "%s:%d %s" % (rel, text.count("\n", 0, element.start) + 1, element.type)

    top = root.children[0] if root.children else None
    for element in root.walk():
        if element.short == "FormLayout" or (element is top and rel in COLUMN_FORMS):
            rows = element.children
            for index, row in enumerate(rows):
                if not _is_setting_row(row, cfg_targets) or row.contains_help():
                    continue
                if "// help: next" in row.raw:
                    continue
                explained = False
                for after in rows[index + 1:]:
                    if after.short == "SettingHelp":
                        explained = True
                        break
                    if _is_section(after) or _is_setting_row(after, cfg_targets):
                        break
                if not explained:
                    found.append(where(row) + ": no SettingHelp after this setting")
        if element.short in ("SettingField", "Field") and element is not top and not element.has_help_property():
            found.append(where(element) + ": a SettingField needs help:")
    if top is not None and _labelled(top) and not top.contains_help():
        found.append(where(top) + ": a form row component needs a SettingHelp inside")
    return found


@pytest.mark.parametrize("rel", FILES)
def test_every_setting_is_explained(rel):
    assert os.path.exists(os.path.join(UI, rel)), rel + " is listed but missing"
    assert problems_in(rel) == []


def test_every_settings_form_is_listed():
    """A new settings form is checked too: every FormLayout file under ui/ is in FILES."""
    listed = set(FILES)
    missing = []
    for folder, _dirs, names in os.walk(UI):
        for name in names:
            if not name.endswith(".qml"):
                continue
            rel = os.path.relpath(os.path.join(folder, name), UI)
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                if "Kirigami.FormLayout" in f.read() and rel not in listed:
                    missing.append(rel)
    assert missing == []


def test_the_check_catches_a_missing_explanation(tmp_path, monkeypatch):
    form = tmp_path / "Form.qml"
    form.write_text("""
import QtQuick
Kirigami.FormLayout {
    QQC2.CheckBox { Kirigami.FormData.label: i18n("A:"); text: "x" }
    Config.SettingHelp { text: i18n("Explained {here}.") }
    QQC2.CheckBox { id: second; text: i18n("B") }
    Item { Kirigami.FormData.isSection: true }
    QQC2.Label { Kirigami.FormData.label: i18n("Status:"); text: "ok" }
    RowLayout {
        Kirigami.FormData.label: i18n("C:")
        QQC2.SpinBox { onValueModified: { if (value) { foo({"a": 1}); } } }
    }
    RowLayout {
        // help: next
        Kirigami.FormData.label: i18n("D:")
    }
    QQC2.TextField { id: e }
    SettingHelp { text: "shared" }
}
""")
    monkeypatch.setattr(sys.modules[__name__], "UI", str(tmp_path))
    found = problems_in("Form.qml")
    assert len(found) == 2, found
    assert "Form.qml:6 QQC2.CheckBox" in found[0]
    assert "Form.qml:9 RowLayout" in found[1]


def _engine_options(module):
    script = (
        "var fs = require('fs');\n"
        "var src = fs.readFileSync(%r, 'utf8').replace('.pragma library', '');\n"
        "eval(src + '\\nglobal.__engines = engines;');\n"
        "var out = [];\n"
        "__engines.forEach(function(e) { e.options.forEach(function(o) { out.push({engine: e.id, label: o.label, help: o.help || ''}); }); });\n"
        "console.log(JSON.stringify(out));\n"
    ) % os.path.join(UI, "voice", module)
    result = subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


@pytest.mark.parametrize("module", ["TtsEngines.js", "SttEngines.js"])
def test_every_voice_engine_option_is_explained(module):
    options = _engine_options(module)
    assert options
    missing = ["%s/%s" % (o["engine"], o["label"]) for o in options if len(o["help"].strip()) < 12]
    assert missing == []
