.pragma library

/**
 * MarkdownRenderer — markdown → HTML and structural-block parsing.
 *
 * Pure helpers used by main.qml to render chat messages and tables.
 * Theme-aware (`isDark` parameter) and tolerant of malformed input
 * (falls back to escaped plaintext on error).
 *
 * @module MarkdownRenderer
 */

var _ALLOWED_URL_SCHEMES = ["http:", "https:", "mailto:"];

/**
 * Sanitize a URL before inlining it into an HTML `href` attribute.
 *
 * Allows only `http:`, `https:`, and `mailto:`. Any other scheme
 * (`javascript:`, `data:`, `file:`, `vbscript:`, custom schemes,
 * `about:`, …) is rejected and the caller is expected to render
 * the link label as plain text.
 *
 * @param {string} url  Raw URL.
 * @returns {string}    Sanitized URL safe for `href="…"`, or `""`.
 */
function sanitizeHref(url) {
    if (url === null || url === undefined)
        return "";
    var s = String(url).trim();
    if (s === "")
        return "";
    var lower = s.toLowerCase();
    for (var i = 0; i < _ALLOWED_URL_SCHEMES.length; i++) {
        var scheme = _ALLOWED_URL_SCHEMES[i];
        if (lower.indexOf(scheme) === 0) {
            var after = s.substring(scheme.length);
            if (after.length === 0)
                continue;
            var first = after.charAt(0);
            var ok = false;
            if (scheme === "mailto:") {
                if (first !== " " && first !== "\t" && first !== "\n" && first !== "\r")
                    ok = true;
            } else {
                if (first === "/" || first === "?" || first === "#")
                    ok = true;
            }
            if (!ok)
                return "";
            // Defense in depth: drop characters that could escape
            // the double-quoted attribute value.
            return s.replace(/[\"\`<>]/g, "");
        }
    }
    // No recognised scheme — most likely a relative path or a
    // scheme we explicitly do not want. Reject.
    return "";
}

/**
 * Convert a markdown string to an inline-styled HTML string suitable
 * for QML `Text` / `TextEdit` `textFormat: Text.RichText`.
 *
 * Supported syntax: fenced code blocks (with optional language label),
 * GFM tables, inline code, ATX headers (`#`–`####`), bold/italic
 * (`**`/`__`/`*`/`_`), `[text](url)` links, `---` horizontal rules,
 * `>` blockquotes, and bullet/numbered lists. Paragraph breaks are
 * rendered as `<br/><br/>`. Code blocks are extracted first and
 * restored last so that other passes do not mangle them.
 *
 * Theme parameters (`isDark`) toggle palette colors for code blocks,
 * tables, links, and rules.
 *
 * @param {string} markdown  Raw markdown text. Empty string returns "".
 * @param {boolean} [isDark]  When true, use the dark-theme palette.
 * @returns {string} HTML string. On error, a plaintext-escaped fallback.
 */
function convertMarkdownToHtml(markdown, isDark) {
    if (!markdown)
        return "";

    try {
        var codeBg = isDark ? "#2d3139" : "#f0f2f5";
        var codeColor = isDark ? "#abb2bf" : "#383a42";
        var inlineBg = isDark ? "#3e4452" : "#e5e5e5";
        var inlineColor = isDark ? "#e06c75" : "#a626a4";
        var linkColor = isDark ? "#61afef" : "#4078f2";
        var borderColor = isDark ? "#3e4452" : "#d0d4dc";
        var tableBorderColor = isDark ? "#4a5165" : "#c8cdd8";
        var tableHeadBg = isDark ? "#363b48" : "#e8eaf0";
        var tableRowAltBg = isDark ? "rgba(255,255,255,0.03)" : "rgba(0,0,0,0.02)";
        var html = markdown;

        // 1. Escape HTML
        html = html.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

        // 2. Extract fenced code blocks
        var codeBlocks = [];
        html = html.replace(/```([a-zA-Z0-9+#\-_]*)\n([\s\S]*?)```/g, function(match, lang, code) {
            var blockIdx = codeBlocks.length;
            var rendered = '<div style="background-color: ' + codeBg + '; color: ' + codeColor + '; font-family: monospace; padding: 10px 12px; margin: 8px 0; border-radius: 6px; border: 1px solid ' + borderColor + '; overflow-x: auto;">' + '<div style="font-size: 0.8em; color: ' + (isDark ? "#5c6370" : "#a0a1a7") + '; margin-bottom: 6px; font-weight: bold; border-bottom: 1px solid ' + borderColor + '; padding-bottom: 4px;">' + (lang ? lang : 'code') + '</div>' + '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; line-height: 1.5;">' + code.replace(/\n$/, '') + '</pre></div>';
            codeBlocks.push(rendered);
            return "%%CB" + blockIdx + "%%";
        });
        html = html.replace(/```([\s\S]*?)```/g, function(match, code) {
            var blockIdx = codeBlocks.length;
            var rendered = '<div style="background-color: ' + codeBg + '; color: ' + codeColor + '; font-family: monospace; padding: 10px 12px; margin: 8px 0; border-radius: 6px; border: 1px solid ' + borderColor + '; overflow-x: auto;">' + '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; line-height: 1.5;">' + code.replace(/\n$/, '') + '</pre></div>';
            codeBlocks.push(rendered);
            return "%%CB" + blockIdx + "%%";
        });

        // 3. Markdown tables
        html = html.replace(/((?:[ \t]*\|.+\|[ \t]*\n)+)/g, function(block) {
            var rows = block.trim().split("\n");
            if (rows.length < 2)
                return block;

            var isSep = /^[\s|:\-]+$/.test(rows[1]);
            var headerRow = rows[0];
            var bodyRows = isSep ? rows.slice(2) : rows.slice(1);
            var parseCells = function(row) {
                return row.replace(/^\s*\|/, '').replace(/\|\s*$/, '').split("|").map(function(c) {
                    return c.trim();
                });
            };
            var t = '<table style="border-collapse: collapse; width: 100%; margin: 8px 0; font-size: 0.9em;">';
            t += '<thead><tr>';
            parseCells(headerRow).forEach(function(cell) {
                t += '<th style="border: 1px solid ' + tableBorderColor + '; padding: 6px 10px; background: ' + tableHeadBg + '; text-align: left; font-weight: bold;">' + cell + '</th>';
            });
            t += '</tr></thead><tbody>';
            bodyRows.forEach(function(row, ri) {
                if (row.trim() === '' || /^[\s|:\-]+$/.test(row))
                    return;

                var bg = (ri % 2 === 1) ? ' background: ' + tableRowAltBg + ';' : '';
                t += '<tr>';
                parseCells(row).forEach(function(cell) {
                    t += '<td style="border: 1px solid ' + tableBorderColor + '; padding: 5px 10px;' + bg + '">' + cell + '</td>';
                });
                t += '</tr>';
            });
            t += '</tbody></table>';
            return t;
        });

        // 4. Inline code
        html = html.replace(/`([^`\n]+)`/g, '<code style="background-color: ' + inlineBg + '; color: ' + inlineColor + '; font-family: monospace; padding: 2px 5px; border-radius: 3px; font-size: 0.92em;">$1</code>');

        // 5. Headers
        html = html.replace(/^#### (.*?)$/gm, '<h4 style="margin: 8px 0; font-weight: bold;">$1</h4>');
        html = html.replace(/^### (.*?)$/gm, '<h3 style="margin: 10px 0; font-weight: bold;">$1</h3>');
        html = html.replace(/^## (.*?)$/gm, '<h2 style="margin: 12px 0; font-weight: bold;">$1</h2>');
        html = html.replace(/^# (.*?)$/gm, '<h1 style="margin: 14px 0; font-weight: bold;">$1</h1>');

        // 6. Bold & Italic
        html = html.replace(/\*\*([^\*\n]+)\*\*/g, '<b>$1</b>');
        html = html.replace(/__([^\_\n]+)__/g, '<b>$1</b>');
        html = html.replace(/\*([^\*\n]+)\*/g, '<i>$1</i>');
        html = html.replace(/_([^\_\n]+)_/g, '<i>$1</i>');

        // 7. Links
        // URLs from LLM output are restricted to http(s) and mailto
        // before being inlined into `href="…"`. Anything else (e.g.
        // `javascript:`, `data:`, `file:`, `vbscript:`) is dropped and
        // rendered as plain text. This blocks XSS via crafted markdown
        // links.
        html = html.replace(/\[([^\]\n]+)\]\(([^)\n]+)\)/g, function(match, label, rawUrl) {
            var safeUrl = sanitizeHref(rawUrl);
            if (safeUrl === "") {
                return label;
            }
            return '<a href="' + safeUrl + '" style="color: ' + linkColor + '; text-decoration: underline;">' + label + '</a>';
        });

        // 8. Horizontal rule
        html = html.replace(/^---+$/gm, '<hr style="border: none; border-top: 1px solid ' + borderColor + '; margin: 10px 0;"/>');

        // 9. Blockquote
        html = html.replace(/^&gt;\s?(.*?)$/gm, '<blockquote style="margin: 4px 0 4px 12px; padding: 4px 10px; border-left: 3px solid ' + borderColor + '; opacity: 0.8;">$1</blockquote>');

        // 10. Bullet lists
        html = html.replace(/^\s*[-*+]\s+(.*?)$/gm, '<ul><li>$1</li></ul>');
        html = html.replace(/<\/ul>\s*\n?\s*<ul>/g, '');

        // 11. Numbered lists
        html = html.replace(/^\s*(\d+)\.\s+(.*?)$/gm, '<ol><li value="$1">$2</li></ol>');
        html = html.replace(/<\/ol>\s*\n?\s*<ol>/g, '');

        // 12. Paragraph breaks
        html = html.replace(/\n\n/g, '<br/><br/>');
        html = html.replace(/\n/g, '<br/>');

        // 13. Restore code blocks
        for (var idx = 0; idx < codeBlocks.length; idx++) {
            html = html.replace("%%CB" + idx + "%%", codeBlocks[idx]);
        }

        return html;
    } catch (e) {
        return String(markdown).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br/>");
    }
}

/**
 * Split a markdown message into structural blocks for selective UI
 * rendering (code blocks, tables, and text segments).
 *
 * Each block is an object of shape:
 *   - `{ type: "text",  content: string, lang: "" }`
 *   - `{ type: "code",  content: string, lang: string }`
 *   - `{ type: "table", content: string, lang: "" }`
 *
 * Fenced code blocks are detected by lines matching `^```lang$` and
 * terminated by `^```$`. Tables are detected by leading `|` on
 * consecutive lines. Everything else becomes a `text` block (with
 * leading/trailing blank lines trimmed).
 *
 * @param {string} markdown  Raw markdown text.
 * @returns {Array<{type: string, content: string, lang: string}>}
 *   Ordered list of blocks. Empty input yields a single empty text
 *   block. On error, returns a single text block containing the raw
 *   input.
 */
function parseMessageBlocks(markdown) {
    if (!markdown)
        return [{"type": "text", "content": "", "lang": ""}];

    try {
        var blocks = [];
        var lines = markdown.split("\n");
        var i = 0;
        while (i < lines.length) {
            // Detect fenced code block
            var fenceMatch = lines[i].match(/^```([a-zA-Z0-9+#\-_]*)\s*$/);
            if (fenceMatch) {
                var lang = fenceMatch[1] || "";
                var codeLines = [];
                i++;
                while (i < lines.length && !lines[i].match(/^```\s*$/)) {
                    codeLines.push(lines[i]);
                    i++;
                }
                i++; // skip closing ```
                blocks.push({"type": "code", "content": codeLines.join("\n"), "lang": lang});
                continue;
            }

            // Detect markdown table block
            if (/^\s*\|/.test(lines[i])) {
                var tableLines = [];
                while (i < lines.length && /^\s*\|/.test(lines[i])) {
                    tableLines.push(lines[i]);
                    i++;
                }
                blocks.push({"type": "table", "content": tableLines.join("\n") + "\n", "lang": ""});
                continue;
            }

            // Regular text
            var textLines = [];
            while (i < lines.length && !lines[i].match(/^```/) && !/^\s*\|/.test(lines[i])) {
                textLines.push(lines[i]);
                i++;
            }
            var textContent = textLines.join("\n").replace(/^\n+/, "").replace(/\n+$/, "");
            if (textContent !== "")
                blocks.push({"type": "text", "content": textContent, "lang": ""});

        }
        if (blocks.length === 0)
            blocks.push({"type": "text", "content": markdown, "lang": ""});

        return blocks;
    } catch (e) {
        return [{"type": "text", "content": markdown, "lang": ""}];
    }
}

/**
 * Convert a markdown table to CSV (RFC 4180).
 *
 * Cells containing commas, double-quotes, or newlines are wrapped in
 * double quotes with internal double quotes doubled. The markdown
 * separator row (e.g. `|---|---|`) is skipped.
 *
 * @param {string} tableMarkdown  Raw markdown table source.
 * @returns {string} CSV text with rows separated by `\n`.
 */
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
