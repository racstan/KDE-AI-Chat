.pragma library

/**
 * Security — central helpers for safe shell embedding, URL validation,
 * and file-path sanitization.
 *
 * The widget's IPC layer (`P5Support.DataSource` with `engine: "executable"`)
 * runs every command through `sh -lc '…'`, which means any `$`, backtick,
 * `(` or `)` in an interpolated string becomes live shell grammar after
 * the outer single-quote context is closed by the inner escape. The
 * older single-quote-only escape left the door open for command
 * substitution when the outer wrapper was a double-quoted string.
 *
 * Use these helpers everywhere a user-controlled or LLM-controlled
 * string is embedded in a shell pipeline or a URL.
 *
 * @module Security
 */

var _ALLOWED_URL_SCHEMES = ["http:", "https:", "mailto:"];
var _SAFE_PATH_CHARS = /^[A-Za-z0-9._\/+@:=\-]+$/;
var _SAFE_SESSION_ID = /^[A-Za-z0-9\-]{1,128}$/;
var _MAX_SHELL_ARG_LEN = 4096;

/**
 * Build a string that is safe to embed inside a single-quoted shell
 * argument (`'…'`). Replaces every single quote with the standard
 * POSIX close-quote / escaped-quote / open-quote sequence and
 * removes the shell metacharacters that would otherwise be
 * re-evaluated by the outer wrapper.
 *
 * - Strips: `$`, backtick, `(`, `)`, `\`, `;`, `&`, `|`, `<`, `>`,
 *           newline, carriage-return, NUL, BEL.
 * - Length-clamped to `_MAX_SHELL_ARG_LEN` to bound memory use.
 * - Non-ASCII characters are preserved (UTF-8 safe for `sh -lc`).
 *
 * @param {string} s  Raw value (null/undefined treated as empty).
 * @returns {string}  Sanitized value safe to embed in `'…'`.
 */
function sanitizeForShell(s) {
    if (s === null || s === undefined)
        return "";
    var out = String(s);
    // Drop the characters that, even after single-quote escaping, can
    // trigger command substitution, backgrounding, or pipeline chaining
    // when the surrounding wrapper re-evaluates the resulting string.
    out = out.replace(/[\$\(\)\\\`\;\&\|\<\>\n\r\0\x07]/g, "");
    // Clamp to a reasonable upper bound to keep individual command
    // lines predictable.
    if (out.length > _MAX_SHELL_ARG_LEN)
        out = out.substring(0, _MAX_SHELL_ARG_LEN);
    // Now apply the standard single-quote escape for the remaining
    // apostrophes so the value lands inside the outer `'…'`.
    return out.replace(/'/g, "'\\''");
}

/**
 * Validate a URL before opening it externally or embedding it in HTML.
 *
 * Returns the original URL only when its scheme is on the allowlist
 * (`http:`, `https:`, `mailto:`) and the URL parses cleanly. Returns
 * the empty string for every other input (including `javascript:`,
 * `file:`, `data:`, `about:`, custom schemes, malformed input, and
 * `null` / `undefined`).
 *
 * @param {string} url  The URL to validate.
 * @returns {string}    The original URL if allowed, or `""`.
 */
function validateUrl(url) {
    if (url === null || url === undefined)
        return "";
    var s = String(url).trim();
    if (s === "")
        return "";
    // Cheap pre-screen — anything that looks like `scheme:` must match
    // the allowlist exactly. Lowercase comparison is safe because URL
    // schemes are case-insensitive.
    var lower = s.toLowerCase();
    var ok = false;
    for (var i = 0; i < _ALLOWED_URL_SCHEMES.length; i++) {
        var scheme = _ALLOWED_URL_SCHEMES[i];
        if (lower.indexOf(scheme) === 0) {
            // Make sure the scheme is the *prefix* of a real authority,
            // not a substring (e.g. `xhttps:` must not match `https:`).
            // For http(s):// and mailto:, the next char must be `/` for
            // web URLs, and any non-control character for mailto
            // (e.g. `mailto:user@example.com`).
            var after = s.substring(scheme.length);
            if (after.length === 0)
                continue;
            var first = after.charAt(0);
            if (scheme === "mailto:") {
                // mailto takes an email address, no path delimiter required
                if (first !== " " && first !== "\t" && first !== "\n" && first !== "\r")
                    ok = true;
            } else {
                if (first === "/" || first === "?" || first === "#")
                    ok = true;
            }
            break;
        }
    }
    if (!ok)
        return "";
    return s;
}

/**
 * Escape a URL for safe inclusion in an HTML `href` attribute.
 *
 * Strips characters that could break out of the double-quoted context
 * or inject JavaScript handlers. The result is also validated by
 * `validateUrl()` so `javascript:`, `data:`, etc. are rejected.
 *
 * @param {string} url  Raw URL.
 * @returns {string}    Sanitized URL safe for `href="…"`, or `""`.
 */
function safeHref(url) {
    var validated = validateUrl(url);
    if (validated === "")
        return "";
    // Defense in depth: drop any double-quote, backtick, or angle
    // bracket that could escape the attribute value.
    return validated.replace(/[\"\`<>]/g, "");
}

/**
 * Validate a local file path before embedding it in a shell command.
 *
 * Allows only characters that are common in real filenames and rejects
 * everything that could be exploited to break out of the quoted
 * argument. Path traversal segments (`..`) are also rejected.
 *
 * Returns `""` for any non-string input, paths containing
 * traversal sequences, or paths with disallowed characters.
 *
 * @param {string} p  Raw file path.
 * @returns {string}  Sanitized path, or `""` if invalid.
 */
function validateFilePath(p) {
    if (p === null || p === undefined)
        return "";
    var s = String(p);
    if (s === "")
        return "";
    // Reject path traversal outright — `..` segments are never needed
    // for legitimate file references.
    if (s.indexOf("..") !== -1)
        return "";
    if (!_SAFE_PATH_CHARS.test(s))
        return "";
    return s;
}

/**
 * Validate a session id (e.g. OpenCode remote session) before using
 * it as a URL path component.
 *
 * Allows the same characters that the OpenCode server itself emits
 * (alphanumerics and dashes) up to a reasonable length. Returns `""`
 * for anything else so the caller can fail fast.
 *
 * @param {string} id  Raw session id.
 * @returns {string}   Sanitized id, or `""` if invalid.
 */
function validateSessionId(id) {
    if (id === null || id === undefined)
        return "";
    var s = String(id);
    if (!_SAFE_SESSION_ID.test(s))
        return "";
    return s;
}

/**
 * Convenience wrapper: sanitize a string and return it wrapped in
 * shell single quotes, ready to be interpolated directly into a
 * `sh -lc '…'` command. Use this as a drop-in replacement for the
 * old `shellEscape()` style calls.
 *
 *     cmd = "sh -lc 'notify-send \"KDE AI Chat\" \"" + Sec.quoteForShell(title) + "\" " + Sec.quoteForShell(body) + " '"
 *
 * @param {string} s  Raw value.
 * @returns {string}  Quoted, sanitized value (`'…'` with escapes).
 */
function quoteForShell(s) {
    return "'" + sanitizeForShell(s) + "'";
}

/**
 * Redact common secret-bearer patterns from a string before it is shown
 * to the user or written to a log.
 *
 * Targets:
 *   - `Authorization: Bearer …` / `Authorization: Basic …` headers
 *   - `api_key=…`, `apikey=…`, `key=…`, `token=…` query parameters
 *   - JSON keys: `"api_key"`, `"apiKey"`, `"access_token"`, `"secret"`
 *   - Sk- prefixed OpenAI-style keys (`sk-…`, `sk-proj-…`)
 *
 * The redaction replaces the value (not the key) with `***` so the
 * surrounding URL / log line is still readable. Patterns are
 * case-insensitive on the key side and only match keys surrounded by
 * reasonable delimiters so we don't mangle unrelated text.
 *
 * @param {string} s  Raw value (null/undefined treated as empty).
 * @returns {string}  Redacted string safe to display.
 */
function scrubSecrets(s) {
    if (s === null || s === undefined)
        return "";
    var out = String(s);
    if (out.length > 8192)
        out = out.substring(0, 8192);
    // Authorization: Bearer xxx / Basic xxx (header form, possibly multi-line)
    out = out.replace(/(authorization\s*:\s*(?:bearer|basic|token|api[_-]?key)\s+)[^\s,;"'<>]+/gi, "$1***");
    // Query parameters with secret-looking names
    out = out.replace(/((?:api[_-]?key|apikey|access[_-]?token|secret[_-]?key|token|key)=)([^&\s"'<>]+)/gi, "$1***");
    // JSON / object-style key/value pairs in body text
    out = out.replace(/("(?:api[_-]?key|apiKey|access[_-]?token|accessToken|secret|secretKey|token)"\s*:\s*")([^"]+)(")/gi, "$1***$3");
    // OpenAI-style sk- keys (20+ chars after prefix). Limited to `[A-Za-z0-9_-]`
    out = out.replace(/\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b/g, "sk-***");
    return out;
}
