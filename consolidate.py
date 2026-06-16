#!/usr/bin/env python3
"""
Consolidate the modular KDE AI Chat widget QML files into a monolithic main.qml.
"""

import re

UI_DIR = "/home/home/Programming/rachitkdeaichat/org.kde.plasma.kdeaichat/contents/ui"

def read(path):
    with open(path, "r") as f:
        return f.read()

def write(path, content):
    with open(path, "w") as f:
        f.write(content)

# ─── Read source files ───────────────────────────────────────────────────────
main_qml = read(f"{UI_DIR}/main.qml")
full_rep = read(f"{UI_DIR}/FullRepresentation.qml")
session_sidebar = read(f"{UI_DIR}/SessionSidebar.qml")
message_content = read(f"{UI_DIR}/MessageContent.qml")

# ─── Step 1: Extract FullRepresentation body ─────────────────────────────────
# FullRepresentation.qml structure:
#   import ...  (lines 1-11)
#   (blank line)
#       Item {      <- this is the outer wrapper, indented with 4 spaces
#         id: fullRep
#         ...content...
#       }           <- closing brace
#
# We want everything INSIDE the Item, de-indented by 4 spaces.

fr_lines = full_rep.split("\n")

# Find the start of "    Item {" 
outer_item_idx = -1
for i, line in enumerate(fr_lines):
    if re.match(r'^\s+Item\s*\{', line):
        outer_item_idx = i
        break

assert outer_item_idx >= 0, "Could not find outer Item { in FullRepresentation.qml"

# Get the lines inside the Item (skip the "    Item {" line itself)
# And skip the very last "}" (and any trailing blank lines)
inner_lines = fr_lines[outer_item_idx + 1:]

# Remove trailing blanks and last "}"
while inner_lines and inner_lines[-1].strip() == "":
    inner_lines.pop()
if inner_lines and inner_lines[-1].strip() == "}":
    inner_lines.pop()

# De-indent by 4 spaces (the outer Item adds 4 spaces)
def dedent4(lines):
    result = []
    for line in lines:
        if line.startswith("    "):
            result.append(line[4:])
        else:
            result.append(line)
    return result

inner_lines = dedent4(inner_lines)
fr_body = "\n".join(inner_lines)

print(f"FullRepresentation body extracted: {len(inner_lines)} lines")

# ─── Step 2: Inline SessionSidebar ───────────────────────────────────────────
# In FullRepresentation (after de-indent by 4), the pattern is:
#
#             Rectangle {
#                 radius: 8
#                 color: Kirigami.Theme.alternateBackgroundColor
#
#                 SessionSidebar {
#                     id: sessionSidebarInstance
#                     anchors.fill: parent
#                     anchors.margins: Kirigami.Units.smallSpacing
#                     chatRoot: root
#                     Component.onCompleted: {
#                         root.sessionsSidebarRef = sessionSidebarInstance;
#                     }
#                 }
#
#             }
#
# We need to replace this whole block with just the inlined SessionSidebar body.

# Find the exact block
ss_usage_start = fr_body.find("            Rectangle {\n                radius: 8\n                color: Kirigami.Theme.alternateBackgroundColor\n\n                SessionSidebar {")
if ss_usage_start < 0:
    print("ERROR: Could not find SessionSidebar usage block in fr_body")
    print("Searching with relaxed pattern...")
    ss_usage_start = fr_body.find("SessionSidebar {")
    if ss_usage_start >= 0:
        print(f"Found 'SessionSidebar {{' at offset {ss_usage_start}")
        print(repr(fr_body[max(0,ss_usage_start-200):ss_usage_start+100]))
    exit(1)

# Find the end of this block: we need to find the closing "}" of the outer Rectangle
# Count braces from ss_usage_start
pos = ss_usage_start
depth = 0
in_block = False
block_end = -1
for i in range(pos, len(fr_body)):
    c = fr_body[i]
    if c == '{':
        depth += 1
        in_block = True
    elif c == '}':
        depth -= 1
        if in_block and depth == 0:
            block_end = i + 1
            break

# Skip trailing newline
while block_end < len(fr_body) and fr_body[block_end] in ('\n', '\r'):
    block_end += 1

old_ss_block = fr_body[ss_usage_start:block_end]
print(f"Found SessionSidebar block ({len(old_ss_block)} chars)")

# Parse SessionSidebar.qml body (the file IS the Rectangle)
ss_lines_raw = session_sidebar.split("\n")
# Skip file header (doc comments + imports)
ss_body_start = 0
for i, line in enumerate(ss_lines_raw):
    stripped = line.strip()
    if stripped.startswith("/**") or stripped.startswith(" *") or stripped.startswith("*/"):
        continue
    if stripped.startswith("import ") or stripped == "":
        continue
    ss_body_start = i
    break

ss_body_lines = ss_lines_raw[ss_body_start:]
# Trim trailing blanks
while ss_body_lines and ss_body_lines[-1].strip() == "":
    ss_body_lines.pop()
ss_body = "\n".join(ss_body_lines)

# Adapt references
ss_body = ss_body.replace("sidebarRoot.chatRoot", "root")
ss_body = ss_body.replace("id: sidebarRoot", "id: inlinedSidebar")
ss_body = ss_body.replace("sidebarRoot.", "inlinedSidebar.")

# Add registration + anchors after id line
ss_body = ss_body.replace(
    "    id: inlinedSidebar\n",
    "    id: inlinedSidebar\n    anchors.fill: parent\n    anchors.margins: Kirigami.Units.smallSpacing\n    Component.onCompleted: { root.sessionsSidebarRef = inlinedSidebar; }\n"
)

# Indent to match the surrounding context (12 spaces for the SessionSidebar rectangle,
# which was at the same level as the removed outer Rectangle)
def indent_block(text, spaces):
    lines = text.split("\n")
    result = []
    for line in lines:
        if line.strip():
            result.append(" " * spaces + line)
        else:
            result.append("")
    return "\n".join(result)

ss_body_indented = indent_block(ss_body, 12)

fr_body = fr_body[:ss_usage_start] + ss_body_indented + "\n" + fr_body[block_end:]

if "SessionSidebar" in fr_body:
    print("WARNING: SessionSidebar reference still found in fr_body")
else:
    print("✓ SessionSidebar successfully inlined")

# ─── Step 3: Inline MessageContent ───────────────────────────────────────────
# Find and replace:
#                                                 MessageContent {
#                                                     messageData: modelData
#                                                     messageIndex: originalIndex
#                                                     chatRoot: root
#                                                 }
mc_usage_start = fr_body.find("MessageContent {")
if mc_usage_start < 0:
    print("WARNING: MessageContent not found (may already be inlined)")
else:
    # Find end of this block
    pos = mc_usage_start
    depth = 0
    in_block = False
    mc_block_end = -1
    for i in range(pos, len(fr_body)):
        c = fr_body[i]
        if c == '{':
            depth += 1
            in_block = True
        elif c == '}':
            depth -= 1
            if in_block and depth == 0:
                mc_block_end = i + 1
                break

    # Find start of line for proper indentation
    line_start = fr_body.rfind("\n", 0, mc_usage_start) + 1
    mc_indent = len(fr_body[line_start:mc_usage_start]) - len(fr_body[line_start:mc_usage_start].lstrip())

    old_mc_block = fr_body[mc_usage_start:mc_block_end]
    print(f"Found MessageContent block ({len(old_mc_block)} chars), indent={mc_indent}")

    # Parse MessageContent.qml
    mc_lines_raw = message_content.split("\n")
    mc_body_start = 0
    for i, line in enumerate(mc_lines_raw):
        if line.strip().startswith("import ") or line.strip() == "":
            continue
        mc_body_start = i
        break

    mc_body_lines = mc_lines_raw[mc_body_start:]
    while mc_body_lines and mc_body_lines[-1].strip() == "":
        mc_body_lines.pop()
    mc_body = "\n".join(mc_body_lines)

    # Adapt references - replace the property-based access with direct vars
    mc_body = mc_body.replace("contentRoot.messageData", "modelData")
    mc_body = mc_body.replace("contentRoot.chatRoot", "root")
    mc_body = mc_body.replace("contentRoot.messageIndex", "originalIndex")

    # Remove internal property declarations (they come from the component interface)
    mc_body = re.sub(r'\n    property var messageData\n', '\n', mc_body)
    mc_body = re.sub(r'\n    property var chatRoot\n', '\n', mc_body)
    mc_body = re.sub(r'\n    property int messageIndex: -1\n', '\n', mc_body)

    # Replace "messageData" references now point to modelData (delegate property)
    mc_body = mc_body.replace("messageData", "modelData")

    # The id and self-references
    mc_body = mc_body.replace("id: contentRoot", "id: inlinedMsgContent")
    mc_body = mc_body.replace("contentRoot.", "inlinedMsgContent.")

    # Fix the visible binding (which may reference old property names)
    old_vis = 'visible: modelData && (root && root.editingMessageIndex !== originalIndex || modelData.role === "error" || modelData.isImage === true)'
    new_vis = 'visible: modelData && (root.editingMessageIndex !== originalIndex || modelData.role === "error" || modelData.isImage === true)'
    mc_body = mc_body.replace(old_vis, new_vis)
    
    # Also fix the original form if present
    old_vis2 = 'visible: modelData && (chatRoot && chatRoot.editingMessageIndex !== messageIndex || modelData.role === "error" || modelData.isImage === true)'
    mc_body = mc_body.replace(old_vis2, new_vis)

    # Indent to match surrounding
    mc_body_indented = indent_block(mc_body, mc_indent)

    # Find the start of line before mc_usage_start to do proper replacement
    fr_body = fr_body[:line_start] + mc_body_indented + fr_body[mc_block_end:]

    if "MessageContent" in fr_body:
        print("WARNING: MessageContent reference still found in fr_body")
    else:
        print("✓ MessageContent successfully inlined")

# ─── Step 4: Move requestDeleteSession to root ────────────────────────────────
# The function was on fullRep, but SessionSidebar (now inlined) calls root.requestDeleteSession
# We need to add this function to root in main.qml.
# The function body: open confirm dialog or directly delete.
# The dialog (deleteChatConfirmDialog) is inside fullRepresentation, so root can't call it directly.
# Solution: add a root.requestDeleteSession that opens the dialog via fullRepresentation reference.
# Actually, since it's all inlined, we can just leave it in the Item and it refers to the
# inlinedSidebar calling root.requestDeleteSession... But root doesn't have it.
# 
# Best solution: find the function in fr_body and keep it there.
# The inlined sidebar calls "root.requestDeleteSession" -- this won't work since
# the function is on the Item not root.
# Fix: rename the call in the inlined sidebar to use a local reference.
# Since the sidebar is now inside the FullRepresentation Item, we can reference
# the Item's function directly. But the Item is anonymous now (id: fullRep was removed).
# 
# Simplest fix: add requestDeleteSession as a function on root in main.qml,
# and have it call the dialog. The dialog is inside fullRepresentation item,
# so we need a property reference to it, or we use a root-level function that
# sets a flag/signal.
# 
# Cleanest approach for monolithic: rename root.requestDeleteSession calls in
# the inlined sidebar to call the function that's defined on the Item directly.
# Give the fullRepresentation Item an id: fullRep, and call fullRep.requestDeleteSession.

# The fr_body already contains "    id: fullRep" (de-indented from the original Item).
# Just ensure requestDeleteSession calls from the inlined sidebar use fullRep.
fr_body = fr_body.replace("root.requestDeleteSession(", "fullRep.requestDeleteSession(")
print("✓ Updated requestDeleteSession calls to use fullRep")

# ─── Step 5: Build the new main.qml ──────────────────────────────────────────
# Remove alias declarations (now dead - ids are direct children of root)
alias_block = """    property alias soundDs: soundDs
    property alias clipboardDs: clipboardDs
    property alias schedulerDs: schedulerDs
    property alias openCodeReconnectTimer: openCodeReconnectTimer
    property alias persistSessionsDebounce: persistSessionsDebounce
    property alias deferSaveStateTimer: deferSaveStateTimer
    property alias streamingBatchTimer: streamingBatchTimer
    property alias openCodeIdleKillTimer: openCodeIdleKillTimer
    property alias openCodeStartPollTimer: openCodeStartPollTimer
    property alias schedulerPollTimer: schedulerPollTimer
    property alias autoStartOpenCodeTimer: autoStartOpenCodeTimer
    property alias opencodeServerDs: opencodeServerDs
    property alias fileReaderDs: fileReaderDs
    property alias customStorageDs: customStorageDs
    property alias fileDialog: kaiAttachFileDialog
    property alias exportFileDialog: kaiExportChatFileDialog
    property alias clipboardHelper: clipboardHelper
    property alias kwalletStartupDs: kwalletStartupDs
    property alias opencodeTerminalDs: opencodeTerminalDs
    property alias openCodePollTimer: openCodePollTimer
    property alias voiceDs: voiceDs
    property alias sendMessageDelayTimer: sendMessageDelayTimer"""

if alias_block in main_qml:
    main_qml = main_qml.replace(alias_block, "    // DataSources and timers are direct children of root (monolithic)")
    print("✓ Removed alias property block")
else:
    print("WARNING: Could not find alias block to remove")

# Replace the fullRepresentation declaration
old_full_rep_call = "    fullRepresentation: FullRepresentation {\n        id: fullRepresentation\n    }"
new_full_rep_block = "    fullRepresentation: Item {\n" + fr_body + "\n    }"

if old_full_rep_call in main_qml:
    main_qml = main_qml.replace(old_full_rep_call, new_full_rep_block)
    print("✓ Replaced fullRepresentation: FullRepresentation { } with inlined Item")
else:
    print("ERROR: Could not find fullRepresentation call to replace")
    exit(1)

# Fix the old comment
old_comment = "// LINKAGE RELATIONSHIPS:\n// - main.qml: The root entrypoint PlasmoidItem.\n// - Linked to MainDataSources.qml (instantiated as 'dataSources' and exposed via property aliases):\n//   Holds all the external process command execution DataSources, Timers, and File Dialogs to keep main.qml under 1000 lines.\n//   It takes a reference to 'root' (this) to read config and update state.\n// - Linked to ChatEngine.js (imported as MainDatabase):\n//   Contains ALL application logic — session, network, streaming, schedule, and voice functions."
new_comment = "// MONOLITHIC ARCHITECTURE (v1.2.9 style):\n// - main.qml: Single root PlasmoidItem containing all UI, DataSources, Timers, and Dialogs.\n//   (Previously modular: FullRepresentation.qml, SessionSidebar.qml, MessageContent.qml,\n//    MainDataSources.qml — all merged here for performance and simplicity.)\n// - Linked to ChatEngine.js:\n//   Contains ALL application logic — session, network, streaming, schedule, and voice functions."
if old_comment in main_qml:
    main_qml = main_qml.replace(old_comment, new_comment)
    print("✓ Updated architecture comment")

# Write output
output_path = f"{UI_DIR}/main.qml"
write(output_path, main_qml)
line_count = len(main_qml.split("\n"))
print(f"\n✓ Written new monolithic main.qml ({line_count} lines, {len(main_qml)} bytes)")
print("\nNext: delete FullRepresentation.qml, SessionSidebar.qml, MessageContent.qml, MainDataSources.qml")
