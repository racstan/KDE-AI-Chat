// Settings → Schedules: messages sent into a chat at set times, even with the
// widget closed (each schedule is a systemd user timer that runs the prompt in
// the background). One switch pauses them all; each schedule has its own
// on/off switch, editor (ScheduleDialog.qml) and history. Everything here
// takes effect at once through the helper; nothing is a cfg_ setting.
import QtQuick
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "config" as Config
import "config/ScheduleDraft.js" as Draft
import "store" as Store

// i18n() and plasmoid are provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    readonly property var plasmoidObject: typeof plasmoid !== "undefined" ? plasmoid : null
    readonly property var configuration: plasmoidObject ? plasmoidObject.configuration : null
    // Tests replace the helper (run(command, payload, onDone)) and the network.
    property var runHelper: null
    property var xhrFactory: null
    // store/Wallet.qml, read only when "Describe when" needs a key; tests replace it.
    property var wallet: walletStore

    // "list", "edit" or "history".
    property string view: "list"
    property var historyItem: null
    property var historyState: null

    readonly property string dataDir: decodeURIComponent(String(StandardPaths.writableLocation(
        StandardPaths.GenericDataLocation)).replace(/^file:\/\//, "")) + "/kdeaichat"
    readonly property var sessions: {
        var raw = chatIndex.indexJson() || (configuration ? (configuration.chatSessionsJson || "[]") : "[]");
        try {
            var list = JSON.parse(raw);
            return Array.isArray(list) ? list : [];
        } catch (e) {
            return [];
        }
    }

    function edit(item) {
        if (item)
            dialog.openItem(item);
        else
            dialog.openNew(Draft.chatChoices(sessions, "").length ? Draft.chatChoices(sessions, "")[0].id : "");
        view = "edit";
    }

    function showHistory(item) {
        historyItem = item;
        historyState = null;
        view = "history";
        service.history(item.id, function(result) {
            page.historyState = result.ok ? result.runState : {"history": [], "runCount": 0};
        });
    }

    Store.ChatStore {
        id: chatIndex
        directory: page.plasmoidObject && String(page.plasmoidObject.id) ? page.dataDir + "/chats/applet-" + page.plasmoidObject.id : ""
    }

    Store.Wallet {
        id: walletStore
    }

    Config.ScheduleService {
        id: service
        Component.onCompleted: {
            if (page.runHelper)
                run = page.runHelper;
            refresh();
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        ScheduleDialog {
            id: dialog
            visible: page.view === "edit"
            Layout.fillWidth: true
            service: service
            sessions: page.sessions
            configuration: page.configuration
            wallet: page.wallet
            xhrFactory: page.xhrFactory
            onClosed: page.view = "list"
        }

        Config.ScheduleHistory {
            visible: page.view === "history"
            Layout.fillWidth: true
            title: page.historyItem ? page.historyItem.name : ""
            runState: page.historyState
            onCloseRequested: page.view = "list"
        }

        ColumnLayout {
            visible: page.view === "list"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                QQC2.Switch {
                    objectName: "masterSwitch"
                    text: i18n("Run scheduled messages")
                    checked: !service.paused
                    onToggled: service.setPaused(!checked)
                }
                Item { Layout.fillWidth: true }
                QQC2.Button {
                    objectName: "newSchedule"
                    text: i18n("New schedule…")
                    icon.name: "list-add"
                    onClicked: page.edit(null)
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.7
                text: i18n("Schedules send their message into the chat at the set times, also when the widget is closed, while you are logged in. The answer appears in the chat, with a notification if you want one.")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: service.error !== ""
                type: Kirigami.MessageType.Error
                text: service.error
            }

            Kirigami.PlaceholderMessage {
                objectName: "noSchedules"
                Layout.fillWidth: true
                visible: service.loaded && service.schedules.length === 0
                icon.name: "view-calendar"
                text: i18n("No schedules yet")
                explanation: i18n("A schedule sends a message into a chat at set times, e.g. “Fetch the latest news” every weekday at 09:00.")
            }

            Repeater {
                model: service.schedules
                delegate: Config.ScheduleRow {
                    required property var modelData
                    objectName: "scheduleRow"
                    item: modelData
                    chatTitle: Draft.chatTitle(page.sessions, modelData.chatId)
                    paused: service.paused
                    onEditRequested: page.edit(modelData)
                    onHistoryRequested: page.showHistory(modelData)
                    onDeleteRequested: service.remove(modelData.id)
                    onEnabledToggled: on => service.setEnabled(modelData, on)
                }
            }
        }
    }
}
