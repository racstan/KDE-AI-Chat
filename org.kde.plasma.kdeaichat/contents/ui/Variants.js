.pragma library

// Model variants: a model's reasoning / thinking levels, in every mode.
//
// A variant is {id, label, send}:
//   id     what a setting stores (a chat's, or the main setting's)
//   label  what the pickers show
//   send   the exact request fragment for the mode, merged into the request:
//            direct (OpenRouter)  {reasoning: {effort}}
//            direct (Anthropic)   {thinking: {type: "adaptive"}, output_config: {effort}}
//            OpenCode             {variant: "<name>"}
//            Pi                   {thinking: "<level>"}
//
// NOTHING here is a per-provider or per-model list. A model has variants only
// when its source reports them (ProviderCheck.js reads them from the provider's
// /models answer, the OpenCode catalogue from OpenCodeCatalog.js, Pi's from
// `pi --list-models` plus Pi's own level vocabulary, which the caller passes
// in from EffectiveConfig.js). A model without variants shows no picker and
// sends nothing. A stored id that is not in the model's current list sends
// nothing either (sendFor).
//
// Plain JavaScript (no QML imports) so tests run it under node.

function _s(value) {
    return value === undefined || value === null ? "" : String(value).trim();
}

// "xhigh" -> "Xhigh": the id with a capital, for pickers.
function title(id) {
    var text = _s(id);
    return text === "" ? "" : text.charAt(0).toUpperCase() + text.substring(1);
}

function make(id, send, label) {
    return {"id": _s(id), "label": label || title(id), "send": send || {}};
}

// The variant with this id, or null.
function find(list, id) {
    var wanted = _s(id);
    if (wanted === "" || !Array.isArray(list))
        return null;
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].id === wanted)
            return list[i];
    }
    return null;
}

// The request fragment for a stored id: a copy of the matching variant's
// `send`, or {} when nothing is stored, the model has no variants or the id
// is no longer in the list.
function sendFor(list, id) {
    var variant = find(list, id);
    return variant ? JSON.parse(JSON.stringify(variant.send || {})) : {};
}

// True when the stored id is one of the list's.
function isValid(list, id) {
    return find(list, id) !== null;
}

// OpenCode: the variant names of a model (the keys of its `variants` map),
// each sent as {variant: name}.
function fromOpenCodeNames(names) {
    var out = [];
    for (var i = 0; Array.isArray(names) && i < names.length; i++) {
        var name = _s(names[i]);
        if (name !== "" && !find(out, name))
            out.push(make(name, {"variant": name}));
    }
    return out;
}

// Pi: for a model `pi --list-models` marks as thinking, Pi's own levels
// (`levels` is EffectiveConfig.PI_THINKING_LEVELS; the empty entry means "the
// model's default" and is not a variant); a model that does not think has none.
function fromPi(levels, thinks) {
    var out = [];
    if (thinks !== true)
        return out;
    for (var i = 0; Array.isArray(levels) && i < levels.length; i++) {
        if (_s(levels[i]) !== "")
            out.push(make(levels[i], {"thinking": _s(levels[i])}));
    }
    return out;
}
