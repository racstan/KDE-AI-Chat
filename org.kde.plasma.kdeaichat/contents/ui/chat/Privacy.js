.pragma library
// Where a chat's messages go, in plain words: the privacy badge above the
// message box (PrivacyBadge.qml) and the empty chat (EmptyState.qml) both use it.
//
// "here"    - a model server on this computer (localhost, 127.x, ::1, 0.0.0.0)
// "network" - a server on the local network (private addresses, *.local)
// "cloud"   - anything else: the provider's servers
// "agent"   - OpenCode or Pi: the agent runs here and sends the messages to the
//             model provider it is set up with (which may be local or cloud)

function placeOf(baseUrl) {
    var url = String(baseUrl || "");
    var m = /^[a-z][a-z0-9+.-]*:\/\/(\[[^\]]*\]|[^\/:?#]*)/i.exec(url);
    var host = m ? m[1].toLowerCase() : "";
    if (host === "")
        return "cloud";
    var ipv4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
    var a = ipv4 ? Number(ipv4[1]) : -1, b = ipv4 ? Number(ipv4[2]) : -1;
    if (host === "localhost" || a === 127 || host === "[::1]" || host === "0.0.0.0")
        return "here";
    if (a === 10 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31) || (a === 169 && b === 254)
            || /\.local$/.test(host) || /^\[f[cd][0-9a-f]{2}:/.test(host))
        return "network";
    return "cloud";
}

// mode: "provider", "opencode" or "pi". Returns {place, icon}; the QML that
// shows it has the (translated) wording for each place.
function describe(mode, baseUrl) {
    if (mode === "opencode" || mode === "pi")
        return {"place": "agent", "icon": "computer"};
    var place = placeOf(baseUrl);
    return {"place": place, "icon": place === "here" ? "computer" : place === "network" ? "network-workgroup" : "folder-cloud"};
}
