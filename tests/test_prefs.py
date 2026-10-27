"""chat/Prefs.js: the look, layout and behaviour options.

Its defaults must be the ones in contents/config/main.xml (the widget reads
the config, the settings pages reset to Prefs.js), and its helpers are run in
node.
"""
import json
import os
import subprocess
import xml.etree.ElementTree as ET

ROOT = os.path.join(os.path.dirname(__file__), "..")
UI = os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui")
MAIN_XML = os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "config", "main.xml")
PREFS = os.path.join(UI, "chat", "Prefs.js")


def _run(snippet):
    with open(PREFS, encoding="utf-8") as f:
        source = f.read().replace(".pragma library", "")
    script = source + "\n" + snippet
    result = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=60, check=True)
    return json.loads(result.stdout)


def _xml_defaults():
    ns = {"k": "http://www.kde.org/standards/kcfg/1.0"}
    out = {}
    for entry in ET.parse(MAIN_XML).getroot().iter("{%s}entry" % ns["k"]):
        default = entry.find("k:default", ns)
        text = (default.text or "") if default is not None else ""
        kind = entry.get("type")
        if kind == "Int":
            value = int(text)
        elif kind == "Bool":
            value = text.strip() == "true"
        else:
            value = text
        out[entry.get("name")] = value
    return out


def test_defaults_match_main_xml():
    data = _run("console.log(JSON.stringify([defaults, appearancePageDefaults, chatPageDefaults]));")
    xml = _xml_defaults()
    for table in data:
        for key, value in table.items():
            assert key in xml, key + " is not a setting in main.xml"
            assert xml[key] == value, "%s: main.xml %r, Prefs.js %r" % (key, xml[key], value)


def test_page_key_lists_cover_every_option():
    data = _run("console.log(JSON.stringify([Object.keys(defaults), lookKeys.concat(layoutKeys, behaviourKeys)]));")
    assert sorted(data[0]) == sorted(data[1])


def test_helpers():
    data = _run("""
var d = new Date(2026, 9, 25, 14, 5).getTime();
var m = new Date(2026, 9, 25, 0, 7).getTime();
console.log(JSON.stringify({
  t24: formatTime(d, "24h"), t12: formatTime(d, "12h"), mid12: formatTime(m, "12h"), sys: formatTime(d, "system"), none: formatTime(0, "12h"),
  enter: [sends("enter", "return", false, false), sends("enter", "return", false, true), sends("enter", "return", true, false)],
  ctrl: [sends("ctrlEnter", "return", false, false), sends("ctrlEnter", "return", true, false), sends("ctrlEnter", "return", true, true)],
  other: sends("enter", "", false, false),
  accent: [accent("#AbC"), accent(" #12ab34 "), accent("red"), accent("")],
  font: [fontFactor(100), fontFactor(150), fontFactor(10), fontFactor(999), fontFactor("x")],
  density: [densityFactor("compact"), densityFactor("normal"), densityFactor("roomy"), densityFactor("?")],
  code: [codeTheme("system"), codeTheme("dark").background, codeTheme("constructor")],
  value: [value({}, "sendKey"), value({sendKey: "ctrlEnter"}, "sendKey"), value({autoScroll: "no"}, "autoScroll"), value(null, "chatFontScale")]
}));
""")
    assert data["t24"] == "14:05"
    assert data["t12"] == "2:05 PM"
    assert data["mid12"] == "12:07 AM"
    assert data["sys"] == "" and data["none"] == ""
    # The default: Enter sends (also with Ctrl, as before), Shift+Enter doesn't.
    assert data["enter"] == [True, False, True]
    assert data["ctrl"] == [False, True, False]
    assert data["other"] is False
    assert data["accent"] == ["#aabbcc", "#12ab34", "", ""]
    assert data["font"] == [1, 1.5, 0.5, 2, 1]
    assert data["density"] == [0.5, 1, 1.5, 1]
    assert data["code"] == [None, "#1e1e1e", None]
    assert data["value"] == ["enter", "ctrlEnter", True, 100]
