"""Model variants: tests/js/variants.test.js in node, `pi --list-models` parsing, and the
guard against model ids or level lists written into the provider code."""
import os
import re
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
UI = os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI)

from kdeaichat import pi_models  # noqa: E402


def test_variants_in_node():
    script = os.path.join(os.path.dirname(__file__), "js", "variants.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr


PI_TABLE = """provider      model                 context  max-out  thinking  images
openai-codex  gpt-5.4               272K     128K     yes       yes
openai-codex  gpt-4o-mini           128K     16K      no        yes
ollama        qwen3:8b              40K      8K       yes       no
ollama        llama3.2              128K     8K       no        no
"""


def test_pi_models_marks_the_thinking_models():
    providers = pi_models.parse_models(PI_TABLE)
    assert [p["id"] for p in providers] == ["openai-codex", "ollama"]
    assert providers[0]["models"] == ["gpt-5.4", "gpt-4o-mini"]
    assert providers[0]["thinking"] == ["gpt-5.4"]
    assert providers[1]["thinking"] == ["qwen3:8b"]


def test_pi_models_without_a_thinking_column_marks_none():
    providers = pi_models.parse_models("provider model context\nx m1 1K\n")
    assert providers == [{"id": "x", "models": ["m1"], "thinking": []}]
    assert pi_models.parse_models("") == []


# --- Nothing hardcoded per provider or model -------------------------------------------------

# Files that decide what is sent to a provider. A variant picker must come from what the
# source reports; these files must not know any model's id or any effort list.
PROVIDER_CODE = ("ProviderService.js", "ProviderCheck.js", "ProviderVariants.js", "Variants.js",
                 os.path.join("backends", "DirectBackend.js"), os.path.join("backends", "OpenCodeCatalog.js"))

# A model id written as a string literal: a family name followed by a version ("gpt-5",
# "claude-3", "llama3.2", "qwen3"), or "vendor/model". Provider NAMES ("Google Gemini",
# "llama.cpp server") have no version and are not model ids.
FAMILY_ID = re.compile(r"""["'][^"']*\b(gpt|claude|gemini|llama|qwen|mistral|mixtral|deepseek|grok|nemotron|kimi|glm|minimax|sonnet|opus|haiku|o[134])[-_.:]?[0-9][^"']*["']""", re.I)
VENDOR_ID = re.compile(r"""["'][a-z0-9_.-]+/[a-z0-9_.:-]+["']""", re.I)
# Two or more effort names close together in one line: a hardcoded level list.
EFFORT = r"\b(minimal|low|medium|high|xhigh|max)\b"
EFFORT_LIST = re.compile(EFFORT + r"[^\n]{0,12}" + EFFORT, re.I)


def _code_lines(name):
    """(number, code) of a source file's lines, with comments left out."""
    with open(os.path.join(UI, name), encoding="utf-8") as f:
        lines = f.read().splitlines()
    out = []
    in_block = False
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if in_block:
            in_block = "*/" not in stripped
            continue
        if stripped.startswith("/*"):
            in_block = "*/" not in stripped
            continue
        if stripped.startswith("//"):
            continue
        out.append((number, line))
    return out


# What may stay, and why. Anything else that looks like a model id or a level list is a failure:
# a variant picker has to come from what the source reports (a provider's /models list, the
# OpenCode catalogue, `pi --list-models`), never from a list in the code.
ALLOWED = (
    # The OpenRouter preset's default model is the router's own id, a PRESETS default.
    ("ProviderService.js", '"model": "openrouter/auto"'),
    # MIME types are not model ids.
    ("*", "\"application/json\""),
    # The old OpenAI completion-only families the chat-model filter hides (not variants).
    ("ProviderCheck.js", "gpt-3.5-turbo-instruct"),
    ("ProviderCheck.js", "davinci"),
)


def _allowed(name, code):
    return any(file in ("*", os.path.basename(name)) and fragment in code for file, fragment in ALLOWED)


def test_provider_code_has_no_model_ids_or_effort_lists():
    problems = []
    for name in PROVIDER_CODE:
        for number, code in _code_lines(name):
            if _allowed(name, code):
                continue
            if FAMILY_ID.search(code) or VENDOR_ID.search(code):
                problems.append("%s:%d model id? %s" % (name, number, code.strip()))
            if EFFORT_LIST.search(code):
                problems.append("%s:%d effort list? %s" % (name, number, code.strip()))
    assert not problems, "hardcoded model ids / variant lists in provider code:\n" + "\n".join(problems)


def test_the_guard_catches_what_it_is_for():
    assert FAMILY_ID.search('var m = "gpt-5";') and FAMILY_ID.search("'claude-3-opus'") and FAMILY_ID.search('"llama3.2:3b"')
    assert VENDOR_ID.search('x = "openai/gpt-5"')
    assert EFFORT_LIST.search('var levels = ["low", "medium", "high"];') and EFFORT_LIST.search('{low: 1, high: 2}')
    assert not FAMILY_ID.search('"name": "Google Gemini"') and not FAMILY_ID.search('"llama.cpp server (local)"')
    assert not EFFORT_LIST.search('var effort = "high";')


def test_pi_levels_have_one_copy_in_the_widget_and_the_bridge_validates_the_same_ones():
    """Pi's own vocabulary lives in EffectiveConfig.js (PI_THINKING_LEVELS) and, for validation,
    in the bridge (THINKING). Nothing else in the widget lists the levels."""
    levels = re.compile(r'"minimal"\s*,\s*"low"\s*,\s*"medium"')
    owners = []
    for directory, _, files in os.walk(UI):
        for name in files:
            if name.endswith((".js", ".qml", ".py")):
                with open(os.path.join(directory, name), encoding="utf-8") as f:
                    if levels.search(f.read()):
                        owners.append(name)
    assert sorted(owners) == ["EffectiveConfig.js", "pi_bridge_server.py"], owners
