"""`pi --list-models` for the widget: Pi's providers and models.

The table has a `thinking` column (yes/no): which models reason. It is the
only variant information Pi gives (the level names are Pi's own), so the
reply lists, per provider, the models and which of them think.
"""
import json
import os
import subprocess
from typing import Any, Dict, List


def parse_models(table: str) -> List[Dict[str, Any]]:
    """Providers (in first-seen order) from the text of `pi --list-models`."""
    lines = table.splitlines()
    header = lines[0].split() if lines else []
    thinking_at = header.index("thinking") if "thinking" in header else -1
    providers: Dict[str, Dict[str, Any]] = {}
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < 2:
            continue
        entry = providers.setdefault(parts[0], {"id": parts[0], "models": [], "thinking": []})
        entry["models"].append(parts[1])
        if 0 <= thinking_at < len(parts) and parts[thinking_at] == "yes":
            entry["thinking"].append(parts[1])
    return list(providers.values())


def cmd_get_pi_models(payload: Dict[str, Any]) -> None:
    try:
        # Pi is a globally installed CLI agent; look in the usual user install folders too.
        env = os.environ.copy()
        env["PATH"] = env.get("PATH", "") + ":" + os.path.expanduser("~/.npm-global/bin") + ":" + os.path.expanduser("~/.local/bin") + ":" + os.path.expanduser("~/bin")
        proc = subprocess.run(["pi", "--list-models"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True, timeout=10, env=env)
        print(json.dumps({"providers": parse_models(proc.stdout)}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))


COMMANDS = {"get_pi_models": cmd_get_pi_models}
