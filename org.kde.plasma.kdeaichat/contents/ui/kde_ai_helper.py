#!/usr/bin/env python3
"""kde_ai_helper — IPC helper invoked by the plasmoid via QProcess.

The QML side sends ``<command> <base64-payload>`` and reads the result on
stdout. The commands live in the ``kdeaichat`` package: each module exports
``COMMANDS`` (name -> ``cmd_*`` function), merged here. Shared validated
helpers (paths, atomic writes, the schedule-store lock) are in
``kdeaichat/common.py``.

This module intentionally has zero third-party dependencies (stdlib
only) so it can run inside the plasmoid install without an extra
virtualenv.
"""
import sys
import json
import base64
from typing import Any, Callable, Dict

from kdeaichat import (chats, config_cleanup, diagnostics, images, local_servers, maintenance, memory, opencode_server,
                       panel_icon, pi_bridge, pi_models, privacy, schedule_chat, schedule_job, schedule_store, schedules,
                       speechnote, storage, stt_commands, stt_install, tts, voice_data, voice_legacy, voice_services)


def _decode_payload(raw: str) -> Dict[str, Any]:
    """Decode the base64+JSON payload passed as ``argv[2]``.

    Returns an empty dict on missing/empty input, exits the process on
    a parse error after printing a diagnostic.
    """
    if not raw:
        return {}
    if raw.startswith("@"):  # chat text: in a private file, not on the command line
        from kdeaichat import private_payload
        try:
            return private_payload.read(raw)
        except (OSError, ValueError) as e:
            print(f"Error reading payload file: {e}")
            sys.exit(1)
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
    if command == "run_schedule":  # started by systemd as `run_schedule <id>` (%i), not base64
        payload: Dict[str, Any] = {"id": sys.argv[2] if len(sys.argv) > 2 else ""}
    else:
        payload = _decode_payload(sys.argv[2]) if len(sys.argv) > 2 else {}

    commands: Dict[str, Callable[[Dict[str, Any]], None]] = {}
    for module in (schedules, schedule_store, schedule_job, schedule_chat, voice_services, stt_commands, maintenance, privacy,
                   chats, images, memory, opencode_server, panel_icon, pi_bridge, pi_models, tts, voice_legacy, stt_install,
                   voice_data, diagnostics, config_cleanup, speechnote, local_servers, storage):
        commands.update(module.COMMANDS)
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
