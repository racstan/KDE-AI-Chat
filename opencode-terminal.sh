#!/bin/bash
SESSION_FILE="/home/home/Programming/rachitkdeaichat/.opencode-session"
if [ -f "$SESSION_FILE" ]; then
    SID=$(cat "$SESSION_FILE")
else
    SID=""
fi

if [ -n "$SID" ]; then
    CMD="opencode --session $SID"
else
    CMD="opencode"
fi

# Start interactive bash with the command prefilled on the command line without executing it
exec bash --rcfile <(echo "[ -f ~/.bashrc ] && source ~/.bashrc; history -s \"$CMD\"; bind '\"\\e[0n\": \"$CMD\"'; echo -ne \"\\e[5n\"")
