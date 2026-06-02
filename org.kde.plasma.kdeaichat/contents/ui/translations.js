var _loadedLangs = {};

function _ensureLang(lang) {
    if (_loadedLangs[lang] || lang === "en")
        return;
    _loadedLangs[lang] = true;
    var files = {
        "ar": "translations_ar.js",
        "zh": "translations_zh.js",
        "fr": "translations_fr.js",
        "de": "translations_de.js",
        "it": "translations_it.js",
        "ja": "translations_ja.js",
        "pt": "translations_pt.js",
        "ru": "translations_ru.js",
        "es": "translations_es.js",
        "hi": "translations_hi.js"
    };
    if (files[lang])
        Qt.include(files[lang]);
}

var dictionary = {};

function getSystemLanguage() {
    var localeName = Qt.locale().name || "en";
    return localeName.split("_")[0];
}

function translate(text, configLanguage) {
    var lang = configLanguage || "system";
    if (lang === "system" || lang === "") {
        lang = getSystemLanguage();
    }
    if (lang === "en") {
        return text;
    }
    _ensureLang(lang);
    if (!dictionary[lang]) {
        return text;
    }
    var val = dictionary[lang][text];
    if (val !== undefined) {
        return val;
    }

    // Dynamic pattern translations for provider settings dynamically loaded
    if (lang === "ar") {
        if (text.endsWith(" key:")) {
            return "مفتاح " + text.slice(0, -5) + ":";
        }
        if (text.endsWith(" URL:")) {
            return "رابط " + text.slice(0, -5) + ":";
        }
        if (text.endsWith(" model:")) {
            return "نموذج " + text.slice(0, -7) + ":";
        }
        if (text.indexOf("Enter the ") === 0 && text.indexOf(", then refresh models") > 0) {
            var part = text.substring(10);
            var endIdx = part.indexOf(" first");
            if (endIdx > 0) {
                var providerPart = part.substring(0, endIdx);
                return "أدخل " + providerPart + " أولاً، ثم قم بتنشيط الموديلات أو كتابة اسم الموديل.";
            }
        }
    } else if (lang === "zh") {
        if (text.endsWith(" key:")) {
            return text.slice(0, -5) + " 密钥：";
        }
        if (text.endsWith(" URL:")) {
            return text.slice(0, -5) + " 地址：";
        }
        if (text.endsWith(" model:")) {
            return text.slice(0, -7) + " 模型：";
        }
    } else if (lang === "de") {
        if (text.endsWith(" key:")) {
            return text.slice(0, -5) + "-Schlüssel:";
        }
        if (text.endsWith(" URL:")) {
            return text.slice(0, -5) + "-URL:";
        }
        if (text.endsWith(" model:")) {
            return text.slice(0, -7) + "-Modell:";
        }
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
    } else if (lang === "es") {
        if (text.endsWith(" key:")) {
            return "Clave de " + text.slice(0, -5) + ":";
        }
        if (text.endsWith(" URL:")) {
            return "URL de " + text.slice(0, -5) + ":";
        }
        if (text.endsWith(" model:")) {
            return "Modelo de " + text.slice(0, -7) + ":";
        }
    } else if (lang === "it") {
        if (text.endsWith(" key:")) {
            return "Chiave " + text.slice(0, -5) + ":";
        }
        if (text.endsWith(" URL:")) {
            return "URL " + text.slice(0, -5) + ":";
        }
        if (text.endsWith(" model:")) {
            return "Modello " + text.slice(0, -7) + ":";
        }
    } else if (lang === "pt") {
        if (text.endsWith(" key:")) {
            return "Chave " + text.slice(0, -5) + ":";
        }
        if (text.endsWith(" URL:")) {
            return "URL " + text.slice(0, -5) + ":";
        }
        if (text.endsWith(" model:")) {
            return "Modelo " + text.slice(0, -7) + ":";
        }
    } else if (lang === "ru") {
        if (text.endsWith(" key:")) {
            return "Ключ " + text.slice(0, -5) + ":";
        }
        if (text.endsWith(" URL:")) {
            return "URL " + text.slice(0, -5) + ":";
        }
        if (text.endsWith(" model:")) {
            return "Модель " + text.slice(0, -7) + ":";
        }
    } else if (lang === "ja") {
        if (text.endsWith(" key:")) {
            return text.slice(0, -5) + "キー:";
        }
        if (text.endsWith(" URL:")) {
            return text.slice(0, -5) + "URL:";
        }
        if (text.endsWith(" model:")) {
            return text.slice(0, -7) + "モデル:";
        }
    } else if (lang === "hi") {
        if (text.endsWith(" key:")) {
            return text.slice(0, -5) + " कुंजी:";
        }
        if (text.endsWith(" URL:")) {
            return text.slice(0, -5) + " URL:";
        }
        if (text.endsWith(" model:")) {
            return text.slice(0, -7) + " मॉडल:";
        }
    }

    return text;
}

var rtlLanguages = ["ar", "he", "fa", "ur", "sd", "ps", "ku", "ug", "dv", "yi"];

function isRtlLanguage(lang) {
    lang = lang || "system";
    if (lang === "system" || lang === "") {
        lang = getSystemLanguage();
    }
    return rtlLanguages.indexOf(lang) >= 0;
}
