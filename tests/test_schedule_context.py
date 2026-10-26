"""schedule_context (Python) gives the same mode/provider/model and Personality block as the widget's JS."""
import datetime as dt
import json
import os
import subprocess

import pytest

from kdeaichat import schedule_context as ctx

UI = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "org.kde.plasma.kdeaichat", "contents", "ui")

PROVIDERS = [{"id": "nvidia", "name": "N", "type": "openai-compat", "baseUrl": "https://n/v1", "model": "n-main"},
             {"id": "openai", "name": "O", "type": "openai-compat", "baseUrl": "https://o/v1", "model": "o-main"}]
CONFIGS = [
    {"provider": "nvidia", "providersJson": json.dumps(PROVIDERS)},
    {"provider": "nvidia", "providersJson": json.dumps(PROVIDERS), "perChatModelSettings": True, "perChatPriority": "chat",
     "useOpenCode": True, "openCodeProvider": "p1", "openCodeModel": "m1", "openCodeAgent": "build",
     "piProvider": "pp", "piModel": "pm", "piThinking": "low"},
    {"provider": "openai", "providersJson": json.dumps(PROVIDERS), "perChatModelSettings": True, "perChatPriority": "main",
     "usePi": True, "piProvider": "pp", "piModel": ""},
]
CHATS = [
    {"value": "a", "source": "provider"},
    {"value": "b", "source": "provider", "chatProvider": "openai", "chatModel": "o-own", "ownModel": True},
    {"value": "c", "source": "opencode", "openCodeModel": "m-own", "openCodeAgent": "plan"},
    {"value": "d", "source": "pi", "chatProvider": "legacy", "chatModel": "legacy-m"},
    {"value": "e", "source": "pi", "piProvider": "x", "piModel": "y", "piThinking": "high", "ownModel": True},
    {"value": "f", "openCodeSessionId": "ses_1"},
    {"value": "g", "messages": [{"role": "user", "harnessChatId": "g"}]},
    {"value": "h", "source": "provider", "projectId": "p-1"},
]
PROJECTS = [{"id": "p-1", "name": "Work", "provider": "openai", "model": "o-project", "instructions": "Be formal."}]


def _node(script):
    result = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def _load(name):
    with open(os.path.join(UI, name), encoding="utf-8") as f:
        return f.read().replace(".pragma library", "")


def test_effective_matches_effective_config_js():
    js = _load("ProviderService.js") + "\n" + _load("chat/EffectiveConfig.js") + """
var out = [];
var configs = %s, chats = %s, projects = %s;
for (var i = 0; i < configs.length; i++) for (var j = 0; j < chats.length; j++) {
    var chat = chats[j], project = null;
    for (var k = 0; k < projects.length; k++) if (projects[k].id === chat.projectId) project = projects[k];
    var e = forSession(configs[i], chat, function(id) { return getProviderConfig(id, configs[i]).model; },
                       function(id) { return ""; }, project);
    out.push([e.mode, e.provider, e.model, e.agent, e.thinking]);
}
console.log(JSON.stringify(out));""" % (json.dumps(CONFIGS), json.dumps(CHATS), json.dumps(PROJECTS))
    expected = _node(js)
    got = []
    for config in CONFIGS:
        for chat in CHATS:
            e = ctx.effective(config, chat, ctx.project_of(chat, PROJECTS))
            got.append([e["mode"], e["provider"], e["model"], e["agent"], e["thinking"]])
    assert got == expected


PERSONAS = [{}, {"userName": "Ana", "userAbout": "Writes\n\n\n\ncode", "userTone": "friendly", "userLanguage": "German",
                 "userNotes": "never emojis", "aiName": "Nova", "aiPersonality": "witty"},
            {"aiPersonality": "custom", "aiPersonalityCustom": "x" * 900, "userName": "  A\tB  "}]


@pytest.mark.parametrize("cfg", PERSONAS)
def test_personality_block_matches_personality_js(cfg):
    js = _load("chat/Personality.js") + "\nconsole.log(JSON.stringify(block(%s)));" % json.dumps(cfg)
    assert ctx.personality_block(cfg) == _node(js)


def test_system_prompt_order_and_switches():
    config = {"systemPrompt": "Main.", "enableSystemPrompt": True, "userName": "Ana"}
    chat = {"chatSystemPrompt": "Chat.", "responseLength": 2}
    project = PROJECTS[0]
    text = ctx.system_prompt(config, chat, project, direct=True)
    assert text == ("## About the user\nName: Ana\n\nMain.\n\n--- Project instructions (Work) ---\nBe formal.\n"
                    "--- End project instructions ---\n\n--- Chat-specific instructions ---\nChat.\n"
                    "--- End chat-specific instructions ---\n\nResponse length preference: " + ctx.LENGTH_TEXT[2])
    assert ctx.system_prompt(config, dict(chat, chatSystemPromptEnabled=False, personalityOff=True), project, True) == ""
    assert "About the user" not in ctx.system_prompt(config, chat, project, direct=False)
    assert ctx.agent_instructions(chat, project).startswith("--- Project instructions (Work)")


def test_history_limit_and_variables():
    msgs = [{"role": "user", "content": str(i)} for i in range(10)] + [{"role": "error", "content": "x"}]
    assert [m["content"] for m in ctx.history(msgs, {"contextMessageLimit": 3})] == ["6", "7", "8", "9"]
    assert len(ctx.history(msgs, {"contextMessageLimit": -1})) == 10
    now = dt.datetime(2026, 10, 27, 9, 5)
    assert ctx.expand("{{date}} {{ weekday }} {{time}} {{last_run}} {{other}}", now, "2026-10-26T15:00:00") == \
        "2026-10-27 Tuesday 09:05 2026-10-26 15:00 {{other}}"
    assert ctx.expand("since {{last_run}}", now, None) == "since never"
