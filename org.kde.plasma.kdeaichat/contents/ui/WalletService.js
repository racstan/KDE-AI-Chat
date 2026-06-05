.pragma library

/**
 * WalletService — KWallet shell command generation
 *
 * Centralizes the shell-script generation for KWallet reads via qdbus.
 * Used by both main.qml (startup bulk read) and ConfigGeneral.qml
 * (config dialog bulk read) to eliminate duplication.
 *
 * The scripts use single-quote escape (`'\\''`) to safely embed values
 * into the outer `sh -lc '...'` wrapper. They auto-detect qdbus6 vs qdbus
 * and use shell-sentinel markers (`__KAI_BULK__:...`, `__KAI_SECRET__:...`)
 * so the QML side can parse stdout lines and correlate with the
 * `#kwallet-startup-load` / `#kwallet-refresh-all` job markers appended
 * to each command.
 */

/**
 * Escape a string for use inside a single-quoted shell argument.
 *
 * Replaces every single-quote with the standard POSIX close-quote /
 * escaped-quote / open-quote sequence: `'\\''`.
 *
 * @param {string} s  Raw value (null/undefined treated as empty).
 * @returns {string}  Escaped value safe to embed in `'…'`.
 */
function shellEscape(s) {
    return sanitizeForShell(s || "").replace(/'/g, "'\\''");
}

/**
 * Strip shell metacharacters that survive single-quote escaping.
 *
 * Removes `$`, backtick, `(`, `)`, `\`, `;`, `&`, `|`, `<`, `>`, newline,
 * carriage return, NUL, and BEL. Length-clamped to 4096 to keep command
 * lines bounded. The result is then safe to single-quote-escape.
 *
 * Mirrors Security.js:sanitizeForShell so this .pragma-library module
 * stays self-contained (it cannot import other .pragma-library modules).
 */
function sanitizeForShell(s) {
    s = String(s);
    if (s.length > 4096)
        s = s.substring(0, 4096);
    return s.replace(/[`$(){}|;&<>\n\r\x00\x07\\\\]/g, "");
}

/**
 * Build a `sh -lc '…'` command that opens a KWallet, reads the API-key
 * entry for every provider in `targets`, and emits a `__KAI_BULK__:DONE`
 * terminator line. Wallet-existence and open/folder checks emit their own
 * sentinel so the QML consumer can bail out early without parsing the
 * rest of stdout.
 *
 * @param {string} walletName  KWallet wallet name (e.g. "kdewallet").
 * @param {string[]} targets   Provider ids whose `kai-chat-<id>-api-key`
 *                             entries should be read.
 * @param {string} [folder]    KWallet folder name. Defaults to "KaiChat".
 * @param {string} [appId]     KWallet app id. Defaults to plasmoid id.
 * @returns {string}           Full shell pipeline ending in a comment
 *                             placeholder for the QML DataSource job tag.
 */
function buildBulkReadCommand(walletName, targets, folder, appId) {
    let escapedWallet = shellEscape(walletName);
    let escapedFolder = shellEscape(folder || "KaiChat");
    let escapedAppId = shellEscape(appId || "org.kde.plasma.kdeaichat");
    let targetList = (targets || []).join(" ");
    return "sh -lc '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "wallets=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null); " + "if ! printf %s \"$wallets\" | grep -Fxq \"$wallet\"; then printf \"__KAI_BULK__:NO_WALLET\"; exit 0; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_BULK__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; printf \"__KAI_BULK__:NO_FOLDER\"; exit 0; fi; " + "for target in " + targetList + "; do " + "key=\"kai-chat-${target}-api-key\"; " + "hasEntry=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasEntry \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasEntry\" = true ]; then secret=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.readPassword \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null); printf \"__KAI_SECRET__:%s:%s\\n\" \"$target\" \"$secret\"; fi; " + "done; " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "printf \"__KAI_BULK__:DONE\"'";
}
