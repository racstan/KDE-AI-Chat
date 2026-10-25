// Settings → Schedules: the background scheduler that sends messages into
// chats at set times, and the list of schedules (edited in ScheduleDialog).
// Starting and stopping the daemon happens right away; the switches below are
// also saved as settings when you press Apply or OK.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "config" as Config

// i18n() and plasmoid are provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    property alias cfg_schedulerEnabled: enabledSwitch.checked
    property alias cfg_executeMissedSchedules: missedCheck.checked

    readonly property var plasmoidObject: typeof plasmoid !== "undefined" ? plasmoid : null
    // Replaces running shell commands (tests); see SchedulerService.runShell.
    property var runShell: null

    function newSchedule() {
        var start = new Date();
        start.setMinutes(start.getMinutes() + 5, 0, 0);
        var chats = scheduleDialog.getChatsList();
        scheduleDialog.draft = {
            "id": scheduler.schedMakeUuid(), "name": "", "enabled": true,
            "chatId": chats.length > 0 ? chats[0].id : "", "chatName": chats.length > 0 ? chats[0].name : "",
            "message": "", "taskType": "single", "startDate": start.toISOString(),
            "schedType": "days", "schedEvery": 1, "schedTime": "09:00", "schedDays": [1], "schedDayOfMonth": 1,
            "limitEnabled": false, "limitCount": 5, "notify": true, "createdAt": new Date().toISOString()
        };
        scheduleDialog.editingIndex = -2;
        scheduleDialog.open();
    }

    Config.SchedulerService {
        id: scheduler
        appletId: page.plasmoidObject ? String(page.plasmoidObject.id) : ""
        configuration: page.plasmoidObject ? page.plasmoidObject.configuration : null
        executeMissed: missedCheck.checked
        polling: enabledSwitch.checked
        runShell: page.runShell
        onAutoStartDetected: function(enabled) { autoStartCheck.checked = enabled; }
    }

    ScheduleDialog {
        id: scheduleDialog
        page: scheduler
    }

    Component.onCompleted: {
        scheduler.schedLoadSchedules();
        scheduler.setup();
        scheduler.poll();
    }

    Kirigami.FormLayout {
        QQC2.Switch {
            id: enabledSwitch
            Kirigami.FormData.label: i18n("Scheduler:")
            text: i18n("Run scheduled messages")
            onToggled: checked ? scheduler.start() : scheduler.stop()
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Status:")
            visible: enabledSwitch.checked
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: scheduler.status !== "" ? scheduler.status : (scheduler.running ? i18n("Running") : i18n("Not running"))
                color: scheduler.running ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
            }
            QQC2.Button {
                text: scheduler.running ? i18n("Restart") : i18n("Start")
                icon.name: scheduler.running ? "view-refresh" : "media-playback-start"
                onClicked: scheduler.restart()
            }
        }

        QQC2.CheckBox {
            id: autoStartCheck
            visible: enabledSwitch.checked
            text: i18n("Start when I log in")
            onToggled: scheduler.setAutoStart(checked)
        }

        QQC2.CheckBox {
            id: missedCheck
            visible: enabledSwitch.checked
            text: i18n("Send messages missed while the computer was off")
            onToggled: scheduler.schedSaveAll()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("After a long time off, this can send many messages at once.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Schedules")
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Active:")
            text: scheduler.schedulerList.length === 0 ? i18n("None")
                : i18np("%1 schedule (%2 on)", "%1 schedules (%2 on)", scheduler.schedulerList.length,
                        scheduler.schedulerList.filter(function(s) { return s && s.enabled; }).length)
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("New Schedule…")
                icon.name: "list-add"
                onClicked: page.newSchedule()
            }
            QQC2.Button {
                text: i18n("Manage…")
                icon.name: "view-list-details"
                onClicked: {
                    scheduleDialog.editingIndex = -1;
                    scheduleDialog.open();
                }
            }
            QQC2.Button {
                text: i18n("Open File")
                icon.name: "document-open"
                onClicked: scheduler.openFile()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: scheduler.schedulesFile
            }
        }

        QQC2.Label {
            visible: !enabledSwitch.checked && scheduler.schedulerList.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18n("Schedules only run while the scheduler is on.")
        }
    }
}
