// Utils.js — Pure utility functions for KDE AI Chat

function pad2(v) {
    return v < 10 ? "0" + v : String(v);
}

function nowTime(ts) {
    var d = ts ? new Date(ts) : new Date();
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

function formatDateTime(ts) {
    return new Date(ts).toLocaleString(undefined, {
        "year": "numeric",
        "month": "short",
        "day": "2-digit",
        "hour": "2-digit",
        "minute": "2-digit"
    });
}

function makeSessionId() {
    var chars = "abcdefghijklmnopqrstuvwxyz0123456789";
    var str = "";
    for (var i = 0; i < 6; i++) {
        str += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return "s-" + str;
}

function extractReadableError(prefix, errObj, fallbackText) {
    if (errObj) {
        if (errObj.data && errObj.data.message)
            return prefix + errObj.data.message;
        if (errObj.message)
            return prefix + errObj.message;
        if (errObj.name)
            return prefix + errObj.name;
    }
    return prefix + (fallbackText || "Unknown error");
}

function formatTokensUsage(tokens, cost) {
    if (!tokens)
        return "";
    var parts = [];
    if (tokens.input !== undefined)
        parts.push("Input: " + tokens.input);
    if (tokens.output !== undefined)
        parts.push("Output: " + tokens.output);
    if (tokens.reasoning !== undefined && tokens.reasoning > 0)
        parts.push("Reasoning: " + tokens.reasoning);
    if (tokens.cache && (tokens.cache.read > 0 || tokens.cache.write > 0))
        parts.push("Cache R/W: " + tokens.cache.read + "/" + tokens.cache.write);
    var res = parts.join(" | ");
    if (cost !== undefined && cost > 0)
        res += " | Cost: $" + cost.toFixed(5);
    return res;
}

function fileIconName(filename) {
    var ext = filename.split('.').pop().toLowerCase();
    if (ext === 'pdf')
        return 'document-pdf';
    if (ext === 'csv')
        return 'spreadsheet';
    if (['doc','docx'].indexOf(ext) >= 0)
        return 'document';
    if (['xls','xlsx'].indexOf(ext) >= 0)
        return 'spreadsheet';
    if (['jpg','jpeg','png','gif','webp','bmp','svg'].indexOf(ext) >= 0)
        return 'image-x-generic';
    if (['mp4','mkv','webm','avi','mov'].indexOf(ext) >= 0)
        return 'video-x-generic';
    if (['mp3','wav','ogg','flac'].indexOf(ext) >= 0)
        return 'audio-x-generic';
    if (ext === 'txt')
        return 'text-plain';
    if (['zip','tar','gz','bz2','7z','rar'].indexOf(ext) >= 0)
        return 'package-x-generic';
    return 'text-plain';
}

// Convert markdown table to CSV string
function tableMarkdownToCsv(tableMarkdown) {
    var rows = tableMarkdown.trim().split("\n");
    var csvRows = [];
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        if (/^[\s|:\-]+$/.test(row))
            continue;
        var cells = row.replace(/^\s*\|/, "").replace(/\|\s*$/, "").split("|");
        var csvCells = cells.map(function(c) {
            var v = c.trim();
            if (v.indexOf(",") >= 0 || v.indexOf("\"") >= 0 || v.indexOf("\n") >= 0)
                v = "\"" + v.replace(/"/g, "\"\"") + "\"";
            return v;
        });
        csvRows.push(csvCells.join(","));
    }
    return csvRows.join("\n");
}
