import os
import sys
import polib
from deep_translator import GoogleTranslator
from concurrent.futures import ThreadPoolExecutor

# Mapping of KDE locale codes to Google Translate language codes
TARGETS = {
    "fr": "fr",
    "ru": "ru",
    "pt": "pt",
    "de": "de"
}

POT_FILE = "plasma_applet_org.kde.plasma.kdeaichat.pot"
LOCALE_DIR = "../contents/locale"

def translate_locale(locale_code, gt_code):
    print(f"Starting translation for {locale_code}...")
    pot = polib.pofile(POT_FILE)
    
    po = polib.POFile()
    po.metadata = pot.metadata.copy()
    po.metadata['Language'] = locale_code
    po.metadata['Content-Type'] = 'text/plain; charset=UTF-8'
    
    translator = GoogleTranslator(source='auto', target=gt_code)
    
    for i, entry in enumerate(pot):
        new_entry = polib.POEntry(msgid=entry.msgid, msgstr="", occurrences=entry.occurrences)
        if not entry.msgid.strip():
            po.append(new_entry)
            continue
            
        try:
            translated = translator.translate(entry.msgid)
            translated = translated.replace("% ", "%")
            new_entry.msgstr = translated
        except Exception as e:
            new_entry.msgstr = entry.msgid
            
        po.append(new_entry)
        
    msg_dir = os.path.join(LOCALE_DIR, locale_code, "LC_MESSAGES")
    os.makedirs(msg_dir, exist_ok=True)
    
    po_path = os.path.join(msg_dir, "plasma_applet_org.kde.plasma.kdeaichat.po")
    mo_path = os.path.join(msg_dir, "plasma_applet_org.kde.plasma.kdeaichat.mo")
    
    po.save(po_path)
    po.save_as_mofile(mo_path)
    print(f"Finished {locale_code}")

def main():
    if not os.path.exists(POT_FILE):
        print(f"Error: {POT_FILE} not found.")
        sys.exit(1)

    with ThreadPoolExecutor(max_workers=4) as executor:
        for locale_code, gt_code in TARGETS.items():
            executor.submit(translate_locale, locale_code, gt_code)

if __name__ == "__main__":
    main()
