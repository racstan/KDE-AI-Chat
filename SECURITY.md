# Security Policy for KDE AI Chat

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.2.x   | ✅ |
| < 1.2   | ❌ (End of life) |

## Reporting a Vulnerability

If you discover a security vulnerability in KDE AI Chat, please report it by emailing **asthanarachit@gmail.com** or opening a [GitHub Security Advisory](https://github.com/racstan/KDE-AI-Chat/security/advisories).

Do **not** report security vulnerabilities via public GitHub issues.

## API Key Security

KDE AI Chat provides three storage modes for API keys, each with different security properties:

### Mode 1: Session Only (Least Persistent)

- Keys are held only in memory (QML/JavaScript variables).
- **Lost when the widget is unloaded or Plasma is restarted.**
- Suitable for temporary, shared, or public workstations.
- No keys written to disk.

### Mode 2: Plain Config (Default)

- Keys are saved to `~/.config/kdeaichatrc` as plain text.
- **Persists across restarts.**
- Keys are readable by any user/process with access to your home directory.
- Base64-encoded payloads are used when writing keys via shell commands to prevent shell injection (not encryption).

### Mode 3: KWallet (Most Secure)

- Keys are stored in **KDE Wallet** (`kwalletd6`) via DBus.
- Encrypted at rest using the KDE Wallet encryption system.
- Requires wallet unlock to access.
- Keys are stored in a dedicated `KaiChat` folder with prefixed entries: `kai-chat-<provider>-api-key`.
- **Recommended for production use.**

### Security Recommendations

- **Always use KWallet mode** on shared or multi-user systems.
- **Never commit** API keys to version control.
- Use **Session Only mode** on public/demo machines.
- Periodically rotate API keys through your provider's dashboard.

## Configuration File Security

The scheduler data directory (`~/.local/share/kdeaichat/`) has **restricted permissions (`700`)**:

- `schedules.json` is created with **`600`** permissions (owner read/write only).
- Pending trigger files have **`600`** permissions.
- The scheduler lock file has **`600`** permissions.

## Shell Command Safety

All external command invocations use the following protections:

1. **Base64 encoding**: Configuration payloads are base64-encoded when passed through shell commands to prevent bash double-quote stripping and injection.
2. **Single-quote escaping**: User-provided strings are escaped with `shellEscape()` which replaces `'` with `'\''`.
3. **Input sanitization**: The `applyLoadedKey()` function filters out error messages, wallet responses, and non-key strings before setting field values.
4. **DBus filters**: Prevent status and warning messages from KWallet operations from being interpreted as API key values.

## Update & Supply Chain Security

- All releases are built from the public GitHub repository.
- Pre-built `.plasmoid` archives are available on the [KDE Store](https://store.kde.org/p/2360152/) and [GitHub Releases](https://github.com/racstan/KDE-AI-Chat/releases).
- The `install.sh` script installs only files from the local repository — no remote downloads.
- The scheduler daemon is copied from the installed package, not downloaded from the internet.

## Verification

To verify a release build:

```bash
# Clone the tagged release
git checkout v1.2.9
# Build from source
zip -r dist/org.kde.plasma.kdeaichat-v1.2.9.plasmoid org.kde.plasma.kdeaichat \
  -x "*.git*" "*__pycache__*" "*.DS_Store"
```

## Dependencies & Trust

The widget relies on these external tools for specific features:

| Tool | Feature | Risk |
|------|---------|------|
| `pdftotext` (poppler-utils) | PDF reading | Low — well-established system package |
| `pandoc` | Word document reading | Low — well-established system package |
| `qdbus6` / `qdbus` | KWallet access | Low — part of Qt/KDE |
| `wl-paste` / `xclip` | Clipboard access | Low — desktop environment utilities |
| `notify-send` (libnotify) | Desktop notifications | Low — standard Linux desktop tool |

## Scheduler Daemon Security

The scheduler daemon (`kde-ai-scheduler.py`) runs as a **systemd user service**:

- Runs with the **user's privileges** only — no root access.
- Reads schedules from `~/.local/share/kdeaichat/schedules.json`.
- Writes trigger files to `~/.local/share/kdeaichat/pending/`.
- Communicates with the widget via **file-based IPC** (no network sockets).
- Listens for **SIGHUP** to reload configuration — no remote management interface.
- No network-facing ports are opened by the daemon itself.
