import QtQuick
import org.kde.plasma.workspace.dbus as DBus

Item {
    Component.onCompleted: {
        var reply = DBus.SessionBus.asyncCall({
            service: "org.kde.kwalletd6",
            path: "/modules/kwalletd6",
            iface: "org.kde.KWallet",
            member: "wallets"
        });
        reply.finished.connect(function() {
            if (reply.isError) {
                console.error("DBUS ERROR wallets:", reply.error);
            } else {
                var val = reply.value;
                if (val !== null && val !== undefined && val.hasOwnProperty("value")) val = val.value;
                console.log("WALLETS:", JSON.stringify(val));
                
                var reply2 = DBus.SessionBus.asyncCall({
                    service: "org.kde.kwalletd6",
                    path: "/modules/kwalletd6",
                    iface: "org.kde.KWallet",
                    member: "open",
                    arguments: ["kdewallet", new DBus.int64(0), "org.kde.plasma.kdeaichat"]
                });
                reply2.finished.connect(function() {
                    if (reply2.isError) {
                        console.error("DBUS ERROR open:", reply2.error);
                    } else {
                        var val2 = reply2.value;
                        if (val2 !== null && val2 !== undefined && val2.hasOwnProperty("value")) val2 = val2.value;
                        console.log("HANDLE:", val2);
                    }
                    Qt.quit();
                });
            }
        });
    }
}
