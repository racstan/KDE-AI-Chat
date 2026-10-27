"""Runs one scheduled prompt in its target chat's own mode, without the widget.

``run_prompt`` is what schedule_job calls for a "run" decision. It finds the
chat, reads the widget's settings for that chat's widget instance, resolves
the chat's mode/provider/model like the widget does (schedule_context), runs
the prompt (direct: schedule_direct with the key from KWallet; OpenCode:
schedule_opencode; Pi: schedule_pi), adds the prompt and the reply to the
chat (schedule_chat) and notifies (schedule_notify). It returns the status
recorded in the run history: "ok", "error: <reason>" or "skipped: <reason>".
A chat never changes mode: a run always uses the chat's own mode, never the
current main setting.
"""
import datetime as dt
import time
from typing import Any, Callable, Dict, List, Optional

from kdeaichat import applet_config, schedule_chat, schedule_notify, schedule_wallet
from kdeaichat import schedule_context as ctx
from kdeaichat import schedule_direct, schedule_opencode, schedule_pi
from kdeaichat.schedule_direct import RunError
from kdeaichat.schedule_wallet import WalletUnavailable

AGENT_TIMEOUT = 20 * 60
DIRECT_DEFAULT_TIMEOUT = 300
DIRECT_MAX_TIMEOUT = 20 * 60


def _direct_timeout(config: Dict[str, Any]) -> float:
    try:
        seconds = int(config.get("requestTimeout") or 0)
    except (TypeError, ValueError):
        seconds = 0
    return float(min(DIRECT_MAX_TIMEOUT, max(60, seconds)) if seconds > 0 else DIRECT_DEFAULT_TIMEOUT)


def _run_direct(config, chat, project, eff, prompt) -> Dict[str, Any]:
    provider = eff["provider"]
    cfg = ctx.provider_config(provider, config)
    if not cfg["found"]:
        raise RunError(f"the provider \"{provider}\" isn't set up in Settings any more.")
    if cfg["type"] == "image":
        raise RunError("image providers can't answer scheduled prompts.")
    if not cfg["baseUrl"].lower().startswith(("http://", "https://")):
        raise RunError(f"the provider \"{provider}\" has no valid server URL.")
    model = eff["model"] or cfg["model"]
    if not model:
        raise RunError(f"no model is chosen for \"{provider}\".")
    try:
        key = schedule_wallet.read_key(provider)
    except WalletUnavailable:
        if not cfg["allowEmptyKey"]:
            raise
        key = ""
    if not key and not cfg["allowEmptyKey"]:
        raise RunError(f"there is no API key for \"{provider}\" in KWallet.")
    turns = ctx.history(chat["messages"] + [{"role": "user", "content": prompt}], config)
    result = schedule_direct.send(cfg, key, model, ctx.system_prompt(config, chat, project, direct=True), turns,
                                  ctx.max_tokens(chat), _direct_timeout(config))
    result["model"] = model
    return result


def _run_opencode(config, chat, project, eff, prompt) -> Dict[str, Any]:
    directory = _workspace(config, chat, project)
    use_agent_model = chat.get("openCodeUseAgentModel", config.get("openCodeUseAgentModel")) is True
    body = schedule_opencode.prompt_body(prompt, eff, ctx.system_prompt(config, chat, project, direct=False), use_agent_model)
    result = schedule_opencode.run(config, chat, directory, body, AGENT_TIMEOUT)
    result["model"] = f"{eff['provider']}/{eff['model']}" if eff["provider"] and eff["model"] else "OpenCode"
    return result


def _run_pi(config, chat, project, eff, prompt) -> Dict[str, Any]:
    body = {"directory": _workspace(config, chat, project), "instructions": ctx.agent_instructions(chat, project),
            "provider": eff["provider"], "model": eff["model"], "thinking": eff["thinking"], "message": prompt}
    result = schedule_pi.run(chat["value"], body, AGENT_TIMEOUT)
    result["model"] = "Pi · " + eff["model"] if eff["model"] else "Pi"
    return result


def _workspace(config: Dict[str, Any], chat: Dict[str, Any], project: Optional[Dict[str, Any]]) -> str:
    """Projects.workspaceFor; without projects the widget falls back to the main folder setting."""
    own = str(chat.get("openCodeWorkspaceCwd") or "").strip()
    if own:
        return own
    if project and chat.get("keepOwnFolder") is not True and str(project.get("folder") or "").strip():
        return str(project["folder"]).strip()
    return ""


RUNNERS: Dict[str, Callable[..., Dict[str, Any]]] = {"provider": _run_direct, "opencode": _run_opencode, "pi": _run_pi}


def _messages(schedule: Dict[str, Any], run_id: str, prompt: str, result: Dict[str, Any]) -> List[Dict[str, Any]]:
    now_ms = int(time.time() * 1000)
    clock = dt.datetime.now().strftime("%H:%M")
    mark = {"scheduled": True, "scheduleName": schedule["name"] or "Scheduled prompt", "scheduleId": schedule["id"],
            "scheduleRunId": run_id}
    user = dict(mark, id=f"sched-{run_id}-u", role="user", content=prompt, time=clock, at=now_ms, model="",
                queueId=0, attachments=[])
    content = result["content"]
    if result.get("notes"):
        content += "\n\n" + "\n".join("_" + n + "_" for n in result["notes"])
    reply = dict(mark, id=f"sched-{run_id}-a", role="assistant", content=content, reasoning=result.get("reasoning", ""),
                 time=clock, at=now_ms + 1, model=result.get("model", ""))
    for key in ("tokens", "cost"):
        if result.get(key):
            reply[key] = result[key]
    return [user, reply]


def run_prompt(schedule: Dict[str, Any], last_success: Optional[str], now: dt.datetime,
               runners: Optional[Dict[str, Callable[..., Dict[str, Any]]]] = None) -> str:
    """Runs ``schedule`` once; returns the status for the run history."""
    name = schedule["name"] or "Scheduled prompt"
    run_id = f"{schedule['id']}-{int(time.time() * 1000)}"

    def failed(status: str, body: str) -> str:
        schedule_notify.send(f"{name}: " + ("skipped" if status.startswith("skipped") else "failed"), body, error=True)
        return status

    ref = schedule_chat.find_chat(schedule["chatId"])
    if ref is None:
        return failed("skipped: chat not found", "The chat this schedule writes to no longer exists.")
    config = applet_config.applet_settings(ref["appletId"])
    if config is None:
        return failed("skipped: widget not found", "The widget that holds this chat isn't set up any more.")
    try:
        chat = dict(ref["meta"], messages=schedule_chat.load_messages(ref))
    except ValueError as e:
        return failed("error: the chat file can't be read", f"The chat file can't be read ({e}); it was left untouched.")
    project = ctx.project_of(chat, schedule_chat.load_projects(ref["directory"]))
    eff = ctx.effective(config, chat, project)
    prompt = ctx.expand(schedule["message"], now, last_success)
    try:
        result = (runners or RUNNERS)[eff["mode"]](config, chat, project, eff, prompt)
    except WalletUnavailable as e:
        body = ("KWallet is locked, so the API key couldn't be read. Unlock it and scheduled prompts run again."
                if e.reason == "wallet locked" else "KWallet isn't available, so the API key couldn't be read.")
        return failed("skipped: " + e.reason, body)
    except RunError as e:
        return failed("error: " + str(e), str(e))
    if not str(result.get("content") or "").strip():
        return failed("error: the reply was empty", "The model sent an empty reply.")
    widget = schedule_notify.plasma_running() and config.get("_configFile", "").endswith("plasma-org.kde.plasma.desktop-appletsrc")
    wants = schedule.get("notify", True) and config.get("notifyOnScheduled", True) is not False
    entry = {"scheduleId": schedule["id"], "scheduleName": name, "notify": bool(wants), "notified": not widget}
    if result.get("sessionId") and not chat.get("openCodeSessionId"):
        entry["sessionUpdates"] = {"openCodeSessionId": result["sessionId"]}
    try:
        schedule_chat.deliver(ref, run_id, _messages(schedule, run_id, prompt, result), entry)
    except (OSError, ValueError) as e:
        return failed("error: the reply couldn't be saved", f"The reply couldn't be added to the chat ({e}).")
    if wants and not widget:
        schedule_notify.send(f"{name} is ready", schedule_notify.preview(result["content"]),
                             fallback_body="A new reply is ready")
    return "ok"
