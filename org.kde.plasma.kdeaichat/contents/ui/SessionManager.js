.pragma library

function makeSessionId() {
    var uuid = createUuid();
    return "s-" + uuid.substring(0, 12);
}

function makeForkSessionId() {
    var uuid = createUuid();
    return "fork-" + uuid.substring(0, 12);
}

function makeScheduleEntryId() {
    var uuid = createUuid();
    return "sched-" + uuid.substring(0, 12);
}

function createUuid() {
    var chars = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx";
    var result = "";
    for (var i = 0; i < chars.length; i++) {
        var c = chars[i];
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

function parseSessions(raw, nowTimeFn) {
    try {
        var arr = typeof raw === "string" ? JSON.parse(raw) : raw;
        if (Array.isArray(arr)) {
            for (var i = 0; i < arr.length; i++) {
                if (!arr[i].messages)
                    arr[i].messages = [];

                if (arr[i].archived === undefined)
                    arr[i].archived = false;

                if (!arr[i].source)
                    arr[i].source = arr[i].openCodeSessionId ? "opencode" : "provider";

                if (arr[i].readCount === undefined)
                    arr[i].readCount = arr[i].messages.length;

                for (var j = 0; j < arr[i].messages.length; j++) {
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

function sessionIndexById(sessions, sessionId) {
    for (var i = 0; i < sessions.length; i++) {
        if (sessions[i].value === sessionId)
            return i;

    }
    return -1;
}

function sortSessionsByUpdated(sessions) {
    var copy = sessions.slice();
    copy.sort(function(a, b) {
        if (!!a.archived !== !!b.archived)
            return a.archived ? 1 : -1;

        return (b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0);
    });
    return copy;
}

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

function base64Encode(str) {
    try {
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
        var result = "";
        var i = 0;
        while (i < str.length) {
            var a = str.charCodeAt(i++);
            var b = i < str.length ? str.charCodeAt(i++) : 0;
            var c = i < str.length ? str.charCodeAt(i++) : 0;
            var bitmap = (a << 16) | (b << 8) | c;
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

function base64Decode(str) {
    try {
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
        var result = "";
        var i = 0;
        str = str.replace(/[^A-Za-z0-9+/=]/g, "");
        while (i < str.length) {
            var enc1 = chars.indexOf(str.charAt(i++));
            var enc2 = chars.indexOf(str.charAt(i++));
            var enc3 = chars.indexOf(str.charAt(i++));
            var enc4 = chars.indexOf(str.charAt(i++));
            var bitmap = (enc1 << 18) | (enc2 << 12) | (enc3 << 6) | enc4;
            result += String.fromCharCode((bitmap >> 16) & 255);
            if (enc3 !== 64) result += String.fromCharCode((bitmap >> 8) & 255);
            if (enc4 !== 64) result += String.fromCharCode(bitmap & 255);
        }
        return result;
    } catch (e) {
        return "";
    }
}
