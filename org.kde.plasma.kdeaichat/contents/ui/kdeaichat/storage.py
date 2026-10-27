"""What the widget keeps on disk, how much, and removing what is safe to remove (Settings -> Storage).

  storage_usage   {} -> {"type": "storage_usage", "root", "items": [{id, size, folder, exists, removable}],
                      "total", "partial", "speech_note": {"folder", "exists"}}
  storage_remove  {item, confirm: true} -> {"type": "storage_removed", item, freed, warnings}
                    | {"type": "storage_error", error}

Items (``ITEMS``): chats, pictures, memories, schedules, backups, caches, voice_old (the venvs, models and
units of the old built-in voice engines) and other (everything else in the data folder). Sizes are disk
space (allocated blocks), counted without following symlinks, with a time cap (``partial`` when it ran out).

Only ``REMOVABLE`` items can be removed (backups, caches, voice_old): never chats, pictures, memories or
schedules (those have their own controls). Everything removed is a fixed path of the widget's own: the data
folder (``~/.local/share/kdeaichat``, XDG_DATA_HOME aware) and the widget's temporary folders. Speech Note's
models, Handy's and the HuggingFace cache are Speech Note's and other apps': the Speech Note folder is only
reported (never counted, never removed), and a HuggingFace model is touched only when the widget downloaded
it itself (recorded by voice_data).
"""
import glob
import json
import os
import shutil
import stat
import time
from typing import Any, Callable, Dict, List, Optional, Tuple

from kdeaichat import chats

ITEMS = ("chats", "pictures", "memories", "schedules", "backups", "caches", "voice_old", "other")
REMOVABLE = ("backups", "caches", "voice_old")
TIME_CAP = 8.0  # seconds for the whole measuring

# Root-level names of the data folder that belong to an item (anything else is "other").
_MEMORY_FILES = ("memory.json", "memory.json.lock")
_VOICE_NAMES = ("venv", "tts-venv", "tts-models", "models", "stt-downloads.json")


def _emit(data: Dict[str, Any]) -> None:
    print(json.dumps(data), flush=True)


def _blocks(st: os.stat_result) -> int:
    return st.st_blocks * 512 if hasattr(st, "st_blocks") else st.st_size


class _Meter:
    """Adds up disk use under paths, without following symlinks, until the time cap."""

    def __init__(self, cap: float = TIME_CAP, now: Callable[[], float] = time.monotonic) -> None:
        self.now = now
        self.deadline = now() + cap
        self.partial = False
        self._links = set()

    def _count(self, st: os.stat_result) -> int:
        if st.st_nlink > 1 and not stat.S_ISDIR(st.st_mode):  # a hard link is counted once
            key = (st.st_dev, st.st_ino)
            if key in self._links:
                return 0
            self._links.add(key)
        return _blocks(st)

    def size(self, path: str, skip: Optional[Callable[[str, int], bool]] = None) -> int:
        try:
            st = os.lstat(path)
        except OSError:
            return 0
        total = self._count(st)
        if not stat.S_ISDIR(st.st_mode):
            return total
        stack: List[Tuple[str, int]] = [(path, 0)]
        while stack:
            if self.now() > self.deadline:
                self.partial = True
                break
            folder, depth = stack.pop()
            try:
                with os.scandir(folder) as entries:
                    for entry in entries:
                        try:
                            es = entry.stat(follow_symlinks=False)
                        except OSError:
                            continue
                        if stat.S_ISDIR(es.st_mode):
                            if skip and skip(entry.path, depth + 1):
                                continue
                            total += self._count(es)
                            stack.append((entry.path, depth + 1))
                        else:
                            total += self._count(es)
            except OSError:
                continue
        return total


def data_root() -> str:
    return chats.data_root()


def _runtime_dir() -> str:
    base = os.environ.get("XDG_RUNTIME_DIR") or ""
    return base if base and os.path.isdir(base) else ""


def _cache_home() -> str:
    return os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")


def cache_specs() -> List[Tuple[str, str]]:
    """The widget's caches and temporary files as ("contents", folder) or ("file", path)."""
    root = data_root()
    specs = [("contents", os.path.join(root, "run")),
             ("contents", os.path.join(_cache_home(), "kdeaichat")),
             ("contents", os.path.expanduser("~/.cache/kdeaichat"))]
    runtime = _runtime_dir()
    if runtime:
        specs += [("contents", os.path.join(runtime, "kdeaichat")), ("contents", os.path.join(runtime, "kdeaichat-tts"))]
    specs += [("file", p) for p in sorted(glob.glob(os.path.join(root, "*.log")))]
    seen, unique = set(), []
    for kind, path in specs:
        if path not in seen:
            seen.add(path)
            unique.append((kind, path))
    return unique


def _is_images_dir(path: str, depth: int) -> bool:
    """chats/applet-<id>/images (depth 2 below the chats folder)."""
    return depth == 2 and os.path.basename(path) == "images"


def _own_models() -> List[str]:
    """HuggingFace model folders the widget's own voice installer downloaded (recorded by voice_data)."""
    try:
        from kdeaichat import voice_data
        found = []
        for name in sorted(voice_data.read_record()):
            folder = voice_data._model_folder(name)
            if os.path.isdir(folder) and not os.path.islink(folder):
                found.append(folder)
        return found
    except Exception:
        return []


def voice_paths() -> List[str]:
    root = data_root()
    paths = [os.path.join(root, name) for name in _VOICE_NAMES]
    return [p for p in paths if os.path.lexists(p)] + _own_models()


def speech_note_folder() -> Dict[str, Any]:
    """Speech Note's models folder: only reported, never counted or removed."""
    folders: List[str] = []
    try:
        from kdeaichat.stt_models import speech_note_dirs
        folders = [f for f in speech_note_dirs(os.path.expanduser("~")) if os.path.isdir(f)]
    except Exception:
        pass
    return {"folder": folders[0] if folders else "", "exists": bool(folders)}


def usage(meter: Optional[_Meter] = None) -> Dict[str, Any]:
    meter = meter or _Meter()
    root = data_root()
    chats_root = chats.chats_root()
    sizes: Dict[str, int] = {}
    sizes["pictures"] = sum(meter.size(p) for p in glob.glob(os.path.join(chats_root, "applet-*", "images"))
                            if os.path.isdir(p) and not os.path.islink(p))
    sizes["chats"] = meter.size(chats_root, skip=_is_images_dir)
    sizes["memories"] = sum(meter.size(os.path.join(root, n)) for n in _MEMORY_FILES)
    schedule_paths = sorted(glob.glob(os.path.join(root, "schedules*"))) + [os.path.join(root, "schedule-runs")]
    sizes["schedules"] = sum(meter.size(p) for p in schedule_paths)
    sizes["backups"] = meter.size(os.path.join(root, "backups"))
    caches = cache_specs()
    sizes["caches"] = sum(meter.size(p) for _, p in caches)
    voice = voice_paths()
    sizes["voice_old"] = sum(meter.size(p) for p in voice)
    known = {"chats", "backups", "run", "schedule-runs", *_MEMORY_FILES, *_VOICE_NAMES}
    other = 0
    try:
        for name in sorted(os.listdir(root)):
            path = os.path.join(root, name)
            if name in known or name.startswith("schedules") or name.endswith(".log"):
                continue
            other += meter.size(path)
    except OSError:
        pass
    sizes["other"] = other
    first_cache = next((p for k, p in caches if k == "contents" and os.path.isdir(p) and not os.path.islink(p)), root)
    folders = {"chats": chats_root, "pictures": chats_root, "memories": root, "schedules": root,
               "backups": os.path.join(root, "backups"), "caches": first_cache, "voice_old": root, "other": root}
    items = []
    for item in ITEMS:
        folder = folders[item]
        if not os.path.isdir(folder):
            folder = root
        items.append({"id": item, "size": sizes[item], "folder": folder if os.path.isdir(folder) else "",
                      "removable": item in REMOVABLE, "exists": sizes[item] > 0})
    return {"type": "storage_usage", "root": root, "root_exists": os.path.isdir(root), "items": items,
            "total": sum(sizes.values()), "partial": meter.partial, "speech_note": speech_note_folder()}


# --- removing -------------------------------------------------------------------------------------

def _remove_path(path: str) -> None:
    """Delete a file, a symlink (itself) or a folder tree; never follows a symlink; skips sockets."""
    try:
        st = os.lstat(path)
    except OSError:
        return
    if stat.S_ISDIR(st.st_mode):
        shutil.rmtree(path, ignore_errors=True)
    elif not (stat.S_ISSOCK(st.st_mode) or stat.S_ISFIFO(st.st_mode)):
        try:
            os.unlink(path)
        except OSError:
            pass


def _clear_contents(folder: str) -> None:
    try:
        if os.path.islink(folder) or not os.path.isdir(folder):
            return
        names = os.listdir(folder)
    except OSError:
        return
    for name in names:
        _remove_path(os.path.join(folder, name))


def _inside(path: str, base: str) -> bool:
    real, real_base = os.path.realpath(os.path.dirname(path)), os.path.realpath(base)
    return real == real_base or real.startswith(real_base + os.sep)


def _remove_backups() -> None:
    folder = os.path.join(data_root(), "backups")
    if _inside(folder, data_root()):
        _clear_contents(folder)


def _remove_caches() -> None:
    for kind, path in cache_specs():
        if kind == "file":
            if _inside(path, data_root()) and os.path.isfile(path) and not os.path.islink(path):
                _remove_path(path)
        else:
            _clear_contents(path)


def _remove_voice(warnings: List[str]) -> None:
    """Old voice engines: stop and remove their units and services, then their own folders only."""
    steps = []
    try:
        from kdeaichat import stt_units
        steps.append(("dictation units", lambda: stt_units.sync({"sttEnabled": False})))
    except Exception as e:
        warnings.append("dictation units: %s" % e)
    try:
        from kdeaichat import voice_legacy
        steps.append(("old read-aloud unit", voice_legacy.cleanup_legacy_tts))
    except Exception as e:
        warnings.append("old read-aloud unit: %s" % e)
    try:
        from kdeaichat import tts, tts_worker
        steps.append(("read-aloud service", lambda: tts_worker.stop(tts.out_dir())))
    except Exception as e:
        warnings.append("read-aloud service: %s" % e)
    for label, step in steps:
        try:
            step()
        except Exception as e:  # keep going: the folders below are removed anyway
            warnings.append("%s: %s" % (label, e))
    root = data_root()
    models = _own_models()
    for path in voice_paths():
        if path in models:
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path, ignore_errors=True)
        elif os.path.dirname(path) == root:  # a fixed child of the data folder, never a link target
            _remove_path(path)


def remove(item: str) -> Dict[str, Any]:
    if item not in REMOVABLE:
        raise ValueError("this can't be removed here")
    before = usage()
    size_before = next(i["size"] for i in before["items"] if i["id"] == item)
    warnings: List[str] = []
    if item == "backups":
        _remove_backups()
    elif item == "caches":
        _remove_caches()
    else:
        _remove_voice(warnings)
    after = usage()
    size_after = next(i["size"] for i in after["items"] if i["id"] == item)
    return {"type": "storage_removed", "item": item, "freed": max(0, size_before - size_after),
            "warnings": warnings}


def cmd_storage_usage(payload: Dict[str, Any]) -> None:
    _emit(usage())


def cmd_storage_remove(payload: Dict[str, Any]) -> None:
    item = payload.get("item")
    if not isinstance(item, str) or item not in REMOVABLE:
        _emit({"type": "storage_error", "error": "this can't be removed here"})
        return
    if payload.get("confirm") is not True:
        _emit({"type": "storage_error", "error": "removal needs confirm: true"})
        return
    try:
        _emit(remove(item))
    except (OSError, ValueError) as e:
        _emit({"type": "storage_error", "error": str(e)})


COMMANDS = {"storage_usage": cmd_storage_usage, "storage_remove": cmd_storage_remove}
