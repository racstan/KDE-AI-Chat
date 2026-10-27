// The toolbar above the chat: the history toggle, pin, settings, the chat
// title (with the incognito mark), New chat, New incognito chat, the Chat
// info panel and a "More" menu (rename, jump, export, clear). Every button
// has an accessible name.
//
// Things that live outside the chat (the settings action, dialogs) are
// requested through signals; the parent wires them up.
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

RowLayout {
    id: header

    property var chat: null
    property string appName: "KDE AI Chat"
    // The history takes the whole view (a narrow popup), so chat actions are
    // hidden and the toggle reads "Back to chat". Set by FullRepresentationContent.
    property bool historyFull: chat ? chat.historyOnlyMode : false
    // Which buttons show (Settings → Appearance, chat/ChatPrefs.qml); all by default.
    readonly property var prefs: chat && chat.prefs ? chat.prefs : null
    readonly property var incognito: chat ? chat.incognito || null : null
    readonly property bool inIncognito: !!incognito && incognito.active

    signal settingsRequested()
    signal chatControlsRequested()
    signal exportRequested(string suggestedFile)
    signal scheduleRequested()

    function exportFileName() {
        var cleanTitle = (header.chat.currentSessionTitle || "New Chat").replace(/[\/\?<>\\:\*\|":\s]+/g, "_");
        var now = new Date();
        var year = now.getFullYear();
        var month = String(now.getMonth() + 1).padStart(2, "0");
        var day = String(now.getDate()).padStart(2, "0");
        var hour = String(now.getHours()).padStart(2, "0");
        var min = String(now.getMinutes()).padStart(2, "0");
        var sec = String(now.getSeconds()).padStart(2, "0");
        var timestamp = year + "-" + month + "-" + day + "_" + hour + "-" + min + "-" + sec;
        var docs = String(StandardPaths.writableLocation(StandardPaths.DocumentsLocation)).replace(/\/+$/, "");
        return docs + "/" + encodeURIComponent(cleanTitle + "_" + timestamp + ".md");
    }

    function clearChat() {
        header.chat.messages = [];
        header.chat.editingMessageIndex = -1;
        header.chat.editingDraft = "";
        header.chat.clearCurrentOpenCodeSessionIfNeeded();
        header.chat.saveCurrentSessionState(true);
    }

    Layout.fillWidth: true

    PC3.ToolButton {
        id: historyButton
        objectName: "historyButton"
        // "Back to chat" always shows: it is the way out of the history.
        visible: header.historyFull || !header.prefs || header.prefs.showHistoryButton

        readonly property string label: header.historyFull ? i18n("Back to chat")
            : (header.chat.historyOnlyMode ? i18n("Hide history") : i18n("Show history"))

        icon.name: header.historyFull ? "go-previous-symbolic" : "view-history"
        checkable: !header.historyFull
        checked: !header.historyFull && header.chat.historyOnlyMode
        Accessible.name: label
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: label
        onClicked: header.chat.historyOnlyMode = !header.chat.historyOnlyMode
    }

    PC3.ToolButton {
        objectName: "pinButton"
        visible: !header.prefs || header.prefs.showPinButton
        icon.name: "window-pin"
        checkable: true
        checked: !header.chat.hideOnWindowDeactivate
        onToggled: header.chat.hideOnWindowDeactivate = !checked
        Accessible.name: checked ? i18n("Unpin (close when clicking away)") : i18n("Pin (keep open)")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: Accessible.name
    }

    PC3.ToolButton {
        objectName: "settingsButton"
        visible: !header.prefs || header.prefs.showSettingsButton
        icon.name: "configure"
        Accessible.name: i18n("Open Settings")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: Accessible.name
        onClicked: header.settingsRequested()
    }

    Item {
        Layout.fillWidth: true
    }

    PC3.Label {
        text: header.historyFull ? i18n("%1 History", header.appName) : (header.chat.currentSessionTitle || i18n("New Chat"))
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        Layout.fillWidth: false
        Layout.maximumWidth: Math.max(50, header.width - 220 - (incognitoBadge.visible ? incognitoBadge.width + header.spacing : 0))
        clip: true
    }

    // An incognito chat is marked (chat/IncognitoBadge.qml); its text goes in a very narrow header.
    IncognitoBadge {
        id: incognitoBadge
        visible: !header.historyFull && header.inIncognito
        chat: header.chat
        compact: header.width < Kirigami.Units.gridUnit * 24
    }

    Item {
        Layout.fillWidth: true
    }

    // New chat: a plain "+" with no menu. It sits away from the More button,
    // whose menu opens on hover and used to hang under this one.
    PC3.ToolButton {
        id: newChatButton
        objectName: "newChatButton"
        visible: !header.prefs || header.prefs.showNewChatButton
        icon.name: "list-add"
        display: PC3.AbstractButton.IconOnly
        enabled: !header.chat.loading
        Accessible.role: Accessible.Button
        Accessible.name: i18n("New chat")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: Accessible.name
        // With the history open, the chat starts in the project it shows.
        onClicked: {
            if (header.chat.historyOnlyMode && header.chat.projects)
                header.chat.projects.newChat();
            else
                header.chat.createSession(true);
        }
    }

    // A chat that is never saved (chat/Incognito.qml); while one is open, its mark has the close button.
    PC3.ToolButton {
        objectName: "incognitoButton"
        visible: !!header.incognito && !header.inIncognito
        icon.name: "view-private"
        display: PC3.AbstractButton.IconOnly
        enabled: !header.chat.loading
        Accessible.name: i18n("New incognito chat (never saved)")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: Accessible.name
        onClicked: header.incognito.start()
    }

    // Chat info: this chat's usage and its own settings.
    PC3.ToolButton {
        id: infoButton
        objectName: "infoButton"
        visible: !header.historyFull && (!header.prefs || header.prefs.showInfoButton)
        icon.name: "documentinfo"
        Accessible.name: i18n("Chat info")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: Accessible.name
        onClicked: header.chatControlsRequested()
    }

    // Everything else that acts on this chat, kept out of the toolbar.
    PC3.ToolButton {
        id: moreButton
        objectName: "moreButton"
        readonly property alias menu: moreMenu
        readonly property alias projectMenu: projectMenu

        visible: !header.historyFull
        icon.name: "overflow-menu"
        Accessible.name: i18n("More actions")
        QQC2.ToolTip.visible: hovered && !moreMenu.visible
        QQC2.ToolTip.text: Accessible.name
        // A click or the keyboard (Enter/Space) opens the menu and focuses it.
        onClicked: {
            moreHover.hoverOpened = false;
            moreMenu.focus = true;
            moreMenu.popup(moreButton, 0, moreButton.height);
            moreMenu.forceActiveFocus();
        }

        // The menu also opens when the pointer rests on the button (after a
        // short delay) and closes once the pointer has been off both the
        // button and the menu for a short grace period. A menu opened by
        // hover does not take the keyboard focus from the message box; a click
        // or key makes it an ordinary menu that stays until dismissed.
        onHoveredChanged: {
            if (hovered && !moreMenu.opened)
                moreHover.openTimer.restart();
            else if (!hovered)
                moreHover.openTimer.stop();
        }
        QtObject {
            id: moreHover

            property bool hoverOpened: false
            property real leftAt: 0

            function pointerOnMenu() {
                for (var i = 0; i < moreMenu.count; i++) {
                    var item = moreMenu.itemAt(i);
                    if (item && item.hovered === true)
                        return true;
                }
                return false;
            }

            property Timer openTimer: Timer {
                interval: 150
                onTriggered: {
                    if (moreButton.hovered && !moreMenu.opened) {
                        moreHover.hoverOpened = true;
                        moreMenu.focus = false;
                        moreMenu.popup(moreButton, 0, moreButton.height);
                    }
                }
            }
            // While a hover-opened menu is open: close it 300 ms after the
            // pointer left the button and the menu.
            property Timer watchTimer: Timer {
                interval: 60
                repeat: true
                running: moreHover.hoverOpened && moreMenu.opened
                onRunningChanged: moreHover.leftAt = 0
                onTriggered: {
                    // On another button of the header: close at once.
                    if (newChatButton.hovered || infoButton.hovered)
                        moreMenu.close();
                    else if (moreButton.hovered || moreHover.pointerOnMenu())
                        moreHover.leftAt = 0;
                    else if (moreHover.leftAt === 0)
                        moreHover.leftAt = Date.now();
                    else if (Date.now() - moreHover.leftAt >= 300)
                        moreMenu.close();
                }
            }
        }

        QQC2.Menu {
            id: moreMenu

            QQC2.MenuItem {
                text: i18n("Rename chat")
                icon.name: "document-edit"
                onTriggered: {
                    header.chat.renamingCurrentChat = !header.chat.renamingCurrentChat;
                    header.chat.currentChatRenameDraft = header.chat.currentSessionTitle || "";
                }
            }
            // Puts the open chat in a project (or none); its mode stays.
            ProjectMenu {
                id: projectMenu
                objectName: "moveToProjectMenu"
                chat: header.chat
                enabled: !header.inIncognito
            }
            QQC2.MenuSeparator {
            }
            QQC2.MenuItem {
                text: i18n("Jump to first message")
                icon.name: "go-top"
                onTriggered: {
                    var list = header.chat.msgListViewRef;
                    if (list && list.count > 0) {
                        header.chat.userScrolledUp = true;
                        list.positionViewAtBeginning();
                    }
                }
            }
            QQC2.MenuItem {
                text: i18n("Jump to previous message")
                icon.name: "go-up"
                onTriggered: header.chat.jumpOneMessageAbove()
            }
            QQC2.MenuItem {
                text: i18n("Jump to next message")
                icon.name: "go-down"
                onTriggered: header.chat.jumpOneMessageBelow()
            }
            QQC2.MenuItem {
                text: i18n("Jump to latest message")
                icon.name: "go-bottom"
                onTriggered: {
                    header.chat.userScrolledUp = false;
                    header.chat.scrollToBottom(true);
                }
            }
            QQC2.MenuSeparator {
            }
            QQC2.MenuItem {
                objectName: "scheduleMessageItem"
                text: i18n("Schedule a message…")
                icon.name: "view-calendar"
                enabled: !header.inIncognito  // nothing can be scheduled into an incognito chat
                onTriggered: header.scheduleRequested()
            }
            QQC2.MenuItem {
                text: i18n("Export chat…")
                icon.name: "document-export"
                enabled: !header.chat.loading && header.chat.messages.length > 0
                onTriggered: header.exportRequested(header.exportFileName())
            }
            QQC2.MenuItem {
                text: i18n("Clear chat")
                icon.name: "edit-clear-all"
                enabled: !header.chat.loading && header.chat.messages.length > 0
                onTriggered: header.clearChat()
            }
        }
    }
}
