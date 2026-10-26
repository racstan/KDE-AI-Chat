// The editor's "More options": start and end date, a run limit, what to do
// with times missed while the computer was off or asleep (catch-up, off by
// default), and the desktop notification.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "ScheduleDraft.js" as Draft

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: options

    property var draft: ({})
    signal fieldChanged(string key, var value)

    readonly property var catchUp: draft.catchUp || {"enabled": false, "withinHours": 12}

    function dateField(text) {
        var t = String(text || "").trim();
        return t === "" ? null : (Draft.normalizeDate(t) || t);
    }

    QQC2.TextField {
        objectName: "startDate"
        Kirigami.FormData.label: i18n("Start on:")
        text: options.draft.startDate || ""
        placeholderText: i18n("YYYY-MM-DD (optional)")
        onEditingFinished: options.fieldChanged("startDate", options.dateField(text))
    }
    SettingHelp {
        text: i18n("The first day this schedule may run, for example 2026-12-01. Leave empty to start right away.")
    }
    QQC2.TextField {
        objectName: "endDate"
        Kirigami.FormData.label: i18n("End after:")
        text: options.draft.endDate || ""
        placeholderText: i18n("YYYY-MM-DD (optional)")
        onEditingFinished: options.fieldChanged("endDate", options.dateField(text))
    }
    SettingHelp {
        text: i18n("The last day it may run. Leave empty to keep going until you turn it off.")
    }
    RowLayout {
        Kirigami.FormData.label: i18n("Stop after:")
        QQC2.CheckBox {
            id: limitCheck
            objectName: "limitCheck"
            checked: Number(options.draft.limitCount) > 0
            onToggled: options.fieldChanged("limitCount", checked ? 5 : null)
        }
        QQC2.SpinBox {
            objectName: "limitCount"
            enabled: limitCheck.checked
            from: 1
            to: 100000
            value: Number(options.draft.limitCount) || 5
            onValueModified: options.fieldChanged("limitCount", value)
        }
        QQC2.Label { text: i18n("runs") }
    }
    SettingHelp {
        text: i18n("Stop by itself after sending the message this many times, for example for a five-day reminder.")
    }
    QQC2.CheckBox {
        objectName: "catchUp"
        Kirigami.FormData.label: i18n("If missed:")
        text: i18n("Run once when the computer is back")
        checked: options.catchUp.enabled === true
        onToggled: options.fieldChanged("catchUp", {"enabled": checked, "withinHours": options.catchUp.withinHours || 12})
        // help: next
    }
    RowLayout {
        visible: options.catchUp.enabled === true
        QQC2.Label { text: i18n("only if missed within") }
        QQC2.SpinBox {
            objectName: "catchUpHours"
            from: 1
            to: 168
            value: Number(options.catchUp.withinHours) || 12
            onValueModified: options.fieldChanged("catchUp", {"enabled": true, "withinHours": value})
        }
        QQC2.Label { text: i18n("hours") }
    }
    SettingHelp {
        text: i18n("If the computer was off or asleep at the set time, send the message once when it is back. Off: the missed time is only noted in the history.")
    }
    QQC2.CheckBox {
        objectName: "notify"
        Kirigami.FormData.label: i18n("Notify:")
        text: i18n("Show a notification when the answer is ready")
        checked: options.draft.notify !== false
        onToggled: options.fieldChanged("notify", checked)
    }
    SettingHelp {
        text: i18n("A desktop notification tells you when the answer has arrived, so you don't have to keep the chat open.")
    }
}
