.pragma library

/**
 * LRUCache — a simple, predictable bounded Map keyed cache.
 *
 * Each entry stores the key in an LRU order list. When the size
 * exceeds `capacity` the oldest entry is evicted. This is a
 * JavaScript-only implementation (no Qt types) so it is usable
 * from both QML and other `.pragma library` modules.
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
    let map = ({} );
    let order = [];
    let self = {
        "capacity": cap,
        "size": 0,
        /**
         * @param {string} key
         * @returns {*} Stored value, or `undefined` if missing.
         */
        "get": function(key) {
            if (!Object.prototype.hasOwnProperty.call(map, key))
                return undefined;
            // Touch: move to the back of the order list
            let idx = order.indexOf(key);
            if (idx !== -1) {
                order.splice(idx, 1);
                order.push(key);
            }
            return map[key];
        },
        /**
         * @param {string} key
         * @param {*} value
         */
        "put": function(key, value) {
            if (Object.prototype.hasOwnProperty.call(map, key)) {
                map[key] = value;
                let idx = order.indexOf(key);
                if (idx !== -1) {
                    order.splice(idx, 1);
                    order.push(key);
                }
                return ;
            }
            map[key] = value;
            order.push(key);
            if (order.length > cap) {
                let oldest = order.shift();
                delete map[oldest];
            }
            self.size = order.length;
        },
        /**
         * Drop all entries.
         */
        "clear": function() {
            map = ({} );
            order = [];
            self.size = 0;
        }
    };
    return self;
}
