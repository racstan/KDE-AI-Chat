import re

with open("org.kde.plasma.kdeaichat/contents/ui/main.qml", "r") as f:
    content = f.read()

# The buttons block
buttons_regex = r"(\s+PC3\.ToolButton \{\n\s+icon\.name: \"mail-attachment\".*?\n\s+\}\n\n\s+PC3\.ToolButton \{\n\s+icon\.name: \"edit-paste\".*?\n\s+\}\n\n)"

match = re.search(buttons_regex, content, flags=re.DOTALL)
if match:
    buttons_text = match.group(1)
    
    # Remove from original location
    content = content.replace(buttons_text, "")
    
    # Insert after QQC2.TextArea ... }
    # Find the end of QQC2.TextArea
    
    # The end of QQC2.TextArea is followed by "\n\n                            PC3.Button {"
    target = "\n\n                            PC3.Button {"
    content = content.replace(target, "\n" + buttons_text + "                            PC3.Button {")
    
    with open("org.kde.plasma.kdeaichat/contents/ui/main.qml", "w") as f:
        f.write(content)
    print("Replaced successfully")
else:
    print("Could not find match")
