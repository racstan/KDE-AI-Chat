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
import configparser
from typing import Any, Callable, Dict, List


def _schedules_path() -> str:
    return os.path.expanduser('~/.local/share/kdeaichat/schedules.json')


def _pending_dir() -> str:
    return os.path.expanduser('~/.local/share/kdeaichat/pending')


def _results_dir() -> str:
    return os.path.expanduser('~/.local/share/kdeaichat/results')


def _load_schedules() -> Dict[str, Any]:
    """Load the schedule store, tolerating legacy list-formatted files.

    Returns a dict with at least ``"version"`` and ``"schedules"`` keys.
    On missing file, returns an empty default. On parse failure, returns
    the empty default as well (the caller's write will overwrite).
    """
    sp = _schedules_path()
    if os.path.exists(sp):
        try:
            with open(sp) as f:
                data: Any = json.load(f)
        except Exception:
            data = None
    else:
        data = None
    if isinstance(data, list):
        return {"version": 1, "schedules": data}
    if isinstance(data, dict):
        return data
    return {"version": 1, "schedules": []}


def cmd_toggle_schedule(payload: Dict[str, Any]) -> None:
    """Enable/disable a schedule by id, clearing ``nextRunAt`` on enable."""
    data = _load_schedules()
    for s in data.get("schedules", []):
        if s.get("id") == payload["schedId"]:
            s["enabled"] = payload["enabled"]
            if payload["enabled"]:
                s["nextRunAt"] = ""
    with open(_schedules_path(), "w") as f:
        json.dump(data, f, indent=2)


def cmd_update_schedule_history_status(payload: Dict[str, Any]) -> None:
    """Patch the most recent history entry for a schedule with a status."""
    sp = _schedules_path()
    if not os.path.exists(sp):
        return
    try:
        with open(sp) as f:
            data: Any = json.load(f)
    except Exception:
        return
    if not isinstance(data, dict):
        return
    history: List[Dict[str, Any]] = data.setdefault("history", [])
    for entry in reversed(history):
        if entry.get("scheduleId") == payload["schedId"]:
            entry["status"] = payload["status"]
            break
    with open(sp, "w") as f:
        json.dump(data, f, indent=2)


def cmd_migrate_history(payload: Dict[str, Any]) -> None:
    """Move (or copy) a history file to a new path, returning its content."""
    old_p: str = os.path.expanduser(payload["oldFullPath"]) if payload["oldFullPath"] else ""
    new_p: str = os.path.expanduser(payload["newFullPath"]) if payload["newFullPath"] else ""
    current_b64: str = payload["currentB64"]
    res: Dict[str, Any] = {"status": "ok", "action": "none"}
    try:
        if not new_p:
            if old_p and os.path.exists(old_p):
                res["action"] = "load"
                with open(old_p, "rb") as f:
                    res["content"] = base64.b64encode(f.read()).decode("utf-8")
        else:
            folder = os.path.dirname(new_p)
            if folder:
                os.makedirs(folder, exist_ok=True)
            if os.path.exists(new_p):
                res["action"] = "load"
                with open(new_p, "rb") as f:
                    res["content"] = base64.b64encode(f.read()).decode("utf-8")
            elif old_p and os.path.exists(old_p):
                shutil.copy2(old_p, new_p)
                res["action"] = "copied"
            else:
                data = base64.b64decode(current_b64).decode("utf-8")
                with open(new_p, "w", encoding="utf-8") as f:
                    f.write(data)
                res["action"] = "exported"
    except Exception as e:
        res["status"] = "error"
        res["message"] = str(e)
    print(base64.b64encode(json.dumps(res).encode("utf-8")).decode("utf-8"))


def cmd_write_history(payload: Dict[str, Any]) -> None:
    """Decode a base64 payload to a UTF-8 text file at ``fullPath``."""
    path = os.path.expanduser(payload["fullPath"])
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(base64.b64decode(payload["b64Str"]).decode("utf-8"))
    print("OK")


def cmd_read_history(payload: Dict[str, Any]) -> None:
    """Read a JSON file and print its contents to stdout."""
    path = os.path.expanduser(payload.get("fullPath", ""))
    if not path or not os.path.exists(path):
        print("[]")
        return
    try:
        with open(path, "r", encoding="utf-8") as f:
            print(f.read())
    except Exception:
        print("[]")


def cmd_delete_session_schedules(payload: Dict[str, Any]) -> None:
    """Remove every schedule whose ``chatId`` matches ``sessionId``."""
    sp = _schedules_path()
    if not os.path.exists(sp):
        return
    try:
        with open(sp) as f:
            data: Any = json.load(f)
    except Exception:
        return
    if not isinstance(data, dict):
        return
    scheds: List[Dict[str, Any]] = data.get("schedules", [])
    data["schedules"] = [s for s in scheds if s.get("chatId") != payload["sessionId"]]
    with open(sp, "w") as f:
        json.dump(data, f, indent=2)


def cmd_poll_pending_triggers(payload: Dict[str, Any]) -> None:
    """Drain the pending trigger directory and return its contents.

    Each file in the pending directory is read, parsed, and removed.
    Schedules are also returned for the QML side to keep its list in
    sync with the persisted store.
    """
    res: List[Dict[str, Any]] = []
    pd = _pending_dir()
    if os.path.exists(pd):
        for f in os.listdir(pd):
            if f.endswith(".json"):
                p = os.path.join(pd, f)
                try:
                    with open(p) as pf:
                        res.append(json.load(pf))
                    os.remove(p)
                except Exception:
                    pass
    scheds: List[Dict[str, Any]] = []
    sp = _schedules_path()
    if os.path.exists(sp):
        try:
            with open(sp) as sf:
                s_data: Any = json.load(sf)
            scheds = s_data.get("schedules", []) if isinstance(s_data, dict) else s_data
        except Exception:
            pass
    print(json.dumps({"pending": res, "schedules": scheds}))


def cmd_delete_schedule(payload: Dict[str, Any]) -> None:
    """Remove a single schedule by id."""
    data = _load_schedules()
    data["schedules"] = [s for s in data.get("schedules", []) if s.get("id") != payload["schedId"]]
    with open(_schedules_path(), "w") as f:
        json.dump(data, f, indent=2)


def cmd_add_schedule(payload: Dict[str, Any]) -> None:
    """Append a new schedule entry to the store."""
    data = _load_schedules()
    data.setdefault("schedules", []).append(payload["entry"])
    with open(_schedules_path(), "w") as f:
        json.dump(data, f, indent=2)


def _load_config(path: str) -> configparser.ConfigParser:
    """Load a configparser file, preserving key case."""
    config = configparser.ConfigParser()
    config.optionxform = str
    if os.path.exists(path):
        config.read(path)
    return config


def cmd_sync_config_keys(payload: Dict[str, Any]) -> None:
    """Merge ``payload["keys"]`` into the ``[General]`` section of a config file."""
    path = os.path.expanduser(payload["configPath"])
    data: Dict[str, Any] = payload["keys"]
    config = _load_config(path)
    if "General" not in config:
        config["General"] = {}
    for k, v in data.items():
        config["General"][k] = str(v)
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, "w") as f:
        config.write(f)


def cmd_clear_config_keys(payload: Dict[str, Any]) -> None:
    """Remove ``payload["keys"]`` from the ``[General]`` section."""
    path = os.path.expanduser(payload["configPath"])
    keys: List[str] = payload["keys"]
    config = _load_config(path)
    if "General" in config:
        for k in keys:
            config["General"].pop(k, None)
        with open(path, "w") as f:
            config.write(f)


def cmd_load_config_keys(payload: Dict[str, Any]) -> None:
    """Dump the ``[General]`` section as a JSON object to stdout."""
    path: str = os.path.expanduser(payload.get("configPath", "~/.config/kdeaichatrc"))
    config = _load_config(path)
    res: Dict[str, str] = dict(config["General"]) if "General" in config else {}
    print(json.dumps(res))


def cmd_setup_scheduler_service(payload: Dict[str, Any]) -> None:
    """Install the scheduler service file, daemon, and schedules store.

    Copies the helper script to the user's bin directory, ensures the
    schedules store exists with restrictive permissions, and writes the
    systemd user unit. Reports whether the unit ended up enabled.
    """
    src = os.path.expanduser(payload["srcPath"])
    dest = os.path.expanduser(payload["destPath"])
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    os.makedirs(_results_dir(), exist_ok=True)
    if os.path.exists(src):
        shutil.copy2(src, dest)
        os.chmod(dest, 0o755)
    sp = _schedules_path()
    if not os.path.exists(sp):
        with open(sp, "w") as f:
            f.write('{"version":1,"schedules":[]}')
        os.chmod(sp, 0o600)
    sdir = os.path.expanduser("~/.config/systemd/user")
    os.makedirs(sdir, exist_ok=True)
    sfile = sdir + "/kde-ai-scheduler.service"
    with open(sfile, "w") as f:
        f.write(payload["serviceContent"])
    os.system("systemctl --user daemon-reload")
    if os.system("systemctl --user is-enabled kde-ai-scheduler.service >/dev/null 2>&1") == 0:
        print("AUTO_ENABLED")
    else:
        print("AUTO_DISABLED")


def cmd_setup_venv_services(payload: Dict[str, Any]) -> None:
    """Install the voice services for STT and TTS systemd user units."""
    venv_py = os.path.expanduser(payload.get("venvPy", "~/.local/share/kdeaichat/venv/bin/python3"))
    if not os.path.exists(venv_py):
        venv_py = shutil.which("python3") or "/usr/bin/python3"

    helper_dir = os.path.dirname(os.path.abspath(__file__))
    voice_helper = os.path.join(helper_dir, "voice", "voice_helper.py")

    sdir = os.path.expanduser("~/.config/systemd/user")
    os.makedirs(sdir, exist_ok=True)

    espeak_path = payload.get("espeakPath", "")
    espeak_env = ""
    if espeak_path:
        espeak_path = os.path.expanduser(espeak_path)
        if os.path.isdir(espeak_path):
            dir_path = espeak_path
        else:
            dir_path = os.path.dirname(espeak_path)
        if dir_path:
            espeak_env = f'\nEnvironment="PATH={dir_path}:%h/.local/bin:/usr/local/bin:/usr/bin:/bin"\nEnvironment="PHONEMIZER_ESPEAK_PATH={dir_path}"'

    # Write STT service
    stt_file = os.path.join(sdir, "kde-ai-stt.service")
    stt_content = f"""[Unit]
Description=KDE AI Chat STT Daemon
After=network.target

[Service]
Type=simple
ExecStart={venv_py} {voice_helper} --stt-server
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1{espeak_env}

[Install]
WantedBy=default.target
"""
    with open(stt_file, "w") as f:
        f.write(stt_content)

    # Write TTS service
    tts_file = os.path.join(sdir, "kde-ai-tts.service")
    tts_content = f"""[Unit]
Description=KDE AI Chat TTS Daemon
After=network.target

[Service]
Type=simple
ExecStart={venv_py} {voice_helper} --tts-server
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1{espeak_env}

[Install]
WantedBy=default.target
"""
    with open(tts_file, "w") as f:
        f.write(tts_content)

    os.system("systemctl --user daemon-reload")
    os.system("systemctl --user enable --now kde-ai-stt.service 2>/dev/null")
    os.system("systemctl --user enable --now kde-ai-tts.service 2>/dev/null")
    print("VOICE_SERVICES_SETUP_OK")

def cmd_delete_venv_setup(payload: Dict[str, Any]) -> None:
    """Disable/stop voice systemd services and delete the venv & downloaded models."""
    # Stop & disable services
    os.system("systemctl --user stop kde-ai-stt.service 2>/dev/null")
    os.system("systemctl --user stop kde-ai-tts.service 2>/dev/null")
    os.system("systemctl --user disable kde-ai-stt.service 2>/dev/null")
    os.system("systemctl --user disable kde-ai-tts.service 2>/dev/null")
    
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
    
    # Remove venv
    venv_py = os.path.expanduser(payload.get("venvPy", "~/.local/share/kdeaichat/venv/bin/python3"))
    venv_dir = venv_py
    if venv_dir.endswith("/bin/python3"):
        venv_dir = venv_dir[:-12]
    
    if os.path.exists(venv_dir) and venv_dir != "/usr" and len(venv_dir) > 5:
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
    """Persist a full schedules payload (replaces the existing file)."""
    p = os.path.expanduser("~/.local/share/kdeaichat")
    os.makedirs(p, exist_ok=True)
    with open(os.path.join(p, "schedules.json"), "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
    print("SCHED_SAVE_OK")


def _process_memory_kb(name: str) -> int:
    """Sum RSS (in KiB) for every process whose command line matches ``name``."""
    r = subprocess.run(["pgrep", "-f", name], capture_output=True, text=True)
    pids = r.stdout.strip().split()
    total = 0
    for pid in pids:
        try:
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
    try:
        req = urllib.request.urlopen("http://127.0.0.1:9015/status", timeout=1.0)
        d = json.loads(req.read())
        stt_vram = d.get("vram_kb", 0)
    except Exception:
        pass

    tts_vram = 0
    try:
        req = urllib.request.urlopen("http://127.0.0.1:9016/status", timeout=1.0)
        d = json.loads(req.read())
        tts_vram = d.get("vram_kb", 0)
    except Exception:
        pass

    # For STT/TTS, check both persistent server processes and one-shot command processes
    stt_mem = _process_memory_kb("voice_helper.py --stt-server")
    if stt_mem == 0:
        stt_mem = _process_memory_kb("voice_helper.py.*start_stt")
    tts_mem = _process_memory_kb("voice_helper.py --tts-server")
    if tts_mem == 0:
        tts_mem = _process_memory_kb("voice_helper.py.*cmd.*tts")
        
    # Only track the widget-launched opencode or opencode serve instances, ignore external processes named just 'opencode'
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
    path = os.path.expanduser(payload["filePath"])
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(base64.b64decode(payload["b64Content"]).decode("utf-8"))
    print("OK")


def _decode_payload(raw: str) -> Dict[str, Any]:
    """Decode the base64+JSON payload passed as ``argv[2]``.

    Returns an empty dict on missing/empty input, exits the process on
    a parse error after printing a diagnostic.
    """
    if not raw:
        return {}
    try:
        raw_bytes = raw.encode("utf-8") if isinstance(raw, str) else raw
        decoded: Any = json.loads(base64.b64decode(raw_bytes).decode("utf-8"))
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
        "sync_config_keys": cmd_sync_config_keys,
        "clear_config_keys": cmd_clear_config_keys,
        "load_config_keys": cmd_load_config_keys,
        "setup_scheduler_service": cmd_setup_scheduler_service,
        "setup_venv_services": cmd_setup_venv_services,
        "setup_voice_services": cmd_setup_venv_services,
        "delete_venv_setup": cmd_delete_venv_setup,
        "delete_voice_setup": cmd_delete_venv_setup,
        "save_all_schedules": cmd_save_all_schedules,
        "get_memory_usage": cmd_get_memory_usage,
        "export_chat": cmd_export_chat,
    }

    if command not in commands:
        print(f"Unknown command: {command}")
        sys.exit(1)

    try:
        commands[command](payload)
    except Exception as e:
        print(f"Error executing {command}: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
