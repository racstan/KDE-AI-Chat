// KWallet access for API keys: the only place keys are stored.
//
// Keys live in the user's network wallet, folder "KaiChat", entry
// "kai-chat-<providerId>-api-key". Used by the widget (read once at startup,
// reloaded when settings change) and by the settings page (read, write,
// remove). `status` says why keys are unavailable, so the UI can tell the
// user instead of failing silently.
import QtQuick
import org.kde.plasma.workspace.dbus as DBus

QtObject {
    id: wallet

    // "unknown" before the first load; "ready"; "disabled" (KWallet switched
    // off); "denied" (open refused or unlock cancelled); "unavailable"
    // (kwalletd not reachable).
    property string status: "unknown"
    readonly property bool usable: status === "ready"
    property bool busy: false
    // providerId -> key, for the keys found at the last load.
    property var keys: ({})

    readonly property string folder: "KaiChat"
    readonly property string appId: "org.kde.plasma.kdeaichat"

    // D-Bus call used for every KWallet request; tests replace it.
    // call(member, args, onReply(value), onError(message))
    property var call: function(member, args, onReply, onError) {
        var reply;
        try {
            reply = DBus.SessionBus.asyncCall({
                "service": "org.kde.kwalletd6",
                "path": "/modules/kwalletd6",
                "iface": "org.kde.KWallet",
                "member": member,
                "arguments": args
            });
        } catch (e) {
            onError(String(e));
            return;
        }
        reply.finished.connect(function() {
            if (reply.isError) {
                onError(String(reply.error));
                return;
            }
            var value = reply.value;
            if (value !== null && value !== undefined && typeof value === "object" && value.hasOwnProperty("value"))
                value = value.value;
            onReply(value);
        });
    }
    // D-Bus integer/bool wrappers; tests replace them with identity functions.
    property var int32: function(v) { return new DBus.int32(v); }
    property var int64: function(v) { return new DBus.int64(v); }
    property var bool_: function(v) { return new DBus.bool(v); }

    signal loaded()

    function entryName(providerId) {
        return "kai-chat-" + providerId + "-api-key";
    }

    function providerIdFromEntry(name) {
        var match = /^kai-chat-(.+)-api-key$/.exec(String(name || ""));
        return match ? match[1] : "";
    }

    function statusMessage() {
        switch (status) {
        case "ready": return i18n("API keys are stored in KWallet.");
        case "disabled": return i18n("KWallet is turned off, so API keys can't be stored or read. Turn it on in System Settings → KDE Wallet.");
        case "denied": return i18n("KWallet didn't allow access to the API keys (the wallet may be locked or access was refused).");
        case "unavailable": return i18n("KWallet isn't running, so API keys can't be read.");
        default: return i18n("Checking KWallet…");
        }
    }

    // Opens the network wallet and calls work(handle, done). done() closes the
    // wallet and calls finished(ok).
    function _withWallet(createFolder, work, finished) {
        busy = true;
        function fail(newStatus) {
            status = newStatus;
            busy = false;
            if (finished) finished(false);
        }
        call("isEnabled", [], function(enabled) {
            if (enabled === false) { fail("disabled"); return; }
            call("networkWallet", [], function(walletName) {
                call("open", [String(walletName || "kdewallet"), int64(0), appId], function(handle) {
                    if (handle === undefined || handle === null || Number(handle) < 0) { fail("denied"); return; }
                    var h = int32(Number(handle));
                    function done(ok) {
                        call("close", [h, bool_(false), appId], function() {}, function() {});
                        status = "ready";
                        busy = false;
                        if (finished) finished(ok !== false);
                    }
                    call("hasFolder", [h, folder, appId], function(hasFolder) {
                        if (hasFolder || !createFolder) {
                            work(h, done, !!hasFolder);
                            return;
                        }
                        call("createFolder", [h, folder, appId], function() { work(h, done, true); },
                             function() { done(false); });
                    }, function() { done(false); });
                }, function() { fail("denied"); });
            }, function() { fail("unavailable"); });
        }, function() { fail("unavailable"); });
    }

    // Reads every key in one call and replaces `keys`. callback(ok, keys).
    function load(callback) {
        _withWallet(false, function(h, done, hasFolder) {
            if (!hasFolder) {
                keys = ({});
                done(true);
                return;
            }
            call("passwordList", [h, folder, appId], function(map) {
                var next = {};
                var names = map ? Object.keys(map) : [];
                for (var i = 0; i < names.length; i++) {
                    var id = providerIdFromEntry(names[i]);
                    var value = String(map[names[i]] || "").trim();
                    if (id && value)
                        next[id] = value;
                }
                keys = next;
                done(true);
            }, function() { done(false); });
        }, function(ok) {
            if (!ok && status !== "ready")
                keys = ({});
            loaded();
            if (callback) callback(ok, keys);
        });
    }

    // Writes several keys at once: {providerId: key}. An empty key removes
    // the entry. callback(ok).
    function writeMany(entries, callback) {
        var ids = Object.keys(entries || {});
        _withWallet(true, function(h, done) {
            var i = 0;
            var allOk = true;
            function next() {
                if (i >= ids.length) { done(allOk); return; }
                var id = ids[i++];
                var value = String(entries[id] || "").trim();
                var updated = Object.assign({}, keys);
                if (value) {
                    call("writePassword", [h, folder, entryName(id), value, appId], function(result) {
                        if (Number(result) === 0) { updated[id] = value; keys = updated; }
                        else allOk = false;
                        next();
                    }, function() { allOk = false; next(); });
                } else {
                    call("removeEntry", [h, folder, entryName(id), appId], function() {
                        delete updated[id];
                        keys = updated;
                        next();
                    }, function() { next(); });
                }
            }
            next();
        }, callback);
    }

    function write(providerId, value, callback) {
        var entries = {};
        entries[providerId] = value;
        writeMany(entries, callback);
    }

    function remove(providerId, callback) {
        write(providerId, "", callback);
    }
}
