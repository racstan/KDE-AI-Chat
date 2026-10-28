// Search across all chats, at the top of the history (chat/SessionList.qml):
// chat names and message text in every chat of this widget, archived ones
// and chats in projects too (labelled), never an incognito chat. The search
// itself is chat/ChatSearch.js, over the chats in memory; it runs once typing
// pauses. While there is a query, the results take the place of the history's
// list. A result shows the chat, the date and a snippet with the match
// marked; opening it (click, Enter) opens the chat at that message.
//
// Keyboard: Ctrl+Shift+F focuses the field (chat/ChatShortcuts.qml); Down or
// Enter go to the results, Up/Down move through them, Enter opens one, Up on
// the first goes back to the field, Esc clears the field.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "ChatSearch.js" as ChatSearch

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: panel

    property var chat: null
    // A narrow popup shows the history instead of the chat: opening a result goes back to the chat.
    property bool closeOnSelect: true
    // The pause in typing before the search runs (ms).
    property int debounce: 250
    readonly property alias field: searchField
    readonly property alias resultList: results
    // There is something in the field: the results show instead of the history's list.
    readonly property bool searching: ChatSearch.normalizeQuery(searchField.text) !== ""
    // The query of the results shown, and the results ({results, more}).
    property string query: ""
    property var found: ({"results": [], "more": false})

    function focusSearch() {
        searchField.forceActiveFocus();
        searchField.selectAll();
    }

    function runSearch() {
        debounceTimer.stop();
        query = ChatSearch.normalizeQuery(searchField.text);
        found = ChatSearch.search(panel._chats(), query);
    }

    // The chats, the open one with the messages on screen (it may not be saved yet).
    function _chats() {
        var list = chat ? chat.sessions || [] : [];
        var at = chat ? chat.sessionIndexById(chat.currentSessionId) : -1;
        if (at < 0)
            return list;
        var copy = list.slice();
        copy[at] = Object.assign({}, copy[at], {"messages": chat.messages || []});
        return copy;
    }

    // Opens the result's chat at its message.
    function open(result) {
        var target = panel.chat;
        if (!target || !result)
            return;
        target.switchSession(result.chatId, function() {
            if (result.kind === "message" && target.msgListViewRef)
                target.msgListViewRef.reveal(result.messageId, result.messageIndex);
        });
        if (panel.closeOnSelect && target.currentSessionId === result.chatId)
            target.historyOnlyMode = false;
    }

    // "Today", "Yesterday" or the date.
    function dayLabel(ms) {
        if (!(ms > 0))
            return "";
        var now = new Date();
        var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        if (ms >= startOfToday)
            return i18n("Today");
        if (ms >= startOfToday - 86400000)
            return i18n("Yesterday");
        return new Date(ms).toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }

    function _goToResults() {
        if (panel.debounce > 0 && debounceTimer.running)
            panel.runSearch();
        if (results.count === 0)
            return false;
        results.currentIndex = 0;
        results.forceActiveFocus();
        return true;
    }

    spacing: Kirigami.Units.smallSpacing

    Timer {
        id: debounceTimer
        interval: panel.debounce
        onTriggered: panel.runSearch()
    }

    // Chats changed (a reply came, a chat was deleted): the results follow.
    Connections {
        target: panel.chat
        function onSessionsChanged() {
            if (panel.query !== "")
                debounceTimer.restart();
        }
    }

    Kirigami.SearchField {
        id: searchField
        objectName: "chatSearchField"
        Layout.fillWidth: true
        placeholderText: i18n("Search all chats…")
        // Ctrl+Shift+F, in chat/ChatShortcuts.qml (Ctrl+F stays free).
        focusSequence: ""
        autoAccept: false
        Accessible.name: i18n("Search all chats")
        onTextChanged: {
            if (ChatSearch.normalizeQuery(text) === "")
                panel.runSearch();
            else
                debounceTimer.restart();
        }
        onAccepted: panel._goToResults()
        Keys.onDownPressed: panel._goToResults()
        Keys.onEscapePressed: function(event) {
            event.accepted = text !== "";
            text = "";
        }
    }

    PC3.Label {
        objectName: "searchStatus"
        visible: panel.searching
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing * 2
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
        text: panel.query !== ChatSearch.normalizeQuery(searchField.text) ? i18n("Searching…")
            : ChatSearch.patternFor(panel.query) === null ? i18n("Type at least two characters.")
            : panel.found.results.length === 0 ? i18n("No chats match “%1”.", panel.query)
            : panel.found.more ? i18n("The first %1 matches. Type more to narrow them down.", panel.found.results.length)
            : i18np("%1 match", "%1 matches", panel.found.results.length)
    }

    ListView {
        id: results
        objectName: "searchResults"

        visible: panel.searching
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: panel.searching ? panel.found.results : []
        spacing: 1
        clip: true
        currentIndex: -1
        keyNavigationEnabled: false
        Accessible.role: Accessible.List
        Accessible.name: i18n("Search results")

        Keys.onUpPressed: {
            if (currentIndex <= 0)
                searchField.forceActiveFocus();
            else
                decrementCurrentIndex();
        }
        Keys.onDownPressed: incrementCurrentIndex()
        Keys.onReturnPressed: panel.open(panel.found.results[currentIndex])
        Keys.onEnterPressed: panel.open(panel.found.results[currentIndex])
        Keys.onEscapePressed: searchField.forceActiveFocus()

        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            id: resultScroll
        }

        delegate: Rectangle {
            id: row

            required property var modelData
            required property int index
            readonly property var project: panel.chat && panel.chat.projects ? panel.chat.projects.byId(modelData.projectId) : null
            readonly property bool current: ListView.isCurrentItem && results.activeFocus
            readonly property string title: modelData.title || i18n("New Chat")

            width: results.width - (resultScroll.visible ? resultScroll.width : 0)
            height: column.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: Kirigami.Units.cornerRadius
            color: current ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
                 : hover.hovered ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)
                 : "transparent"
            border.width: current ? 1 : 0
            border.color: Kirigami.Theme.highlightColor

            Accessible.role: Accessible.Button
            Accessible.name: title
            Accessible.description: modelData.before + modelData.match + modelData.after
            Accessible.onPressAction: panel.open(modelData)

            HoverHandler {
                id: hover
            }
            TapHandler {
                onTapped: {
                    results.currentIndex = row.index;
                    panel.open(row.modelData);
                }
            }

            ColumnLayout {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        objectName: "resultProjectDot"
                        visible: row.project !== null
                        Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                        Layout.preferredHeight: Layout.preferredWidth
                        radius: width / 2
                        color: row.project ? row.project.color : "transparent"
                    }
                    // The chat's name; a match in it is marked.
                    PC3.Label {
                        objectName: "resultTitle"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        textFormat: Text.StyledText
                        text: row.modelData.kind === "title"
                            ? ChatSearch.highlighted(row.modelData)
                            : ChatSearch.escapeHtml(row.title)
                        font.bold: true
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    // Where the chat is: a project, or the archive.
                    PC3.Label {
                        objectName: "resultPlace"
                        visible: text !== ""
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 6
                        text: [row.project ? row.project.name : "", row.modelData.archived ? i18n("Archived") : ""]
                            .filter(function(t) { return t !== ""; }).join(" · ")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont
                    }
                    PC3.Label {
                        objectName: "resultDate"
                        text: panel.dayLabel(row.modelData.at)
                        color: Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont
                        Layout.minimumWidth: implicitWidth
                    }
                }

                // The text around the match, which is marked.
                PC3.Label {
                    objectName: "resultSnippet"
                    visible: row.modelData.kind === "message"
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    text: (row.modelData.role === "user" ? "<i>" + ChatSearch.escapeHtml(i18n("You:")) + "</i> " : "")
                        + ChatSearch.highlighted(row.modelData)
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    opacity: 0.85
                }
            }
        }
    }
}
