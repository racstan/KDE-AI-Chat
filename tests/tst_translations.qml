import QtQuick 2.15
import QtTest 1.0
import "../org.kde.plasma.kdeaichat/contents/ui/translations.js" as Translations
import "../org.kde.plasma.kdeaichat/contents/ui/ProviderData.js" as ProviderData

TestCase {
    name: "TranslationsAndProviders"

    function test_provider_registry() {
        var providers = ProviderData.providerData;
        compare(providers.length > 0, true, "Provider data should have entries");
        
        // Find openai
        var foundOpenAi = false;
        for (var i = 0; i < providers.length; i++) {
            if (providers[i].id === "openai") {
                foundOpenAi = true;
                compare(providers[i].name, "OpenAI");
            }
        }
        compare(foundOpenAi, true, "Should have openai provider");
    }

    function test_translate_english() {
        var result = Translations.translate("Hello", "en");
        compare(result, "Hello", "English translation should return original text");
    }

    function test_translate_dynamic_patterns() {
        // German dynamic patterns
        var resultKey = Translations.translate("OpenAI key:", "de");
        compare(resultKey, "OpenAI-Schlüssel:", "German key translation");

        var resultUrl = Translations.translate("OpenAI URL:", "de");
        compare(resultUrl, "OpenAI-URL:", "German URL translation");

        var resultModel = Translations.translate("OpenAI model:", "de");
        compare(resultModel, "OpenAI-Modell:", "German model translation");
        
        // Spanish dynamic patterns
        var resultKeyEs = Translations.translate("OpenAI key:", "es");
        compare(resultKeyEs, "Clave de OpenAI:", "Spanish key translation");
    }
}
