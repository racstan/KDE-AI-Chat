import re

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigGeneral.qml", "r") as f:
    content = f.read()

# Pattern to find API key RowLayouts and add a Save button next to Show/Hide
pattern = r'(RowLayout {\s*Kirigami\.FormData\.label: "[^"]+ key:"\s*visible: page\.providerEnabled\("([^"]+)"\).*?)(QQC2\.Button {\s*id: [a-zA-Z]+KeyShowHide.*?\n\s*})'

def repl(match):
    prefix = match.group(1)
    provider = match.group(2)
    show_hide = match.group(3)
    field_id = provider + "ApiKeyField" if provider != "openai" else "apiKeyField"
    
    save_button = f"""QQC2.Button {{
                    text: "Save"
                    onClicked: {{
                        page.saveKey("{provider}", {field_id}.text);
                        page.refreshIfActiveProvider("{provider}");
                    }}
                }}

                """
    return prefix + save_button + show_hide

new_content = re.sub(pattern, repl, content, flags=re.DOTALL)

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigGeneral.qml", "w") as f:
    f.write(new_content)
