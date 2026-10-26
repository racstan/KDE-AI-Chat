"""What a scheduled run sends: the chat's own mode, provider, model and prompt.

Python versions of the widget's rules, kept small and tested against the JS
(tests/test_schedule_context.py):
- ``effective``: chat/EffectiveConfig.js ``forSession`` (a chat keeps its
  mode; per-chat model settings and the project's provider/model apply the
  same way);
- ``provider_config``: ProviderService.js ``getProviderConfig``;
- ``system_prompt``: chat/DirectRequest.qml ``directSystemPrompt`` /
  ``buildEffectiveSystemPrompt`` (Personality block for direct chats, the
  main system prompt, project and chat instructions, response length);
- ``history``: DirectRequest ``limitContextMessages`` over the chat's user
  and assistant messages, as plain text (attachments are not re-sent);
- ``expand``: the prompt variables {{date}}, {{time}}, {{weekday}}, {{last_run}}.

Not included headless: memories (MemoryRecall needs the widget's recall
logic), tools, and the direct model's variant (reasoning level), which needs
the model catalogue.
"""
import datetime as dt
import json
import re
from typing import Any, Dict, List, Optional

PERSONALITY_TONES = {"friendly": "friendly and warm", "professional": "professional and to the point",
                     "concise": "short and direct, without filler", "playful": "light and playful, with some humour"}
PERSONALITIES = {
    "friendly": "Friendly and encouraging: warm, patient and positive.",
    "professional": "Professional: clear, precise and neutral, like an expert colleague.",
    "witty": "Witty: helpful first, with a dry sense of humour where it fits.",
    "mentor": "A mentor: explain the why, check understanding and help the user learn rather than only giving answers.",
    "concise": "Concise: the shortest complete answer, no small talk.",
}
LIMITS = {"userName": 60, "userAbout": 600, "userLanguage": 60, "userNotes": 800, "aiName": 40, "aiPersonalityCustom": 800}
LENGTH_TEXT = ["", "Keep the response short and focused, around 256 output tokens unless the task requires more.",
               "Give a balanced response, around 1024 output tokens at most.",
               "Give a detailed response, around 4096 output tokens at most.",
               "Give a comprehensive response, up to roughly 8192 output tokens when useful."]
MODEL_KEYS = ["chatProvider", "chatModel", "chatVariant", "openCodeProvider", "openCodeModel", "openCodeAgent",
              "openCodeVariant", "piProvider", "piModel", "piThinking"]
LOCAL_IDS = ["local", "ollama", "lmstudio", "litellm"]
DEFAULT_MAX_TOKENS = 4096


def _s(value: Any) -> str:
    return "" if value is None else str(value).strip()


# --- Mode, provider, model (EffectiveConfig.js) ---------------------------------

def chat_mode(chat: Dict[str, Any]) -> str:
    if _s(chat.get("source")) in ("provider", "opencode", "pi"):
        return _s(chat.get("source"))
    if _s(chat.get("openCodeSessionId")):
        return "opencode"
    if any(isinstance(m, dict) and _s(m.get("harnessChatId")) for m in chat.get("messages") or []):
        return "pi"
    return "provider"


def _has_own(chat: Dict[str, Any]) -> bool:
    if chat.get("ownModel") is True:
        return True
    if chat.get("ownModel") is False:
        return False
    return any(_s(chat.get(k)) for k in MODEL_KEYS)


def effective(config: Dict[str, Any], chat: Dict[str, Any], project: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """EffectiveConfig.forSession for a stored chat: {mode, provider, model, agent, thinking, variant}."""
    use_chat = config.get("perChatModelSettings") is True and _has_own(chat)
    chat_first = config.get("perChatPriority") != "main"
    project_provider = _s((project or {}).get("provider"))
    project_model = _s((project or {}).get("model")) if project_provider else ""
    main_direct = project_provider or _s(config.get("provider")) or "openai"
    mode = chat_mode(chat)
    legacy_pi = use_chat and "piProvider" not in chat and "piModel" not in chat and mode == "pi"

    def field(main_value: Any, chat_value: Any) -> str:
        order = [main_value] if not use_chat else ([chat_value, main_value] if chat_first else [main_value, chat_value])
        return next((_s(v) for v in order if _s(v)), "")

    def model_for(pid: str) -> str:
        return provider_config(pid, config).get("model", "")

    provider = field(main_direct, "" if legacy_pi else (chat.get("chatProvider") if use_chat else ""))
    chat_direct_provider = (_s(chat.get("chatProvider")) or main_direct) if use_chat and not legacy_pi else ""
    own_model = chat.get("chatModel") if use_chat and not legacy_pi and chat_direct_provider == provider else ""
    use_project_model = project_model != "" and provider == project_provider
    model = field(project_model if use_project_model else model_for(provider), own_model)
    out = {"mode": mode, "provider": provider, "model": model, "agent": "", "thinking": "", "variant": ""}
    get = (lambda k: chat.get(k)) if use_chat else (lambda k: "")
    if mode == "opencode":
        out.update(provider=field(config.get("openCodeProvider"), get("openCodeProvider")),
                   model=field(config.get("openCodeModel"), get("openCodeModel")),
                   agent=field(config.get("openCodeAgent"), get("openCodeAgent")),
                   variant=field(config.get("openCodeVariant"), get("openCodeVariant")))
    elif mode == "pi":
        out.update(provider=field(config.get("piProvider"), get("chatProvider" if legacy_pi else "piProvider")),
                   model=field(config.get("piModel"), get("chatModel" if legacy_pi else "piModel")),
                   thinking=field(config.get("piThinking"), get("piThinking")))
        out["variant"] = out["thinking"]
    return out


# --- Providers (ProviderService.js) ----------------------------------------------

def provider_list(config: Dict[str, Any]) -> List[Dict[str, Any]]:
    try:
        data = json.loads(config.get("providersJson") or "[]")
    except ValueError:
        return []
    return [p for p in data if isinstance(p, dict) and p.get("id")] if isinstance(data, list) else []


def provider_config(provider_id: str, config: Dict[str, Any]) -> Dict[str, Any]:
    """{found, type, baseUrl, model, headers, allowEmptyKey} for a provider id."""
    entries = provider_list(config)
    entry = next((p for p in entries if str(p.get("id")) == provider_id), None)
    if entry is None:
        return {"found": False, "type": "openai-compat", "baseUrl": "", "model": "", "headers": None, "allowEmptyKey": False}
    kind = entry.get("type") if entry.get("type") in ("anthropic", "image") else "openai-compat"
    base = _s(entry.get("baseUrl"))
    local = provider_id in LOCAL_IDS or bool(re.match(r"^https?://(localhost|127\.0\.0\.1|\[::1\])[:/]", base, re.I))
    headers = entry.get("headers") if isinstance(entry.get("headers"), dict) else None
    return {"found": True, "type": kind, "baseUrl": base, "model": _s(entry.get("model")), "headers": headers,
            "allowEmptyKey": local}


# --- System prompt ------------------------------------------------------------------

def _clamp(value: Any, limit: int, multi_line: bool) -> str:
    s = re.sub(r"\r\n?", "\n", _s(value) if value is not None else "")
    s = re.sub(r"[\x00-\x09\x0b-\x1f\x7f]", "", s) if multi_line else re.sub(r"[\x00-\x1f\x7f]+", " ", s)
    s = re.sub(r"\n{3,}", "\n\n", s).strip()
    return s[:limit - 1].rstrip() + "…" if len(s) > limit else s


def personality_block(config: Dict[str, Any]) -> str:
    """Personality.js ``block``."""
    user = []
    if _clamp(config.get("userName"), LIMITS["userName"], False):
        user.append("Name: " + _clamp(config.get("userName"), LIMITS["userName"], False))
    if _clamp(config.get("userAbout"), LIMITS["userAbout"], True):
        user.append("About them: " + _clamp(config.get("userAbout"), LIMITS["userAbout"], True))
    if PERSONALITY_TONES.get(_s(config.get("userTone"))):
        user.append("Preferred tone: " + PERSONALITY_TONES[_s(config.get("userTone"))] + ".")
    if _clamp(config.get("userLanguage"), LIMITS["userLanguage"], False):
        user.append("Reply in " + _clamp(config.get("userLanguage"), LIMITS["userLanguage"], False) + ", whatever language they write in.")
    if _clamp(config.get("userNotes"), LIMITS["userNotes"], True):
        user.append("Always / never:\n" + _clamp(config.get("userNotes"), LIMITS["userNotes"], True))
    persona = []
    ai_name = _clamp(config.get("aiName"), LIMITS["aiName"], False)
    if ai_name:
        persona.append("Your name is " + ai_name + ". Use this name for yourself, even where other instructions call you something else.")
    kind = _s(config.get("aiPersonality"))
    text = _clamp(config.get("aiPersonalityCustom"), LIMITS["aiPersonalityCustom"], True) if kind == "custom" else PERSONALITIES.get(kind, "")
    if text:
        persona.append("Personality: " + text)
    parts = (["## About the user\n" + "\n".join(user)] if user else []) + (["## Your persona\n" + "\n".join(persona)] if persona else [])
    return "\n\n".join(parts)


def project_of(chat: Dict[str, Any], projects: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    pid = _s(chat.get("projectId"))
    return next((p for p in projects if pid and _s(p.get("id")) == pid), None)


def project_block(project: Optional[Dict[str, Any]]) -> str:
    text = _s((project or {}).get("instructions"))
    return f"--- Project instructions ({project.get('name')}) ---\n{text}\n--- End project instructions ---" if text else ""


def chat_block(chat: Dict[str, Any]) -> str:
    text = _s(chat.get("chatSystemPrompt"))
    return f"--- Chat-specific instructions ---\n{text}\n--- End chat-specific instructions ---" if text else ""


def system_prompt(config: Dict[str, Any], chat: Dict[str, Any], project: Optional[Dict[str, Any]], direct: bool) -> str:
    """DirectRequest.directSystemPrompt (direct) or buildEffectiveSystemPrompt (OpenCode); memories left out."""
    parts: List[str] = []
    if chat.get("chatSystemPromptEnabled") is not False:
        main = _s(config.get("systemPrompt"))[:100000]
        if config.get("enableSystemPrompt") is not False and main:
            parts.append(main)
        for block in (project_block(project), chat_block(chat)):
            if block:
                parts.append(block)
        length = _int(chat.get("responseLength"))
        if 0 < length < len(LENGTH_TEXT):
            parts.append("Response length preference: " + LENGTH_TEXT[length])
    rest = "\n\n".join(parts)
    block = personality_block(config) if direct and chat.get("personalityOff") is not True else ""
    return block + "\n\n" + rest if block and rest else (block or rest)


def agent_instructions(chat: Dict[str, Any], project: Optional[Dict[str, Any]]) -> str:
    """Projects.instructionsFor: what Pi gets appended to its system prompt."""
    parts = [project_block(project)]
    if chat.get("chatSystemPromptEnabled") is not False:
        parts.append(chat_block(chat))
    return "\n\n".join(p for p in parts if p)


def max_tokens(chat: Dict[str, Any]) -> int:
    limits = [DEFAULT_MAX_TOKENS, 512, 1024, 4096, 8192]
    length = _int(chat.get("responseLength"))
    return limits[length] if 0 <= length < len(limits) else DEFAULT_MAX_TOKENS


def _int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


# --- Conversation and prompt -------------------------------------------------------

def history(messages: List[Dict[str, Any]], config: Dict[str, Any]) -> List[Dict[str, str]]:
    """The last messages as {role, content} (DirectRequest.limitContextMessages)."""
    convo = [m for m in messages if m.get("role") in ("user", "assistant")]
    try:
        configured = int(config.get("contextMessageLimit"))
    except (TypeError, ValueError):
        configured = -1
    keep = min(100, configured + 1) if configured >= 0 else 100
    convo = convo[-keep:] if keep > 0 else []
    out, total = [], 0
    for m in reversed(convo):
        content = "" if m.get("content") is None else str(m.get("content"))
        if not content and m.get("role") == "assistant" and m.get("images"):
            content = "[image]"
        size = len(json.dumps(m, ensure_ascii=False))
        if total + size > 6000000 and out:
            break
        total += size
        if content:
            out.append({"role": m["role"], "content": content})
    return list(reversed(out))


def expand(message: str, now: dt.datetime, last_run: Optional[str]) -> str:
    """{{date}} 2026-10-27, {{time}} 09:00, {{weekday}} Tuesday, {{last_run}} (or "never")."""
    last = "never"
    if last_run:
        try:
            last = dt.datetime.fromisoformat(last_run).strftime("%Y-%m-%d %H:%M")
        except ValueError:
            pass
    values = {"date": now.strftime("%Y-%m-%d"), "time": now.strftime("%H:%M"), "weekday": now.strftime("%A"), "last_run": last}
    return re.sub(r"\{\{\s*(date|time|weekday|last_run)\s*\}\}", lambda m: values[m.group(1)], message)
