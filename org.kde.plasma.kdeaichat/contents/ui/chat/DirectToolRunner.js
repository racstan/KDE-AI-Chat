.pragma library

// Pure logic of chat/DirectToolRunner.qml: cutting a tool result, the key an "Always
// allow" is remembered under, whether a call must be approved, and the text of its
// arguments on the permission card. Plain JavaScript, so tests run it in node.

var RESULT_LIMIT = 32768;     // characters of a tool result the model gets
var COMPACT_ARGS = 160;       // arguments up to this long show on one line (and in a notification)
var ARGS_LIMIT = 4000;        // the card shows at most this much of the arguments

// A result as a string, cut to `limit` characters with a note that it was cut.
function cutResult(output, limit) {
    var text = output === undefined || output === null ? "" : (typeof output === "string" ? output : _json(output));
    limit = limit > 0 ? limit : RESULT_LIMIT;
    if (text.length <= limit)
        return text;
    return text.substring(0, limit) + "\n\n[The result was cut: " + text.length + " characters, only the first " + limit + " are shown.]";
}

function _json(value) {
    try {
        return JSON.stringify(value);
    } catch (e) {
        return String(value);
    }
}

// What "Always allow" remembers a tool under (kdeaichat/tool_approvals.py has the same shapes), or ""
// when the tool can't be remembered. entry: a DirectTools.toolRegistry() entry.
function approvalKey(entry) {
    if (!entry)
        return "";
    if (entry.approvalKey)
        return String(entry.approvalKey);
    if (entry.kind === "mcp" && entry.server)
        return "mcp:" + entry.server + ":" + entry.realName;
    if (entry.kind === "workspace" && entry.folder)
        return "workspace:" + entry.folder + ":" + entry.realName;
    if (entry.kind === "skill")
        return "skill:" + entry.realName;
    return "";
}

// A tool that changes things, or any MCP tool, asks first unless its key is remembered.
function needsApproval(entry, approvedKeys) {
    if (!entry || (entry.risk !== "change" && entry.kind !== "mcp"))
        return false;
    var key = approvalKey(entry);
    return !(key !== "" && (approvedKeys || []).indexOf(key) >= 0);
}

// The arguments of a call as the lines of a permission card: one compact line when short, else indented JSON
// (cut). [] for no arguments.
function argsLines(args) {
    if (!args || typeof args !== "object" || Object.keys(args).length === 0)
        return [];
    var compact = _json(args);
    if (compact.length <= COMPACT_ARGS)
        return [compact];
    var pretty;
    try {
        pretty = JSON.stringify(args, null, 2);
    } catch (e) {
        pretty = compact;
    }
    return [pretty.length > ARGS_LIMIT ? pretty.substring(0, ARGS_LIMIT) + "\n..." : pretty];
}
