// Settings -> Spending: what this month's replies cost, from the usage log (kdeaichat/usage.py, only read here,
// through the helper's usage_months and usage_month), a monthly budget per provider and the share of a budget
// at which an alert shows. The budgets and the alert share are settings (cfg_spendingBudgets, cfg_spendingAlertPercent);
// the log never is. `helperRunner` is a property so a test can pass a fake.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "store" as Store
import "config" as Config
import "ProviderService.js" as ProviderService
import "chat/ChatStats.js" as Stats
import "chat/Spending.js" as Spending

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    property var helperRunner: defaultRunner
    // Saved by Plasma: the budgets as a JSON object (provider id -> dollars), and the alert share in percent.
    property string cfg_spendingBudgets: "{}"
    property int cfg_spendingAlertPercent: 80

    // plasmoid is provided by Plasma at runtime (the provider list); absent in a page on its own.
    readonly property var configuration: typeof plasmoid !== "undefined" && plasmoid ? plasmoid.configuration : null
    readonly property var budgets: Spending.parseBudgets(page.cfg_spendingBudgets)

    // The month on screen ("YYYY-MM"), the helper's answer for it (null until it arrives) and the logged months.
    property string month: ""
    property var usage: null
    property var logMonths: []
    property bool loading: false
    property string errorText: ""

    readonly property var monthItems: Spending.monthList(page.logMonths, Spending.monthOf(new Date())).map(function(value) {
        return {"value": value, "text": page.monthLabel(value)};
    })
    // The providers listed: the configured ones, then any with spending this month. Budgets are not part of this
    // list, so a budget typed into a row changes that row in place and the field keeps its focus.
    readonly property var providerIds: Spending.providerRows(ProviderService.getSupportedProviders(page.configuration),
                                                             page.usage ? page.usage.providers : ({}), ({})).map(function(line) { return line.id; })
    readonly property var rows: page.providerIds.map(function(providerId) { return page.rowFor(providerId); })

    // One provider's month: its totals and its budget.
    function rowFor(providerId) {
        return Spending.providerRows([providerId], page.usage ? page.usage.providers : ({}), page.budgets)[0];
    }

    function monthLabel(value) {
        const parts = String(value).split("-");
        return Qt.locale().monthName(parseInt(parts[1], 10) - 1) + " " + parts[0];
    }

    function monthIndex() {
        for (let i = 0; i < page.monthItems.length; i++) {
            if (page.monthItems[i].value === page.month)
                return i;
        }
        return -1;
    }

    function providerName(providerId) {
        return ProviderService.getProviderDisplayName(providerId, page.configuration);
    }

    // The month's totals over all providers, in one line.
    function summaryText() {
        if (page.usage === null)
            return "";
        let count = 0, input = 0, output = 0, cost = 0, costCount = 0;
        for (let i = 0; i < page.rows.length; i++) {
            count += page.rows[i].count;
            input += page.rows[i].input;
            output += page.rows[i].output;
            cost += page.rows[i].cost;
            costCount += page.rows[i].costCount;
        }
        const money = costCount > 0 ? i18n("cost %1", Stats.formatCost(cost)) : i18n("cost unknown");
        return i18n("%1 replies: %2 in, %3 out, %4.", count, Stats.formatCount(input), Stats.formatCount(output), money);
    }

    function refreshMonths() {
        page.helperRunner.run("usage_months", {}, function(stdout, exitCode) {
            const reply = Spending.parseReply(stdout);
            page.logMonths = exitCode === 0 && reply && Array.isArray(reply.months) ? reply.months : [];
        });
    }

    function loadMonth(value) {
        page.month = value;
        page.loading = true;
        page.errorText = "";
        page.helperRunner.run("usage_month", {"month": value}, function(stdout, exitCode) {
            if (page.month !== value)
                return;  // another month was picked meanwhile
            page.loading = false;
            const reply = Spending.parseReply(stdout);
            if (exitCode === 0 && reply && reply.type === "usage_month") {
                page.usage = reply;
            } else {
                page.usage = null;
                page.errorText = i18n("Could not read the spending log.");
            }
        });
    }

    function refresh() {
        page.refreshMonths();
        page.loadMonth(page.month);
    }

    // Saves a provider's budget (0 removes it) in the budgets setting.
    function setBudget(providerId, dollars) {
        const map = Spending.parseBudgets(page.cfg_spendingBudgets);
        if (dollars > 0)
            map[providerId] = dollars;
        else
            delete map[providerId];
        page.cfg_spendingBudgets = Spending.serializeBudgets(map);
    }

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            const path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    Component.onCompleted: {
        page.loadMonth(Spending.monthOf(new Date()));
        page.refreshMonths();
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.75
            text: i18n("What the replies cost, as each provider reported it. Nothing is estimated: a reply without a cost counts in tokens only, and budgets count only the costs reported.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: i18n("Month:")
                font.bold: true
            }
            QQC2.ComboBox {
                objectName: "spendingMonth"
                Accessible.name: i18n("Month to show")
                model: page.monthItems
                textRole: "text"
                valueRole: "value"
                currentIndex: page.monthIndex()
                onActivated: function(index) { page.loadMonth(page.monthItems[index].value); }
            }
            Item {
                Layout.fillWidth: true
            }
            QQC2.Button {
                objectName: "spendingRefresh"
                icon.name: "view-refresh"
                text: i18n("Refresh")
                enabled: !page.loading
                onClicked: page.refresh()
            }
        }

        Kirigami.InlineMessage {
            objectName: "spendingError"
            Layout.fillWidth: true
            visible: page.errorText !== ""
            type: Kirigami.MessageType.Error
            text: page.errorText
        }

        QQC2.Label {
            objectName: "spendingSummary"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.bold: true
            visible: page.usage !== null
            text: page.summaryText()
        }

        Repeater {
            model: page.providerIds

            delegate: Config.SpendingProviderRow {
                required property var modelData

                objectName: "spendingRow-" + modelData
                Layout.fillWidth: true
                providerId: modelData
                providerName: page.providerName(modelData)
                totals: page.rowFor(modelData)
                budget: page.budgets[modelData] || 0
                onBudgetChosen: function(chosenId, dollars) { page.setBudget(chosenId, dollars); }
            }
        }

        QQC2.Label {
            objectName: "spendingNoProviders"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.75
            visible: page.usage !== null && page.rows.length === 0
            text: i18n("No provider yet. Add one in Settings → Connection and its spending shows here.")
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: i18n("Alert at this share of a budget:")
                font.bold: true
            }
            QQC2.SpinBox {
                objectName: "spendingAlertPercent"
                Accessible.name: i18n("Alert at this share of a budget, in percent")
                from: 1
                to: 100
                value: page.cfg_spendingAlertPercent
                onValueModified: page.cfg_spendingAlertPercent = value
            }
        }

        Config.SettingHelp {
            text: i18n("An alert shows when a provider's month reaches this share of its budget, and again when it reaches the full budget. Each alert shows once per provider, month and level, in the chat's status line and as a desktop notification if reply notifications are on. Sending is never stopped.")
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            level: 4
            text: i18n("Per day")
        }

        QQC2.Label {
            objectName: "spendingNoDays"
            Layout.fillWidth: true
            visible: page.usage !== null && Object.keys(page.usage.days || {}).length === 0
            opacity: 0.75
            text: i18n("No replies this month yet.")
        }

        Config.SpendingDayBars {
            objectName: "spendingDays"
            Layout.fillWidth: true
            days: page.usage ? page.usage.days : ({})
        }
    }
}
