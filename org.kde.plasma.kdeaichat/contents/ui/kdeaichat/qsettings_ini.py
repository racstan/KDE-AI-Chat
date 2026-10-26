"""Read and write the INI files the widget's chat store writes (QtCore ``Settings``).

store/ChatStore.qml writes each value as one string under ``[General]``
(``messages=<JSON>``, ``sessions=<JSON>``, ``version=1``). Qt 6 escapes a
string value like this (QSettingsPrivate::iniEscapedString): ``\\`` and ``"``
get a backslash, control characters become ``\\n``-style or ``\\xHH`` escapes
(a hex digit right after a ``\\x`` escape is escaped too), everything else is
written as UTF-8, and the value is put in double quotes when it contains
``;``, ``,`` or ``=`` or starts or ends with a space. A string starting with
``@`` gets a second ``@``. ``unescape`` undoes exactly that
(iniUnescapedStringList), and ``write_values`` writes the same form, so the
widget reads what the scheduled job wrote and the other way round
(tests/test_schedule_ini_qt.py checks both directions against Qt itself).
"""
import os
import re
from typing import Dict, List, Optional, Tuple

from kdeaichat.common import atomic_write_text

_SIMPLE = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v",
           '"': '"', "?": "?", "'": "'", "\\": "\\"}
_ESCAPE_OUT = {"\a": "\\a", "\b": "\\b", "\f": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\v": "\\v",
               '"': '\\"', "\\": "\\\\"}
_HEX = "0123456789abcdefABCDEF"
_SECTION = re.compile(r"^\s*\[(.*)\]\s*$")
MAX_INI_BYTES = 64 * 1024 * 1024


def escape(value: str) -> str:
    """One string value as Qt 6 writes it (without the ``key=``)."""
    if value.startswith("@"):
        value = "@" + value
    out: List[str] = []
    needs_quotes = False
    escape_next_if_digit = False
    for ch in value:
        if ch in ";,=":
            needs_quotes = True
        if escape_next_if_digit and ch in _HEX:
            out.append("\\x%x" % ord(ch))
            continue
        escape_next_if_digit = False
        if ch == "\0":
            out.append("\\0")
            escape_next_if_digit = True
        elif ch in _ESCAPE_OUT:
            out.append(_ESCAPE_OUT[ch])
        elif ord(ch) <= 0x1F:
            out.append("\\x%x" % ord(ch))
            escape_next_if_digit = True
        else:
            out.append(ch)
    text = "".join(out)
    if needs_quotes or text.startswith(" ") or text.endswith(" "):
        text = '"' + text + '"'
    return text


def unescape(raw: str) -> str:
    """A value as Qt 6 reads it back (one string; a list is joined with ", ")."""
    items: List[str] = []
    parts: List[str] = []
    length = 0          # characters in parts
    chop_limit = 0      # trailing spaces before this point came from escapes and are kept
    in_quotes = quoted = False
    n = len(raw)

    def skip_spaces(pos: int) -> int:
        while pos < n and raw[pos] in " \t":
            pos += 1
        return pos

    def finish() -> str:
        text = "".join(parts)
        if not quoted:
            text = text[:chop_limit] + text[chop_limit:].rstrip(" \t\r\n\v\f")
        return text

    i = skip_spaces(0)
    while i < n:
        ch = raw[i]
        if ch == "\\":
            i += 1
            if i >= n:
                break
            ch = raw[i]
            i += 1
            if ch in _SIMPLE:
                parts.append(_SIMPLE[ch])
                length += 1
                chop_limit = length
                continue
            if ch == "x" and i < n and raw[i] in _HEX:
                value = 0
                while i < n and raw[i] in _HEX:
                    value = ((value << 4) + int(raw[i], 16)) & 0xFFFF
                    i += 1
                parts.append(chr(value))
                length += 1
            elif "0" <= ch <= "7":
                value = int(ch)
                while i < n and "0" <= raw[i] <= "7":
                    value = ((value << 3) + int(raw[i])) & 0xFFFF
                    i += 1
                parts.append(chr(value))
                length += 1
            chop_limit = length
        elif ch == '"':
            i += 1
            quoted = True
            in_quotes = not in_quotes
            if not in_quotes:
                i = skip_spaces(i)
                chop_limit = length
        elif ch == "," and not in_quotes:
            items.append(finish())
            parts, length, chop_limit, quoted = [], 0, 0, False
            i = skip_spaces(i + 1)
        else:
            j = i + 1
            while j < n and raw[j] not in '\\",':
                j += 1
            parts.append(raw[i:j])
            length += j - i
            i = j
    last = finish()
    text = ", ".join(items + [last]) if items else last
    return text[1:] if text.startswith("@@") else text


def _key_of(line: str) -> Optional[Tuple[str, str]]:
    if "=" not in line or line.lstrip().startswith(";"):
        return None
    key, raw = line.split("=", 1)
    return key.strip(), raw.rstrip("\r")


def _lines(path: str) -> List[str]:
    try:
        if os.path.getsize(path) > MAX_INI_BYTES:
            raise ValueError(f"{os.path.basename(path)} is too large")
        with open(path, encoding="utf-8", errors="replace", newline="") as f:
            lines = f.read().split("\n")
    except FileNotFoundError:
        return []
    while lines and lines[-1] == "":
        lines.pop()
    return lines


def read_values(path: str) -> Dict[str, str]:
    """The ``[General]`` values of an INI file, unescaped; {} when it is missing."""
    values: Dict[str, str] = {}
    section = "General"     # keys before any header belong to [General]
    for line in _lines(path):
        match = _SECTION.match(line)
        if match:
            section = match.group(1)
            continue
        pair = _key_of(line) if section == "General" else None
        if pair:
            values[pair[0]] = unescape(pair[1])
    return values


def read_value(path: str, key: str, default: str = "") -> str:
    return read_values(path).get(key, default)


def write_values(path: str, updates: Dict[str, str]) -> None:
    """Set ``[General]`` keys (other keys and sections are kept), atomically, mode 0600."""
    out: List[str] = []
    section = "General"
    has_header = False
    done = set()

    def flush() -> None:
        out.extend(f"{k}={escape(v)}" for k, v in updates.items() if k not in done)
        done.update(updates)

    for line in _lines(path):
        match = _SECTION.match(line)
        if match:
            if section == "General":
                flush()
            section = match.group(1)
            has_header = has_header or section == "General"
            out.append(line)
            continue
        pair = _key_of(line) if section == "General" else None
        if pair and pair[0] in updates:
            out.append(f"{pair[0]}={escape(updates[pair[0]])}")
            done.add(pair[0])
        else:
            out.append(line)
    if section == "General":
        flush()
    if not has_header:
        out.insert(0, "[General]")
    atomic_write_text(path, "\n".join(out) + "\n", mode=0o600)
