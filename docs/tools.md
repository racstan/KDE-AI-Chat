# Tools in direct chats

In a **direct** chat the AI can use tools: tools from your own **MCP servers**, a **web search**, and **reading a web page**. You set them up in **Settings → Tools**. OpenCode and Pi chats have their own tools and don't use these.

**Every tool call waits for you.** The chat shows what the AI wants to run and with which input, with three buttons:

- **Allow** runs it this once;
- **Always allow** runs it now and from then on without asking (for that one tool, in every chat);
- **Reject** tells the AI it may not.

Settings → Tools lists the tools you always allow; **Ask again for all tools** clears the list. Scheduled runs never get tools.

## MCP servers

[MCP](https://modelcontextprotocol.io/) servers are small programs that give an AI tools (files, calendars, databases, ...). Paste them in the common `mcpServers` format, the same one Claude Desktop, VS Code and others use:

```json
{
  "mcpServers": {
    "files": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/me/Documents"]
    },
    "remote-example": {
      "url": "https://mcp.example.com/mcp",
      "headers": {"Authorization": "Bearer ..."}
    }
  }
}
```

- A server with `command` runs on your computer (`args`, `env` and `cwd` are optional). It starts when a direct chat first needs the tool list and stops after ten minutes without use.
- A server with `url` is a remote one (Streamable HTTP).
- **Check servers** starts them and lists their tools, or says what went wrong.

The AI sees each tool as `<server>__<tool>`, for example `files__read_file`.

**Headers are stored in the widget's settings file**, not in KWallet. Use a remote server's token only if you are fine with that file holding it.

## Web search

Choose where searches go:

| Search | What you need |
| :--- | :--- |
| **SearXNG** | The address of a SearXNG server (your own, or one you trust) with the JSON format turned on. |
| **Brave Search** | A Brave Search API key. |
| **Tavily** | A Tavily API key. |

Keys are kept in KWallet, in the **KDEAIChat-tools** folder. The widget itself never reads them back; only the tool process does, when a search runs.

## Reading a web page

`fetch_url` downloads one page and gives the AI its readable text (at most about 50,000 characters). It only connects to public addresses: links to your computer or your home network, or redirects that lead there, are refused.

## How it works

The tools run in a small helper process on your computer (`tool_bridge_server.py`). It listens only on `127.0.0.1`, answers only the widget (a random token, stored in a file only you can read), and exits after ten minutes without use. Its log is `~/.local/share/kdeaichat/tool-bridge.log`.
