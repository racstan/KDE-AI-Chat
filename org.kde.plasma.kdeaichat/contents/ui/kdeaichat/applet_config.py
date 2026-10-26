"""The widget's settings, read (never written) outside the widget.

A scheduled run happens without the widget, so it reads the same settings
the widget would see as ``plasmoid.configuration``: the defaults from
``contents/config/main.xml``, overlaid with the applet's
``[...][Applets][<id>][Configuration][General]`` group in Plasma's applet
config (``plasma-org.kde.plasma.desktop-appletsrc``; ``plasmawindowedrc``
for a windowed dev run). Values are typed like KConfigXT does (Bool, Int,
String). Stdlib only.
"""
import glob
import os
import re
import xml.etree.ElementTree as ET
from typing import Any, Dict, List, Optional

MAIN_XML = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "config", "main.xml")
PLUGIN_PREFIX = "org.kde.plasma.kdeaichat"
MAX_CONFIG_BYTES = 32 * 1024 * 1024
_GROUP = re.compile(r"^\[(.*)\]\s*$")


def config_home() -> str:
    return os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")


def _unescape(value: str) -> str:
    """KConfig's printable form back to text (\\s \\t \\n \\r \\\\ \\; \\, \\xHH)."""
    out = bytearray()
    raw = value.encode("utf-8", "surrogateescape")
    i = 0
    simple = {ord("s"): b" ", ord("t"): b"\t", ord("n"): b"\n", ord("r"): b"\r", ord("\\"): b"\\",
              ord(";"): b";", ord(","): b","}
    while i < len(raw):
        c = raw[i]
        if c == 0x5C and i + 1 < len(raw):
            nxt = raw[i + 1]
            if nxt in simple:
                out += simple[nxt]
                i += 2
                continue
            if nxt == ord("x") and i + 3 < len(raw):
                try:
                    out.append(int(raw[i + 2:i + 4].decode("ascii"), 16))
                    i += 4
                    continue
                except ValueError:
                    pass
        out.append(c)
        i += 1
    return out.decode("utf-8", "replace")


def parse_kconfig(path: str) -> Dict[str, Dict[str, str]]:
    """{group name: {key: value}} of a KConfig file; localized/flagged keys skipped."""
    groups: Dict[str, Dict[str, str]] = {}
    try:
        if os.path.getsize(path) > MAX_CONFIG_BYTES:
            return groups
        with open(path, encoding="utf-8", errors="surrogateescape") as f:
            lines = f.read().splitlines()
    except OSError:
        return groups
    current: Optional[Dict[str, str]] = None
    for line in lines:
        if not line or line.startswith("#"):
            continue
        match = _GROUP.match(line)
        if match:
            current = groups.setdefault(line.strip(), {})
            continue
        if current is None or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if "[" in key:
            continue
        current[key] = _unescape(value)
    return groups


def defaults(main_xml: str = MAIN_XML) -> Dict[str, Any]:
    """main.xml entries -> typed defaults."""
    out: Dict[str, Any] = {}
    root = ET.parse(main_xml).getroot()
    for entry in root.iter():
        if not entry.tag.endswith("entry"):
            continue
        name, kind = entry.get("name"), entry.get("type", "String")
        default = next((c.text or "" for c in entry if c.tag.endswith("default")), "")
        out[name] = _typed(kind, default)
    return out


def _types(main_xml: str = MAIN_XML) -> Dict[str, str]:
    root = ET.parse(main_xml).getroot()
    return {e.get("name"): e.get("type", "String") for e in root.iter() if e.tag.endswith("entry")}


def _typed(kind: str, value: str) -> Any:
    if kind == "Bool":
        return value.strip().lower() in ("true", "1", "yes", "on")
    if kind in ("Int", "UInt"):
        try:
            return int(value.strip() or 0)
        except ValueError:
            return 0
    if kind == "Double":
        try:
            return float(value.strip() or 0)
        except ValueError:
            return 0.0
    return value


def candidate_files() -> List[str]:
    home = config_home()
    first = [os.path.join(home, "plasma-org.kde.plasma.desktop-appletsrc"), os.path.join(home, "plasmawindowedrc")]
    rest = sorted(p for p in glob.glob(os.path.join(home, "*appletsrc")) if p not in first)
    return [p for p in first + rest if os.path.isfile(p)]


def applet_settings(applet_id: str, main_xml: str = MAIN_XML) -> Optional[Dict[str, Any]]:
    """The settings of widget instance ``applet_id`` (the N of chats/applet-N), or None.

    ``_configFile`` names the file they came from.
    """
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", applet_id or ""):
        return None
    suffix = f"[Applets][{applet_id}]"
    for path in candidate_files():
        groups = parse_kconfig(path)
        for name, values in groups.items():
            if name.endswith(suffix) and values.get("plugin", "").startswith(PLUGIN_PREFIX):
                general = groups.get(name + "[Configuration][General]", {})
                settings = defaults(main_xml)
                types = _types(main_xml)
                for key, value in general.items():
                    settings[key] = _typed(types.get(key, "String"), value)
                settings["_configFile"] = path
                return settings
    return None
