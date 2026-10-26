.pragma library

// Slash commands of the message box. Typing "/" lists the built-in commands
// first, then the prompt templates (PromptTemplates.js). Plain functions, so
// tests run them in node.
//
// A built-in command is never sent to the model: Enter on a line that is a
// command runs it. Anything else that starts with "/" is ordinary text: a
// template ("/name rest" expands, see PromptTemplates.expand) or, when it
// matches no command or template, a normal message ("/etc/hosts?" is sent as
// typed). A command is a SINGLE line "/name" or "/name argument"; text that
// continues on another line is a message. A built-in wins over a template
// of the same name.
//
//   /model [name]               change this chat's model (no name: open the picker)
//   /variant [name]             change this chat's variant (only listed when
//                               the model has variants)
//   /new                        start a new chat
//   /mode <direct|opencode|pi>  the mode of NEW chats only; the open chat keeps its mode
//   /image <prompt>             make a picture with the default image service (direct chats only)
//   /remember <text>            save a memory for every chat; "/remember chat: <text>" for this
//                               chat only, "/remember project: <text>" for its project

var MODES = ["direct", "opencode", "pi"];

// name, argument hint ("" = takes none) and the description shown in the
// list (plain English: the QML passes it through i18n() with the same text).
var COMMANDS = [
    {"name": "model", "args": "[name]", "description": "Change this chat's model"},
    {"name": "variant", "args": "[name]", "description": "Change this chat's variant (reasoning level)", "needsVariants": true},
    {"name": "new", "args": "", "description": "Start a new chat"},
    {"name": "mode", "args": "<direct|opencode|pi>", "description": "Mode for NEW chats only; this chat keeps its mode"},
    {"name": "image", "args": "<prompt>", "description": "Make a picture with the default image service"},
    {"name": "remember", "args": "<text>", "description": "Save a memory for every chat"}
];

// The argument of /remember: {scope: "all"|"chat"|"project", text}. A
// leading "chat:" or "project:" picks the scope.
function rememberArg(arg) {
    var match = /^(chat|project|all)\s*:\s*/i.exec(arg || "");
    return match ? {"scope": match[1].toLowerCase(), "text": arg.substring(match[0].length).trim()}
                 : {"scope": "all", "text": String(arg || "").trim()};
}

function find(name) {
    for (var i = 0; i < COMMANDS.length; i++) {
        if (COMMANDS[i].name === name)
            return COMMANDS[i];
    }
    return null;
}

// "/name arg" (one line) -> {name, arg, spaced}; null for any other text.
function parse(text) {
    if (!text || text.charAt(0) !== "/" || /\n/.test(text))
        return null;
    var space = text.indexOf(" ");
    var name = text.substring(1, space > -1 ? space : text.length);
    if (name === "" || /\s/.test(name))
        return null;
    return {"name": name, "arg": space > -1 ? text.substring(space + 1).trim() : "", "spaced": space > -1};
}

// The built-in command a line is: {command, arg}; null when it is not one
// (so it is a message to send).
function resolve(text) {
    var parsed = parse((text || "").trim());
    var command = parsed ? find(parsed.name) : null;
    return command ? {"command": command, "arg": parsed.arg} : null;
}

// Items whose name equals, starts with, then contains `query` (case-insensitive).
function rank(items, query, nameOf) {
    var q = query.toLowerCase();
    var exact = [];
    var starts = [];
    var contains = [];
    for (var i = 0; i < items.length; i++) {
        var n = nameOf(items[i]).toLowerCase();
        if (n === q && q !== "")
            exact.push(items[i]);
        else if (n.indexOf(q) === 0)
            starts.push(items[i]);
        else if (n.indexOf(q) > 0)
            contains.push(items[i]);
    }
    return exact.concat(starts, contains);
}

// What the list under the input shows for `text`. Entries:
// {kind: "command"|"template"|"option", name, usage, description, insert},
// where `insert` is what Tab puts in the box. ctx: {hasVariants, models: [id],
// variants: [id]}: the options of /model, /variant and /mode follow the command.
function suggest(text, templates, ctx) {
    ctx = ctx || {};
    if (!text || text.charAt(0) !== "/")
        return [];
    var parsed = parse(text);
    if (parsed && parsed.spaced) {
        var command = find(parsed.name);
        var pool = !command ? null : command.name === "model" ? ctx.models
            : command.name === "variant" ? ctx.variants : command.name === "mode" ? MODES : null;
        if (!pool)
            return [];
        return rank(pool, parsed.arg, function(id) { return String(id); }).map(function(id) {
            return {"kind": "option", "name": String(id), "usage": "", "description": "", "insert": "/" + command.name + " " + id};
        });
    }
    if (/[ \n]/.test(text))
        return [];
    var query = text.substring(1);
    var commands = COMMANDS.filter(function(c) { return !c.needsVariants || ctx.hasVariants === true; });
    var result = rank(commands, query, function(c) { return c.name; }).map(function(c) {
        return {"kind": "command", "name": c.name, "usage": c.args, "description": c.description, "insert": "/" + c.name + (c.args !== "" ? " " : "")};
    });
    return result.concat(rank(templates || [], query, function(t) { return t.name; }).map(function(t) {
        return {"kind": "template", "name": t.name, "usage": "", "description": t.prompt.replace(/\s+/g, " "), "insert": "/" + t.name + " "};
    }));
}

function modeName(mode) {
    return mode === "opencode" ? "OpenCode" : mode === "pi" ? "Pi" : "Direct";
}
