#!/usr/bin/env python3
"""kde_ai_helper — IPC helper invoked by the plasmoid via QProcess.

Each ``cmd_*`` function implements one RPC command. The QML side
sends ``<command> <base64-payload>`` and reads the result on stdout.

This module intentionally has zero third-party dependencies (stdlib
only) so it can run inside the plasmoid install without an extra
virtualenv.
"""
import sys
import os
import json
import base64
import shutil
import subprocess
import shlex
import fcntl
import re
import secrets
import tempfile
import time
import signal
from contextlib import contextmanager
from typing import Any, Callable, Dict, List

from kdeaichat import chats, opencode_server, pi_bridge, pi_models, privacy


_MAX_FILE_BYTES = 50 * 1024 * 1024
_MAX_SCHEDULE_STORE_BYTES = 5 * 1024 * 1024
_MAX_CONFIG_BYTES = 5 * 1024 * 1024


def _as_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "on")
    return default


def _safe_path(value: Any, *, allow_empty: bool = False) -> str:
    """Return a normalized absolute user path or raise ``ValueError``.

    The QML side validates paths before putting them into an IPC command, but
    this helper is also callable directly and is the last trust boundary for
    filesystem operations.  Spaces and normal Unicode filenames are allowed;
    control characters and traversal components are not.
    """
    if value is None:
        if allow_empty:
            return ""
        raise ValueError("path is required")
    raw = str(value)
    if raw == "":
        if allow_empty:
            return ""
        raise ValueError("path is required")
    if len(raw) > 4096 or any(ch in raw for ch in ("\x00", "\n", "\r")):
        raise ValueError("invalid path")
    expanded = os.path.expanduser(raw)
    if not os.path.isabs(expanded):
        raise ValueError("path must be absolute")
    if any(part == ".." for part in expanded.split(os.sep)):
        raise ValueError("path traversal is not allowed")
    normalized = os.path.normpath(expanded)
    if any(part == ".." for part in normalized.split(os.sep)):
        raise ValueError("path traversal is not allowed")
    return normalized


def _atomic_write_text(path: str, content: str, mode: int = 0o600) -> None:
    """Atomically write a private text file and preserve its permissions."""
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", dir=folder or None)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
        os.chmod(path, mode)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _atomic_write_json(path: str, data: Any) -> None:
    _atomic_write_text(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def _voice_token_path() -> str:
    return os.path.expanduser("~/.local/share/kdeaichat/voice-http-token")


def ensure_voice_http_token(path: str = "") -> str:
    """Create/read the per-user token used by the local voice HTTP daemons."""
    token_path = _safe_path(path or _voice_token_path())
    folder = os.path.dirname(token_path)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    try: os.chmod(folder, 0o700)
    except OSError: pass
    lock_path = token_path + ".lock"
    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.chmod(lock_path, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        try:
            with open(token_path, "r", encoding="ascii") as f:
                token = f.read().strip()
            if len(token) >= 32 and re.fullmatch(r"[A-Za-z0-9_-]+", token):
                os.chmod(token_path, 0o600)
                return token
        except (OSError, UnicodeError):
            pass

        token = secrets.token_urlsafe(32)
        fd, temporary = tempfile.mkstemp(prefix="." + os.path.basename(token_path) + ".", dir=folder)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="ascii") as f:
                f.write(token + "\n")
                f.flush()
                os.fsync(f.fileno())
            os.replace(temporary, token_path)
            os.chmod(token_path, 0o600)
        except Exception:
            try: os.close(fd)
            except OSError: pass
            try: os.unlink(temporary)
            except OSError: pass
            raise
        return token
    finally:
        try: fcntl.flock(lock_fd, fcntl.LOCK_UN)
        finally: os.close(lock_fd)


def _systemd_quote(value: str) -> str:
    """Quote one systemd unit value without allowing unit-file injection."""
    text = str(value)
    if not text or len(text) > 4096 or any(ord(ch) < 0x20 or ch == "\x7f" for ch in text):
        raise ValueError("unsafe path for systemd service")
    # systemd accepts C-style escapes in quoted values. Escape all syntax
    # characters instead of rejecting valid paths containing spaces or parens.
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%") + '"'


@contextmanager
def _schedule_store_lock():
    """Serialize helper mutations with the background scheduler daemon."""
    lock_path = _schedules_path() + ".lock"
    folder = os.path.dirname(lock_path)
    if folder:
        os.makedirs(folder, mode=0o700, exist_ok=True)
        try: os.chmod(folder, 0o700)
        except OSError: pass
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _schedules_path() -> str:
    return os.path.join(chats.data_root(), 'schedules.json')


def _pending_dir() -> str:
    return os.path.join(chats.data_root(), 'pending')


def _results_dir() -> str:
    return os.path.join(chats.data_root(), 'results')


def _load_schedules() -> Dict[str, Any]:
    """Load the schedule store, tolerating legacy list-formatted files.

    Returns a dict with at least ``"version"`` and ``"schedules"`` keys.
    On missing file, returns an empty default. On parse failure, returns
    the empty default as well (the caller's write will overwrite).
    """
    sp = _schedules_path()
    if os.path.exists(sp):
        try:
            if os.path.getsize(sp) > _MAX_SCHEDULE_STORE_BYTES:
                raise ValueError("schedule store is too large")
            with open(sp) as f:
                data: Any = json.load(f)
        except ValueError:
            raise
        except Exception:
            data = None
    else:
        data = None
    if isinstance(data, list):
        return {"version": 1, "schedules": data}
    if isinstance(data, dict):
        schedules = data.get("schedules", [])
        history = data.get("history", [])
        data["schedules"] = schedules if isinstance(schedules, list) else []
        data["history"] = history if isinstance(history, list) else []
        return data
    return {"version": 1, "schedules": []}


def cmd_toggle_schedule(payload: Dict[str, Any]) -> None:
    """Enable/disable a schedule by id, clearing ``nextRunAt`` on enable."""
    with _schedule_store_lock():
        data = _load_schedules()
        sched_id = str(payload.get("schedId", ""))
        enabled = _as_bool(payload.get("enabled", False), False)
        for s in data.get("schedules", []):
            if isinstance(s, dict) and s.get("id") == sched_id:
                s["enabled"] = enabled
                if enabled:
                    s["nextRunAt"] = ""
        _atomic_write_json(_schedules_path(), data)


def cmd_update_schedule_history_status(payload: Dict[str, Any]) -> None:
    """Patch the most recent history entry for a schedule with a status."""
    sp = _schedules_path()
    if not os.path.exists(sp):
        return
    with _schedule_store_lock():
        try:
            if os.path.getsize(sp) > _MAX_SCHEDULE_STORE_BYTES:
                return
            with open(sp) as f:
                data: Any = json.load(f)
        except Exception:
            return
        if not isinstance(data, dict):
            return
        history: List[Dict[str, Any]] = data.setdefault("history", [])
        sched_id = str(payload.get("schedId", ""))
        status = str(payload.get("status", ""))[:256]
        for entry in reversed(history):
            if isinstance(entry, dict) and entry.get("scheduleId") == sched_id:
                entry["status"] = status
                break
        _atomic_write_json(sp, data)


def cmd_migrate_history(payload: Dict[str, Any]) -> None:
    """Move (or copy) a history file to a new path, returning its content."""
    old_p: str = _safe_path(payload.get("oldFullPath", ""), allow_empty=True)
    new_p: str = _safe_path(payload.get("newFullPath", ""), allow_empty=True)
    current_b64: str = str(payload.get("currentB64", ""))
    res: Dict[str, Any] = {"status": "ok", "action": "none"}
    try:
        if not new_p:
            if old_p and os.path.exists(old_p):
                if os.path.getsize(old_p) > _MAX_FILE_BYTES:
                    raise ValueError("history file is too large")
                res["action"] = "load"
                with open(old_p, "rb") as f:
                    res["content"] = base64.b64encode(f.read()).decode("utf-8")
        else:
            folder = os.path.dirname(new_p)
            if folder:
                os.makedirs(folder, mode=0o700, exist_ok=True)
            if os.path.exists(new_p):
                if os.path.getsize(new_p) > _MAX_FILE_BYTES:
                    raise ValueError("history file is too large")
                res["action"] = "load"
                with open(new_p, "rb") as f:
                    res["content"] = base64.b64encode(f.read()).decode("utf-8")
            elif old_p and os.path.exists(old_p):
                if os.path.getsize(old_p) > _MAX_FILE_BYTES:
                    raise ValueError("history file is too large")
                shutil.copy2(old_p, new_p)
                res["action"] = "copied"
            else:
                data_bytes = base64.b64decode(current_b64, validate=True)
                if len(data_bytes) > _MAX_FILE_BYTES:
                    raise ValueError("history export is too large")
                data = data_bytes.decode("utf-8")
                _atomic_write_text(new_p, data)
                res["action"] = "exported"
    except Exception as e:
        res["status"] = "error"
        res["message"] = str(e)
    print(base64.b64encode(json.dumps(res).encode("utf-8")).decode("utf-8"))


def cmd_write_history(payload: Dict[str, Any]) -> None:
    """Decode a base64 payload to a UTF-8 text file at ``fullPath``."""
    path = _safe_path(payload.get("fullPath", ""))
    data = base64.b64decode(str(payload.get("b64Str", "")), validate=True)
    if len(data) > _MAX_FILE_BYTES:
        raise ValueError("history export is too large")
    _atomic_write_text(path, data.decode("utf-8"))
    print("OK")


def cmd_read_history(payload: Dict[str, Any]) -> None:
    """Read a JSON file and print its contents to stdout."""
    path = _safe_path(payload.get("fullPath", ""), allow_empty=True)
    if not path or not os.path.exists(path):
        print("[]")
        return
    try:
        if os.path.getsize(path) > _MAX_FILE_BYTES:
            print("[]")
            return
        with open(path, "r", encoding="utf-8") as f:
            print(f.read(_MAX_FILE_BYTES + 1))
    except Exception:
        print("[]")


def cmd_delete_session_schedules(payload: Dict[str, Any]) -> None:
    """Remove every schedule whose ``chatId`` matches ``sessionId``."""
    sp = _schedules_path()
    if not os.path.exists(sp):
        return
    with _schedule_store_lock():
        try:
            if os.path.getsize(sp) > _MAX_SCHEDULE_STORE_BYTES:
                return
            with open(sp) as f:
                data: Any = json.load(f)
        except Exception:
            return
        if not isinstance(data, dict):
            return
        scheds: List[Dict[str, Any]] = data.get("schedules", [])
        session_id = str(payload.get("sessionId", ""))
        data["schedules"] = [s for s in scheds if isinstance(s, dict) and s.get("chatId") != session_id]
        _atomic_write_json(sp, data)


def cmd_poll_pending_triggers(payload: Dict[str, Any]) -> None:
    """Drain the pending trigger directory and return its contents.

    Each file in the pending directory is read, parsed, and removed.
    Schedules are also returned for the QML side to keep its list in
    sync with the persisted store.
    """
    res: List[Dict[str, Any]] = []
    pd = _pending_dir()
    if os.path.exists(pd):
        for f in sorted(os.listdir(pd))[:50]:
            if f.endswith(".json"):
                p = os.path.join(pd, f)
                try:
                    if os.path.getsize(p) > 512 * 1024:
                        raise ValueError("pending trigger is too large")
                    with open(p) as pf:
                        item = json.load(pf)
                    if isinstance(item, dict) and len(str(item.get("message", ""))) <= 200000:
                        res.append(item)
                except (OSError, ValueError, json.JSONDecodeError):
                    pass
                finally:
                    try: os.remove(p)
                    except OSError: pass
    scheds: List[Dict[str, Any]] = []
    try:
        with _schedule_store_lock():
            scheds = _load_schedules().get("schedules", [])
    except Exception:
        pass
    print(json.dumps({"pending": res, "schedules": scheds}))


def cmd_delete_schedule(payload: Dict[str, Any]) -> None:
    """Remove a single schedule by id."""
    with _schedule_store_lock():
        data = _load_schedules()
        sched_id = str(payload.get("schedId", ""))
        data["schedules"] = [s for s in data.get("schedules", []) if isinstance(s, dict) and s.get("id") != sched_id]
        _atomic_write_json(_schedules_path(), data)


def cmd_add_schedule(payload: Dict[str, Any]) -> None:
    """Append a new schedule entry to the store."""
    entry = payload.get("entry")
    if not isinstance(entry, dict):
        raise ValueError("schedule entry must be an object")
    with _schedule_store_lock():
        data = _load_schedules()
        data.setdefault("schedules", []).append(entry)
        _atomic_write_json(_schedules_path(), data)


def cmd_setup_scheduler_service(payload: Dict[str, Any]) -> None:
    """Install the scheduler service file, daemon, and schedules store.

    Copies the helper script to the user's bin directory, ensures the
    schedules store exists with restrictive permissions, and writes the
    systemd user unit. Reports whether the unit ended up enabled.
    """
    src = _safe_path(payload.get("srcPath", ""))
    dest = _safe_path(payload.get("destPath", ""))
    os.makedirs(os.path.dirname(dest), mode=0o700, exist_ok=True)
    os.makedirs(_results_dir(), mode=0o700, exist_ok=True)
    try: os.chmod(os.path.dirname(dest), 0o700); os.chmod(_results_dir(), 0o700)
    except OSError: pass
    if os.path.exists(src):
        shutil.copy2(src, dest)
        os.chmod(dest, 0o755)
    sp = _schedules_path()
    with _schedule_store_lock():
        if not os.path.exists(sp):
            _atomic_write_json(sp, {"version": 1, "schedules": []})
    sdir = os.path.expanduser("~/.config/systemd/user")
    os.makedirs(sdir, mode=0o700, exist_ok=True)
    sfile = sdir + "/kde-ai-scheduler.service"
    service_content = str(payload.get("serviceContent", ""))
    if not service_content or "\x00" in service_content or len(service_content) > 32768:
        raise ValueError("invalid scheduler service content")
    _atomic_write_text(sfile, service_content, mode=0o600)
    os.system("systemctl --user daemon-reload")
    if os.system("systemctl --user is-enabled kde-ai-scheduler.service >/dev/null 2>&1") == 0:
        print("AUTO_ENABLED")
    else:
        print("AUTO_DISABLED")


def cmd_setup_venv_services(payload: Dict[str, Any]) -> None:
    """Install the voice services for STT and TTS systemd user units."""
    requested_venv = _safe_path(payload.get("venvPy", "~/.local/share/kdeaichat/venv/bin/python3"))
    venv_py = requested_venv
    if not os.path.exists(venv_py) and venv_py.endswith("/bin/python3"):
        alternate = venv_py[:-len("python3")] + "python"
        if os.path.exists(alternate):
            venv_py = alternate
    if not os.path.exists(venv_py):
        venv_py = shutil.which("python3") or "/usr/bin/python3"
    venv_py = _safe_path(venv_py)

    helper_dir = os.path.dirname(os.path.abspath(__file__))
    voice_helper = _safe_path(os.path.join(helper_dir, "voice", "voice_helper.py"))
    token_path = _safe_path(_voice_token_path())
    ensure_voice_http_token(token_path)

    sdir = os.path.expanduser("~/.config/systemd/user")
    os.makedirs(sdir, mode=0o700, exist_ok=True)

    espeak_env = ""
    espeak_path = payload.get("espeakPath", "")
    if espeak_path:
        # A custom executable/directory is optional. Refuse unsafe unit-file
        # input rather than attempting to interpret relative paths or control
        # characters.
        raw_espeak = _safe_path(espeak_path)
        dir_path = raw_espeak if os.path.isdir(raw_espeak) else os.path.dirname(raw_espeak)
        if dir_path:
            env_path = f"PATH={dir_path}:{os.path.expanduser('~/.local/bin')}:/usr/local/bin:/usr/bin:/bin"
            espeak_env = "\nEnvironment=" + _systemd_quote(env_path)
            espeak_env += "\nEnvironment=" + _systemd_quote(f"PHONEMIZER_ESPEAK_PATH={dir_path}")

    venv_arg = _systemd_quote(venv_py)
    helper_arg = _systemd_quote(voice_helper)
    token_arg = _systemd_quote(token_path)

    def write_voice_unit(path: str, server_flag: str) -> None:
        content = f"""[Unit]
Description=KDE AI Chat {server_flag.upper().lstrip('-') } Daemon
After=network.target

[Service]
Type=simple
ExecStart={venv_arg} {helper_arg} {server_flag} --token-file {token_arg}
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1{espeak_env}

[Install]
WantedBy=default.target
"""
        _atomic_write_text(path, content, mode=0o600)

    write_voice_unit(os.path.join(sdir, "kde-ai-stt.service"), "--stt-server")
    write_voice_unit(os.path.join(sdir, "kde-ai-tts.service"), "--tts-server")

    os.system("systemctl --user daemon-reload")
    voice_enabled = _as_bool(payload.get("voiceEnabled", True), True)
    voice_tts_enabled = _as_bool(payload.get("voiceTtsEnabled", True), True)
    if voice_enabled:
        os.system("systemctl --user enable --now kde-ai-stt.service 2>/dev/null")
    else:
        os.system("systemctl --user disable --now kde-ai-stt.service 2>/dev/null")

    if voice_enabled and voice_tts_enabled:
        os.system("systemctl --user enable --now kde-ai-tts.service 2>/dev/null")
    else:
        os.system("systemctl --user disable --now kde-ai-tts.service 2>/dev/null")
    print("VOICE_SERVICES_SETUP_OK")

def cmd_delete_venv_setup(payload: Dict[str, Any]) -> None:
    """Disable/stop voice systemd services and delete the venv & downloaded models."""
    # Stop & disable services
    os.system("systemctl --user stop kde-ai-stt.service 2>/dev/null")
    os.system("systemctl --user stop kde-ai-tts.service 2>/dev/null")
    os.system("systemctl --user disable kde-ai-stt.service 2>/dev/null")
    os.system("systemctl --user disable kde-ai-tts.service 2>/dev/null")
    
    # Remove the HTTP capability token as part of voice teardown.
    for token_file in (_voice_token_path(), _voice_token_path() + ".lock"):
        try:
            os.remove(token_file)
        except OSError:
            pass

    # Remove service files
    sdir = os.path.expanduser("~/.config/systemd/user")
    for sfile in ("kde-ai-stt.service", "kde-ai-tts.service"):
        p = os.path.join(sdir, sfile)
        if os.path.exists(p):
            try:
                os.remove(p)
            except Exception:
                pass
    os.system("systemctl --user daemon-reload")
    
    # Remove venv only when it is an explicitly selected absolute path with
    # the expected virtualenv layout. Never recursively remove an arbitrary
    # user-supplied directory.
    try:
        venv_py = _safe_path(payload.get("venvPy", "~/.local/share/kdeaichat/venv/bin/python3"))
    except ValueError:
        venv_py = ""
    venv_dir = venv_py[:-12] if venv_py.endswith("/bin/python3") else ""
    if venv_dir and os.path.exists(venv_dir) and venv_dir != "/usr" and len(venv_dir) > 5:
        try:
            shutil.rmtree(venv_dir)
        except Exception:
            pass
            
    # Remove default models folder
    models_dir = os.path.expanduser("~/.cache/kdeaichat/models")
    if os.path.exists(models_dir):
        try:
            shutil.rmtree(models_dir)
        except Exception:
            pass
            
    # Remove default huggingface cache faster-whisper/kokoro entries
    hf_cache = os.path.expanduser("~/.cache/huggingface/hub")
    if os.path.isdir(hf_cache):
        try:
            for entry in os.listdir(hf_cache):
                if "faster-whisper" in entry or "kokoro" in entry:
                    p = os.path.join(hf_cache, entry)
                    if os.path.isdir(p):
                        try:
                            shutil.rmtree(p)
                        except Exception:
                            pass
        except Exception:
            pass
                        
    print("DELETE_SETUP_OK")


def cmd_save_all_schedules(payload: Dict[str, Any]) -> None:
    """Persist a full schedules payload (replaces the existing file atomically)."""
    if not isinstance(payload, dict):
        raise ValueError("schedule payload must be an object")
    if len(json.dumps(payload, ensure_ascii=False).encode("utf-8")) > 1500000:
        raise ValueError("schedule payload is too large")
    p = os.path.expanduser("~/.local/share/kdeaichat")
    os.makedirs(p, mode=0o700, exist_ok=True)
    try: os.chmod(p, 0o700)
    except OSError: pass
    target = os.path.join(p, "schedules.json")
    try:
        with _schedule_store_lock():
            try:
                disk = _load_schedules()
            except Exception:
                disk = {"version": 1, "schedules": [], "history": []}
            merged_history = []
            seen = set()
            for history in (disk.get("history", []), payload.get("history", [])):
                for entry in history if isinstance(history, list) else []:
                    if not isinstance(entry, dict):
                        continue
                    key = entry.get("id") or json.dumps(entry, sort_keys=True, ensure_ascii=False)
                    if key not in seen:
                        seen.add(key)
                        merged_history.append(entry)
            payload_to_write = dict(payload)
            payload_to_write["schedules"] = [s for s in payload.get("schedules", []) if isinstance(s, dict)][:1000]
            payload_to_write["history"] = merged_history[-1000:]
            if not isinstance(payload_to_write.get("settings"), dict):
                payload_to_write["settings"] = disk.get("settings", {}) if isinstance(disk.get("settings", {}), dict) else {}
            _atomic_write_json(target, payload_to_write)
        print("SCHED_SAVE_OK")
    except Exception as e:
        sys.stderr.write(f"Error saving schedules: {e}\n")
        print("SCHED_SAVE_ERROR")


def _process_memory_kb(name: str, env_filter: str = None) -> int:
    """Sum RSS (in KiB) for every process whose command line matches ``name``."""
    r = subprocess.run(["pgrep", "-f", name], capture_output=True, text=True)
    pids = r.stdout.strip().split()
    total = 0
    for pid in pids:
        try:
            if env_filter:
                try:
                    with open(f"/proc/{pid}/environ", "rb") as f:
                        env_data = f.read()
                    if env_filter.encode("utf-8") not in env_data:
                        continue
                except Exception:
                    continue

            with open(f"/proc/{pid}/status") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        total += int(line.split()[1])
        except Exception:
            pass
    return total


def cmd_get_memory_usage(payload: Dict[str, Any]) -> None:
    """Return RSS totals (KiB) for the opencode, stt, tts, and scheduler processes."""
    import urllib.request
    
    stt_vram = 0
    token = _read_existing_voice_token()
    headers = {"X-KDE-AI-Chat-Token": token} if token else {}

    try:
        req = urllib.request.Request("http://127.0.0.1:9015/status", headers=headers)
        with urllib.request.urlopen(req, timeout=1.0) as response:
            d = json.loads(response.read())
        stt_vram = d.get("vram_kb", 0)
    except Exception:
        pass

    tts_vram = 0
    try:
        req = urllib.request.Request("http://127.0.0.1:9016/status", headers=headers)
        with urllib.request.urlopen(req, timeout=1.0) as response:
            d = json.loads(response.read())
        tts_vram = d.get("vram_kb", 0)
    except Exception:
        pass

    # For STT/TTS, check both persistent server processes and one-shot command processes
    stt_mem = _process_memory_kb("voice_helper.py.*--stt-server")
    if stt_mem == 0:
        stt_mem = _process_memory_kb("voice_helper.py.*start_stt")
    tts_mem = _process_memory_kb("voice_helper.py.*--tts-server")
    if tts_mem == 0:
        tts_mem = _process_memory_kb("voice_helper.py.*cmd.*tts")
        
    # Track the opencode serve instance (server). We don't need env_filter because any opencode serve process on the machine is the one we connect to.
    opencode_mem = _process_memory_kb("opencode serve")
    
    d: Dict[str, int] = {
        "opencode": opencode_mem,
        "stt": stt_mem,
        "tts": tts_mem,
        "stt_vram": stt_vram,
        "tts_vram": tts_vram,
        "scheduler": _process_memory_kb("kde-ai-scheduler.py"),
    }
    print(json.dumps(d))


def cmd_export_chat(payload: Dict[str, Any]) -> None:
    """Decode a base64 chat export and write it to ``filePath`` as UTF-8."""
    path = _safe_path(payload.get("filePath", ""))
    data = base64.b64decode(str(payload.get("b64Content", "")), validate=True)
    if len(data) > _MAX_FILE_BYTES:
        raise ValueError("chat export is too large")
    _atomic_write_text(path, data.decode("utf-8"))
    print("OK")


def _read_existing_voice_token(path: str = "") -> str:
    """Read an existing voice token without creating one as a side effect."""
    token_path = _safe_path(path or _voice_token_path())
    try:
        with open(token_path, "r", encoding="ascii") as f:
            token = f.read().strip()
        return token if re.fullmatch(r"[A-Za-z0-9_-]{32,}", token) else ""
    except (OSError, UnicodeError, ValueError):
        return ""


def cmd_get_voice_token(payload: Dict[str, Any]) -> None:
    """Return the private token shared by the widget and voice daemons."""
    print(json.dumps({"type": "voice_token", "token": ensure_voice_http_token()}))


def _legacy_watchdog_pids(helper_name: str = "kde_ai_helper.py") -> List[int]:
    """PIDs of monitors started by the removed plasmashell watchdog.

    Matched by exact command line (``... kde_ai_helper.py plasmashell_watchdog
    <payload>``) so a reused PID or an unrelated process is never signalled.
    """
    pids = []
    try:
        entries = os.listdir("/proc")
    except OSError:
        return pids
    for entry in entries:
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(os.path.join("/proc", entry, "cmdline"), "rb") as f:
                argv = [part.decode("utf-8", "replace") for part in f.read().split(b"\0") if part]
        except OSError:
            continue
        for i, arg in enumerate(argv[:-1]):
            if os.path.basename(arg) == helper_name and argv[i + 1] == "plasmashell_watchdog":
                pids.append(int(entry))
                break
    return pids


def cmd_stop_legacy_watchdog(payload: Dict[str, Any]) -> None:
    """Stop a plasmashell watchdog left running by a version before 1.4.0.

    That monitor survives widget upgrades and restarts plasmashell once its
    heartbeat file goes stale, which it always does now that nothing writes
    it. Stop it and remove its files.
    """
    stopped = []
    for pid in _legacy_watchdog_pids():
        try:
            os.kill(pid, signal.SIGTERM)
            stopped.append(pid)
        except OSError:
            pass
    folder = os.path.expanduser("~/.local/share/kdeaichat")
    for name in ("plasmashell-heartbeat", "plasmashell-watchdog.pid", "plasmashell-watchdog.last-restart"):
        try:
            os.unlink(os.path.join(folder, name))
        except OSError:
            pass
    print(json.dumps({"status": "ok", "stopped": stopped}))


def _decode_payload(raw: str) -> Dict[str, Any]:
    """Decode the base64+JSON payload passed as ``argv[2]``.

    Returns an empty dict on missing/empty input, exits the process on
    a parse error after printing a diagnostic.
    """
    if not raw:
        return {}
    try:
        raw_bytes = raw.encode("ascii") if isinstance(raw, str) else raw
        decoded: Any = json.loads(base64.b64decode(raw_bytes, validate=True).decode("utf-8"))
        if isinstance(decoded, dict):
            return decoded
        return {}
    except Exception as e:
        print(f"Error parsing payload: {e}")
        sys.exit(1)


def main() -> None:
    """Dispatch to the named ``cmd_*`` function with the decoded payload."""
    if len(sys.argv) < 2:
        print("Usage: kde_ai_helper.py <command> [b64payload]")
        sys.exit(1)

    command = sys.argv[1]
    payload = _decode_payload(sys.argv[2]) if len(sys.argv) > 2 else {}

    commands: Dict[str, Callable[[Dict[str, Any]], None]] = {
        "toggle_schedule": cmd_toggle_schedule,
        "update_schedule_history_status": cmd_update_schedule_history_status,
        "migrate_history": cmd_migrate_history,
        "write_history": cmd_write_history,
        "read_history": cmd_read_history,
        "delete_session_schedules": cmd_delete_session_schedules,
        "poll_pending_triggers": cmd_poll_pending_triggers,
        "delete_schedule": cmd_delete_schedule,
        "add_schedule": cmd_add_schedule,
        "setup_scheduler_service": cmd_setup_scheduler_service,
        "setup_venv_services": cmd_setup_venv_services,
        "setup_voice_services": cmd_setup_venv_services,
        "delete_venv_setup": cmd_delete_venv_setup,
        "delete_voice_setup": cmd_delete_venv_setup,
        "save_all_schedules": cmd_save_all_schedules,
        "get_memory_usage": cmd_get_memory_usage,
        "export_chat": cmd_export_chat,
        "get_voice_token": cmd_get_voice_token,
        "stop_legacy_watchdog": cmd_stop_legacy_watchdog,
    }

    commands.update({**privacy.COMMANDS, **chats.COMMANDS, **opencode_server.COMMANDS, **pi_bridge.COMMANDS, **pi_models.COMMANDS})
    if command not in commands:
        print(f"Unknown command: {command}")
        sys.exit(1)

    try:
        # Each schedule mutator acquires the shared lock around its complete
        # read/modify/write operation. Keeping locking inside the commands
        # avoids nested flock calls when the helper is invoked directly.
        commands[command](payload)
    except Exception as e:
        print(f"Error executing {command}: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
