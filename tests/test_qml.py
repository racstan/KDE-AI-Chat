"""Runs the offscreen QML tests in tests/qml/ under Qt 6's qmltestrunner.

Fails if any test fails or if a warning points into the widget's own files.
Skipped when no Qt 6 qmltestrunner (with the Kirigami/Plasma QML modules) is
installed, unless REQUIRE_QML_TESTS=1.
"""
import glob
import os
import shutil
import subprocess
import tempfile
import time

import pytest

ROOT = os.path.join(os.path.dirname(__file__), "..")
QML_TESTS = os.path.join(ROOT, "tests", "qml")
SCREENS = os.path.join(ROOT, "build", "qml-screens")


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
# CI sets this so a missing runner fails instead of silently skipping.
REQUIRED = os.environ.get("REQUIRE_QML_TESTS") == "1"


@pytest.mark.skipif(RUNNER is None and not REQUIRED, reason="Qt 6 qmltestrunner not installed")
def test_qml_suite():
    assert RUNNER, "REQUIRE_QML_TESTS=1 but no Qt 6 qmltestrunner was found"
    _run(QML_TESTS, dict(os.environ))


def _run(qml_input, env):
    os.makedirs(SCREENS, exist_ok=True)
    # org.kde.desktop renders controls in the Breeze style, so screenshots
    # look like the real widget.
    env["QT_QPA_PLATFORM"] = "offscreen"
    env.setdefault("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop")
    # Components that run the real helper (voice/SttBackend.qml syncs the
    # dictation units at start) must never touch the user's systemd units.
    env.setdefault("KDEAICHAT_UNIT_DIR", os.path.join(SCREENS, "..", "qml-units"))
    env.setdefault("KDEAICHAT_SYSTEMCTL", "true")
    result = subprocess.run(
        [RUNNER, "-platform", "offscreen", "-input", qml_input],
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
    return output


def _color_scheme(name):
    path = os.path.join("/usr/share/color-schemes", name + ".colors")
    return path if os.path.exists(path) else None


def _kde_platform_theme():
    for base in ("/usr/lib/qt6/plugins", "/usr/lib64/qt6/plugins", "/usr/lib/x86_64-linux-gnu/qt6/plugins"):
        if glob.glob(os.path.join(base, "platformthemes", "KDEPlasmaPlatformTheme6*")):
            return True
    return False


@pytest.mark.skipif(RUNNER is None and not REQUIRED, reason="Qt 6 qmltestrunner not installed")
@pytest.mark.parametrize("scheme,theme,icons", [
    ("BreezeLight", "light", "breeze"),
    ("BreezeDark", "dark", "breeze-dark"),
])
def test_qml_mockups(scheme, theme, icons):
    """Screenshots of each chat state under a real Plasma colour scheme.

    KDE's platform theme reads the scheme from a temporary kdeglobals, as in
    a Plasma session, so Kirigami.Theme and the Breeze controls get their
    colours the same way they do on the desktop. Nothing in the test sets a
    colour. The mockup names each shot after the scheme it actually saw, so
    a fresh mockup-*-<theme>.png proves the scheme took effect.
    """
    assert RUNNER, "REQUIRE_QML_TESTS=1 but no Qt 6 qmltestrunner was found"
    colors = _color_scheme(scheme)
    if not colors or not _kde_platform_theme():
        if REQUIRED:
            pytest.fail("Breeze colour schemes or KDE's Qt platform theme are not installed")
        pytest.skip("Breeze colour schemes or KDE's Qt platform theme are not installed")
    with tempfile.TemporaryDirectory() as home:
        config = os.path.join(home, "config")
        os.makedirs(config)
        with open(colors, encoding="utf-8") as src, open(os.path.join(config, "kdeglobals"), "w", encoding="utf-8") as dst:
            dst.write(src.read())
            dst.write("\n[Icons]\nTheme=%s\n" % icons)
        env = dict(os.environ, QT_QPA_PLATFORMTHEME="kde", XDG_CONFIG_HOME=config,
                   XDG_CACHE_HOME=os.path.join(home, "cache"))
        started = time.time()
        output = _run(os.path.join(QML_TESTS, "mockups.qml"), env)
    assert "MOCKUP theme " + theme in output, output
    shots = glob.glob(os.path.join(SCREENS, "mockup-*-%s.png" % theme))
    fresh = [p for p in shots if os.path.getmtime(p) >= started - 1]
    assert len(fresh) >= 9, (shots, output)
