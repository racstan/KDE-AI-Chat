import re

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigGeneral.qml", "r") as f:
    content = f.read()

# Pattern to find the corrupted save buttons
# We know they start with QQC2.Button { \n property bool saved: false
# and end with \n                        saved = true;\n                        resetTimer.start();}\n                }
pattern = r'(QQC2\.Button \{\s*property bool saved: false.*?resetTimer\.start\(\);\}\s*\})'

providers = ["openai", "anthropic", "groq", "deepseek", "minimax", "fireworks", "google", "openrouter", "mistral", "cloudflare", "nvidia", "huggingface", "xai", "litellm"]
fields = {
    "openai": "apiKeyField.text",
    "anthropic": "anthropicApiKeyField.text",
    "groq": "groqApiKeyField.text",
    "deepseek": "deepseekApiKeyField.text",
    "minimax": "minimaxApiKeyField.text",
    "fireworks": "fireworksApiKeyField.text",
    "google": "googleApiKeyField.text",
    "openrouter": "openrouterApiKeyField.text",
    "mistral": "mistralApiKeyField.text",
    "cloudflare": "cloudflareApiKeyField.text",
    "nvidia": "nvidiaApiKeyField.text",
    "huggingface": "huggingfaceApiKeyField.text",
    "xai": "xaiApiKeyField.text",
    "litellm": "litellmApiKeyField.text",
}

def repl(match):
    # Find which provider this button is for by looking for page.saveKey("provider",
    s = match.group(0)
    provider_match = re.search(r'page\.saveKey\("([^"]+)"', s)
    if not provider_match:
        return s # Fallback
    
    provider = provider_match.group(1)
    field = fields[provider]
    
    timer_id = provider + "SaveTimer"
    
    clean_button = f"""QQC2.Button {{
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {{
                        id: {timer_id}
                        interval: 2000
                        onTriggered: parent.saved = false
                    }}
                    
                    onClicked: {{
                        page.saveKey("{provider}", {field});
                        page.refreshIfActiveProvider("{provider}");
                        saved = true;
                        {timer_id}.start();
                    }}
                }}"""
    return clean_button

new_content = re.sub(pattern, repl, content, flags=re.DOTALL)

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigGeneral.qml", "w") as f:
    f.write(new_content)
