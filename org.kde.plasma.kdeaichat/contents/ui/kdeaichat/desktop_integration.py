"""Desktop integration (Settings -> Desktop integration): KRunner, the Dolphin menu and the selection shortcut.

Both live outside the widget's package, so they are installed only while their switch is on, and removed
when it is switched off:

  desktop_sync    {krunner, dolphin, selection, prefix, restart_krunner} -> {"type": "desktop_status", ...}
  desktop_status  {} -> {"type": "desktop_status", "krunner": bool, "dolphin": bool, "selection": bool, "prefix": str}

KRunner: ``krunner/dbusplugins/kdeaichat-runner.desktop`` (describes the D-Bus runner) and
``dbus-1/services/org.kde.kdeaichat.runner.service`` (lets D-Bus start scripts/kdeaichat-runner on demand).
Dolphin: ``kio/servicemenus/kdeaichat-ask.desktop`` (KDE 6 format, executable) running scripts/kdeaichat-ask.
Selection shortcut: ``applications/kdeaichat-ask-selection.desktop``, an ordinary application entry that runs
``scripts/kdeaichat-ask --selection`` and carries ``X-KDE-Shortcuts=Meta+Alt+A``: Plasma's global-shortcut
service (kglobalacceld) takes the default shortcut from that key, and the user changes it in System Settings
-> Keyboard -> Shortcuts (the entry is listed there under "Ask KDE AI Chat about the selected text"; if it is
not, "Add Application..." there finds it). Our file never contains the user's choice, so re-installing
cannot reset it.
All four are under ``$XDG_DATA_HOME`` (default ~/.local/share), so nothing needs root. Every file carries
the marker ``X-KDEAIChat-Managed=true`` (or ``# X-KDEAIChat-Managed``): only files with it are ever
replaced or deleted, so a file of the same name that is someone else's is left alone. Writes are atomic.
These files are outside the package, so removing the widget does not remove them: the settings page asks
to switch the options off first (a dead KRunner/Dolphin entry otherwise points at a script that is gone).
Every start of the widget re-runs the sync, so a moved or updated widget repairs them.
The runner's prefix (default "ai") and the switches are kept in ``<data>/kdeaichat/desktop-integration.json``,
which the runner reads. Folders can be replaced for tests and dev runs: KDEAICHAT_KRUNNER_DIR,
KDEAICHAT_DBUS_SERVICE_DIR, KDEAICHAT_SERVICEMENU_DIR, KDEAICHAT_APPLICATIONS_DIR, KDEAICHAT_DESKTOP_STATE.
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Any, Dict, List

from kdeaichat import common

SERVICE_NAME = "org.kde.kdeaichat.runner"
RUNNER_FILE = "kdeaichat-runner.desktop"
SERVICE_FILE = SERVICE_NAME + ".service"
MENU_FILE = "kdeaichat-ask.desktop"
SELECTION_FILE = "kdeaichat-ask-selection.desktop"
DEFAULT_SHORTCUT = "Meta+Alt+A"  # not used by Plasma, KWin or Spectacle by default (Spectacle has Meta+Alt+R)
MARKER = "X-KDEAIChat-Managed=true"
# Documents and pictures the widget's attachment code (doc_extractor.py) reads.
MIME_TYPES = ["text/plain", "text/markdown", "text/csv", "application/pdf", "application/json", "text/x-python",
              "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "image/png",
              "image/jpeg", "image/webp", "image/gif", "image/bmp"]
DEFAULT_PREFIX = "ai"


def _data_home() -> str:
    return os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")


def folders() -> Dict[str, str]:
    base = _data_home()
    return {
        "krunner": os.environ.get("KDEAICHAT_KRUNNER_DIR") or os.path.join(base, "krunner", "dbusplugins"),
        "service": os.environ.get("KDEAICHAT_DBUS_SERVICE_DIR") or os.path.join(base, "dbus-1", "services"),
        "menu": os.environ.get("KDEAICHAT_SERVICEMENU_DIR") or os.path.join(base, "kio", "servicemenus"),
        "applications": os.environ.get("KDEAICHAT_APPLICATIONS_DIR") or os.path.join(base, "applications"),
        "state": os.environ.get("KDEAICHAT_DESKTOP_STATE") or os.path.join(base, "kdeaichat", "desktop-integration.json"),
    }


def _scripts_dir() -> str:
    return os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "scripts")


def _quote(arg: str, desktop: bool = True) -> str:
    """One argument of an Exec= line (desktop entry, or D-Bus service file): quoted when it needs it.

    Desktop-entry spec: inside double quotes a backslash, ", ` and $ get a backslash, and as the value of a
    desktop file every backslash is doubled once more (so a backslash becomes four, a quote becomes \\\\").
    A D-Bus service file has no second level. Control characters (a newline would end the line) are refused."""
    if any(ord(c) < 32 or ord(c) == 127 for c in arg):
        raise ValueError("a path with control characters cannot be used in a launcher: %r" % arg)
    if arg and not any(c in arg for c in ' \t"\'\\><~|&;$*?#()`%'):
        return arg
    out = arg.replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`").replace("$", "\\$")
    if desktop:
        out = out.replace("\\", "\\\\").replace("%", "%%")
    return '"' + out + '"'


def _python() -> str:
    return sys.executable if os.path.isabs(sys.executable or "") else (shutil.which("python3") or "/usr/bin/python3")


def runner_desktop() -> str:
    return "\n".join([
        "[Desktop Entry]", "Type=Service", "Name=KDE AI Chat", "Comment=Ask KDE AI Chat a question: type \"ai\" and your question",
        "Icon=dialog-messages", "X-KDE-ServiceTypes=Plasma/Runner", "X-Plasma-API=DBus",
        "X-Plasma-DBusRunner-Service=" + SERVICE_NAME, "X-Plasma-DBusRunner-Path=/runner",
        "X-KDE-PluginInfo-Name=kdeaichat", "X-KDE-PluginInfo-Version=1.0", "X-KDE-PluginInfo-License=PolyForm-Noncommercial-1.0.0",
        # Without this KRunner (KF6) treats the runner as switched off.
        "X-KDE-PluginInfo-EnabledByDefault=true", MARKER, ""])


def runner_service() -> str:
    runner = os.path.join(_scripts_dir(), "kdeaichat-runner")
    return "\n".join(["[D-BUS Service]", "Name=" + SERVICE_NAME,
                      "Exec=" + _quote(_python(), False) + " " + _quote(runner, False), "# " + MARKER, ""])


def menu_desktop() -> str:
    ask = os.path.join(_scripts_dir(), "kdeaichat-ask")
    return "\n".join([
        "[Desktop Entry]", "Type=Service", "MimeType=" + ";".join(MIME_TYPES) + ";", "Actions=askKdeAiChat",
        "X-KDE-Priority=TopLevel", "X-KDE-StartupNotify=false", MARKER, "",
        "[Desktop Action askKdeAiChat]", "Name=Ask KDE AI Chat about this file", "Icon=dialog-messages",
        "Exec=" + _quote(_python()) + " " + _quote(ask) + " --files %F", ""])


def selection_desktop() -> str:
    ask = os.path.join(_scripts_dir(), "kdeaichat-ask")
    return "\n".join([
        "[Desktop Entry]", "Type=Application", "Name=Ask KDE AI Chat about the selected text",
        "Comment=Quote the text selected in any app in KDE AI Chat", "Icon=dialog-messages",
        "Exec=" + _quote(_python()) + " " + _quote(ask) + " --selection", "Terminal=false", "StartupNotify=false",
        "Categories=Utility;", "OnlyShowIn=KDE;", "X-KDE-Shortcuts=" + DEFAULT_SHORTCUT, MARKER, ""])


def _ours(path: str) -> bool:
    try:
        with open(path, encoding="utf-8") as f:
            return MARKER in f.read(65536)
    except OSError:
        return False


def _install(path: str, content: str, mode: int) -> bool:
    """Atomically writes a file of ours; refuses to replace one that isn't. True when it changed."""
    if os.path.lexists(path) and not _ours(path):
        raise ValueError("%s already exists and is not from KDE AI Chat" % path)
    try:
        with open(path, encoding="utf-8") as f:
            if f.read() == content and stat.S_IMODE(os.stat(path).st_mode) == mode:
                return False
    except OSError:
        pass
    folder = os.path.dirname(path)
    os.makedirs(folder, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".kdeaichat-", dir=folder)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
        return True
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _remove(path: str) -> None:
    if os.path.lexists(path) and _ours(path):
        os.unlink(path)


def _files(kind: str) -> List[str]:
    f = folders()
    if kind == "krunner":
        return [os.path.join(f["krunner"], RUNNER_FILE), os.path.join(f["service"], SERVICE_FILE)]
    if kind == "selection":
        return [os.path.join(f["applications"], SELECTION_FILE)]
    return [os.path.join(f["menu"], MENU_FILE)]


def is_installed(kind: str) -> bool:
    return all(_ours(p) for p in _files(kind))


def clean_prefix(value: Any) -> str:
    value = value.strip() if isinstance(value, str) else ""
    return value if value and len(value) <= 24 and not any(c.isspace() or c in "\"'\\" for c in value) else DEFAULT_PREFIX


def _write_state(krunner: bool, dolphin: bool, selection: bool, prefix: str) -> None:
    path = folders()["state"]
    data = json.dumps({"krunner": krunner, "dolphin": dolphin, "selection": selection, "prefix": prefix})
    common.atomic_write_text(path, data, 0o600)  # removes its temp file when the write fails


def _run_tool(args: List[str]) -> None:
    """Runs a desktop tool, best effort. Not when the files go to other folders (tests, dev runs)."""
    if os.environ.get("KDEAICHAT_KRUNNER_DIR") or not shutil.which(args[0]):
        return
    try:
        subprocess.run(args, capture_output=True, timeout=10, check=False)
    except (OSError, subprocess.SubprocessError):
        pass


def _reload_bus() -> None:
    """dbus-broker only sees a new or removed .service file after ReloadConfig; without it the
    runner's name "is not activatable" and KRunner gets no answer."""
    _run_tool(["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
               "org.freedesktop.DBus", "ReloadConfig"])


def _restart_krunner() -> None:
    """So KRunner notices the runner at once (it keeps running between uses)."""
    _run_tool(["kquitapp6", "krunner"])


def sync(krunner: bool, dolphin: bool, prefix: str = DEFAULT_PREFIX, restart_krunner: bool = False,
         selection: bool = False) -> Dict[str, Any]:
    """Makes the files match the switches. Returns the status, with "errors" (plain words) for what failed."""
    prefix = clean_prefix(prefix)
    errors: List[str] = []
    was = is_installed("krunner")
    f = folders()
    runner_changed = False
    try:
        if krunner:
            runner_changed = _install(os.path.join(f["krunner"], RUNNER_FILE), runner_desktop(), 0o644)
            runner_changed = _install(os.path.join(f["service"], SERVICE_FILE), runner_service(), 0o644) or runner_changed
        else:
            for p in _files("krunner"):
                _remove(p)
    except (OSError, ValueError) as error:
        errors.append("KRunner: %s" % error)
    try:
        if dolphin:
            _install(os.path.join(f["menu"], MENU_FILE), menu_desktop(), 0o755)  # Dolphin needs the executable bit
        else:
            _remove(os.path.join(f["menu"], MENU_FILE))
    except (OSError, ValueError) as error:
        errors.append("Dolphin: %s" % error)
    try:
        if selection:
            _install(os.path.join(f["applications"], SELECTION_FILE), selection_desktop(), 0o755)
        else:
            _remove(os.path.join(f["applications"], SELECTION_FILE))
    except (OSError, ValueError) as error:
        errors.append("Shortcut: %s" % error)
    try:
        if krunner or dolphin or selection or os.path.exists(f["state"]):
            _write_state(krunner and is_installed("krunner"), dolphin and is_installed("dolphin"),
                         selection and is_installed("selection"), prefix)
    except OSError as error:
        errors.append("settings file: %s" % error)
    if runner_changed or was != is_installed("krunner"):
        _reload_bus()
        # A changed runner file (an update) needs a KRunner restart too, even at start-up.
        if runner_changed or restart_krunner:
            _restart_krunner()
    return status(prefix, errors)


def status(prefix: str = "", errors: Any = None) -> Dict[str, Any]:
    if not prefix:
        try:
            with open(folders()["state"], encoding="utf-8") as fh:
                prefix = json.load(fh).get("prefix", DEFAULT_PREFIX)
        except (OSError, ValueError, AttributeError):
            prefix = DEFAULT_PREFIX
    return {"type": "desktop_status", "krunner": is_installed("krunner"), "dolphin": is_installed("dolphin"),
            "selection": is_installed("selection"), "prefix": clean_prefix(prefix), "errors": list(errors or [])}


def cmd_desktop_sync(payload: Dict[str, Any]) -> None:
    print(json.dumps(sync(payload.get("krunner") is True, payload.get("dolphin") is True, payload.get("prefix", DEFAULT_PREFIX),
                          payload.get("restart_krunner") is True, payload.get("selection") is True)), flush=True)


def cmd_desktop_status(payload: Dict[str, Any]) -> None:
    print(json.dumps(status()), flush=True)


COMMANDS = {"desktop_sync": cmd_desktop_sync, "desktop_status": cmd_desktop_status}
