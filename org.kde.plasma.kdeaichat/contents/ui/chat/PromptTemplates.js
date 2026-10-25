.pragma library

// Prompt templates: the `promptTemplates` setting is a JSON list of
// {name, prompt}. Typing "/name rest" in the composer sends the template's
// prompt followed by "rest"; "/" at the start suggests templates by name.
// Plain functions, so tests run them in node.

function parse(json) {
    try {
        var list = JSON.parse(json || "[]");
        if (!Array.isArray(list))
            return [];
        return list.filter(function(t) { return t && t.name && t.prompt; })
            .map(function(t) { return {"name": String(t.name), "prompt": String(t.prompt)}; });
    } catch (e) {
        return [];
    }
}

// "/name rest" with a known template -> its prompt + "\n\n" + rest; anything
// else comes back unchanged.
function expand(text, templates) {
    if (!text || text.charAt(0) !== "/")
        return text;
    var space = text.search(/[ \n]/);
    var name = text.substring(1, space > -1 ? space : text.length).trim();
    for (var i = 0; i < templates.length; i++) {
        if (templates[i].name === name) {
            var rest = space > -1 ? text.substring(space).trim() : "";
            return templates[i].prompt + (rest ? "\n\n" + rest : "");
        }
    }
    return text;
}

// Templates to suggest while the user types "/na": those whose name starts
// with, then contains, what follows the slash. Empty once a space is typed
// (the name is complete) or when the text doesn't start with "/".
function suggest(text, templates) {
    if (!text || text.charAt(0) !== "/" || /[ \n]/.test(text))
        return [];
    var query = text.substring(1).toLowerCase();
    var starts = [];
    var contains = [];
    for (var i = 0; i < templates.length; i++) {
        var name = templates[i].name.toLowerCase();
        if (name.indexOf(query) === 0)
            starts.push(templates[i]);
        else if (name.indexOf(query) > 0)
            contains.push(templates[i]);
    }
    return starts.concat(contains);
}
