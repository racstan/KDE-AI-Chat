.pragma library

/**
 * RequestDeduplicator — collapse duplicate in-flight chat requests.
 *
 * Prevents the user from accidentally sending the same message twice
 * (e.g. a double-click of the send button, or two near-simultaneous
 * key presses) from triggering two parallel HTTP calls to the
 * provider. Requests are identified by a hash of `(provider, model,
 * lastUserText, sessionId)` so that a follow-up genuine message in
 * the same session is never blocked, and a retry of the same message
 * with a different model is also treated as a distinct request.
 *
 * The module exposes three operations:
 *  - `key(...)` to build the dedup key for a request
 *  - `tryClaim(key)` to atomically mark a key as in-flight
 *  - `release(key)` to clear a key once the request finishes
 *
 * Storage is a simple in-memory map. `.pragma library` modules are
 * shared across all QML components, so claims made in main.qml are
 * visible to all other consumers in the same process.
 *
 * @module RequestDeduplicator
 */

let _inFlight = {};

/**
 * Build a deduplication key for an outgoing chat request.
 *
 * The key is a stable, opaque string. Two requests with the same
 * `(provider, model, lastUserText, sessionId)` produce the same key.
 *
 * @param {string} provider      Provider id (e.g. "openai", "anthropic").
 * @param {string} model         Model name (may be empty for routed backends).
 * @param {string} lastUserText  The last user message in the conversation
 *   (used to identify the *current* turn, not the full history).
 * @param {string} sessionId     The chat session id.
 * @returns {string} Opaque dedup key.
 */
function key(provider, model, lastUserText, sessionId) {
    return (provider || "") + "\u0001" + (model || "") + "\u0001" + (lastUserText || "") + "\u0001" + (sessionId || "");
}

/**
 * Try to claim a key as in-flight. Returns `true` if the claim was
 * granted (caller should proceed with the request). Returns `false`
 * if the key is already in flight (caller should bail out and show
 * a "duplicate request" message).
 *
 * @param {string} dedupKey  Key built by `key()`.
 * @returns {boolean} True if newly claimed, false if a duplicate.
 */
function tryClaim(dedupKey) {
    if (_inFlight[dedupKey])
        return false;
    _inFlight[dedupKey] = true;
    return true;
}

/**
 * Release a previously claimed key. Should be called from both
 * success and error paths of the HTTP request.
 *
 * @param {string} dedupKey  Key that was previously claimed.
 */
function release(dedupKey) {
    if (dedupKey)
        delete _inFlight[dedupKey];
}

/**
 * Test whether a key is currently in flight. Useful for UI state
 * without claiming the slot.
 *
 * @param {string} dedupKey  Key to test.
 * @returns {boolean} True if a request with this key is in flight.
 */
function isInFlight(dedupKey) {
    return !!_inFlight[dedupKey];
}

/**
 * Return the current count of in-flight requests. Intended for
 * diagnostics and tests.
 *
 * @returns {number} Number of tracked in-flight requests.
 */
function inFlightCount() {
    return Object.keys(_inFlight).length;
}

/**
 * Clear all tracked in-flight requests. Intended for tests and for
 * the rare "reset all" button; callers should normally prefer the
 * targeted `release()`.
 */
function clearAll() {
    _inFlight = {};
}
