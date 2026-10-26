"""The scheduled job's INI writer/reader (kdeaichat/qsettings_ini.py) against Qt's own QSettings.

Both directions, through the widget's real store/ChatStore.qml under qmltestrunner:
Python writes a chat file that ChatStore.loadAll() must read back exactly, and
ChatStore writes one that Python must read back exactly. The messages are
chosen to hit every escaping rule (quotes, backslashes, control characters,
";,=" and the quoting they force, leading/trailing spaces, "@", non-BMP).
"""
import json
import os
import shutil

import pytest

from kdeaichat import qsettings_ini, schedule_chat
from tests.test_qml import RUNNER, REQUIRED, ROOT, _run

TRICKY = [
    {"role": "user", "content": "plain"},
    {"role": "assistant", "content": 'quotes " and \\ backslash; semicolon, comma = equals'},
    {"role": "user", "content": "lines\nand\ttabs\r\nand \x01\x02 controls \x7f del, then hex-looking 1\x01a"},
    {"role": "assistant", "content": "  spaces around  "},
    {"role": "user", "content": "@at start"},
    {"role": "assistant", "content": "Unicode: é ß 中文 😀   sep", "reasoning": "<think>x</think>"},
    {"role": "user", "content": "nul \x00 then digits 123"},
]

QML = r'''
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

TestCase {
    name: "IniInterop"
    property var tricky: %(tricky)s
    property string dir: %(dir)s

    Component { id: storeComponent; Store.ChatStore {} }

    function make(directory) {
        var s = createTemporaryObject(storeComponent, null, {"directory": directory});
        s.runHelper = function(command, payload, onDone) { if (onDone) onDone(""); };
        s.prepare(null);
        return s;
    }

    // Python wrote <dir>/from-python: ChatStore reads it back exactly.
    function test_reads_what_python_wrote() {
        var sessions = make(dir + "/from-python").loadAll();
        verify(sessions !== null, "index read");
        compare(sessions.length, 1);
        compare(sessions[0].value, "chat:1");
        compare(JSON.stringify(sessions[0].messages), JSON.stringify(tricky));
    }

    // ChatStore writes <dir>/from-qt for Python to read.
    function test_writes_for_python() {
        var s = make(dir + "/from-qt");
        s.save([{"value": "chat:1", "text": "Qt", "messages": tricky}], true);
    }
}
'''


@pytest.mark.skipif(RUNNER is None and not REQUIRED, reason="Qt 6 qmltestrunner not installed")
def test_python_and_qt_read_each_others_chat_files():
    work = os.path.join(ROOT, "build", "ini-interop")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(os.path.join(work, "from-python"))
    py_dir = os.path.join(work, "from-python")
    qsettings_ini.write_values(os.path.join(py_dir, "index.ini"),
                               {"version": "1", "sessions": json.dumps([{"value": "chat:1", "text": "Py"}])})
    qsettings_ini.write_values(os.path.join(py_dir, schedule_chat.file_name_for_id("chat:1")),
                               {"messages": json.dumps(TRICKY, ensure_ascii=False, separators=(",", ":"))})
    test_file = os.path.join(work, "tst_ini_interop.qml")
    with open(test_file, "w", encoding="utf-8") as f:
        f.write(QML % {"tricky": json.dumps(TRICKY), "dir": json.dumps(os.path.realpath(work))})
    _run(test_file, dict(os.environ))

    qt_file = os.path.join(work, "from-qt", schedule_chat.file_name_for_id("chat:1"))  # Qt decodes %3A: "chat-chat:1.ini"
    assert os.path.exists(qt_file)
    assert json.loads(qsettings_ini.read_value(qt_file, "messages")) == TRICKY
    # and the job's append keeps Qt's other keys and Qt can still read it (round trip through Python)
    qsettings_ini.write_values(qt_file, {"messages": json.dumps(TRICKY + [{"role": "user", "content": "more"}])})
    assert json.loads(qsettings_ini.read_value(qt_file, "messages"))[-1] == {"role": "user", "content": "more"}
