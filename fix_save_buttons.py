import re

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigGeneral.qml", "r") as f:
    content = f.read()

# Change System prompt to Behavior
content = content.replace('name: "System Prompt"', 'name: "Behavior"')
content = content.replace('iconName: "system-run"', 'iconName: "preferences-system-behavior"') # just in case they want a different icon

# Update Save buttons to provide visual feedback
pattern = r'(QQC2\.Button {\s*text: "Save"\s*onClicked: {)(.*?)(}\s*})'
def repl(match):
    start = match.group(1)
    body = match.group(2)
    end = match.group(3)
    
    new_start = start.replace('text: "Save"', 'id: saveBtn\n                    property bool saved: false\n                    text: saved ? "Saved!" : "Save"\n                    icon.name: saved ? "dialog-ok" : "document-save"\n                    onClicked: {')
    new_body = body + """
                        parent.children[2].saved = true;
                        if (!parent.children[2].resetTimer) {
                            var t = Qt.createQmlObject('import QtQuick; Timer { interval: 2000; onTriggered: parent.saved = false }', parent.children[2], "resetTimer");
                            parent.children[2].resetTimer = t;
                        }
                        parent.children[2].resetTimer.start();"""
                        
    # Wait, using parent.children[2] is fragile. It's better to give the button a unique id or just use `this`.
    # But QML allows accessing properties directly if we are in the Button scope!
    # Wait, the `onClicked` scope is the Button. So we can just use `saved = true`.
    
    better_start = start.replace('text: "Save"', 'property bool saved: false\n                    text: saved ? "Saved!" : "Save"\n                    icon.name: saved ? "dialog-ok" : "document-save"\n                    Timer {\n                        id: resetTimer\n                        interval: 2000\n                        onTriggered: parent.saved = false\n                    }\n                    onClicked: {')
    better_body = body + "\n                        saved = true;\n                        resetTimer.start();"
    
    return better_start + better_body + end

new_content = re.sub(pattern, repl, content, flags=re.DOTALL)

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigGeneral.qml", "w") as f:
    f.write(new_content)
