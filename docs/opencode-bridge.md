# OpenCode Developer Bridge

The OpenCode Developer Bridge connects KDE AI Chat to a local [OpenCode](https://opencode.ai/) server, transforming the chat widget into an interactive development environment.

## Overview

When enabled, the bridge replaces standard AI provider calls with OpenCode's REST API. All prompts are sent to the local OpenCode server, which executes them using its configured providers, tools, MCP servers, and agents. Responses stream back into the chat widget with structured context items, tool call information, token usage diagnostics, and cost breakdowns.

## Architecture

```
KDE AI Chat (Plasmoid)
       │
       │  HTTP REST API (localhost:4096)
       ▼
OpenCode Server (opencode serve)
       │
       ├── AI Providers (OpenAI, Claude, etc.)
       ├── MCP Servers
       ├── Tool Execution (bash, fetch, etc.)
       └── File System Access
```

## Prerequisites

- [OpenCode](https://opencode.ai/) installed and configured
- Node.js 18+ (OpenCode dependency)

## Setup

### 1. Start the OpenCode Server

You can start the server manually:

```bash
opencode serve --port 4096
```

Or configure KDE AI Chat to auto-start the server (see Settings below).

### 2. Enable the Bridge in Settings

1. Open KDE AI Chat settings (right-click widget → **Configure**).
2. Toggle **OpenCode Mode** on.
3. Set the **OpenCode Server URL** (default: `http://127.0.0.1:4096/v1`).
4. Click **Check Server** to verify connectivity.
5. Select an **OpenCode Provider** and **Model** from the discovered options.
6. Click **Apply**.

### 3. Auto-Start Configuration

Enable **Auto-start OpenCode server** in settings to have the widget launch OpenCode automatically when needed. The default start command is:

```bash
logf="${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log"
nohup opencode serve --port 4096 >"$logf" 2>&1 &
```

You can customize the start and stop commands in the settings panel.

## Usage

### Basic Chat

Once the bridge is active, simply type messages as normal. All messages are routed through OpenCode.

### Slash Commands

In OpenCode mode, the following slash commands are available:

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/version` | Show installed OpenCode version |
| `/session` | Show current session info (remote session ID, server URL) |
| `/schedule` | Create/manage scheduled prompts |

### Interactive Elements

The bridge supports several interactive features:

- **Tool Invocation Context**: When OpenCode executes tools (bash, file operations, etc.), the widget displays them as context items on the assistant message.
- **Permission Requests**: When OpenCode needs permission to execute an action (e.g., running a shell command), interactive allow/deny buttons are rendered in the chat.
- **Question Prompts**: When OpenCode needs clarification, structured multiple-choice questions with custom answer support are displayed.
- **Token & Cost Diagnostics**: Real-time token usage (input, output, reasoning, cache) and cost are shown on assistant message bubbles.

### Session Management

The bridge maintains a mapping between widget chat sessions and OpenCode server sessions. Each chat session gets a corresponding remote session on the OpenCode server. This enables:

- History persistence across widget reloads
- Session export via `/export` (synced from OpenCode server)
- Forking conversation branches

## REST API Reference

The bridge uses the following OpenCode server endpoints:

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `POST` | `/v1/session` | Create a new session |
| `POST` | `/v1/session/{id}/message` | Send a message (sync) |
| `POST` | `/v1/session/{id}/prompt_async` | Send a message (async) |
| `GET` | `/v1/session/{id}/message` | List session messages |
| `GET` | `/v1/event` | SSE event stream |
| `POST` | `/v1/session/{id}/abort` | Abort a running request |
| `POST` | `/v1/session/{id}/permissions/{pid}` | Respond to permission request |
| `GET` | `/config/providers` | List configured providers and models |

### SSE Events

The widget listens to the `/v1/event` SSE stream for real-time updates:

| Event Type | Description |
|------------|-------------|
| `message.updated` | Assistant message metadata updated |
| `message.part.updated` | New text/content part available (streaming) |
| `session.idle` | Request completed |
| `question.asked` | OpenCode needs user input |
| `question.replied` | User's answer received |
| `permission.asked` | OpenCode needs permission for an action |
| `permission.replied` | Permission response received |
| `session.next.step.ended` | Token/cost data available for the step |

## Troubleshooting

### Server Not Reachable

If the widget shows "OpenCode server check failed":

1. Verify OpenCode is installed: `opencode --version`
2. Start the server manually: `opencode serve --port 4096`
3. Check the server URL in settings (default: `http://127.0.0.1:4096/v1`)
4. Check the server log if auto-start is enabled: `cat "${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log"`

### No Providers Discovered

If the server is running but no providers are found:

1. Configure providers in OpenCode: `opencode` (TUI) → configure providers
2. Or edit `~/.config/opencode/config.json` directly
3. Click **Refresh Discovery** in the widget settings panel

### Bridge Not Responding

1. Click **Stop Server** in settings.
2. Click **Start Server** to restart.
3. If issues persist, reset from **Apply** to reinitialize.

## Helper Script

A helper script `opencode-terminal.sh` is included in the repository to launch a terminal with the current OpenCode session pre-filled:

```bash
./opencode-terminal.sh
```

This opens a bash shell with the `opencode --session <id>` command ready on the command line.
