.pragma library

/**
 * SessionManager — session identity, parsing, and base64 utilities.
 *
 * Pure helpers used by main.qml and ConfigGeneral.qml to keep session
 * lifecycle logic out of UI code. All functions are synchronous and
 * stateless.
 *
 * @module SessionManager
 */

/**
 * Generate a session id suitable for the local chat list.
 *
 * Format: `s-<12 hex chars>` derived from a UUIDv4. The 12-char suffix
 * keeps sidebar labels compact while remaining collision-resistant
 * for typical personal-session volumes.
 *
 * @returns {string} A new session id, e.g. `"s-3f2a9b1e7c4d"`.
 */
function makeSessionId() {
    let uuid = createUuid();
    return "s-" + uuid.substring(0, 12);
}

/**
 * Generate a session id for a forked conversation.
 *
 * Format: `fork-<12 hex chars>` so the sidebar can visually distinguish
 * forks from origin sessions.
 *
 * @returns {string} A new fork session id.
 */
function makeForkSessionId() {
    let uuid = createUuid();
    return "fork-" + uuid.substring(0, 12);
}

/**
 * Generate an id for a scheduler entry.
 *
 * Format: `sched-<12 hex chars>`. The scheduler daemon uses this as
 * the primary key when writing schedule JSON, so it must be globally
 * unique within the user's schedule file.
 *
 * @returns {string} A new scheduler entry id.
 */
function makeScheduleEntryId() {
    let uuid = createUuid();
    return "sched-" + uuid.substring(0, 12);
}

/**
 * Generate an RFC4122 version-4 UUID.
 *
 * Used internally by the public id helpers. Implemented manually
 * because `.pragma library` JavaScript modules do not have access to
 * the QML `Qt` namespace (`Qt.createUuid()` is unavailable here).
 *
 * Format: `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx` where `4` is the
 * version nibble and `y` is one of `{8,9,a,b}` (the variant bits).
 *
 * Note: Not cryptographically secure — uses `Math.random()`. Sufficient
 * for client-side UI ids that are never exposed to the network.
 *
 * @returns {string} A new UUIDv4 string.
 */
function createUuid() {
    let chars = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx";
    let result = "";
    for (let i = 0; i < chars.length; i++) {
        let c = chars[i];
        if (c === "x") {
            result += Math.floor(Math.random() * 16).toString(16);
        } else if (c === "y") {
            result += (Math.floor(Math.random() * 4) + 8).toString(16);
        } else {
            result += c;
        }
    }
    return result;
}

/**
 * Coerce a raw session list (JSON string or pre-parsed array) into a
 * normalized array with all expected fields populated.
 *
 * For each session, fills in:
 *  - `messages`: empty array if missing
 *  - `archived`: false if missing
 *  - `source`: `"opencode"` or `"provider"` based on `openCodeSessionId`
 *  - `readCount`: message count if missing
 *  - `updatedAt`: `createdAt` or `Date.now()` if missing
 *
 * For each message, fills in:
 *  - `at`: timestamp (uses `updatedAt`/`createdAt` as fallback)
 *  - `time`: formatted time string via the `nowTimeFn(ms)` callback
 *
 * On parse failure, returns an empty array — never throws.
 *
 * @param {string|Array} raw  Serialized or pre-parsed session list.
 * @param {function(number):string} [nowTimeFn]  Optional formatter for
 *   the `time` field. Receives the millisecond timestamp.
 * @returns {Array} Normalized session array (possibly empty).
 */
function parseSessions(raw, nowTimeFn) {
    try {
        let arr = typeof raw === "string" ? JSON.parse(raw) : raw;
        if (Array.isArray(arr)) {
            for (let i = 0; i < arr.length; i++) {
                if (!arr[i].messages)
                    arr[i].messages = [];

                if (arr[i].archived === undefined)
                    arr[i].archived = false;

                if (!arr[i].source)
                    arr[i].source = arr[i].openCodeSessionId ? "opencode" : "provider";

                if (arr[i].readCount === undefined)
                    arr[i].readCount = arr[i].messages.length;

                for (let j = 0; j < arr[i].messages.length; j++) {
                    if (!arr[i].messages[j].at)
                        arr[i].messages[j].at = arr[i].updatedAt || arr[i].createdAt || Date.now();

                    if (!arr[i].messages[j].time && nowTimeFn)
                        arr[i].messages[j].time = nowTimeFn(arr[i].messages[j].at);

                }
                if (!arr[i].updatedAt)
                    arr[i].updatedAt = arr[i].createdAt || Date.now();

            }
            return arr;
        }
        return [];
    } catch (e) {
        return [];
    }
}

/**
 * Find the index of a session within an array by its id.
 *
 * @param {Array} sessions  Session list.
 * @param {string} sessionId  The session id to look up (`value` field).
 * @returns {number} Index into the array, or -1 if not found.
 */
function sessionIndexById(sessions, sessionId) {
    for (let i = 0; i < sessions.length; i++) {
        if (sessions[i].value === sessionId)
            return i;

    }
    return -1;
}

/**
 * Return a copy of the session list sorted for sidebar display.
 *
 * Sort order:
 *  1. Non-archived before archived.
 *  2. Within each group, most recently updated first
 *     (`updatedAt`, falling back to `createdAt`).
 *
 * The input array is not mutated; a shallow copy is returned.
 *
 * @param {Array} sessions  Session list.
 * @returns {Array} New sorted array.
 */
function sortSessionsByUpdated(sessions) {
    let copy = sessions.slice();
    copy.sort(function(a, b) {
        if (!!a.archived !== !!b.archived)
            return a.archived ? 1 : -1;

        return (b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0);
    });
    return copy;
}

/**
 * Check whether a session list is already in the canonical sort order
 * produced by `sortSessionsByUpdated`.
 *
 * This lets call sites skip the O(n log n) sort + array reassignment
 * cascade when nothing has changed that could affect the order — most
 * commonly after a no-op `saveCurrentSessionState()` call. Returned
 * true means the array can be passed through unchanged.
 *
 * @param {Array} sessions  Session list to test.
 * @returns {boolean} True if the list is already sorted by the same
 *                    comparator as `sortSessionsByUpdated`.
 */
function isSessionOrderCorrect(sessions) {
    if (!sessions || sessions.length < 2)
        return true;

    for (let i = 1; i < sessions.length; i++) {
        let prev = sessions[i - 1];
        let cur = sessions[i];
        if (!!prev.archived !== !!cur.archived) {
            if (!!prev.archived)
                return false;
        } else {
            let prevTs = prev.updatedAt || prev.createdAt || 0;
            let curTs = cur.updatedAt || cur.createdAt || 0;
            if (prevTs < curTs)
                return false;
        }
    }
    return true;
}

/**
 * Build a fresh session object.
 *
 * @param {string} sessionId  Id to assign (`value` field).
 * @param {boolean} [useOpenCode]  If true, `source` is `"opencode"`.
 * @returns {Object} A new session object with default fields populated.
 */
function createSessionObj(sessionId, useOpenCode) {
    return {
        "value": sessionId,
        "text": "New Chat",
        "createdAt": Date.now(),
        "updatedAt": Date.now(),
        "archived": false,
        "source": useOpenCode ? "opencode" : "provider",
        "openCodeSessionId": "",
        "readCount": 0,
        "messages": []
    };
}

/**
 * Build a session object that is a fork of another session.
 *
 * The fork inherits the parent's `source` and `openCodeSessionId` and
 * gets a back-pointer (`parentSessionId`, `parentSessionTitle`) so the
 * UI can show "Forked from <title>".
 *
 * @param {Object} originalSession  The session being forked from.
 * @param {string} forkId  Id to assign to the new fork.
 * @param {string} forkTitle  Display title for the new fork.
 * @param {Array} forkedMessages  Messages carried over to the fork.
 * @returns {Object} A new session object representing the fork.
 */
function forkSessionObj(originalSession, forkId, forkTitle, forkedMessages) {
    return {
        "value": forkId,
        "text": forkTitle,
        "createdAt": Date.now(),
        "updatedAt": Date.now(),
        "archived": false,
        "source": originalSession.source || "provider",
        "openCodeSessionId": originalSession.openCodeSessionId || "",
        "parentSessionId": originalSession.value,
        "parentSessionTitle": originalSession.text || "Original Chat",
        "readCount": forkedMessages.length,
        "messages": forkedMessages
    };
}

/**
 * Encode a string to base64 (RFC 4648 standard alphabet).
 *
 * Implemented manually because `.pragma library` modules do not have
 * `btoa`. Returns the empty string on any error (e.g. surrogate pairs
 * in the input).
 *
 * @param {string} str  Raw string to encode.
 * @returns {string} Base64-encoded string, or `""` on failure.
 */
function base64Encode(str) {
    try {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
        let result = "";
        let i = 0;
        while (i < str.length) {
            let a = str.charCodeAt(i++);
            let b = i < str.length ? str.charCodeAt(i++) : 0;
            let c = i < str.length ? str.charCodeAt(i++) : 0;
            let bitmap = (a << 16) | (b << 8) | c;
            result += chars.charAt((bitmap >> 18) & 63);
            result += chars.charAt((bitmap >> 12) & 63);
            result += i - 2 < str.length ? chars.charAt((bitmap >> 6) & 63) : "=";
            result += i - 1 < str.length ? chars.charAt(bitmap & 63) : "=";
        }
        return result;
    } catch (e) {
        return "";
    }
}

/**
 * Decode a base64 string (RFC 4648 standard alphabet).
 *
 * Implemented manually because `.pragma library` modules do not have
 * `atob`. Strips any non-base64 characters before decoding. Returns
 * the empty string on any error.
 *
 * @param {string} str  Base64-encoded string to decode.
 * @returns {string} Decoded string, or `""` on failure.
 */
function base64Decode(str) {
    try {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
        let result = "";
        let i = 0;
        str = str.replace(/[^A-Za-z0-9+/=]/g, "");
        while (i < str.length) {
            let enc1 = chars.indexOf(str.charAt(i++));
            let enc2 = chars.indexOf(str.charAt(i++));
            let enc3 = chars.indexOf(str.charAt(i++));
            let enc4 = chars.indexOf(str.charAt(i++));
            let bitmap = (enc1 << 18) | (enc2 << 12) | (enc3 << 6) | enc4;
            result += String.fromCharCode((bitmap >> 16) & 255);
            if (enc3 !== 64) result += String.fromCharCode((bitmap >> 8) & 255);
            if (enc4 !== 64) result += String.fromCharCode(bitmap & 255);
        }
        return result;
    } catch (e) {
        return "";
    }
}

/**
 * Immutably update a single session inside a sessions array.
 *
 * Replaces the repeated pattern:
 *   let updated = sessions.slice();
 *   let item = Object.assign({}, updated[idx]);
 *   item.X = Y;
 *   updated[idx] = item;
 *   sessions = updated;
 *
 * with a single call:
 *   sessions = updateSession(sessions, sessionId, function(s) { s.X = Y; });
 *
 * The original array is not mutated. A shallow copy is returned with the
 * target session replaced by the mutator's output. If no session matches
 * `sessionId`, the original array is returned unchanged.
 *
 * @param {Array} sessions   Current session list.
 * @param {string} sessionId The session id (`value` field) to update.
 * @param {Function} mutator Called with a shallow clone of the matching
 *                           session. May mutate its argument freely.
 * @returns {Array} New sessions array with the updated session.
 */
function updateSession(sessions, sessionId, mutator) {
    for (let i = 0; i < sessions.length; i++) {
        if (sessions[i].value === sessionId) {
            let updated = sessions.slice();
            let clone = {};
            let src = updated[i];
            for (let k in src) {
                if (src.hasOwnProperty(k))
                    clone[k] = src[k];
            }
            mutator(clone);
            updated[i] = clone;
            return updated;
        }
    }
    return sessions;
}
