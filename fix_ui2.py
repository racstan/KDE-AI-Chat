import re

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigSystemPrompt.qml", "r") as f:
    content = f.read()

content = content.replace(
    "Layout.preferredHeight: Kirigami.Units.gridUnit * 6",
    "Layout.preferredHeight: Kirigami.Units.gridUnit * 6\n            implicitHeight: Kirigami.Units.gridUnit * 6"
).replace(
    "Layout.preferredHeight: Kirigami.Units.gridUnit * 10",
    "Layout.preferredHeight: Kirigami.Units.gridUnit * 10\n            implicitHeight: Kirigami.Units.gridUnit * 10"
)

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigSystemPrompt.qml", "w") as f:
    f.write(content)
