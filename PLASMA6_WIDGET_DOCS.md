# KDE Plasma 6 Widget Development Reference

*Sourced from https://develop.kde.org/docs/plasma/widget/ — May 2026*

---

## 1. Key Plasma 6 Rules (things that BREAK widgets)

| Rule | Correct | Wrong |
|------|---------|-------|
| Root element | `PlasmoidItem { }` | `Item { }` |
| Import plasmoid | `import org.kde.plasma.plasmoid` (no version) | `import org.kde.plasma.plasmoid 2.0` |
| Expanded toggle | `root.expanded = !root.expanded` | `plasmoid.expanded = !plasmoid.expanded` |
| PlasmaCore removed | Use `Kirigami` for icons, spacing | `import org.kde.plasma.core as PlasmaCore` |
| API min version | `"X-Plasma-API-Minimum-Version": "6.0"` in metadata.json | Missing this key → widget invisible in Plasma 6 |
| WorkerScript files | Plain JS: `WorkerScript.onMessage = function(msg) {}` at top level | QML-wrapped or with `import QtQuick` |
| IDs in Components | Can't access IDs inside `Component {}` from outside. Use root property refs. | Cross-scope ID access → ReferenceError → blink loop |

---

## 2. Minimal Working Widget Structure

```
org.kde.plasma.mywidget/
├── metadata.json
└── contents/
    └── ui/
        └── main.qml
```

No config or worker needed for basics.

---

## 3. metadata.json (required fields for Plasma 6)

```json
{
    "KPlugin": {
        "Id": "org.kde.plasma.mywidget",
        "Name": "My Widget",
        "Description": "What it does",
        "Icon": "dialog-messages",
        "Category": "Utilities",
        "License": "GPL-2.0+"
    },
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API-Minimum-Version": "6.0"
}
```

**Critical**: `"X-Plasma-API-Minimum-Version": "6.0"` is REQUIRED or Plasma 6 won't show the widget in "Add Widgets".

---

## 4. main.qml — Panel widget with popup (minimal)

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Force compact icon in panel; popup opens on click
    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        id: compactRoot
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.fill: parent
            source: "dialog-messages"
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: 400
        Layout.minimumHeight: 500
        Layout.preferredWidth: 420
        Layout.preferredHeight: 520

        PC3.Label {
            anchors.centerIn: parent
            text: "Hello from Kai Chat!"
        }
    }
}
```

---

## 5. Popup size

Set `Layout.preferredWidth` and `Layout.preferredHeight` in the `fullRepresentation` root Item.

---

## 6. Configuration

To add settings:
1. Add `contents/config/main.xml` with schema
2. Add `contents/config/config.qml` to declare tabs
3. Add `contents/ui/ConfigGeneral.qml` for the settings UI
4. Reference in metadata.json: `"X-Plasma-ConfigurationUI": "ui/ConfigGeneral.qml"`

Access config values: `plasmoid.configuration.myKey`
Write config: `plasmoid.configuration.myKey = "value"`

---

## 7. WorkerScript (for background API calls)

The `.mjs` file must be plain JS — NO QML, NO imports:

```js
// apiWorker.mjs — correct format
WorkerScript.onMessage = function(msg) {
    // handle msg
    WorkerScript.sendMessage({ type: "result", data: "..." })
}

function helperFunction() { ... }
```

In main.qml, put the WorkerScript at ROOT scope (NOT inside a Component):

```qml
PlasmoidItem {
    id: root

    WorkerScript {
        id: apiWorker
        source: "apiWorker.mjs"
        onMessage: function(msg) {
            // handle response
        }
    }

    fullRepresentation: Component {
        // fullRep code here — can call apiWorker.sendMessage() via root
    }
}
```

---

## 8. Cross-scope ID references

Items inside `Component { }` blocks cannot be accessed by ID from parent scope.
Use root-level property refs:

```qml
PlasmoidItem {
    id: root
    property var chatListRef: null   // declared at root

    fullRepresentation: Item {
        ListView {
            id: chatListView
            Component.onCompleted: root.chatListRef = chatListView  // register at root
        }
    }
}

// Now root.chatListRef.positionViewAtEnd() works from anywhere
```

---

## 9. P5Support.DataSource (running shell commands)

```qml
import org.kde.plasma.plasma5support as P5Support

P5Support.DataSource {
    id: execDs
    engine: "executable"
    connectedSources: []
    onNewData: function(sourceName, data) {
        var stdout = data["stdout"] || ""
        var stderr = data["stderr"] || ""
        disconnectSource(sourceName)
    }
}

// To run a command:
execDs.connectedSources.push("echo hello")
```

---

## 10. Install commands

```bash
# Install user-local
kpackagetool6 --install org.kde.plasma.mywidget

# Upgrade existing
kpackagetool6 --upgrade org.kde.plasma.mywidget

# Verify installed
kpackagetool6 --type Plasma/Applet --list
```

---

## 11. Testing without full plasmashell restart

```bash
# Test in a window (fastest)
plasmawindowed org.kde.plasma.kaichat

# Check for QML errors
qmllint contents/ui/main.qml
node --check contents/ui/apiWorker.mjs

# Restart just the shell (slower)
systemctl --user restart plasma-plasmashell.service
```

---

## 12. Debugging flicker/blink loop

A widget that constantly flickers = QML runtime error causing reload loop.

Root causes found in this project:
1. ReferenceError: accessing an ID that lives inside a `Component {}` from outside
2. Extra `}` or `{` making the file unparseable
3. Unescaped `"` inside a QML string literal (e.g. `"text with "quotes" inside"`)
4. WorkerScript file using QML syntax (`import QtQuick`) instead of plain JS
5. Missing import or using removed Plasma 5 API (PlasmaCore, FrameSvgItem)

How to find it:
```bash
journalctl --user -b -f | grep -E "(kaichat|ReferenceError|TypeError|SyntaxError|qml)" 
```
Then click on the widget to trigger the reload and watch the error.

---

## 13. Spacing / sizes (Kirigami)

```qml
import org.kde.kirigami as Kirigami

spacing: Kirigami.Units.smallSpacing   // ~4px
spacing: Kirigami.Units.largeSpacing   // ~16px
width: Kirigami.Units.iconSizes.medium  // 32px
```

---

## 14. Native Configure Window Requirements (KDE docs)

From KDE Plasma widget configuration docs:

---

## 15. Provider Endpoint Notes (Web-Sourced, May 2026)

These references were collected while implementing multi-provider defaults.

### OpenAI-compatible style endpoints

- Groq OpenAI compatibility docs: use OpenAI SDK with base URL `https://api.groq.com/openai/v1` and `GROQ_API_KEY`.
- OpenRouter API overview: chat completions endpoint is `POST /api/v1/chat/completions` at `https://openrouter.ai/api/v1` with optional headers like `HTTP-Referer` and `X-OpenRouter-Title`.
- Mistral API reference: chat endpoint available at `POST /v1/chat/completions` on `https://api.mistral.ai/v1`.
- Hugging Face Inference Providers chat completion docs: OpenAI-compatible router base URL `https://router.huggingface.co/v1` with bearer token auth.
- NVIDIA NIM docs reference model APIs under NIM endpoints; current widget defaults use `https://integrate.api.nvidia.com/v1` for OpenAI-compatible chat-style routing.
- xAI/Grok: configured as OpenAI-compatible pattern with base `https://api.x.ai/v1`.

### Cloudflare Workers AI note

- Cloudflare docs index confirms Workers AI REST API under Cloudflare API resources. Widget default is configured for account-scoped endpoint style:
    `https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1`

If provider behavior differs per account/product, adjust `Base URL` in Configure.

---

## 16. KWallet CLI Notes (Validated Locally)

Environment checks in this workspace:

- `kwallet-query` exists in PATH (`/usr/bin/kwallet-query`)
- available wallets reported by `kwalletd6`: `MyPasswords`, `kdewallet`

Useful commands:

```bash
# list entries
kwallet-query -f KaiChat -l kdewallet

# write password (reads value from stdin)
printf '%s' 'SECRET' | kwallet-query -f KaiChat -w kai-chat-openai-api-key kdewallet

# read password
kwallet-query -f KaiChat -r kai-chat-openai-api-key kdewallet
```

This plasmoid now uses `kwallet-query` in Configure for Save/Load key actions.

---

## 17. Wallet Reset Notes (May 2026)

Actions taken in this workspace:

- Deleted unknown wallet `MyPasswords` using:

```bash
qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.deleteWallet MyPasswords
```

- Deleted stale `KaiChatWallet` and kept widget default wallet name as `KaiChatWallet` for a clean start.

Important limitation:

- KWallet master password cannot be programmatically forced to a literal value through `kwallet-query` or the exposed DBus API in a non-interactive way.
- Creating/changing wallet master password is handled by KDE wallet UI prompts.

Practical setup path:

1. Open `kwalletmanager5`.
2. Create wallet `KaiChatWallet`.
3. Set password to `password`.
4. Use Kai Chat Configure -> KWallet save/load actions.

---

## 18. UI/UX Adjustments (May 2026)

- History expand/collapse toggle moved to top-left beside centered chat title.
- Chat session rename/delete controls are attached to each history row.
- History rows now show last modified timestamp.
- Messages display send/receive time and assistant model tag.
- Input bar now has bounded height with internal scrolling; send button position is stable.
- Added docs page for About/website target: `docs/ABOUT.html`.

1. `contents/config/main.xml` defines serialized config keys.
2. `contents/config/config.qml` defines configuration tabs (`ConfigModel`, `ConfigCategory`).
3. `contents/ui/ConfigGeneral.qml` (and other pages) provide UI fields.
4. Each UI field must expose `cfg_` aliases (e.g. `property alias cfg_apiKey: apiKeyField.text`).

Key point for this project: without `contents/config/config.qml`, the right-click Configure window can show only default pages (like shortcuts/about) and miss custom settings.

Reference: https://develop.kde.org/docs/plasma/widget/configuration/

---

## 15. Secret Service / KWallet Bridge via `secret-tool`

`secret-tool` works with providers implementing the Freedesktop Secret Service API (`org.freedesktop.secrets`), including KDE wallet integrations that expose Secret Service.

Important commands:

```bash
# store
printf '%s' "$KEY" | secret-tool store --label='Kai Chat OpenAI Key' service kai-chat-openai account default

# lookup
secret-tool lookup service kai-chat-openai account default

# clear
secret-tool clear service kai-chat-openai account default

# search metadata
secret-tool search --all service kai-chat-openai
```

Behavior notes:
- Items are matched by attribute key/value pairs.
- Re-running `store` with same attributes updates existing item.
- `lookup` returns first unlocked matching item.

Reference:
- https://manpages.ubuntu.com/manpages/jammy/man1/secret-tool.1.html
- https://wiki.archlinux.org/title/GNOME/Keyring
