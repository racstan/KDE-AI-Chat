// Settings -> Spending (ConfigSpending.qml with config/SpendingProviderRow.qml and config/SpendingDayBars.qml)
// and the budget alerts of a finished reply (chat/SpendingLog.qml, chat/Notifier.qml's spendingAlert). The
// helper is a stand-in: it answers the usage log's commands and applies the alert rule of kdeaichat/usage.py.
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 760
    height: 900

    property QtObject plasmoid: QtObject {
        property QtObject configuration: QtObject {
            property string providersJson: '[{"id":"openrouter","name":"OpenRouter","type":"openai-compat","baseUrl":"https://openrouter.ai/api/v1","model":"openai/gpt-4o"},{"id":"ollama","name":"Ollama","type":"openai-compat","baseUrl":"http://localhost:11434/v1","model":"llama3"}]'
        }
    }

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    // The helper as a stand-in: the usage log answers and the alert rule (once per provider, month and level).
    QtObject {
        id: helper
        property var calls: []
        property bool noCosts: false
        property bool fail: false
        // Known costs per provider this month, and the levels already alerted.
        property var spent: ({})
        property var shown: ({})

        function monthData(month) {
            const known = !helper.noCosts;
            return {"type": "usage_month", "month": month, "skipped": 0, "models": [],
                    "providers": {
                        "openrouter": {"count": 4, "input": 12000, "output": 3400, "cacheRead": 1000, "cost": known ? 2.5 : 0, "costCount": known ? 4 : 0},
                        "ollama": {"count": 2, "input": 900, "output": 150, "cacheRead": 0, "cost": 0, "costCount": 0}},
                    "days": {
                        "2026-10-01": {"count": 4, "input": 12000, "output": 3400, "cacheRead": 1000, "cost": known ? 2.5 : 0, "costCount": known ? 4 : 0},
                        "2026-10-02": {"count": 2, "input": 900, "output": 150, "cacheRead": 0, "cost": 0, "costCount": 0}}};
        }

        function usageAdd(payload) {
            const entry = payload.entry;
            const provider = entry.provider;
            const before = helper.spent[provider] || 0;
            const after = entry.cost === null ? before : before + entry.cost;
            helper.spent[provider] = after;
            const limit = payload.budgets[provider];
            if (!limit || entry.cost === null)
                return [];
            const levels = [payload.alertPercent, 100].filter(function(level, i, all) { return all.indexOf(level) === i; });
            const old = helper.shown[provider] || [];
            const crossed = levels.filter(function(level) {
                return before + 1e-9 < limit * level / 100 && limit * level / 100 <= after + 1e-9;
            });
            const fresh = crossed.filter(function(level) { return old.indexOf(level) < 0; });
            if (fresh.length === 0)
                return [];
            helper.shown[provider] = old.concat(fresh);
            return [{"provider": provider, "percent": Math.max.apply(null, fresh), "spent": after, "budget": limit}];
        }

        function run(command, payload, onDone) {
            helper.calls = helper.calls.concat([{command: command, payload: payload}]);
            if (command === "usage_months") {
                Qt.callLater(function() { onDone(JSON.stringify({"type": "usage_months", "months": ["2026-09", "2026-10"]}), 0, ""); });
            } else if (command === "usage_month") {
                Qt.callLater(function() { onDone(JSON.stringify(helper.monthData(payload.month)), 0, ""); });
            } else if (command === "usage_add") {
                if (helper.fail) {
                    Qt.callLater(function() { onDone("", 1, "stand-in failure"); });
                } else {
                    const alerts = helper.usageAdd(payload);
                    Qt.callLater(function() { onDone(JSON.stringify({"type": "usage_added", "alerts": alerts}), 0, ""); });
                }
            }
        }
    }

    // The chat a reply belongs to: its settings, the open session and the status line of its composer.
    QtObject {
        id: chat
        property var plasmoid: ({"configuration": {"spendingBudgets": '{"openrouter": 10}', "spendingAlertPercent": 80}})
        property string currentSessionId: "s-1"
        property var composerRef: composer
        function getHelperPath() { return "/usr/share/kdeaichat/kde_ai_helper.py"; }
        function providerDisplayName(providerId) { return providerId === "openrouter" ? "OpenRouter" : providerId; }
    }

    QtObject {
        id: composer
        property var notices: []
        function showNotice(text) { composer.notices = composer.notices.concat([text]); }
    }

    QtObject {
        id: notifications
        property var alerts: []
        function spendingAlert(title, text) {
            notifications.alerts = notifications.alerts.concat([{title: title, text: text}]);
            return true;
        }
    }

    Chat.SpendingLog {
        id: log
        chat: chat
        notifierRef: notifications
        runHelper: helper.run
    }

    // The real notifier, with its desktop notification replaced by a recorder.
    Chat.Notifier {
        id: realNotifier
        property var sent: []
        sender: function(title, text, chatId, isError) {
            realNotifier.sent = realNotifier.sent.concat([{title: title, text: text, chatId: chatId}]);
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    HarnessTestCase {
        id: tc
        name: "Spending"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        // Opens the settings page with saved values, once the helper has answered.
        function openPage(extra) {
            const component = Qt.createComponent(uiDir + "ConfigSpending.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({"width": root.width, "height": root.height, "helperRunner": helper,
                                                               "cfg_spendingBudgets": '{"openrouter": 10}',
                                                               "cfg_spendingAlertPercent": 80}, extra || {}));
            verify(page !== null);
            tryVerify(() => page.usage !== null, 3000, "the month's totals arrive");
            wait(50);
            return page;
        }

        function row(id) {
            const line = findChild(page, "spendingRow-" + id);
            verify(line, "row " + id);
            return line;
        }

        function dayText(key) {
            return findChild(findChild(page, "spendingDay-" + key), "spendingDayText").text;
        }

        function init() {
            helper.calls = [];
            helper.noCosts = false;
            helper.fail = false;
            helper.spent = ({});
            helper.shown = ({});
            composer.notices = [];
            notifications.alerts = [];
            realNotifier.sent = [];
        }

        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            wait(100);
        }

        function test_1_shows_this_months_totals_budgets_and_days() {
            openPage();
            const openrouter = row("openrouter");
            compare(findChild(openrouter, "spendingName").text, "OpenRouter");
            compare(findChild(openrouter, "spendingTokens").text, "12,000 in · 3,400 out · 1,000 from cache");
            compare(findChild(openrouter, "spendingCost").text, "$2.50");
            compare(findChild(openrouter, "spendingUsed").text, "25% of the budget used");
            compare(findChild(openrouter, "spendingBudget").text, "10");
            compare(findChild(page, "spendingAlertPercent").value, 80);
            compare(findChild(page, "spendingSummary").text, "6 replies: 12,900 in, 3,550 out, cost $2.50.");
            // A provider whose replies reported no cost: "cost unknown", no budget used, an empty budget field.
            const ollama = row("ollama");
            compare(findChild(ollama, "spendingTokens").text, "900 in · 150 out");
            compare(findChild(ollama, "spendingCost").text, "Cost unknown");
            verify(!findChild(ollama, "spendingUsed").visible);
            compare(findChild(ollama, "spendingBudget").text, "");
            compare(dayText("2026-10-01"), "15,400 tokens · $2.50");
            compare(dayText("2026-10-02"), "1,050 tokens · cost unknown");
            // The busiest day fills its bar; the quieter one is shorter.
            const busiest = findChild(findChild(page, "spendingDay-2026-10-01"), "spendingDayBar");
            const quiet = findChild(findChild(page, "spendingDay-2026-10-02"), "spendingDayBar");
            verify(busiest.parent.width > 0);
            compare(busiest.width, busiest.parent.width);
            verify(quiet.width > 0 && quiet.width < busiest.width);
            wait(300);
            screenshot(page, "config-spending-wide");
        }

        function test_2_a_month_without_reported_costs_says_cost_unknown() {
            helper.noCosts = true;
            openPage();
            compare(findChild(row("openrouter"), "spendingCost").text, "Cost unknown");
            compare(findChild(page, "spendingSummary").text, "6 replies: 12,900 in, 3,550 out, cost unknown.");
            compare(dayText("2026-10-01"), "15,400 tokens · cost unknown");
        }

        function test_3_the_month_picker_asks_for_the_month_chosen() {
            openPage();
            const picker = findChild(page, "spendingMonth");
            verify(picker !== null);
            let index = -1;
            for (let i = 0; i < picker.count; i++) {
                if (picker.model[i].value === "2026-09")
                    index = i;
            }
            verify(index >= 0, "2026-09 is offered");
            picker.currentIndex = index;
            picker.activated(index);
            tryVerify(() => page.usage !== null && page.usage.month === "2026-09", 2000, "September is loaded");
            const last = helper.calls[helper.calls.length - 1];
            compare(last.command, "usage_month");
            compare(last.payload.month, "2026-09");
            compare(picker.currentIndex, index);
        }

        function test_4_a_budget_is_saved_and_an_empty_one_removes_it() {
            openPage();
            const ollamaBudget = findChild(row("ollama"), "spendingBudget");
            ollamaBudget.text = "5";
            ollamaBudget.editingFinished();
            compare(JSON.parse(page.cfg_spendingBudgets).ollama, 5);
            compare(JSON.parse(page.cfg_spendingBudgets).openrouter, 10);
            // With a budget the used line shows, even before any cost is known (0% of it).
            verify(findChild(row("ollama"), "spendingUsed").visible);
            compare(findChild(row("ollama"), "spendingUsed").text, "0% of the budget used");
            ollamaBudget.text = "";
            ollamaBudget.editingFinished();
            verify(!("ollama" in JSON.parse(page.cfg_spendingBudgets)));
            compare(ollamaBudget.text, "");
            // Not a positive number: refused, the saved budget stays and the field shows it again.
            const openrouterBudget = findChild(row("openrouter"), "spendingBudget");
            openrouterBudget.text = "-3";
            openrouterBudget.editingFinished();
            compare(JSON.parse(page.cfg_spendingBudgets).openrouter, 10);
            compare(openrouterBudget.text, "10");
        }

        function test_5_the_alert_share_is_saved() {
            openPage();
            // A user's key press (valueModified), not a program's change: the saved share follows it.
            findChild(page, "spendingAlertPercent").forceActiveFocus();
            keyClick(Qt.Key_Up);
            compare(page.cfg_spendingAlertPercent, 81);
        }

        function test_6_an_alert_at_80_and_at_100_percent_is_shown_once() {
            const first = {"provider": "openrouter", "model": "openai/gpt-4o", "mode": "direct", "input": 100, "output": 20, "cacheRead": 0, "cost": 8.5};
            log.recordReply(first, "s-1");
            tryVerify(() => composer.notices.length === 1, 2000, "the 80% note");
            compare(composer.notices[0], "OpenRouter: 80% of this month's budget is used ($8.50 of $10.00).");
            compare(notifications.alerts.length, 1);
            compare(notifications.alerts[0].title, "Budget alert");
            log.recordReply(Object.assign({}, first, {"cost": 0.5}), "s-1");
            tryVerify(() => helper.calls.length === 2, 2000);
            wait(50);
            compare(composer.notices.length, 1, "80% is not shown again");
            log.recordReply(Object.assign({}, first, {"cost": 1.0}), "s-1");
            tryVerify(() => composer.notices.length === 2, 2000, "the 100% note");
            compare(composer.notices[1], "OpenRouter: this month's budget of $10.00 is used up ($10.00 so far). Messages are still sent.");
            compare(notifications.alerts.length, 2);
            log.recordReply(Object.assign({}, first, {"cost": 1.0}), "s-1");
            tryVerify(() => helper.calls.length === 4, 2000);
            wait(50);
            compare(composer.notices.length, 2, "100% is not shown again");
            compare(notifications.alerts.length, 2);
            // The entry holds the reply's numbers and nothing else (no chat text, title or id); the budgets are sent.
            const sent = helper.calls[0].payload;
            compare(Object.keys(sent.entry).sort().join(","), "at,cacheRead,cost,input,mode,model,output,provider");
            compare(sent.budgets.openrouter, 10);
            compare(sent.alertPercent, 80);
        }

        function test_7_an_alert_for_another_chat_is_a_notification_only() {
            log.recordReply({"provider": "openrouter", "mode": "direct", "input": 1, "output": 1, "cost": 9}, "s-2");
            tryVerify(() => notifications.alerts.length === 1, 2000);
            wait(50);
            compare(composer.notices.length, 0, "the note belongs to the chat it was spent in");
        }

        function test_8_a_failed_write_or_a_reply_without_counts_changes_nothing() {
            helper.fail = true;
            log.recordReply({"provider": "openrouter", "mode": "direct", "input": 1, "output": 1, "cost": 9}, "s-1");
            tryVerify(() => helper.calls.length === 1, 2000);
            wait(50);
            compare(composer.notices.length, 0);
            compare(notifications.alerts.length, 0);
            helper.fail = false;
            // No token counts (not logged) and no provider (not logged): nothing is sent to the helper.
            log.recordReply({"provider": "openrouter", "mode": "direct", "cost": 9}, "s-1");
            log.recordReply({"mode": "direct", "input": 1, "output": 1, "cost": 9}, "s-1");
            wait(50);
            compare(helper.calls.length, 1);
        }

        function test_9_the_desktop_alert_follows_the_reply_setting_and_the_popup() {
            verify(realNotifier.spendingAlert("Budget alert", "A & B"));
            compare(realNotifier.sent.length, 1);
            compare(realNotifier.sent[0].title, "Budget alert");
            compare(realNotifier.sent[0].text, "A &amp; B");
            compare(realNotifier.sent[0].chatId, "");
            realNotifier.replyEnabled = false;
            verify(!realNotifier.spendingAlert("Budget alert", "off"));
            realNotifier.replyEnabled = true;
            realNotifier.popupOpen = true;
            verify(!realNotifier.spendingAlert("Budget alert", "popup open"));
            realNotifier.popupOpen = false;
            compare(realNotifier.sent.length, 1);
        }
    }
}
