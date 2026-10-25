.pragma library
// Times and dates as the chat shows them.

function pad2(v) {
    return v < 10 ? ("0" + v) : String(v);
}

// "HH:MM" of `ts` (now when ts is empty).
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

// "Today", "Yesterday", "Day before yesterday" or "Mon DD, YYYY".
function dayBucketLabel(ts) {
    var target = new Date(ts);
    var now = new Date();
    var today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    var targetDay = new Date(target.getFullYear(), target.getMonth(), target.getDate());
    var daysDiff = Math.floor((today.getTime() - targetDay.getTime()) / 8.64e+07);
    if (daysDiff === 0)
        return "Today";

    if (daysDiff === 1)
        return "Yesterday";

    if (daysDiff === 2)
        return "Day before yesterday";

    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return months[target.getMonth()] + " " + pad2(target.getDate()) + ", " + target.getFullYear();
}
