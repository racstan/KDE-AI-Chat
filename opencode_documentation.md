# OpenCode CLI & API Documentation Reference

## Overview
OpenCode is an open-source, provider-agnostic AI coding agent built with a client/server architecture. It provides:
1. A powerful terminal user interface (TUI) and command-line interface (CLI).
2. A REST API server for external clients/widgets (such as KDE AI Chat).
3. Tool integration like `bash` execution, `fetch` HTTP client, and `sourcegraph` code search.
4. Model Context Protocol (MCP) server support and Language Server Protocol (LSP) clients.

---

## 1. CLI Commands & Options

### Startup options:
* `opencode` - Launch interactive terminal user interface (TUI).
* `opencode -d` - Run with debug logging enabled.
* `opencode -c <dir>` - Specify custom project working directory.
* `opencode serve --port <port>` - Start the client/server REST API endpoint (defaults to 4096).

### Inline Execution options:
* `opencode -p <prompt>` - Run a non-interactive prompt.
* `opencode -p <prompt> -f json` - Run prompt and request JSON format output.
* `opencode -q` - Run in quiet mode (minimal decoration).
* `opencode -h` or `opencode --help` - Show help.
* `opencode -v` or `opencode --version` - Show version.

---

## 2. API & Built-in Commands

When using the `/` command in OpenCode mode, the following commands are matched:
* `/help` - Show available commands & help interface.
* `/models` - List all active and available AI models.
* `/providers` - Manage and inspect AI providers and credentials.
* `/stats` - Show comprehensive token usage, efficiency, and cost statistics.
* `/session` - Manage session IDs, active states, and context lists.
* `/agent` - Manage running agents and specify target models.
* `/plugin` - Manage, install, or update plugins and extension configurations.
* `/db` - Launch database tools, explore schemas, and execute queries.
* `/mcp` - Manage MCP (Model Context Protocol) servers.
* `/export` - Export current session history and metadata as JSON.
* `/import` - Import a past session history JSON file.
* `/pr` - Fetch GitHub pull request branch contents and run OpenCode analyze/diff.

---

## 3. Configuration Structure (`~/.config/opencode/config.json`)

```json
{
  "data": {
    "directory": ".opencode"
  },
  "providers": {
    "openai": {
      "apiKey": "your-api-key",
      "disabled": false
    },
    "anthropic": {
      "apiKey": "your-api-key",
      "disabled": false
    },
    "copilot": {
      "disabled": false
    },
    "groq": {
      "apiKey": "your-api-key",
      "disabled": false
    },
    "openrouter": {
      "apiKey": "your-api-key",
      "disabled": false
    }
  },
  "agents": {
    "coder": {
      "model": "claude-3.7-sonnet",
      "maxTokens": 5000
    },
    "task": {
      "model": "claude-3.7-sonnet",
      "maxTokens": 5000
    },
    "title": {
      "model": "claude-3.7-sonnet",
      "maxTokens": 80
    }
  },
  "shell": {
    "path": "/bin/bash",
    "args": ["-l"]
  },
  "mcpServers": {
    "example": {
      "type": "stdio",
      "command": "path/to/mcp-server",
      "env": [],
      "args": []
    }
  },
  "lsp": {
    "go": {
      "disabled": false,
      "command": "gopls"
    }
  },
  "debug": false,
  "debugLSP": false,
  "autoCompact": true
}
```

---

## 4. Environment Variables
* `LOCAL_ENDPOINT=http://localhost:1235/v1` - Override self-hosted provider API endpoint.
