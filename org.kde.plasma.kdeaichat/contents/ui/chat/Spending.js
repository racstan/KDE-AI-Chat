.pragma library

// Pure helpers for the spending log (kdeaichat/usage.py): the budgets setting, the helper's replies, the
// provider lines and the per-day bars of Settings -> Spending. Used by chat/SpendingLog.qml and
// config/ConfigSpending.qml. Plain JavaScript on purpose (tested with node: tests/js/spending.test.js).

var MAX_BUDGET = 1000000000000;

// The budgets setting (spendingBudgets: a JSON object of provider id -> monthly limit in dollars) as an object
// with only the usable entries: positive finite numbers.
function parseBudgets(text) {
    var data = null;
    try { data = JSON.parse(String(text || "{}")); } catch (e) { data = null; }
    return cleanBudgets(data);
}

function cleanBudgets(map) {
    var out = {};
    if (!map || typeof map !== "object" || Array.isArray(map))
        return out;
    Object.keys(map).forEach(function(id) {
        var value = map[id];
        if (id !== "" && typeof value === "number" && isFinite(value) && value > 0 && value <= MAX_BUDGET)
            out[id] = value;
    });
    return out;
}

function serializeBudgets(map) {
    return JSON.stringify(cleanBudgets(map));
}

// The helper's answer: its last output line as an object, or null.
function parseReply(stdout) {
    try {
        var data = JSON.parse(String(stdout || "").trim().split("\n").pop());
        return data && typeof data === "object" && !Array.isArray(data) ? data : null;
    } catch (e) {
        return null;
    }
}

// How much of a budget is spent, in whole percent (0 without a usable budget).
function percentUsed(spent, budget) {
    var limit = Number(budget) || 0;
    return limit > 0 ? Math.round((Number(spent) || 0) / limit * 100) : 0;
}

// "YYYY-MM" of a Date, in local time.
function monthOf(date) {
    var month = date.getMonth() + 1;
    return date.getFullYear() + "-" + (month < 10 ? "0" : "") + month;
}

// The months to offer: the helper's list plus `current`, unique, newest first.
function monthList(months, current) {
    var seen = {};
    var out = [];
    (months || []).concat([current]).forEach(function(m) {
        if (typeof m === "string" && /^\d{4}-(0[1-9]|1[0-2])$/.test(m) && !seen[m]) {
            seen[m] = true;
            out.push(m);
        }
    });
    return out.sort().reverse();
}

// One line per provider, in this order: the configured providers, then any other provider with spending
// or a budget. Each line carries the month's totals and its monthly budget (0 = none).
function providerRows(configuredIds, providers, budgets) {
    var seen = {};
    var ids = [];
    function add(id) {
        if (typeof id === "string" && id !== "" && !seen[id]) {
            seen[id] = true;
            ids.push(id);
        }
    }
    (configuredIds || []).forEach(add);
    Object.keys(providers || {}).forEach(add);
    Object.keys(budgets || {}).forEach(add);
    return ids.map(function(id) {
        var totals = (providers || {})[id] || {};
        return {"id": id, "count": totals.count || 0, "input": totals.input || 0, "output": totals.output || 0,
                "cacheRead": totals.cacheRead || 0, "cost": totals.cost || 0, "costCount": totals.costCount || 0,
                "budget": (budgets || {})[id] || 0};
    });
}

// The month's days in date order, each with a bar length (fraction of the busiest day's tokens, 0..1).
function dayRows(days) {
    var keys = Object.keys(days || {}).sort();
    var rows = keys.map(function(key) {
        var totals = days[key] || {};
        var tokens = (totals.input || 0) + (totals.output || 0);
        return {"key": key, "label": String(parseInt(key.slice(8), 10)), "tokens": tokens, "count": totals.count || 0,
                "cost": totals.cost || 0, "costCount": totals.costCount || 0, "fraction": 0};
    });
    var busiest = rows.reduce(function(max, row) { return Math.max(max, row.tokens); }, 0);
    rows.forEach(function(row) { row.fraction = busiest > 0 ? row.tokens / busiest : 0; });
    return rows;
}
