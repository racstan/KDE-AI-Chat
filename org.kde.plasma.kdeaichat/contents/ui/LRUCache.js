.pragma library

/**
 * LRUCache — a simple, predictable bounded Map keyed cache.
 *
 * Each entry is stored in a `Map`, which natively preserves insertion
 * order. The least-recently-used entry is the first key in iteration
 * order. This implementation is O(1) for both get and put, in contrast
 * to the previous array-based version that did an O(N) `indexOf` on
 * every cache touch (and ran 500 string comparisons per cache hit at
 * capacity 500 — measurable during streaming where the same key is
 * hit on every token).
 *
 * Usage:
 *   let cache = LRUCache.create(500);
 *   let html = cache.get(key);
 *   if (html === undefined) {
 *       html = renderExpensive(input);
 *       cache.put(key, html);
 *   }
 *
 * Eviction is by insertion order (FIFO-with-eviction), which is a
 * good-enough approximation of LRU for the widget's markdown/blocks
 * caches: streaming tokens keep hitting the same keys and older
 * unrelated content is shed first.
 */

/**
 * Construct a new cache. Returns an object exposing `get`, `put`,
 * `clear`, and `size`.
 *
 * @param {number} [capacity=500]  Maximum number of entries. Values
 *                                <= 0 fall back to the default.
 * @returns {object}
 */
function create(capacity) {
    let cap = Math.max(1, Math.floor(capacity || 500));
    let map = new Map();
    let self = {
        "capacity": cap,
        "size": 0,
        /**
         * @param {string} key
         * @returns {*} Stored value, or `undefined` if missing.
         */
        "get": function(key) {
            if (!map.has(key))
                return undefined;
            // Touch: delete + re-insert moves the key to the back
            // (most-recently-used position) in O(1).
            let value = map.get(key);
            map.delete(key);
            map.set(key, value);
            return value;
        },
        /**
         * @param {string} key
         * @param {*} value
         */
        "put": function(key, value) {
            if (map.has(key)) {
                map.delete(key);
            }
            map.set(key, value);
            if (map.size > cap) {
                // First key in iteration order is the oldest entry.
                let oldest = map.keys().next().value;
                map.delete(oldest);
            }
            self.size = map.size;
        },
        /**
         * Drop all entries.
         */
        "clear": function() {
            map.clear();
            self.size = 0;
        }
    };
    return self;
}
