// One provider on Settings -> Spending: this month's tokens and cost, and its monthly budget in dollars.
// An empty budget field means no budget. Typing a budget emits budgetChosen with the value (0 = none); a value
// that is not a positive number is refused and the field goes back to the saved budget.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../chat/ChatStats.js" as Stats
import "../chat/Spending.js" as Spending

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

RowLayout {
    id: line

    property string providerId: ""
    property string providerName: ""
    // This month's totals for the provider: {count, input, output, cacheRead, cost, costCount}.
    property var totals: ({})
    // The monthly budget in dollars; 0 = none.
    property real budget: 0

    signal budgetChosen(string chosenId, real dollars)

    function budgetText(value) {
        return value > 0 ? String(Math.round(value * 100) / 100) : "";
    }

    readonly property string tokensText: {
        const text = i18n("%1 in · %2 out", Stats.formatCount(totals.input || 0), Stats.formatCount(totals.output || 0));
        return (totals.cacheRead || 0) > 0 ? text + i18n(" · %1 from cache", Stats.formatCount(totals.cacheRead)) : text;
    }
    readonly property string costText: {
        if ((totals.costCount || 0) > 0) {
            const money = Stats.formatCost(totals.cost);
            return (totals.count || 0) > (totals.costCount || 0) ? i18n("%1 (some replies had no cost)", money) : money;
        }
        return (totals.count || 0) > 0 ? i18n("Cost unknown") : i18n("No replies this month");
    }

    spacing: Kirigami.Units.largeSpacing
    onBudgetChanged: field.text = budgetText(budget)

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        QQC2.Label {
            objectName: "spendingName"
            Layout.fillWidth: true
            text: line.providerName
            textFormat: Text.PlainText
            font.bold: true
            elide: Text.ElideRight
        }
        QQC2.Label {
            objectName: "spendingTokens"
            Layout.fillWidth: true
            text: line.tokensText
            textFormat: Text.PlainText
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
        }
        QQC2.Label {
            objectName: "spendingCost"
            Layout.fillWidth: true
            text: line.costText
            textFormat: Text.PlainText
            font: Kirigami.Theme.smallFont
            wrapMode: Text.Wrap
        }
        QQC2.Label {
            objectName: "spendingUsed"
            Layout.fillWidth: true
            visible: line.budget > 0
            text: i18n("%1% of the budget used", Spending.percentUsed(line.totals.cost, line.budget))
            textFormat: Text.PlainText
            font: Kirigami.Theme.smallFont
            opacity: 0.8
        }
    }

    QQC2.TextField {
        id: field
        objectName: "spendingBudget"
        Layout.preferredWidth: Kirigami.Units.gridUnit * 7
        placeholderText: i18n("No limit")
        text: line.budgetText(line.budget)
        Accessible.name: i18n("Monthly budget for %1, in dollars", line.providerName)

        onEditingFinished: {
            const typed = text.trim().replace(",", ".");
            const dollars = typed === "" ? 0 : Number(typed);
            if (typed === "" || (isFinite(dollars) && dollars > 0))
                line.budgetChosen(line.providerId, dollars);
            field.text = line.budgetText(line.budget);
        }
    }
}
