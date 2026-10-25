// The request fragment of a direct chat's variant (reasoning / thinking level).
// A chat stores only the variant's id; the fragment is looked up here, when
// the request is built, from what the provider reports for the model
// (ProviderVariants.js: its /models list, cached per provider). A chat without
// a variant sends no request for it, and a stored id the model no longer
// offers sends nothing. `chat` is the widget root (main.qml).
import QtQuick
import "../ProviderCheck.js" as ProviderCheck
import "../ProviderVariants.js" as ProviderVariants
import "../Variants.js" as Variants

QtObject {
    id: direct

    property var chat: null
    // Replaces XMLHttpRequest in tests.
    property var xhrFactory: null

    // cb(send): `send` is {} for no variant. cfg: the provider config of the
    // request (chat.getProviderConfig).
    function resolve(sessionId, cfg, cb) {
        var eff = chat.effectiveConfig(sessionId);
        if (eff.mode !== "provider" || eff.variant === "") {
            cb({});
            return;
        }
        ProviderVariants.forModel(cfg, cfg.apiKey, cfg.model, ProviderCheck.listModels, function(variants) {
            cb(Variants.sendFor(variants, eff.variant));
        }, {"xhrFactory": direct.xhrFactory});
    }
}
