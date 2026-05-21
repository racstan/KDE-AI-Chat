#!/usr/bin/env python3
import json
import re
import sys
import xml.etree.ElementTree as ET

# Define expected provider values and their corresponding QML/XML keys
PROVIDERS = {
    "openai": {"url": "baseUrl", "key": "apiKey", "model": "model"},
    "anthropic": {"url": None, "key": "anthropicApiKey", "model": "anthropicModel"},
    "groq": {"url": "groqBaseUrl", "key": "groqApiKey", "model": "groqModel"},
    "deepseek": {"url": "deepSeekBaseUrl", "key": "deepSeekApiKey", "model": "deepSeekModel"},
    "minimax": {"url": "miniMaxBaseUrl", "key": "miniMaxApiKey", "model": "miniMaxModel"},
    "fireworks": {"url": "fireworksBaseUrl", "key": "fireworksApiKey", "model": "fireworksModel"},
    "google": {"url": "googleBaseUrl", "key": "googleApiKey", "model": "googleModel"},
    "openrouter": {"url": "openRouterBaseUrl", "key": "openRouterApiKey", "model": "openRouterModel"},
    "mistral": {"url": "mistralBaseUrl", "key": "mistralApiKey", "model": "mistralModel"},
    "cloudflare": {"url": "cloudflareBaseUrl", "key": "cloudflareApiKey", "model": "cloudflareModel"},
    "nvidia": {"url": "nvidiaBaseUrl", "key": "nvidiaApiKey", "model": "nvidiaModel"},
    "huggingface": {"url": "huggingFaceBaseUrl", "key": "huggingFaceApiKey", "model": "huggingFaceModel"},
    "xai": {"url": "xaiBaseUrl", "key": "xaiApiKey", "model": "xaiModel"},
    "lmstudio": {"url": "lmStudioBaseUrl", "key": None, "model": "lmStudioModel"},
    "local": {"url": "localBaseUrl", "key": None, "model": "localModel"},
    "ollama": {"url": "ollamaBaseUrl", "key": None, "model": "ollamaModel"},
}

def main():
    print("--- KDE AI Chat Provider Consistency Check ---")
    
    # 1. Load and parse main.xml
    xml_path = "org.kde.plasma.kdeaichat/contents/config/main.xml"
    print(f"Parsing {xml_path}...")
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        xml_entries = {entry.attrib["name"] for entry in root.findall(".//*") if "name" in entry.attrib}
    except Exception as e:
        print(f"Error parsing XML: {e}")
        sys.exit(1)

    # 2. Read ConfigGeneral.qml
    qml_config_path = "org.kde.plasma.kdeaichat/contents/ui/ConfigGeneral.qml"
    print(f"Reading {qml_config_path}...")
    with open(qml_config_path, "r", encoding="utf-8") as f:
        config_qml = f.read()

    # 3. Read main.qml
    main_qml_path = "org.kde.plasma.kdeaichat/contents/ui/main.qml"
    print(f"Reading {main_qml_path}...")
    with open(main_qml_path, "r", encoding="utf-8") as f:
        main_qml = f.read()

    # 4. Perform check for each provider
    errors = 0
    for provider, keys in PROVIDERS.items():
        print(f"\nAuditing Provider: '{provider}'")
        
        # Check XML entries
        for role, key_name in keys.items():
            if not key_name:
                continue
            
            # XML Check
            if key_name not in xml_entries:
                print(f"  [ERROR] XML: Key '{key_name}' is missing in main.xml!")
                errors += 1
            else:
                print(f"  [OK] XML: Found '{key_name}'")
                
            # QML Alias Check
            alias_pattern = f"property alias cfg_{key_name}:"
            if alias_pattern not in config_qml:
                print(f"  [ERROR] ConfigGeneral.qml: Property alias 'cfg_{key_name}' is missing!")
                errors += 1
            else:
                print(f"  [OK] ConfigGeneral.qml: Found alias 'cfg_{key_name}'")
                
            # ConfigGeneral.qml TextField definition check
            field_pattern = f"id: {key_name}Field"
            if key_name not in ["baseUrl", "apiKey", "model"]: # openai defaults are differently structured in standard QML
                if field_pattern not in config_qml:
                    print(f"  [ERROR] ConfigGeneral.qml: TextField id '{key_name}Field' is missing!")
                    errors += 1
                else:
                    print(f"  [OK] ConfigGeneral.qml: Found TextField '{key_name}Field'")

        # Check main.qml runtime config resolver entry
        resolver_block_pattern = f'provider === "{provider}"'
        if provider == "openai":
            resolver_block_pattern = 'baseUrl || "https://api.openai.com/v1"'
            
        if resolver_block_pattern not in main_qml:
            print(f"  [ERROR] main.qml: Resolver block for '{provider}' is missing!")
            errors += 1
        else:
            print(f"  [OK] main.qml: Found resolver block for '{provider}'")

    print("\n--- Summary ---")
    if errors == 0:
        print("🎉 SUCCESS: All 16 providers are 100% correct, verified, and aligned across files!")
        sys.exit(0)
    else:
        print(f"❌ FAILURE: Found {errors} mismatch(es) or missing keys.")
        sys.exit(1)

if __name__ == "__main__":
    main()
