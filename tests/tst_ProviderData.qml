import QtQuick 2.0
import QtTest 1.0
import "../org.kde.plasma.kdeaichat/contents/ui/ProviderData.js" as P

TestCase {
    name: "ProviderDataTests"

    function test_idList_contains_openai() {
        var ids = P.idList();
        verify(ids.length >= 21, "idList should have at least 21 providers, got " + ids.length);
        compare(ids[0], "openai");
    }

    function test_getProvider_returns_correct_display_name() {
        var p = P.getProvider("anthropic");
        compare(p.name, "Anthropic");
    }

    function test_getProvider_returns_openai_for_unknown() {
        var p = P.getProvider("nonexistent");
        compare(p.id, "openai");
    }

    function test_needsApiKey_returns_true_for_openai() {
        verify(P.needsApiKey("openai") === true);
    }

    function test_needsApiKey_returns_false_for_ollama() {
        verify(P.needsApiKey("ollama") === false);
    }

    function test_displayName_returns_correct() {
        compare(P.displayName("deepseek"), "DeepSeek");
    }

    function test_defaultUrl_returns_non_empty_for_openai() {
        var url = P.defaultUrl("openai");
        verify(url.length > 0);
        compare(url, "https://api.openai.com/v1");
    }

    function test_defaultUrl_returns_empty_string_for_unknown() {
        compare(P.defaultUrl(""), "");
    }

    function test_defaultModel_returns_correct() {
        var m = P.defaultModel("google");
        compare(m, "gemini-3-flash-preview");
    }

    function test_guideText_returns_non_empty_for_openai() {
        var g = P.guideText("openai");
        verify(g.length > 0);
        verify(g.indexOf("OpenAI") >= 0);
    }

    function test_guideText_returns_empty_for_unknown() {
        compare(P.guideText("bogus"), "");
    }

    function test_configField_empty_prefix_ApiKey() {
        compare(P.configField("openai", "ApiKey"), "apiKey");
        compare(P.configField("openai", "Model"), "model");
        compare(P.configField("openai", "BaseUrl"), "baseUrl");
    }

    function test_configField_custom_prefix() {
        compare(P.configField("deepseek", "ApiKey"), "deepSeekApiKey");
        compare(P.configField("openrouter", "BaseUrl"), "openRouterBaseUrl");
        compare(P.configField("lmstudio", "Model"), "lmStudioModel");
    }

    function test_comboModel_contains_all_providers() {
        var m = P.comboModel();
        verify(m.length >= 21);
        compare(m[0].value, "openai");
        compare(m[0].text, "OpenAI");
    }

    function test_walletKeyName() {
        compare(P.walletKeyName("openai"), "kai-chat-openai-api-key");
        compare(P.walletKeyName("xai"), "kai-chat-xai-api-key");
    }

    function test_buildRuntimeConfig_basic() {
        var cfg = { apiKey: "sk-test", model: "gpt-4o", baseUrl: "https://custom/v1" };
        var r = P.buildRuntimeConfig("openai", cfg);
        compare(r.type, "openai-compat");
        compare(r.apiKey, "sk-test");
        compare(r.model, "gpt-4o");
        compare(r.baseUrl, "https://custom/v1");
        compare(r.allowEmptyKey, false);
    }

    function test_buildRuntimeConfig_defaults() {
        var cfg = {};
        var r = P.buildRuntimeConfig("ollama", cfg);
        compare(r.type, "openai-compat");
        compare(r.apiKey, "");
        compare(r.allowEmptyKey, true);
    }
}
