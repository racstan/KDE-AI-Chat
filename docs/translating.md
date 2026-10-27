# Translating

The widget comes with translations for German, Spanish, French, Hindi, Portuguese, Russian and Simplified Chinese. They were made by machine translation and **have not been checked by people who speak those languages**. Help is welcome, both to fix what is wrong and to add a new language.

## Where the files are

All paths are inside `org.kde.plasma.kdeaichat/`.

- **Template**: `translate/plasma_applet_org.kde.plasma.kdeaichat.pot` lists every text the widget shows. It is the starting point for a new language.
- **Translations**: `contents/locale/<language>/LC_MESSAGES/plasma_applet_org.kde.plasma.kdeaichat.po` (for example `contents/locale/de/LC_MESSAGES/`). The `.mo` file next to it is the compiled copy that Plasma reads.
- `translate/files.txt` lists the source files that contain texts.
- `translate/do_translate.py` and `translate/do_translate_fast.py` make the machine translations. They need the Python packages `polib` and `deep_translator`.

## How to help

1. **Fix a language.** Open its `.po` file in a text editor or a tool such as Lokalize. Look for texts that read badly. Fix the `msgstr` lines. Keep placeholders such as `%1` and `%2` exactly as they are. Keep names of settings the same as in the translation of the settings page, so the manual and the screen agree.
2. **Add a language.** Copy the `.pot` file to `contents/locale/<language code>/LC_MESSAGES/` as a `.po` file, fill in the translations, and compile it with `msgfmt`:
   ```bash
   msgfmt -o plasma_applet_org.kde.plasma.kdeaichat.mo plasma_applet_org.kde.plasma.kdeaichat.po
   ```
3. **Try it.** Install the widget from source (`./install.sh`), restart Plasma (`systemctl --user restart plasma-plasmashell.service`) and run it in your language.
4. **Send it.** Open a pull request at <https://github.com/racstan/KDE-AI-Chat>, or an issue with the `.po` file attached.

Even a short report such as "the German text for X is wrong, it should be Y" helps.
