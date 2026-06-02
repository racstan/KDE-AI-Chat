import QtQuick

QtObject {
    id: root

    property bool isDark: false

    readonly property var _colors: {
        var d = root.isDark;
        return {
            codeBg:              d ? "#2d3139" : "#f0f2f5",
            codeColor:           d ? "#abb2bf" : "#383a42",
            inlineBg:            d ? "#3e4452" : "#e5e5e5",
            inlineColor:         d ? "#e06c75" : "#a626a4",
            linkColor:           d ? "#61afef" : "#4078f2",
            borderColor:         d ? "#3e4452" : "#d0d4dc",
            tableBorderColor:    d ? "#4a5165" : "#c8cdd8",
            tableHeadBg:         d ? "#363b48" : "#e8eaf0",
            tableRowAltBg:       d ? "rgba(255,255,255,0.03)" : "rgba(0,0,0,0.02)",
            hrColor:             d ? "#3e4452" : "#d0d4dc",
            codeHeaderColor:     d ? "#5c6370" : "#a0a1a7"
        };
    }

    function toHtml(markdown) {
        if (!markdown)
            return "";

        var c = root._colors;
        var html = markdown;

        // 1. Escape HTML
        html = html.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

        // 2. Extract fenced code blocks
        var codeBlocks = [];
        html = html.replace(/```([a-zA-Z0-9+#\-_]*)\n([\s\S]*?)```/g, function(match, lang, code) {
            var idx = codeBlocks.length;
            codeBlocks.push(
                '<div style="background-color: ' + c.codeBg + '; color: ' + c.codeColor
                + '; font-family: monospace; padding: 10px 12px; margin: 8px 0; border-radius: 6px; border: 1px solid '
                + c.borderColor + '; overflow-x: auto;">'
                + '<div style="font-size: 0.8em; color: ' + c.codeHeaderColor
                + '; margin-bottom: 6px; font-weight: bold; border-bottom: 1px solid ' + c.borderColor
                + '; padding-bottom: 4px;">' + (lang || 'code') + '</div>'
                + '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; line-height: 1.5;">'
                + code.replace(/\n$/, '') + '</pre></div>'
            );
            return "%%CB" + idx + "%%";
        });
        html = html.replace(/```([\s\S]*?)```/g, function(match, code) {
            var idx = codeBlocks.length;
            codeBlocks.push(
                '<div style="background-color: ' + c.codeBg + '; color: ' + c.codeColor
                + '; font-family: monospace; padding: 10px 12px; margin: 8px 0; border-radius: 6px; border: 1px solid '
                + c.borderColor + '; overflow-x: auto;">'
                + '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; line-height: 1.5;">'
                + code.replace(/\n$/, '') + '</pre></div>'
            );
            return "%%CB" + idx + "%%";
        });

        // 3. Markdown tables
        html = html.replace(/((?:[ \t]*\|.+\|[ \t]*\n)+)/g, function(block) {
            var rows = block.trim().split("\n");
            if (rows.length < 2) return block;
            var isSep = /^[\s|:\-]+$/.test(rows[1]);
            var headerRow = rows[0];
            var bodyRows = isSep ? rows.slice(2) : rows.slice(1);
            var parseCells = function(row) {
                return row.replace(/^\s*\|/, '').replace(/\|\s*$/, '').split("|").map(function(c) { return c.trim(); });
            };
            var t = '<table style="border-collapse: collapse; width: 100%; margin: 8px 0; font-size: 0.9em;">';
            t += '<thead><tr>';
            parseCells(headerRow).forEach(function(cell) {
                t += '<th style="border: 1px solid ' + c.tableBorderColor + '; padding: 6px 10px; background: ' + c.tableHeadBg + '; text-align: left; font-weight: bold;">' + cell + '</th>';
            });
            t += '</tr></thead><tbody>';
            bodyRows.forEach(function(row, ri) {
                if (row.trim() === '' || /^[\s|:\-]+$/.test(row)) return;
                var bg = (ri % 2 === 1) ? ' background: ' + c.tableRowAltBg + ';' : '';
                t += '<tr>';
                parseCells(row).forEach(function(cell) {
                    t += '<td style="border: 1px solid ' + c.tableBorderColor + '; padding: 5px 10px;' + bg + '">' + cell + '</td>';
                });
                t += '</tr>';
            });
            t += '</tbody></table>';
            return t;
        });

        // 4. Inline code
        html = html.replace(/`([^`\n]+)`/g,
            '<code style="background-color: ' + c.inlineBg + '; color: ' + c.inlineColor
            + '; font-family: monospace; padding: 2px 5px; border-radius: 3px; font-size: 0.92em;">$1</code>');

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
        html = html.replace(/\[([^\]\n]+)\]\(([^)\n]+)\)/g,
            '<a href="$2" style="color: ' + c.linkColor + '; text-decoration: underline;">$1</a>');

        // 8. Horizontal rule
        html = html.replace(/^---+$/gm,
            '<hr style="border: none; border-top: 1px solid ' + c.hrColor + '; margin: 10px 0;"/>');

        // 9. Blockquote
        html = html.replace(/^&gt;\s?(.*?)$/gm,
            '<blockquote style="margin: 4px 0 4px 12px; padding: 4px 10px; border-left: 3px solid ' + c.borderColor + '; opacity: 0.8;">$1</blockquote>');

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
    }

    // Split raw markdown into typed blocks: {type:"text"|"code"|"table", content, lang}
    function parseBlocks(markdown) {
        if (!markdown)
            return [{ type: "text", content: "", lang: "" }];

        var blocks = [];
        var lines = markdown.split("\n");
        var i = 0;
        while (i < lines.length) {
            var fenceMatch = lines[i].match(/^```([a-zA-Z0-9+#\-_]*)\s*$/);
            if (fenceMatch) {
                var lang = fenceMatch[1] || "";
                var codeLines = [];
                i++;
                while (i < lines.length && !lines[i].match(/^```\s*$/)) {
                    codeLines.push(lines[i]);
                    i++;
                }
                i++;
                blocks.push({ type: "code", content: codeLines.join("\n"), lang: lang });
                continue;
            }
            if (/^\s*\|/.test(lines[i])) {
                var tableLines = [];
                while (i < lines.length && /^\s*\|/.test(lines[i])) {
                    tableLines.push(lines[i]);
                    i++;
                }
                blocks.push({ type: "table", content: tableLines.join("\n"), lang: "" });
                continue;
            }
            var textLines = [];
            while (i < lines.length && !lines[i].match(/^```/) && !/^\s*\|/.test(lines[i])) {
                textLines.push(lines[i]);
                i++;
            }
            blocks.push({ type: "text", content: textLines.join("\n"), lang: "" });
        }
        return blocks;
    }
}
