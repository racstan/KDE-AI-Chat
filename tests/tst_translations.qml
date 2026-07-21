import QtQuick 2.15
import QtTest 1.0
import "../org.kde.plasma.kdeaichat/contents/ui/translations.js" as Translations

TestCase {
    name: "TranslationsAndProviders"

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
