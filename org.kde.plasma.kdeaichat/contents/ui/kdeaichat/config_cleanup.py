"""``cleanup_old_settings``: remove settings 1.4.0 no longer uses from the applet config.

Older versions left many settings in the widget's group of Plasma's applet
config (``[Containments][N][Applets][<id>][Configuration][General]`` in
``plasma-org.kde.plasma.desktop-appletsrc``). Plasma never removes a key
that main.xml stops declaring, and ``plasmoid.configuration`` can't remove
one either (it only reverts declared keys to their default), so the widget
asks the helper once per start.

What is removed, from this widget's own group only:
- ``DROPPED``: keys older versions declared and 1.4.0 doesn't (nothing reads
  them any more), always.
- migration-only keys, only once their migration is done, judged from the
  same group: the old plaintext API keys and ``userMemory`` when empty (the
  migrations clear them only after a verified move); ``enableMemory`` once
  ``userMemory`` is empty; the old dictation keys once ``sttSettingsMigrated``
  is true; ``chatSessionsJson`` when it is empty.

Safety: the file is read and rewritten under KConfig's own lock file
(``<file>.lock``, QLockFile format) so plasmashell can't write in between;
only whole lines of those keys inside that one group are dropped, every
other byte stays; the old file is copied to
``~/.local/share/kdeaichat/backups/appletsrc-<date>`` first (0600, the last
five kept); the new one replaces it atomically with the same mode. Nothing
is written when there is nothing to remove, so running it again is a no-op.
Plasma only writes keys it changed, so a removed key stays removed.
"""
import datetime as dt
import glob
import json
import os
import re
import socket
import tempfile
import time
from typing import Any, Dict, List, Optional, Tuple

from kdeaichat import applet_config, chats

# Declared by older versions (git history of contents/config/main.xml), not by 1.4.0.
DROPPED = frozenset("""
appearanceMode askClearChatConfirmation askDeleteChatConfirmation autoRestartPlasmaShell autoStartOpenCodeServer
compactContextAfter customHistoryPath desktopSelectionEnabled enableCompactingContext enableMcpTools
enablePerformanceEnhancements executeMissedSchedules gatheredSysInfo globalContextAutoCompact
globalContextCompactThreshold globalContextEnabled globalContextLimit googleImageBaseUrl googleImageModel
huggingfaceImageBaseUrl huggingfaceImageModel keyClearInput keyCopyLastReply keyFocusInput keyNewChat keyNextSession
keyPrevSession keyRefresh keySettings keyStorageMode keyToggleHistory keyToggleSearch keyToggleSearchSidebar
kwalletAutoPrompt kwalletName language mcpServersJson mimoBaseUrl mimoModel moonshotBaseUrl moonshotModel
notificationsShowContent openaiImageModel openCodeAutoKill openCodeAutoKillMinutes openCodeStartCommand
openCodeStopCommand pollinationsBaseUrl pollinationsModel preselectedChatId preselectedChatName qwenBaseUrl qwenModel
replicateImageBaseUrl replicateImageModel responseLength schedulerAutoStart schedulerEnabled schedulerHistoryLimit
showInteractiveGuides stabilityImageBaseUrl stabilityImageModel sysInfoCPU sysInfoDateTime sysInfoDesktop sysInfoDisk
sysInfoGPU sysInfoHostname sysInfoKernel sysInfoLocale sysInfoMemory sysInfoNetwork sysInfoOS sysInfoShell
sysInfoUser togetherImageBaseUrl togetherImageModel uiLanguage useKWallet voiceCallEnabled voiceEspeakPath
voiceTtsModel voiceTtsModelPath voiceTtsVoice voiceVenvPath
""".split())

# The plaintext key settings store/Migration.qml moves into KWallet (must match privacy.LEGACY_KEY_PROVIDERS).
OLD_KEYS = frozenset("""
apiKey anthropicApiKey groqApiKey deepSeekApiKey miniMaxApiKey fireworksApiKey googleApiKey openRouterApiKey
mistralApiKey cloudflareApiKey nvidiaApiKey huggingFaceApiKey xaiApiKey litellmApiKey maritacaApiKey perplexityApiKey
qwenApiKey moonshotApiKey mimoApiKey huggingfaceImageApiKey replicateApiKey stabilityApiKey togetherImageApiKey
""".split())

# Copied once into the stt* settings by voice/SttConfig.js, which then sets sttSettingsMigrated.
OLD_DICTATION = frozenset(("voiceEnabled", "voiceGpuEnabled", "voiceSttModel", "voiceSttModelPath", "voiceLanguage"))

KEEP_BACKUPS = 5
LOCK_WAIT = 3.0
_KEY = re.compile(r"^\s*([^=\[\s]+)\s*(\[\$[a-z]+\])*\s*=")


def removable(values: Dict[str, str]) -> List[str]:
    """The keys of one [Configuration][General] group (key -> raw value) that can go."""
    out = {k for k in values if k in DROPPED}
    out |= {k for k in values if k in OLD_KEYS and values[k].strip() == ""}
    memory_done = values.get("userMemory", "").strip() == ""
    if memory_done:
        out |= {k for k in ("userMemory", "enableMemory") if k in values}
    if values.get("sttSettingsMigrated", "").strip().lower() == "true":
        out |= {k for k in values if k in OLD_DICTATION}
    if values.get("chatSessionsJson", "x").strip() in ("", "[]"):
        out.add("chatSessionsJson")
    return sorted(out)


def find_group(lines: List[str], applet_id: str) -> Optional[str]:
    """The name of this applet's [Configuration][General] group, if its plugin is ours."""
    suffix = f"[Applets][{applet_id}]"
    current, plugin_of = None, {}
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current = stripped
            continue
        if current and current.endswith(suffix) and stripped.startswith("plugin="):
            plugin_of[current] = stripped[len("plugin="):]
    for group, plugin in plugin_of.items():
        if plugin.startswith(applet_config.PLUGIN_PREFIX):
            return group + "[Configuration][General]"
    return None


def plan(text: str, applet_id: str) -> Tuple[Optional[str], List[str], str]:
    """(group, keys removed, new text) for the config file's ``text``."""
    lines = text.splitlines(keepends=True)
    group = find_group(lines, applet_id)
    if not group:
        return None, [], text
    values: Dict[str, str] = {}
    current = None
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current = stripped
        elif current == group:
            match = _KEY.match(line)
            if match:
                values[match.group(1)] = line.split("=", 1)[1].rstrip("\r\n")
    remove = set(removable(values))
    if not remove:
        return group, [], text
    kept, current = [], None
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current = stripped
        elif current == group:
            match = _KEY.match(line)
            if match and match.group(1) in remove:
                continue
        kept.append(line)
    return group, sorted(remove), "".join(kept)


def config_file(applet_id: str) -> Optional[str]:
    """The first applet config file that has this applet with our plugin (as applet_config reads it)."""
    for path in applet_config.candidate_files():
        try:
            if os.path.getsize(path) > applet_config.MAX_CONFIG_BYTES:
                continue
            with open(path, encoding="utf-8", errors="surrogateescape") as f:
                if find_group(f.read().splitlines(), applet_id):
                    return path
        except OSError:
            continue
    return None


def _stale(lock: str) -> bool:
    """A lock left by a process of this host that no longer runs (QLockFile's rule); removed if so."""
    try:
        with open(lock, encoding="utf-8", errors="replace") as f:
            fields = f.read().splitlines()
        pid = int(fields[0]) if fields and fields[0].strip().isdigit() else 0
        host = fields[2].strip() if len(fields) > 2 else ""
        if pid <= 0 or (host and host != socket.gethostname()) or os.path.exists(f"/proc/{pid}"):
            return False
        os.unlink(lock)
        return True
    except OSError:
        return False


def _lock(path: str) -> Optional[str]:
    """Take KConfig's lock file (QLockFile: pid, app name, host name); None if busy."""
    lock = path + ".lock"
    deadline = time.monotonic() + LOCK_WAIT
    while True:
        try:
            fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        except FileExistsError:
            if _stale(lock):
                continue
            if time.monotonic() > deadline:
                return None
            time.sleep(0.1)
            continue
        with os.fdopen(fd, "w") as f:
            f.write(f"{os.getpid()}\nkdeaichat-helper\n{socket.gethostname()}\n")
        return lock


def backup(path: str, now: dt.datetime) -> str:
    folder = os.path.join(chats.data_root(), "backups")
    os.makedirs(folder, mode=0o700, exist_ok=True)
    os.chmod(folder, 0o700)
    target = os.path.join(folder, f"appletsrc-{now:%Y%m%d-%H%M%S}")
    n = 1
    while os.path.exists(target):
        n += 1
        target = os.path.join(folder, f"appletsrc-{now:%Y%m%d-%H%M%S}-{n}")
    with open(path, "rb") as src:
        data = src.read()
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as out:
        out.write(data)
    for old in sorted(glob.glob(os.path.join(folder, "appletsrc-*")))[:-KEEP_BACKUPS]:
        os.unlink(old)
    return target


def _replace(path: str, text: str) -> None:
    mode = os.stat(path).st_mode & 0o7777
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".kdeaichat-cleanup-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def cleanup(applet_id: str, path: Optional[str] = None, now: Optional[dt.datetime] = None) -> Dict[str, Any]:
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", applet_id or ""):
        return {"status": "error", "message": "bad applet id"}
    path = path or config_file(applet_id)
    if not path:
        return {"status": "not-found"}
    lock = _lock(path)
    if not lock:
        return {"status": "busy", "file": path}
    try:
        with open(path, encoding="utf-8", errors="surrogateescape", newline="") as f:
            text = f.read()
        group, removed, new_text = plan(text, applet_id)
        if not group:
            return {"status": "not-found", "file": path}
        if not removed:
            return {"status": "clean", "file": path, "removed": []}
        saved = backup(path, now or dt.datetime.now())
        _replace(path, new_text)
        return {"status": "removed", "file": path, "removed": removed, "backup": saved}
    finally:
        os.unlink(lock)


def cmd_cleanup_old_settings(payload: Dict[str, Any]) -> None:
    print(json.dumps(cleanup(str(payload.get("appletId") or ""))))


COMMANDS = {"cleanup_old_settings": cmd_cleanup_old_settings}
