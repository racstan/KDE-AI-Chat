import os
import sys
import time
import polib
from deep_translator import GoogleTranslator

# Mapping of KDE locale codes to Google Translate language codes
TARGETS = {
    "es": "es",
    "fr": "fr",
    "ru": "ru",
    "pt": "pt",
    "de": "de"
}

POT_FILE = "plasma_applet_org.kde.plasma.kdeaichat.pot"
LOCALE_DIR = "../contents/locale"

def main():
    if not os.path.exists(POT_FILE):
        print(f"Error: {POT_FILE} not found.")
        sys.exit(1)

    pot = polib.pofile(POT_FILE)

    for locale_code, gt_code in TARGETS.items():
        print(f"\nTranslating to {locale_code} ({gt_code})...")
        
        # Create a new PO file based on the POT file
        po = polib.POFile()
        po.metadata = pot.metadata.copy()
        po.metadata['Language'] = locale_code
        po.metadata['Content-Type'] = 'text/plain; charset=UTF-8'
        
        translator = GoogleTranslator(source='auto', target=gt_code)
        
        total = len(pot)
        for i, entry in enumerate(pot):
            new_entry = polib.POEntry(
                msgid=entry.msgid,
                msgstr="",
                occurrences=entry.occurrences
            )
            
            # Skip empty strings
            if not entry.msgid.strip():
                po.append(new_entry)
                continue
                
            try:
                # Handle basic placeholders like %1, %2 (Google Translate sometimes breaks them, but we'll try)
                translated = translator.translate(entry.msgid)
                # Quick fix for % 1 -> %1
                translated = translated.replace("% ", "%")
                new_entry.msgstr = translated
            except Exception as e:
                print(f"  Error translating '{entry.msgid}': {e}")
                new_entry.msgstr = entry.msgid # fallback to English
                
            po.append(new_entry)
            
            if (i+1) % 20 == 0:
                print(f"  {i+1}/{total} translated...")

        # Save PO
        msg_dir = os.path.join(LOCALE_DIR, locale_code, "LC_MESSAGES")
        os.makedirs(msg_dir, exist_ok=True)
        
        po_path = os.path.join(msg_dir, "plasma_applet_org.kde.plasma.kdeaichat.po")
        mo_path = os.path.join(msg_dir, "plasma_applet_org.kde.plasma.kdeaichat.mo")
        
        po.save(po_path)
        print(f"Saved {po_path}")
        
        # Compile MO
        po.save_as_mofile(mo_path)
        print(f"Compiled {mo_path}")

if __name__ == "__main__":
    main()
