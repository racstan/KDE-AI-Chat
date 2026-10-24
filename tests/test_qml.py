"""Runs the offscreen QML tests in tests/qml/ under Qt 6's qmltestrunner.

Fails if any test fails or if a warning points into the widget's own files.
Skipped when no Qt 6 qmltestrunner (with the Kirigami/Plasma QML modules) is
installed.
"""
import os
import shutil
import subprocess

import pytest

ROOT = os.path.join(os.path.dirname(__file__), "..")
QML_TESTS = os.path.join(ROOT, "tests", "qml")


def _qt6_runner():
    for name in ("qmltestrunner6", "qmltestrunner-qt6"):
        path = shutil.which(name)
        if path:
            return path
    for path in ("/usr/lib/qt6/bin/qmltestrunner", "/usr/lib64/qt6/bin/qmltestrunner"):
        if os.access(path, os.X_OK):
            return path
    return None


RUNNER = _qt6_runner()


@pytest.mark.skipif(RUNNER is None, reason="Qt 6 qmltestrunner not installed")
def test_qml_suite():
    os.makedirs(os.path.join(ROOT, "build", "qml-screens"), exist_ok=True)
    # org.kde.desktop renders controls in the Breeze style, so screenshots
    # look like the real widget.
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
    env.setdefault("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop")
    result = subprocess.run(
        [RUNNER, "-platform", "offscreen", "-input", QML_TESTS],
        capture_output=True,
        text=True,
        timeout=300,
        env=env,
        cwd=ROOT,
    )
    output = result.stdout + result.stderr
    own_warnings = [
        line for line in output.splitlines()
        if "/contents/ui/" in line
        and ("QWARN" in line or "Warning" in line)
        and "used before its declaration" not in line
    ]
    assert result.returncode == 0, output
    assert not own_warnings, "\n".join(own_warnings)
