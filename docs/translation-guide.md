# Translation Guide

KDE AI Chat supports **11 languages** through a lightweight JavaScript-based translation system. This guide explains how to add a new language or update an existing translation.

## How It Works

Translations use a simple key-value dictionary system defined in `contents/ui/translations_*.js` files. The translation engine in `contents/ui/translations.js` loads all language files and provides a `translate()` function used throughout the UI.

## Supported Languages

| Code | Language | File |
|------|----------|------|
| `en` | English | Built-in (fallback) |
| `ar` | Arabic | `translations_ar.js` |
| `zh` | Chinese | `translations_zh.js` |
| `fr` | French | `translations_fr.js` |
| `de` | German | `translations_de.js` |
| `it` | Italian | `translations_it.js` |
| `ja` | Japanese | `translations_ja.js` |
| `pt` | Portuguese | `translations_pt.js` |
| `ru` | Russian | `translations_ru.js` |
| `es` | Spanish | `translations_es.js` |
| `hi` | Hindi | `translations_hi.js` |

## Adding a New Language

### 1. Create the dictionary file

Create a new file `contents/ui/translations_<code>.js` using the two-letter ISO 639-1 language code:

```javascript
// translations_fr.js — French
var fr_dictionary = {
    // ── Main UI ──
    "New Chat": "Nouvelle discussion",
    "Send": "Envoyer",
    "Stop": "Arrêter",
    "Ask anything...": "Demander quelque chose...",

    // ── Settings ──
    "General": "Général",
    "Provider": "Fournisseur",
    "API Key Storage": "Stockage des clés API",
    "Other settings": "Autres paramètres",

    // ── Scheduler ──
    "Create Schedule": "Créer un planning",
    "Edit Schedule": "Modifier le planning",
    "Schedules": "Plannings",
    "Active": "Actifs",
    "Archived": "Archivés",
    "History": "Historique",

    // ── OpenCode ──
    "OpenCode Bridge": "Pont OpenCode",
    "Start server": "Démarrer le serveur",
    "Stop server": "Arrêter le serveur",
};
```

### 2. Register the dictionary

In `contents/ui/translations.js`:

1. Add a Qt.include statement at the top:
   ```javascript
   Qt.include("translations_fr.js");
   ```

2. Add the dictionary to the `dictionary` object:
   ```javascript
   var dictionary = {
       "ar": ar_dictionary,
       "zh": zh_dictionary,
       "fr": fr_dictionary,
       // ...
   };
   ```

### 3. Add dynamic pattern translations (Recommended)

For provider-specific fields, add dynamic pattern matching in the `translate()` function:

```javascript
} else if (lang === "fr") {
    if (text.endsWith(" key:")) {
        return "Clé " + text.slice(0, -5) + " :";
    }
    if (text.endsWith(" URL:")) {
        return "URL " + text.slice(0, -5) + " :";
    }
    if (text.endsWith(" model:")) {
        return "Modèle " + text.slice(0, -7) + " :";
    }
}
```

This ensures provider-specific fields like `OpenAI key:`, `OpenAI URL:`, `OpenAI model:` are translated dynamically.

### 4. Add the language code to the settings dropdown

The language selection dropdown in `ConfigGeneral.qml` displays available languages. Add your new language code to the model.

### 5. Test the translation

1. Build the widget: `./install.sh`
2. Restart Plasma: `systemctl --user restart plasma-plasmashell.service`
3. Open widget settings and select your language from the dropdown.

## Translation Guidelines

- **Keep the same keys** as the English defaults in `translations.js`.
- **Maintain formatting**: Preserve Markdown, HTML tags, and placeholder tokens like `%1`.
- **Dynamic patterns**: Copy the dynamic pattern section structure from another language if adding provider field translations.
- **Context**: Some strings may appear in multiple contexts — check the surrounding UI for accurate translation.
- **Fallback**: If a key is missing from your dictionary, the English text will be shown.

## Finding Strings to Translate

Search for `translate(` calls in the QML files to find all translatable strings:

```bash
grep -rn 'translate(' org.kde.plasma.kdeaichat/contents/ui/*.qml
```

This will give you the complete list of strings that need translation.
