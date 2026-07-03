import re

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigSystemPrompt.qml", "r") as f:
    content = f.read()

# Replace Layout.minimumHeight/maximumHeight with Layout.preferredHeight and explicit height
# To strictly fix the box size
def repl_scroll(m):
    return m.group(0).replace(
        "Layout.minimumHeight: Kirigami.Units.gridUnit * 6\n            Layout.maximumHeight: Kirigami.Units.gridUnit * 6", 
        "Layout.preferredHeight: Kirigami.Units.gridUnit * 6"
    ).replace(
        "Layout.minimumHeight: Kirigami.Units.gridUnit * 10\n            Layout.maximumHeight: Kirigami.Units.gridUnit * 10", 
        "Layout.preferredHeight: Kirigami.Units.gridUnit * 10"
    )

content = re.sub(r'QQC2\.ScrollView \{.*?\}', repl_scroll, content, flags=re.DOTALL)

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigSystemPrompt.qml", "w") as f:
    f.write(content)
