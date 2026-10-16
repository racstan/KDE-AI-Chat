import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid
import "ProviderService.js" as ProviderService
import "Security.js" as Sec

Item {
    id: repRoot
    anchors.fill: parent

    function getBlocksForMessage(content) {
        if (!content) return [];
        let blocks = [];
        let parts = content.split("```");
        for (let i = 0; i < parts.length; i++) {
            let part = parts[i];
            if (i % 2 === 0) {
                if (part.length > 0 || parts.length === 1) {
                    blocks.push({ "type": "text", "text": part });
                }
            } else {
                let newlineIdx = part.indexOf("\n");
                let language = "code";
                let code = part;
                if (newlineIdx !== -1) {
                    let possibleLang = part.substring(0, newlineIdx).trim();
                    if (/^[a-zA-Z0-9+#-]+$/.test(possibleLang) && possibleLang.length < 15) {
                        language = possibleLang;
                        code = part.substring(newlineIdx + 1);
                    }
                }
                // Strip trailing newline if present to keep code tidy
                if (code.endsWith("\n")) {
                    code = code.substring(0, code.length - 1);
                }
                blocks.push({ "type": "code", "language": language, "text": code });
            }
        }
        return blocks;
    }

    // Shared look for the chat view: one corner radius and one way to tint.
    readonly property real cornerRadius: Kirigami.Units.cornerRadius || Kirigami.Units.smallSpacing
    function tint(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    // Prompt templates (and Pi's own commands) offered while typing "/name".
    function slashSuggestions(text) {
        var m = /^\/([^\s]*)$/.exec(String(text || ""));
        if (!m)
            return [];
        var query = m[1].toLowerCase();
        var list = [];
        try {
            var templates = JSON.parse(plasmoid.configuration.promptTemplates || "[]");
            for (var i = 0; Array.isArray(templates) && i < templates.length; i++) {
                var t = templates[i];
                if (t && t.name && String(t.name).toLowerCase().indexOf(query) === 0)
                    list.push({"name": String(t.name), "detail": String(t.prompt || "").replace(/\s+/g, " ").substring(0, 80)});
            }
        } catch (e) {
        }
        if (root.piMode) {
            var piCommands = [{"name": "help", "detail": i18n("Show Pi's commands")}, {"name": "version", "detail": i18n("Show the installed Pi version")}];
            for (var j = 0; j < piCommands.length; j++) {
                if (piCommands[j].name.indexOf(query) === 0)
                    list.push(piCommands[j]);
            }
        }
        return list;
    }

    // Regenerating a reply removes everything after it, so ask first
    // when there is anything after it.
    function requestRegenerate(index, variant) {
        var later = root.messages.length - 1 - index;
        if (later <= 0) {
            root.regenerateResponse(index, variant);
            return;
        }
        regenerateDialog.messageIndex = index;
        regenerateDialog.variant = variant;
        regenerateDialog.laterCount = later;
        regenerateDialog.open();
    }

    Connections {
        target: root.voiceManagerRef || null
        function onIsPlayingChanged() {
            if (root.voiceManagerRef && !root.voiceManagerRef.isPlaying) {
                root.playingMessageIndex = -1;
            }
        }
    }


    DropArea {
        id: dropArea

        anchors.fill: parent
        onEntered: function(drag) {
            if (drag.hasUrls)
                drag.accept(Qt.CopyAction);

        }
        onDropped: function(drop) {
            if (drop.hasUrls) {
                for (var i = 0; i < drop.urls.length; i++) {
                    root.attachFile(drop.urls[i]);
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: repRoot.tint(Kirigami.Theme.highlightColor, 0.15)
            border.color: Kirigami.Theme.highlightColor
            border.width: 2
            radius: repRoot.cornerRadius
            visible: parent.containsDrag
            z: 999

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                icon.name: "mail-attachment"
                text: i18n("Drop files to attach them")
            }
        }

    }

    ColumnLayout {
        id: mainContentColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        anchors.rightMargin: chatSettingsDialog.visible && !chatSettingsDialog.overlaysChat ? chatSettingsDialog.width + Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // Header: chat list, title with where messages go, chat actions.
        RowLayout {
            id: headerRow

            readonly property var destination: root.chatDestination()

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.ToolButton {
                text: root.historyOnlyMode ? i18n("Back to Chat") : i18n("Chats")
                icon.name: root.historyOnlyMode ? "go-previous" : "view-history"
                display: PC3.AbstractButton.IconOnly
                QQC2.ToolTip.text: i18nc("@info:tooltip %1 is an action name", "%1 (Ctrl+H)", text)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: root.historyOnlyMode = !root.historyOnlyMode
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: root.historyOnlyMode ? i18n("Chats") : root.displayTitle(root.currentSessionTitle)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Shows the provider and model, and whether messages leave
                // this computer. Clicking it opens Chat Settings.
                PC3.ToolButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: parent.width
                    visible: !root.historyOnlyMode && headerRow.destination.name !== ""
                    flat: true
                    font: Kirigami.Theme.smallFont
                    icon.name: headerRow.destination.kind === "pi" ? "utilities-terminal" : (headerRow.destination.local ? "computer" : "network-connect")
                    icon.width: Kirigami.Units.iconSizes.small
                    icon.height: Kirigami.Units.iconSizes.small
                    text: headerRow.destination.model
                        ? i18nc("@action:button chat destination: provider · model", "%1 · %2", headerRow.destination.name, headerRow.destination.model)
                        : headerRow.destination.name
                    Accessible.description: root.chatDestinationDescription(headerRow.destination)
                    QQC2.ToolTip.text: root.chatDestinationDescription(headerRow.destination) + "\n" + i18n("Click to change the model for this chat.")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    onClicked: chatSettingsDialog.toggleForSession(root.currentSessionId)
                }
            }

            PC3.ToolButton {
                text: i18n("Keep Open")
                icon.name: "window-pin"
                display: PC3.AbstractButton.IconOnly
                checkable: true
                checked: !root.hideOnWindowDeactivate
                onToggled: root.hideOnWindowDeactivate = !checked
                QQC2.ToolTip.text: checked ? i18n("Stays open when you click elsewhere") : i18n("Keep open when clicking elsewhere")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PC3.ToolButton {
                text: i18n("New Chat")
                icon.name: "list-add"
                display: PC3.AbstractButton.IconOnly
                enabled: !root.loading
                QQC2.ToolTip.text: i18nc("@info:tooltip %1 is an action name", "%1 (Ctrl+N)", text)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: root.createSession(true)
            }

            PC3.ToolButton {
                id: moreButton

                text: i18n("More Actions")
                icon.name: "overflow-menu"
                display: PC3.AbstractButton.IconOnly
                down: moreMenu.visible
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered && !moreMenu.visible
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onPressed: moreMenu.visible ? moreMenu.close() : moreMenu.popup(moreButton, 0, moreButton.height)

                PC3.Menu {
                    id: moreMenu

                    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

                    PC3.MenuItem {
                        visible: !root.historyOnlyMode
                        height: visible ? implicitHeight : 0
                        text: i18n("Chat Settings")
                        icon.name: "document-properties"
                        onTriggered: chatSettingsDialog.toggleForSession(root.currentSessionId)
                    }
                    PC3.MenuItem {
                        visible: !root.historyOnlyMode
                        height: visible ? implicitHeight : 0
                        text: i18n("Rename Chat")
                        icon.name: "edit-rename"
                        onTriggered: {
                            root.currentChatRenameDraft = root.currentSessionTitle || "";
                            root.renamingCurrentChat = true;
                        }
                    }
                    PC3.MenuItem {
                        visible: !root.historyOnlyMode
                        height: visible ? implicitHeight : 0
                        text: i18n("Export Chat…")
                        icon.name: "document-export"
                        enabled: !root.loading && root.messages.length > 0
                        onTriggered: root.openExportDialog()
                    }
                    PC3.MenuItem {
                        visible: !root.historyOnlyMode
                        height: visible ? implicitHeight : 0
                        text: i18n("Clear Chat")
                        icon.name: "edit-clear-history"
                        enabled: !root.loading && root.messages.length > 0
                        onTriggered: root.clearCurrentChat()
                    }
                    PC3.MenuSeparator {
                        visible: !root.historyOnlyMode
                        height: visible ? implicitHeight : 0
                    }
                    PC3.MenuItem {
                        visible: !root.historyOnlyMode
                        height: visible ? implicitHeight : 0
                        text: i18n("Go to First Message")
                        icon.name: "go-top"
                        enabled: root.messages.length > 0
                        onTriggered: {
                            if (root.msgListViewRef && root.msgListViewRef.count > 0) {
                                root.userScrolledUp = true;
                                root.msgListViewRef.positionViewAtBeginning();
                            }
                        }
                    }
                    PC3.MenuItem {
                        visible: !root.historyOnlyMode
                        height: visible ? implicitHeight : 0
                        text: i18n("Previous Question")
                        icon.name: "go-up"
                        enabled: root.messages.length > 0
                        onTriggered: root.jumpOneMessageAbove()
                    }
                    PC3.MenuItem {
                        visible: !root.historyOnlyMode
                        height: visible ? implicitHeight : 0
                        text: i18n("Next Question")
                        icon.name: "go-down"
                        enabled: root.messages.length > 0
                        onTriggered: root.jumpOneMessageBelow()
                    }
                    PC3.MenuSeparator {
                        visible: !root.historyOnlyMode
                        height: visible ? implicitHeight : 0
                    }
                    PC3.MenuItem {
                        text: i18n("Configure KDE AI Chat…")
                        icon.name: "configure"
                        onTriggered: Plasmoid.internalAction("configure").trigger()
                    }
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.sessionHistoryLoadError !== ""
            type: root.sessionHistoryLoadBlocked ? Kirigami.MessageType.Error : Kirigami.MessageType.Warning
            text: root.sessionHistoryLoadError
            actions: [
                Kirigami.Action {
                    visible: root.sessionHistoryLoadBlocked
                    text: i18n("Start Over…")
                    icon.name: "edit-clear-history"
                    onTriggered: replaceHistoryDialog.open()
                },
                Kirigami.Action {
                    visible: !root.sessionHistoryLoadBlocked
                    text: i18n("Dismiss")
                    icon.name: "dialog-close"
                    onTriggered: root.sessionHistoryLoadError = ""
                }
            ]
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.historyOnlyMode && root.openCodeMode
            spacing: Kirigami.Units.smallSpacing

            Component.onCompleted: {
                if (root.openCodeMode && root.openCodeAgentsList.length === 0)
                    root.fetchOpenCodeAgents();
            }
            onVisibleChanged: {
                if (visible && root.openCodeAgentsList.length === 0)
                    root.fetchOpenCodeAgents();
            }

            PC3.ToolButton {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                icon.name: "folder"
                text: {
                    var p = root.openCodeWorkspaceCwd;
                    return p ? (p.substring(p.lastIndexOf("/") + 1) || p) : i18n("Choose Workspace…");
                }
                display: PC3.AbstractButton.TextBesideIcon
                QQC2.ToolTip.text: {
                    var lines = [root.openCodeWorkspaceCwd ? i18n("OpenCode workspace: %1", root.openCodeWorkspaceCwd) : i18n("Choose the folder OpenCode works in.")];
                    var sess = root.currentOpenCodeSessionId();
                    if (sess)
                        lines.push(i18n("OpenCode session: %1", sess));
                    return lines.join("\n");
                }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: workspaceFolderDialog.open()
            }

            PC3.ComboBox {
                id: agentSelectorCombo

                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                // The list is populated from OpenCode's API/configuration.
                // Never invent agent names locally: an empty list means that
                // OpenCode has not reported any agents yet.
                model: root.openCodeAgentsList
                textRole: "text"
                valueRole: "value"
                enabled: model.length > 0
                displayText: model.length > 0 ? currentText : i18n("No agents")
                currentIndex: {
                    var cur = root.openCodeAgent || "";
                    for (var i = 0; i < model.length; i++) {
                        if (model[i].value === cur) return i;
                    }
                    return 0;
                }
                onActivated: {
                    if (!model[currentIndex]) return;
                    var val = model[currentIndex].value;
                    root.openCodeAgent = val;
                    plasmoid.configuration.openCodeAgent = val;
                }
                Accessible.name: i18n("OpenCode agent")
                QQC2.ToolTip.text: i18n("OpenCode agent. Agents and their models come from opencode.json.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PC3.ToolButton {
                text: i18n("Reload Agents")
                icon.name: "view-refresh"
                display: PC3.AbstractButton.IconOnly
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: root.fetchOpenCodeAgents()
            }

            PC3.ToolButton {
                text: root.currentOpenCodeSessionId() !== "" ? i18n("Open Session in Terminal") : i18n("Open OpenCode in Terminal")
                icon.name: "utilities-terminal"
                display: PC3.AbstractButton.IconOnly
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: root.openOpenCodeInTerminal(root.currentOpenCodeSessionId())
            }

            PC3.ToolButton {
                text: i18n("Load History from OpenCode")
                icon.name: "document-import"
                display: PC3.AbstractButton.IconOnly
                enabled: !root.loading && root.currentOpenCodeSessionId() !== ""
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: root.syncOpenCodeSessionHistory()
            }
        }

        RowLayout {
            visible: !root.historyOnlyMode && root.renamingCurrentChat
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.TextField {
                id: renameField

                Layout.fillWidth: true
                text: root.currentChatRenameDraft
                placeholderText: i18n("Chat name")
                Accessible.name: i18n("Chat name")
                onTextChanged: root.currentChatRenameDraft = text
                onAccepted: {
                    root.renameCurrentSession(root.currentChatRenameDraft);
                    root.renamingCurrentChat = false;
                    root.focusInput();
                }
                Keys.onEscapePressed: {
                    root.renamingCurrentChat = false;
                    root.focusInput();
                }
                onVisibleChanged: {
                    if (visible) {
                        forceActiveFocus();
                        selectAll();
                    }
                }
            }

            PC3.ToolButton {
                text: i18n("Save Name")
                icon.name: "dialog-ok-apply"
                display: PC3.AbstractButton.IconOnly
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: {
                    root.renameCurrentSession(root.currentChatRenameDraft);
                    root.renamingCurrentChat = false;
                }
            }

            PC3.ToolButton {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                display: PC3.AbstractButton.IconOnly
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: root.renamingCurrentChat = false
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.historyOnlyMode ? 1 : 0

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: repRoot.cornerRadius
                        color: Kirigami.Theme.alternateBackgroundColor
                        clip: true

                        Connections {
                            function onClearChatInput() {
                                msgInput.text = "";
                            }

                            target: root
                        }

                        ListView {
                            id: msgList

                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            model: root.messages
                            spacing: Kirigami.Units.largeSpacing
                            clip: true
                            reuseItems: false
                            cacheBuffer: 1000

                            // Smooth free-flowing touchpad kinetics
                            boundsBehavior: Flickable.DragAndOvershootBounds
                            flickDeceleration: 1800
                            maximumFlickVelocity: 6000
                            pixelAligned: false

                            QQC2.ScrollBar.vertical: PC3.ScrollBar {
                                id: verticalScrollBar
                            }

                            WheelHandler {
                                id: msgListWheelHandler
                                target: msgList
                                orientation: Qt.Vertical
                                onWheel: function(event) {
                                    // Touchpads report pixels. Mouse wheels report
                                    // notches of 120; scroll the user's configured
                                    // number of lines per notch.
                                    var delta = 0;
                                    if (event && event.pixelDelta && event.pixelDelta.y !== 0)
                                        delta = event.pixelDelta.y;
                                    else if (event && event.angleDelta)
                                        delta = event.angleDelta.y / 120 * Qt.styleHints.wheelScrollLines * Kirigami.Units.gridUnit;
                                    if (delta !== 0) {
                                        var newY = msgList.contentY - delta;
                                        var minY = msgList.originY;
                                        var maxY = Math.max(minY, msgList.originY + msgList.contentHeight - msgList.height);
                                        msgList.contentY = Math.max(minY, Math.min(newY, maxY));
                                        if (!root.restoringResponseScroll)
                                            root.responseScrollUserMoved = true;
                                        if (!msgList.atYEnd) root.userScrolledUp = true;
                                        event.accepted = true;
                                    }
                                }
                            }

                            onWidthChanged: forceLayout()
                            onHeightChanged: forceLayout()
                            Component.onCompleted: root.msgListViewRef = msgList
                            // Track whether user manually scrolled away from bottom
                            onMovementStarted: {
                                if (!root.restoringResponseScroll)
                                    root.responseScrollUserMoved = true;
                                if (!msgList.atYEnd)
                                    root.userScrolledUp = true;
                            }
                            onAtYEndChanged: {
                                if (msgList.atYEnd)
                                    root.userScrolledUp = false;
                            }
                            onContentYChanged: {
                                if (root.restoringResponseScroll)
                                    return;
                                if (!msgList.atYEnd) {
                                    if (msgList.moving || msgList.dragging || verticalScrollBar.pressed || verticalScrollBar.active)
                                        root.userScrolledUp = true;
                                }
                            }

                            delegate: Item {
                                id: messageDelegate

                                property bool showDayHeader: index === 0 || root.messageDayKeyAt(index) !== root.messageDayKeyAt(index - 1)
                                property bool reasoningExpanded: false
                                property string lastSelectedText: ""
                                readonly property bool isUser: modelData.role === "user" || modelData.role === "queued"
                                readonly property bool isSpecial: modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "system_compacted"
                                readonly property bool isLast: index === root.messages.length - 1
                                readonly property bool isPlayingThis: !!(root.voiceManagerRef && root.voiceManagerRef.isPlaying && root.playingMessageIndex === index)

                                width: msgList.width
                                implicitHeight: delegateCol.implicitHeight
                                height: implicitHeight

                                HoverHandler {
                                    id: messageHover
                                }

                                Column {
                                    id: delegateCol

                                    width: parent.width
                                    spacing: Kirigami.Units.largeSpacing

                                    Item {
                                        visible: showDayHeader
                                        width: parent.width
                                        height: showDayHeader ? dayHeaderChip.implicitHeight : 0

                                        Rectangle {
                                            id: dayHeaderChip

                                            anchors.horizontalCenter: parent.horizontalCenter
                                            radius: height / 2
                                            color: repRoot.tint(Kirigami.Theme.textColor, 0.08)
                                            implicitWidth: dayHeaderText.implicitWidth + Kirigami.Units.largeSpacing * 2
                                            implicitHeight: dayHeaderText.implicitHeight + Kirigami.Units.smallSpacing

                                            PC3.Label {
                                                id: dayHeaderText

                                                anchors.centerIn: parent
                                                font: Kirigami.Theme.smallFont
                                                color: Kirigami.Theme.disabledTextColor
                                                text: root.dayDividerLabelForIndex(index)
                                            }
                                        }
                                    }

                                    Item {
                                        width: parent.width
                                        height: bubble.implicitHeight

                                        Rectangle {
                                            id: bubble

                                            width: Math.min(msgList.width * 0.8, Kirigami.Units.gridUnit * 32)
                                            implicitHeight: bubbleCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                                            radius: repRoot.cornerRadius
                                            color: messageDelegate.isUser
                                                ? repRoot.tint(Kirigami.Theme.highlightColor, modelData.role === "queued" ? 0.1 : 0.2)
                                                : modelData.role === "error" ? Kirigami.Theme.negativeBackgroundColor
                                                : messageDelegate.isSpecial ? repRoot.tint(Kirigami.Theme.focusColor, 0.12)
                                                : Kirigami.Theme.backgroundColor
                                            border.width: 1
                                            border.color: modelData.role === "error" ? Kirigami.Theme.negativeTextColor
                                                : messageDelegate.isSpecial ? Kirigami.Theme.focusColor
                                                : repRoot.tint(Kirigami.Theme.textColor, 0.16)

                                            // Position horizontally using x to prevent anchor conflicts during delegate reuse
                                            x: messageDelegate.isUser ? (parent.width - width - Kirigami.Units.largeSpacing) : Kirigami.Units.largeSpacing

                                            Column {
                                                id: bubbleCol

                                                width: parent.width - Kirigami.Units.largeSpacing * 2
                                                x: Kirigami.Units.largeSpacing
                                                y: Kirigami.Units.largeSpacing
                                                spacing: Kirigami.Units.smallSpacing

                                                RowLayout {
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing

                                                    Kirigami.Icon {
                                                        visible: modelData.role === "error"
                                                        source: "dialog-error"
                                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                                    }

                                                    PC3.Label {
                                                        text: {
                                                            switch (modelData.role) {
                                                            case "user": return i18n("You");
                                                            case "queued": return i18n("You · waiting to send");
                                                            case "error": return i18n("Couldn't get a reply");
                                                            case "question_request": return i18n("OpenCode asks");
                                                            case "permission_request": return i18n("OpenCode needs permission");
                                                            case "system_compacted": return i18n("Summary of earlier messages");
                                                            }
                                                            return i18n("Assistant");
                                                        }
                                                        font.bold: true
                                                    }

                                                    PC3.Label {
                                                        Layout.fillWidth: true
                                                        text: {
                                                            var time = root.formatMessageTime(modelData, index);
                                                            if (modelData.role === "assistant" && modelData.model)
                                                                return i18nc("message time · model name", "%1 · %2", time, modelData.model);
                                                            return time;
                                                        }
                                                        font: Kirigami.Theme.smallFont
                                                        color: Kirigami.Theme.disabledTextColor
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                Rectangle {
                                                    id: reasoningBlock

                                                    property string reasoningText: (root.currentStreamIndex === index && (root.currentStreamReasoning !== "" || root.currentStreamExtractedReasoning !== "")) ? (root.currentStreamReasoning + (root.currentStreamReasoning && root.currentStreamExtractedReasoning ? "\n" : "") + root.currentStreamExtractedReasoning) : (modelData.reasoning || "")

                                                    visible: modelData.role === "assistant" && reasoningText.length > 0 && root.editingMessageIndex !== index
                                                    width: parent.width
                                                    implicitHeight: reasoningCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                                                    radius: repRoot.cornerRadius
                                                    color: repRoot.tint(Kirigami.Theme.focusColor, 0.08)
                                                    border.width: 1
                                                    border.color: repRoot.tint(Kirigami.Theme.focusColor, 0.22)

                                                    ColumnLayout {
                                                        id: reasoningCol
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.top: parent.top
                                                        anchors.margins: Kirigami.Units.smallSpacing
                                                        spacing: Kirigami.Units.smallSpacing

                                                        PC3.ToolButton {
                                                            Layout.fillWidth: true
                                                            text: reasoningExpanded ? i18n("Hide Reasoning") : i18n("Show Reasoning")
                                                            icon.name: reasoningExpanded ? "arrow-up" : "arrow-down"
                                                            onClicked: reasoningExpanded = !reasoningExpanded
                                                        }

                                                        PC3.Label {
                                                            visible: reasoningExpanded
                                                            Layout.fillWidth: true
                                                            wrapMode: Text.Wrap
                                                            textFormat: Text.PlainText
                                                            text: reasoningBlock.reasoningText
                                                            color: Kirigami.Theme.disabledTextColor
                                                        }
                                                    }
                                                }

                                                Loader {
                                                    active: root.editingMessageIndex === index && modelData.role !== "error"
                                                    width: parent.width

                                                    sourceComponent: PC3.TextArea {
                                                        width: parent ? parent.width : implicitWidth
                                                        maximumLength: 200000
                                                        text: root.editingDraft
                                                        wrapMode: Text.WordWrap
                                                        Accessible.name: i18n("Edit message")
                                                        onTextChanged: root.editingDraft = text
                                                        Component.onCompleted: {
                                                            forceActiveFocus();
                                                            cursorPosition = length;
                                                        }
                                                        Keys.onPressed: function(event) {
                                                            if (event.key === Qt.Key_Escape) {
                                                                event.accepted = true;
                                                                root.editingMessageIndex = -1;
                                                                root.editingDraft = "";
                                                                root.focusInput();
                                                            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                                                                event.accepted = true;
                                                                root.saveEditedMessage();
                                                            }
                                                        }
                                                    }
                                                }

                                                Column {
                                                    id: messageBlocksCol
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing
                                                    visible: root.editingMessageIndex !== index || modelData.role === "error"

                                                    property var blocksList: modelData.role === "error" ? [{ type: "text", text: modelData.content }] : repRoot.getBlocksForMessage((root.currentStreamIndex === index && root.currentStreamText !== "") ? root.currentStreamText : modelData.content)

                                                    Component {
                                                        id: textBlockComp
                                                        TextEdit {
                                                            id: textBlockLabel
                                                            width: parent.width
                                                            readOnly: true
                                                            cursorVisible: false
                                                            selectByMouse: true
                                                            persistentSelection: true
                                                            wrapMode: Text.Wrap
                                                            textFormat: modelData.role === "error" ? Text.PlainText : Text.MarkdownText
                                                            color: Kirigami.Theme.textColor
                                                            selectionColor: Kirigami.Theme.highlightColor
                                                            selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                            font: Kirigami.Theme.defaultFont

                                                            property int savedSelectionStart: -1
                                                            property int savedSelectionEnd: -1

                                                            onLinkActivated: function(link) {
                                                                var safeLink = Sec.validateUrl(link);
                                                                if (safeLink)
                                                                    Qt.openUrlExternally(safeLink);
                                                            }

                                                            onSelectedTextChanged: {
                                                                 if (selectedText && selectedText.trim().length > 0) {
                                                                     lastSelectedText = selectedText;
                                                                     savedSelectionStart = selectionStart;
                                                                     savedSelectionEnd = selectionEnd;
                                                                 } else if (!ttsPlayButton.hovered) {
                                                                     lastSelectedText = "";
                                                                     savedSelectionStart = -1;
                                                                     savedSelectionEnd = -1;
                                                                 }
                                                            }

                                                            Connections {
                                                                target: root
                                                                function onPlayingMessageIndexChanged() {
                                                                    if (root.playingMessageIndex === index) {
                                                                        if (savedSelectionStart !== -1 && savedSelectionEnd !== -1) {
                                                                            Qt.callLater(function() {
                                                                                if (savedSelectionStart !== -1 && savedSelectionEnd !== -1) {
                                                                                    textBlockLabel.select(savedSelectionStart, savedSelectionEnd);
                                                                                }
                                                                            });
                                                                        }
                                                                    } else {
                                                                        textBlockLabel.deselect();
                                                                    }
                                                                }
                                                            }

                                                            Connections {
                                                                target: root.voiceManagerRef || null
                                                                ignoreUnknownSignals: true

                                                                function onCurrentPlayingChunkChanged() {
                                                                    if (messageDelegate.isPlayingThis) {
                                                                        let chunk = root.voiceManagerRef.currentPlayingChunk;
                                                                        if (chunk && chunk.length > 2) {
                                                                            let baseText = blockData.text;
                                                                            let cleanChunk = chunk.replace(/[^\w\s]/g, " ").trim();
                                                                            let words = cleanChunk.split(/\s+/).filter(function(w) { return w.length > 0; });
                                                                            if (words.length > 0) {
                                                                                let regexStr = "";
                                                                                for (let i = 0; i < words.length; i++) {
                                                                                    let escapedWord = words[i].replace(/[.*+?^${}()|[\\\]]/g, "\\$&");
                                                                                    if (i > 0) {
                                                                                        regexStr += "[^a-zA-Z0-9]*?";
                                                                                    }
                                                                                    regexStr += escapedWord;
                                                                                }
                                                                                try {
                                                                                    let regex = new RegExp(regexStr, "i");
                                                                                    let match = baseText.match(regex);
                                                                                    if (match) {
                                                                                        let startIdx = match.index;
                                                                                        let endIdx = startIdx + match[0].length;
                                                                                        textBlockLabel.select(startIdx, endIdx);
                                                                                        return;
                                                                                    }
                                                                                } catch(e) {}
                                                                            }
                                                                            let startIdx = baseText.indexOf(chunk);
                                                                            if (startIdx !== -1) {
                                                                                textBlockLabel.select(startIdx, startIdx + chunk.length);
                                                                            }
                                                                        } else {
                                                                            textBlockLabel.deselect();
                                                                        }
                                                                    }
                                                                }

                                                                function onIsPlayingChanged() {
                                                                    if (!root.voiceManagerRef || !root.voiceManagerRef.isPlaying) {
                                                                        textBlockLabel.deselect();
                                                                    }
                                                                }
                                                            }

                                                            // Never let message text load remote images or HTML.
                                                            text: Sec.sanitizeMarkdown(blockData.text)
                                                         }
                                                     }

                                                    Component {
                                                        id: codeBlockComp

                                                        // Code blocks scroll sideways only, so the mouse
                                                        // wheel keeps scrolling the chat. Long blocks are
                                                        // collapsed with a "Show All" button.
                                                        Rectangle {
                                                            id: codeBlock

                                                            readonly property int lineCount: blockData.text.split("\n").length
                                                            readonly property int collapsedLines: 20
                                                            property bool expanded: false

                                                            width: parent.width
                                                            implicitHeight: codeCellCol.implicitHeight
                                                            radius: repRoot.cornerRadius
                                                            color: repRoot.tint(Kirigami.Theme.textColor, 0.06)
                                                            border.width: 1
                                                            border.color: repRoot.tint(Kirigami.Theme.textColor, 0.12)

                                                            ColumnLayout {
                                                                id: codeCellCol
                                                                anchors.left: parent.left
                                                                anchors.right: parent.right
                                                                spacing: 0

                                                                RowLayout {
                                                                    Layout.fillWidth: true
                                                                    Layout.leftMargin: Kirigami.Units.largeSpacing
                                                                    Layout.rightMargin: Kirigami.Units.smallSpacing
                                                                    Layout.topMargin: Kirigami.Units.smallSpacing

                                                                    PC3.Label {
                                                                        Layout.fillWidth: true
                                                                        text: blockData.language && blockData.language !== "code" ? blockData.language : i18n("Code")
                                                                        font: Kirigami.Theme.smallFont
                                                                        color: Kirigami.Theme.disabledTextColor
                                                                        elide: Text.ElideRight
                                                                    }

                                                                    PC3.ToolButton {
                                                                        id: copyBtn
                                                                        text: copiedTimer.running ? i18n("Copied") : i18n("Copy Code")
                                                                        icon.name: copiedTimer.running ? "checkmark" : "edit-copy"
                                                                        display: PC3.AbstractButton.IconOnly
                                                                        QQC2.ToolTip.text: text
                                                                        QQC2.ToolTip.visible: hovered || copiedTimer.running
                                                                        QQC2.ToolTip.delay: copiedTimer.running ? 0 : Kirigami.Units.toolTipDelay
                                                                        onClicked: {
                                                                            root.copyTextToClipboard(blockData.text);
                                                                            copiedTimer.start();
                                                                        }
                                                                        Timer {
                                                                            id: copiedTimer
                                                                            interval: 1500
                                                                            repeat: false
                                                                        }
                                                                    }
                                                                }

                                                                Flickable {
                                                                    id: codeFlick

                                                                    Layout.fillWidth: true
                                                                    Layout.leftMargin: Kirigami.Units.largeSpacing
                                                                    Layout.rightMargin: Kirigami.Units.largeSpacing
                                                                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                                                                    Layout.preferredHeight: codeBlock.expanded || codeBlock.lineCount <= codeBlock.collapsedLines
                                                                        ? codeText.implicitHeight + (codeScroll.visible ? codeScroll.height : 0)
                                                                        : codeText.implicitHeight * codeBlock.collapsedLines / codeBlock.lineCount
                                                                    flickableDirection: Flickable.HorizontalFlick
                                                                    boundsBehavior: Flickable.StopAtBounds
                                                                    contentWidth: codeText.implicitWidth
                                                                    contentHeight: codeText.implicitHeight
                                                                    clip: true

                                                                    QQC2.ScrollBar.horizontal: PC3.ScrollBar {
                                                                        id: codeScroll
                                                                    }

                                                                    TextEdit {
                                                                        id: codeText
                                                                        text: blockData.text
                                                                        textFormat: Text.PlainText
                                                                        font.family: "monospace"
                                                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize
                                                                        color: Kirigami.Theme.textColor
                                                                        selectionColor: Kirigami.Theme.highlightColor
                                                                        selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                                        readOnly: true
                                                                        selectByMouse: true
                                                                        persistentSelection: true
                                                                        wrapMode: Text.NoWrap

                                                                        onSelectedTextChanged: {
                                                                            if (selectedText && selectedText.trim().length > 0)
                                                                                lastSelectedText = selectedText;
                                                                            else if (!ttsPlayButton.hovered)
                                                                                lastSelectedText = "";
                                                                        }
                                                                    }
                                                                }

                                                                PC3.ToolButton {
                                                                    Layout.alignment: Qt.AlignHCenter
                                                                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                                                                    visible: codeBlock.lineCount > codeBlock.collapsedLines
                                                                    text: codeBlock.expanded ? i18n("Show Less") : i18np("Show All %1 Line", "Show All %1 Lines", codeBlock.lineCount)
                                                                    icon.name: codeBlock.expanded ? "arrow-up" : "arrow-down"
                                                                    onClicked: codeBlock.expanded = !codeBlock.expanded
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Repeater {
                                                        model: messageBlocksCol.blocksList
                                                        delegate: Loader {
                                                            width: parent.width
                                                            property var blockData: modelData
                                                            sourceComponent: modelData.type === "code" ? codeBlockComp : textBlockComp
                                                        }
                                                    }
                                                }

                                                // A note when this message asked for a longer or shorter reply.
                                                PC3.Label {
                                                    visible: !!modelData.instructionKind
                                                    width: parent.width
                                                    text: modelData.instructionKind === "longer" ? i18n("Asked for a longer answer") : i18n("Asked for a shorter answer")
                                                    font: Kirigami.Theme.smallFont
                                                    color: Kirigami.Theme.disabledTextColor
                                                }

                                                // Error details and next steps.
                                                Flow {
                                                    visible: modelData.role === "error"
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing

                                                    PC3.Button {
                                                        text: i18n("Try Again")
                                                        icon.name: "view-refresh"
                                                        enabled: !root.loading
                                                        onClicked: root.retryFailedMessage(index)
                                                    }

                                                    PC3.Button {
                                                        visible: modelData.action === "settings"
                                                        text: i18n("Open Settings…")
                                                        icon.name: "configure"
                                                        onClicked: Plasmoid.internalAction("configure").trigger()
                                                    }

                                                    PC3.ToolButton {
                                                        id: errorDetailsToggle
                                                        visible: !!modelData.details
                                                        checkable: true
                                                        text: checked ? i18n("Hide Details") : i18n("Show Details")
                                                        icon.name: checked ? "arrow-up" : "arrow-down"
                                                    }
                                                }

                                                TextEdit {
                                                    visible: errorDetailsToggle.checked && !!modelData.details
                                                    width: parent.width
                                                    readOnly: true
                                                    selectByMouse: true
                                                    wrapMode: Text.Wrap
                                                    textFormat: Text.PlainText
                                                    text: modelData.details || ""
                                                    font: Kirigami.Theme.smallFont
                                                    color: Kirigami.Theme.disabledTextColor
                                                }

                                                Flow {
                                                    width: parent.width
                                                    visible: !!(modelData.attachments && modelData.attachments.length > 0)
                                                    spacing: Kirigami.Units.smallSpacing

                                                    Repeater {
                                                        model: modelData.attachments || []

                                                        delegate: PC3.ToolButton {
                                                            id: sentAttachment

                                                            readonly property bool isImage: modelData.type === "image"

                                                            width: Math.min(implicitWidth, Kirigami.Units.gridUnit * 10)
                                                            flat: false
                                                            text: modelData.name || ""
                                                            display: PC3.AbstractButton.TextBesideIcon
                                                            font: Kirigami.Theme.smallFont
                                                            icon.name: isImage ? "" : root.fileIconName(modelData.name)
                                                            icon.source: isImage ? (modelData.content ? ("data:" + (modelData.mimeType || "image/png") + ";base64," + modelData.content) : ("file://" + modelData.path)) : ""
                                                            enabled: !!modelData.path
                                                            QQC2.ToolTip.text: i18n("Open %1", modelData.path || modelData.name || "")
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                            onClicked: {
                                                                var safePath = Sec.validateFilePath(modelData.path || "");
                                                                if (safePath)
                                                                    Qt.openUrlExternally("file://" + safePath);
                                                            }
                                                        }
                                                    }
                                                }

                                                RowLayout {
                                                    visible: modelData.role === "permission_request"
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing

                                                    PC3.Button {
                                                        visible: modelData.status === "pending"
                                                        text: i18n("Allow")
                                                        icon.name: "dialog-ok-apply"
                                                        onClicked: root.respondToPermission(modelData.permissionId, true)
                                                    }

                                                    PC3.Button {
                                                        visible: modelData.status === "pending"
                                                        text: i18n("Deny")
                                                        icon.name: "dialog-cancel"
                                                        onClicked: root.respondToPermission(modelData.permissionId, false)
                                                    }

                                                    Kirigami.Icon {
                                                        visible: modelData.status === "allowed" || modelData.status === "denied"
                                                        source: modelData.status === "allowed" ? "dialog-ok-apply" : "dialog-cancel"
                                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                                    }

                                                    PC3.Label {
                                                        Layout.fillWidth: true
                                                        visible: modelData.status !== "pending"
                                                        text: modelData.status === "allowed" ? i18n("Allowed") : modelData.status === "denied" ? i18n("Denied") : modelData.status === "allowing..." ? i18n("Allowing…") : i18n("Denying…")
                                                        color: modelData.status === "allowed" ? Kirigami.Theme.positiveTextColor : modelData.status === "denied" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                                    }
                                                }

                                                Column {
                                                    id: questionCol

                                                    property string qId: modelData.questionId || ""
                                                    property var qQuestions: modelData.questions || []
                                                    property bool qAllowCustom: modelData.allowCustom !== false
                                                    property string qStatus: modelData.status || ""
                                                    // One single-choice question: an option answers it right away.
                                                    readonly property bool quickReply: qQuestions.length === 1 && !qQuestions[0].multiple

                                                    visible: modelData.role === "question_request"
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing

                                                    Repeater {
                                                        model: (questionCol.qStatus === "pending" && questionCol.qQuestions.length > 0) ? questionCol.qQuestions : []

                                                        delegate: Column {
                                                            id: questionItemCol

                                                            required property var modelData
                                                            required property int index
                                                            property bool qMultiple: modelData.multiple || false

                                                            width: parent.width
                                                            spacing: Kirigami.Units.smallSpacing

                                                            PC3.Label {
                                                                visible: (modelData.header || "") !== ""
                                                                width: parent.width
                                                                text: modelData.header || ""
                                                                font.bold: true
                                                                wrapMode: Text.Wrap
                                                            }

                                                            Flow {
                                                                width: parent.width
                                                                spacing: Kirigami.Units.smallSpacing
                                                                visible: !!(modelData.options && modelData.options.length > 0)

                                                                Repeater {
                                                                    model: modelData.options || []

                                                                    delegate: PC3.Button {
                                                                        id: optionBtn

                                                                        required property var modelData
                                                                        required property int index

                                                                        text: optionBtn.modelData.label || ""
                                                                        checkable: !questionCol.quickReply
                                                                        checked: root.questionOptionSelected(questionCol.qId, questionItemCol.index, optionBtn.modelData.label || "")
                                                                        icon.name: checked ? "checkmark" : ""
                                                                        QQC2.ToolTip.text: optionBtn.modelData.description || ""
                                                                        QQC2.ToolTip.visible: hovered && (optionBtn.modelData.description || "") !== ""
                                                                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                                        onClicked: {
                                                                            root.toggleQuestionOption(questionCol.qId, questionItemCol.index, optionBtn.modelData.label || "", questionItemCol.qMultiple);
                                                                            if (questionCol.quickReply)
                                                                                root.respondToQuestion(questionCol.qId, optionBtn.modelData.label || "", false);
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            Kirigami.Separator {
                                                                visible: questionItemCol.index < questionCol.qQuestions.length - 1
                                                                width: parent.width
                                                            }
                                                        }
                                                    }

                                                    PC3.TextField {
                                                        id: questionReplyField

                                                        visible: questionCol.qStatus === "pending" && questionCol.qAllowCustom
                                                        width: parent.width
                                                        placeholderText: questionCol.qQuestions.length > 0 ? i18n("Or type your own answer…") : i18n("Type your answer…")
                                                        Accessible.name: i18n("Your answer")
                                                        onAccepted: {
                                                            if (text.trim() !== "")
                                                                root.respondToQuestion(questionCol.qId, text, false);
                                                        }
                                                    }

                                                    RowLayout {
                                                        width: parent.width
                                                        spacing: Kirigami.Units.smallSpacing

                                                        PC3.Button {
                                                            visible: questionCol.qStatus === "pending" && !(questionCol.quickReply && !questionCol.qAllowCustom)
                                                            text: i18n("Send Answer")
                                                            icon.name: "document-send"
                                                            onClicked: root.submitQuestionAnswer(questionCol.qId, questionCol.qQuestions, questionReplyField)
                                                        }

                                                        PC3.Button {
                                                            visible: questionCol.qStatus === "pending"
                                                            text: i18n("Skip")
                                                            icon.name: "dialog-cancel"
                                                            onClicked: root.respondToQuestion(questionCol.qId, "", true)
                                                        }

                                                        PC3.Label {
                                                            Layout.fillWidth: true
                                                            visible: questionCol.qStatus !== "pending"
                                                            wrapMode: Text.Wrap
                                                            text: questionCol.qStatus === "answered" ? i18n("Answered: “%1”", modelData.submittedAnswer || "") : questionCol.qStatus === "dismissed" ? i18n("Skipped") : questionCol.qStatus === "answering..." ? i18n("Sending answer…") : i18n("Skipping…")
                                                            color: questionCol.qStatus === "answered" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                                        }
                                                    }
                                                }

                                                Kirigami.InlineMessage {
                                                    visible: root.editingMessageIndex === index && modelData.role !== "error" && !messageDelegate.isLast
                                                    width: parent.width
                                                    type: Kirigami.MessageType.Warning
                                                    text: i18n("Saving this edit removes every message after it.")
                                                }

                                                PC3.Label {
                                                    visible: modelData.role === "assistant" && text !== ""
                                                    width: parent.width
                                                    horizontalAlignment: Text.AlignRight
                                                    text: root.formatTokensSummary(modelData.tokens)
                                                    font: Kirigami.Theme.smallFont
                                                    color: Kirigami.Theme.disabledTextColor

                                                    HoverHandler {
                                                        id: tokensHover
                                                    }
                                                    QQC2.ToolTip.text: root.formatTokensUsage(modelData.tokens, modelData.cost)
                                                    QQC2.ToolTip.visible: tokensHover.hovered
                                                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                }

                                                // What the assistant looked at or did (OpenCode tools, web search).
                                                Column {
                                                    visible: modelData.role === "assistant" && !!(modelData.contextItems && modelData.contextItems.length > 0)
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing

                                                    PC3.ToolButton {
                                                        id: contextToggle

                                                        checkable: true
                                                        font: Kirigami.Theme.smallFont
                                                        text: i18np("Used %1 tool", "Used %1 tools", modelData.contextItems ? modelData.contextItems.length : 0)
                                                        icon.name: checked ? "arrow-up" : "arrow-down"
                                                    }

                                                    Flow {
                                                        visible: contextToggle.checked
                                                        width: parent.width
                                                        spacing: Kirigami.Units.smallSpacing

                                                        Repeater {
                                                            model: modelData.contextItems || []

                                                            delegate: Rectangle {
                                                                required property string modelData

                                                                width: Math.min(ctxLabel.implicitWidth + Kirigami.Units.largeSpacing * 2, bubbleCol.width)
                                                                height: ctxLabel.implicitHeight + Kirigami.Units.smallSpacing
                                                                radius: height / 2
                                                                color: repRoot.tint(Kirigami.Theme.textColor, 0.08)

                                                                PC3.Label {
                                                                    id: ctxLabel

                                                                    anchors.centerIn: parent
                                                                    width: Math.min(implicitWidth, parent.width - Kirigami.Units.largeSpacing * 2)
                                                                    text: modelData
                                                                    font: Kirigami.Theme.smallFont
                                                                    elide: Text.ElideMiddle
                                                                    maximumLineCount: 1
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                // Message actions. Copy is always shown; the rest
                                                // appear on hover, on keyboard focus, and on the
                                                // latest message.
                                                RowLayout {
                                                    id: messageActions

                                                    readonly property bool revealed: messageHover.hovered || messageDelegate.isLast || messageDelegate.isPlayingThis
                                                        || editBtn.activeFocus || ttsPlayButton.activeFocus || regenerateBtn.activeFocus || deleteBtn.activeFocus

                                                    width: parent.width
                                                    spacing: 0

                                                    PC3.ToolButton {
                                                        text: i18n("Copy")
                                                        icon.name: "edit-copy"
                                                        display: PC3.AbstractButton.IconOnly
                                                        enabled: root.currentStreamIndex !== index
                                                        visible: root.editingMessageIndex !== index
                                                        QQC2.ToolTip.text: text
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                        onClicked: root.copyTextToClipboard(modelData.content)
                                                    }

                                                    PC3.ToolButton {
                                                        id: ttsPlayButton

                                                        visible: root.voiceEnabled && root.voiceTtsEnabled && modelData.role !== "error" && root.editingMessageIndex !== index
                                                        opacity: messageActions.revealed ? 1 : 0
                                                        enabled: root.currentStreamIndex !== index
                                                        text: messageDelegate.isPlayingThis ? i18n("Stop Reading") : ((lastSelectedText && lastSelectedText.trim().length > 0) ? i18n("Read Selection Aloud") : i18n("Read Aloud"))
                                                        icon.name: messageDelegate.isPlayingThis ? "media-playback-stop" : "audio-speakers-symbolic"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.text: text
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                        onClicked: {
                                                            if (!root.voiceManagerRef)
                                                                return;
                                                            if (messageDelegate.isPlayingThis) {
                                                                root.voiceManagerRef.stopTTS();
                                                                root.playingMessageIndex = -1;
                                                                return;
                                                            }
                                                            if (root.voiceManagerRef.isPlaying)
                                                                root.voiceManagerRef.stopTTS();
                                                            let textToPlay = (lastSelectedText && lastSelectedText.trim().length > 0) ? lastSelectedText : modelData.content;
                                                            root.playingMessageIndex = index;
                                                            root.voiceManagerRef.playTTS(textToPlay);
                                                        }

                                                        PC3.BusyIndicator {
                                                            anchors.centerIn: parent
                                                            width: parent.width * 0.8
                                                            height: parent.height * 0.8
                                                            running: !!(root.voiceManagerRef && root.voiceManagerRef.ttsGenerating && root.playingMessageIndex === index)
                                                            visible: running
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        id: editBtn

                                                        visible: root.editingMessageIndex !== index && modelData.role !== "error" && modelData.role !== "system_compacted"
                                                        opacity: messageActions.revealed ? 1 : 0
                                                        enabled: root.currentStreamIndex !== index
                                                        text: i18n("Edit")
                                                        icon.name: "document-edit"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.text: text
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                        onClicked: {
                                                            root.editingMessageIndex = index;
                                                            root.editingDraft = modelData.content;
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        visible: root.editingMessageIndex === index && modelData.role !== "error"
                                                        text: i18n("Save Edit")
                                                        icon.name: "dialog-ok-apply"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.text: i18nc("@info:tooltip %1 is an action name", "%1 (Ctrl+Enter)", text)
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                        onClicked: root.saveEditedMessage()
                                                    }

                                                    PC3.ToolButton {
                                                        visible: root.editingMessageIndex === index && modelData.role !== "error"
                                                        text: i18n("Cancel Edit")
                                                        icon.name: "dialog-cancel"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.text: i18nc("@info:tooltip %1 is an action name", "%1 (Esc)", text)
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                        onClicked: {
                                                            root.editingMessageIndex = -1;
                                                            root.editingDraft = "";
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        id: regenerateBtn

                                                        visible: modelData.role === "assistant" || modelData.role === "opencode_assistant"
                                                        opacity: messageActions.revealed ? 1 : 0
                                                        enabled: root.currentStreamIndex !== index
                                                        text: i18n("Regenerate")
                                                        icon.name: "view-refresh"
                                                        display: PC3.AbstractButton.IconOnly
                                                        down: regenerateMenu.visible
                                                        QQC2.ToolTip.text: text
                                                        QQC2.ToolTip.visible: hovered && !regenerateMenu.visible
                                                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                        onPressed: regenerateMenu.visible ? regenerateMenu.close() : regenerateMenu.popup(regenerateBtn, 0, regenerateBtn.height)

                                                        PC3.Menu {
                                                            id: regenerateMenu

                                                            closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

                                                            PC3.MenuItem {
                                                                text: i18n("Regenerate")
                                                                icon.name: "view-refresh"
                                                                onTriggered: repRoot.requestRegenerate(index, "")
                                                            }
                                                            PC3.MenuItem {
                                                                text: i18n("Regenerate Longer")
                                                                icon.name: "format-text-bold"
                                                                onTriggered: repRoot.requestRegenerate(index, "longer")
                                                            }
                                                            PC3.MenuItem {
                                                                text: i18n("Regenerate Shorter")
                                                                icon.name: "format-text-strikethrough"
                                                                onTriggered: repRoot.requestRegenerate(index, "shorter")
                                                            }
                                                        }
                                                    }

                                                    Item {
                                                        Layout.fillWidth: true
                                                    }

                                                    PC3.ToolButton {
                                                        id: deleteBtn

                                                        opacity: messageActions.revealed ? 1 : 0
                                                        enabled: root.currentStreamIndex !== index
                                                        visible: root.editingMessageIndex !== index
                                                        text: modelData.role === "queued" ? i18n("Remove from Queue") : i18n("Delete Message")
                                                        icon.name: "edit-delete"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.text: text
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                        onClicked: root.deleteMessage(index)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Shown in an empty chat: what to do next, or what's
                        // missing before the chat can be used.
                        Kirigami.PlaceholderMessage {
                            id: emptyChatPlaceholder

                            readonly property string setupIssue: visible ? root.chatSetupIssue() : ""

                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.gridUnit * 4
                            visible: root.messages.length === 0
                            icon.name: setupIssue ? "configure" : "dialog-messages"
                            text: setupIssue ? i18n("Almost ready") : i18n("Ask anything")
                            explanation: setupIssue
                                ? setupIssue
                                : root.chatDestinationDescription(headerRow.destination) + "\n" + i18n("Attach files with the paperclip or by dropping them here. Type / to use a prompt template.")
                            helpfulAction: Kirigami.Action {
                                enabled: emptyChatPlaceholder.setupIssue !== ""
                                text: i18n("Open Settings…")
                                icon.name: "configure"
                                onTriggered: Plasmoid.internalAction("configure").trigger()
                            }
                        }

                        PC3.Button {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Kirigami.Units.largeSpacing
                            anchors.rightMargin: Kirigami.Units.largeSpacing + verticalScrollBar.width
                            visible: root.userScrolledUp && root.messages.length > 0
                            text: i18n("Latest")
                            icon.name: "go-down"
                            QQC2.ToolTip.text: i18n("Go to the latest message")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            onClicked: {
                                root.userScrolledUp = false;
                                root.scrollToBottom(true);
                            }
                        }
                    }

                    RowLayout {
                        visible: root.loading || !!(root.voiceManagerRef && root.voiceManagerRef.phase !== "")
                        spacing: Kirigami.Units.smallSpacing

                        PC3.BusyIndicator {
                            running: root.loading || !!(root.voiceManagerRef && (root.voiceManagerRef.sttBusy || root.voiceManagerRef.ttsGenerating))
                            visible: running
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }

                        PC3.Label {
                            text: {
                                if (root.loading && root.mcpActivity)
                                    return root.mcpActivity;
                                if (root.loading)
                                    return root.streamingResponse ? i18n("Writing a reply…") : i18n("Thinking…");
                                if (root.voiceManagerRef)
                                    return root.voiceManagerRef.statusText;
                                return "";
                            }
                            color: Kirigami.Theme.disabledTextColor
                        }

                        PC3.ToolButton {
                            visible: !root.loading && !!(root.voiceManagerRef && root.voiceManagerRef.isPlaying)
                            text: i18n("Stop Reading")
                            icon.name: "media-playback-stop"
                            display: PC3.AbstractButton.IconOnly
                            QQC2.ToolTip.text: text
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            onClicked: {
                                if (root.voiceManagerRef)
                                    root.voiceManagerRef.stopTTS();
                                root.playingMessageIndex = -1;
                            }
                        }
                    }

                    // Short-lived notices (attachments, export, Undo offers).
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: root.noticeText !== ""
                        text: root.noticeText
                        type: root.noticeType === "error" ? Kirigami.MessageType.Error
                            : root.noticeType === "warning" ? Kirigami.MessageType.Warning
                            : root.noticeType === "positive" ? Kirigami.MessageType.Positive
                            : Kirigami.MessageType.Information
                        actions: [
                            Kirigami.Action {
                                visible: root.noticeActionText !== ""
                                text: root.noticeActionText
                                icon.name: "edit-undo"
                                onTriggered: root.triggerNoticeAction()
                            },
                            Kirigami.Action {
                                text: i18n("Dismiss")
                                icon.name: "dialog-close"
                                displayHint: Kirigami.DisplayHint.IconOnly
                                onTriggered: root.dismissNotice()
                            }
                        ]
                    }

                    // Files waiting to be sent.
                    Flow {
                        Layout.fillWidth: true
                        visible: root.attachedFiles.length > 0
                        spacing: Kirigami.Units.smallSpacing

                        Repeater {
                            model: root.attachedFiles

                            delegate: Rectangle {
                                readonly property bool failed: modelData.error !== ""

                                width: Math.min(chipRow.implicitWidth + Kirigami.Units.smallSpacing * 2, Kirigami.Units.gridUnit * 12)
                                height: chipRow.implicitHeight + Kirigami.Units.smallSpacing
                                radius: repRoot.cornerRadius
                                color: failed ? Kirigami.Theme.negativeBackgroundColor : repRoot.tint(Kirigami.Theme.textColor, 0.08)
                                border.width: 1
                                border.color: failed ? Kirigami.Theme.negativeTextColor : repRoot.tint(Kirigami.Theme.textColor, 0.15)

                                RowLayout {
                                    id: chipRow

                                    anchors.fill: parent
                                    anchors.leftMargin: Kirigami.Units.smallSpacing
                                    anchors.rightMargin: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing

                                    Item {
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small

                                        PC3.BusyIndicator {
                                            anchors.fill: parent
                                            visible: modelData.loading
                                            running: modelData.loading
                                        }

                                        Image {
                                            anchors.fill: parent
                                            visible: !modelData.loading && !failed && modelData.type === "image"
                                            source: visible ? (modelData.content ? ("data:" + (modelData.mimeType || "image/png") + ";base64," + modelData.content) : ("file://" + modelData.path)) : ""
                                            sourceSize.width: Kirigami.Units.iconSizes.small * 2
                                            sourceSize.height: Kirigami.Units.iconSizes.small * 2
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            clip: true
                                        }

                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            visible: !modelData.loading && (failed || modelData.type !== "image")
                                            source: failed ? "dialog-error" : root.fileIconName(modelData.name)
                                        }
                                    }

                                    PC3.Label {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: modelData.name
                                        elide: Text.ElideMiddle
                                        font: Kirigami.Theme.smallFont
                                    }

                                    PC3.ToolButton {
                                        text: i18n("Remove %1", modelData.name)
                                        icon.name: "edit-delete-remove"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.text: i18n("Remove")
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                        onClicked: root.removeAttachedFile(index)
                                    }
                                }
                            }
                        }
                    }

                    // Why an attachment can't be sent, in words rather than colour.
                    PC3.Label {
                        id: attachmentErrorsLabel

                        readonly property var failedFiles: root.attachedFiles.filter(function(f) { return f.error !== ""; })

                        Layout.fillWidth: true
                        visible: failedFiles.length > 0
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.negativeTextColor
                        text: failedFiles.map(function(f) { return i18n("%1: %2", f.name, f.error); }).join("\n")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PC3.ScrollView {
                            id: inputScroll

                            Layout.fillWidth: true
                            Layout.minimumHeight: Kirigami.Units.gridUnit * 3
                            Layout.maximumHeight: Kirigami.Units.gridUnit * 7
                            Layout.preferredHeight: msgInput.implicitHeight

                            PC3.TextArea {
                                id: msgInput

                                maximumLength: 200000
                                wrapMode: Text.WordWrap
                                placeholderText: i18n("Ask anything… (type / for templates)")
                                Accessible.name: i18n("Message")
                                focus: true

                                onActiveFocusChanged: {
                                    if (activeFocus)
                                        root.ensureWalletLoaded();
                                }
                                // Sync to root property so root-scope functions can read/clear it
                                onTextChanged: root.chatInputText = text
                                Keys.onPressed: function(event) {
                                    if (slashPopup.visible) {
                                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                                            event.accepted = true;
                                            var n = slashPopup.matches.length;
                                            slashList.currentIndex = (slashList.currentIndex + (event.key === Qt.Key_Down ? 1 : n - 1)) % n;
                                            return;
                                        }
                                        if (event.key === Qt.Key_Tab || ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier))) {
                                            event.accepted = true;
                                            slashPopup.accept();
                                            return;
                                        }
                                        if (event.key === Qt.Key_Escape) {
                                            event.accepted = true;
                                            slashPopup.dismissedFor = msgInput.text;
                                            return;
                                        }
                                    }
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                        event.accepted = true;
                                        root.sendMessage();
                                    } else if (event.key === Qt.Key_Up && msgInput.text === "" && !root.loading) {
                                        // Up in an empty input edits your last message.
                                        for (var i = root.messages.length - 1; i >= 0; i--) {
                                            var role = root.messages[i].role;
                                            if (role === "user" || role === "queued") {
                                                event.accepted = true;
                                                root.editingMessageIndex = i;
                                                root.editingDraft = root.messages[i].content;
                                                root.msgListViewRef.positionViewAtIndex(i, ListView.Contain);
                                                break;
                                            }
                                        }
                                    } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                        root.checkClipboardForAttachments();
                                        event.accepted = false;
                                    }
                                }
                                Component.onCompleted: {
                                    if (root.expanded)
                                        focusTimer.start();
                                    msgInput.text = root.chatInputText;
                                }

                                Connections {
                                    target: root
                                    function onChatInputTextChanged() {
                                        if (msgInput.text !== root.chatInputText) {
                                            msgInput.text = root.chatInputText;
                                        }
                                    }
                                }

                                Timer {
                                    id: focusTimer

                                    interval: 120
                                    repeat: false
                                    onTriggered: {
                                        if (msgInput.enabled && msgInput.visible)
                                            msgInput.forceActiveFocus();
                                    }
                                }

                                Connections {
                                    function onExpandedChanged() {
                                        if (root.expanded)
                                            focusTimer.start();
                                    }

                                    function onFocusInputRequested() {
                                        focusTimer.start();
                                    }

                                    target: root
                                }
                            }
                        }

                        // Template suggestions while typing "/name".
                        QQC2.Popup {
                            id: slashPopup

                            parent: inputScroll

                            property string dismissedFor: ""
                            readonly property var matches: msgInput.activeFocus && msgInput.text !== dismissedFor ? repRoot.slashSuggestions(msgInput.text) : []

                            function accept() {
                                var item = matches[slashList.currentIndex];
                                if (!item)
                                    return;
                                msgInput.text = "/" + item.name + " ";
                                msgInput.cursorPosition = msgInput.length;
                            }

                            visible: matches.length > 0
                            closePolicy: QQC2.Popup.NoAutoClose
                            x: 0
                            y: -height - Kirigami.Units.smallSpacing
                            width: inputScroll.width
                            height: Math.min(slashList.contentHeight, Kirigami.Units.gridUnit * 10) + topPadding + bottomPadding
                            padding: Kirigami.Units.smallSpacing
                            onMatchesChanged: slashList.currentIndex = 0

                            ListView {
                                id: slashList

                                anchors.fill: parent
                                clip: true
                                model: slashPopup.matches
                                currentIndex: 0

                                delegate: PC3.ItemDelegate {
                                    required property var modelData
                                    required property int index

                                    width: ListView.view.width
                                    highlighted: ListView.isCurrentItem
                                    text: "/" + modelData.name
                                    onClicked: {
                                        slashList.currentIndex = index;
                                        slashPopup.accept();
                                        msgInput.forceActiveFocus();
                                    }

                                    contentItem: ColumnLayout {
                                        spacing: 0
                                        PC3.Label {
                                            Layout.fillWidth: true
                                            text: "/" + modelData.name
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        PC3.Label {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: modelData.detail
                                            font: Kirigami.Theme.smallFont
                                            color: Kirigami.Theme.disabledTextColor
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignBottom
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                spacing: 0

                                PC3.ToolButton {
                                    id: addButton

                                    text: i18n("Add to Message")
                                    icon.name: "mail-attachment"
                                    display: PC3.AbstractButton.IconOnly
                                    down: addMenu.visible
                                    QQC2.ToolTip.text: text
                                    QQC2.ToolTip.visible: hovered && !addMenu.visible
                                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                    onPressed: addMenu.visible ? addMenu.close() : addMenu.popup(addButton, 0, -addMenu.implicitHeight)

                                    PC3.Menu {
                                        id: addMenu

                                        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

                                        PC3.MenuItem {
                                            text: i18n("Attach Files…")
                                            icon.name: "mail-attachment"
                                            onTriggered: fileDialog.open()
                                        }
                                        PC3.MenuItem {
                                            text: i18n("Capture Screen Region…")
                                            icon.name: "spectacle"
                                            onTriggered: root.captureScreenRegion()
                                        }
                                        PC3.MenuItem {
                                            text: i18n("Paste from Clipboard")
                                            icon.name: "edit-paste"
                                            onTriggered: {
                                                root.checkClipboardForAttachments();
                                                var txt = root.readClipboardText();
                                                if (txt && txt.trim() !== "")
                                                    msgInput.insert(msgInput.cursorPosition, txt);
                                            }
                                        }
                                    }
                                }

                                PC3.ToolButton {
                                    id: recordButton

                                    visible: root.voiceEnabled
                                    readonly property bool recording: !!(root.voiceManagerRef && root.voiceManagerRef.isRecording)
                                    text: recording ? i18n("Stop Dictation") : i18n("Dictate")
                                    icon.name: recording ? "media-playback-stop" : "audio-input-microphone"
                                    display: PC3.AbstractButton.IconOnly
                                    QQC2.ToolTip.text: recording ? text : i18n("Dictate (speech is processed on this computer)")
                                    QQC2.ToolTip.visible: hovered
                                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                    onClicked: {
                                        if (!root.voiceManagerRef)
                                            return;
                                        if (recording)
                                            root.voiceManagerRef.stopRecording();
                                        else
                                            root.voiceManagerRef.startRecording();
                                    }

                                    PC3.BusyIndicator {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.8
                                        height: parent.height * 0.8
                                        running: !!(root.voiceManagerRef && root.voiceManagerRef.sttBusy)
                                        visible: running
                                    }
                                }
                            }

                            RowLayout {
                                spacing: Kirigami.Units.smallSpacing

                                PC3.Button {
                                    id: sendButton

                                    readonly property bool hasContent: root.chatInputText.trim() !== "" || root.attachedFiles.length > 0
                                    readonly property bool attachmentsReady: root.attachmentsReadyToSend()

                                    text: root.loading ? i18nc("@action:button add message to the queue", "Queue") : i18n("Send")
                                    icon.name: root.loading ? "list-add" : "document-send"
                                    enabled: attachmentsReady && hasContent
                                    QQC2.ToolTip.text: {
                                        if (!attachmentsReady)
                                            return attachmentErrorsLabel.failedFiles.length > 0
                                                ? i18np("Remove the attachment that couldn't be read", "Remove the %1 attachments that couldn't be read", attachmentErrorsLabel.failedFiles.length)
                                                : i18n("Wait for attachments to finish loading");
                                        if (root.loading)
                                            return i18n("Send after the current reply finishes");
                                        return i18n("Send (Enter). New line: Shift+Enter.");
                                    }
                                    QQC2.ToolTip.visible: hovered
                                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                    onClicked: root.sendMessage()
                                }

                                PC3.ToolButton {
                                    visible: root.loading
                                    text: i18n("Stop")
                                    icon.name: "media-playback-stop"
                                    display: PC3.AbstractButton.IconOnly
                                    QQC2.ToolTip.text: i18nc("@info:tooltip %1 is an action name", "%1 (Esc)", i18n("Stop the reply"))
                                    QQC2.ToolTip.visible: hovered
                                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                    onClicked: root.stopStreaming()
                                }
                            }
                        }
                    }
                }
            }

            Loader {
                id: historyLoader

                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.historyOnlyMode
                visible: status === Loader.Ready

                sourceComponent: Component {
                    ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.SearchField {
                            id: chatSearch

                            Layout.fillWidth: true
                            placeholderText: i18n("Search chats…")
                            Component.onCompleted: forceActiveFocus()
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: repRoot.cornerRadius
                            color: Kirigami.Theme.alternateBackgroundColor

                            ListView {
                                id: historyList

                                readonly property string query: chatSearch.text.trim().toLowerCase()

                                function matches(session) {
                                    if (!query)
                                        return true;
                                    if (String(session.text || "").toLowerCase().indexOf(query) >= 0)
                                        return true;
                                    var msgs = session.messages || [];
                                    for (var i = 0; i < msgs.length; i++) {
                                        if (String(msgs[i].content || "").toLowerCase().indexOf(query) >= 0)
                                            return true;
                                    }
                                    return false;
                                }

                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                model: root.sessions
                                clip: true
                                cacheBuffer: 5000

                                QQC2.ScrollBar.vertical: PC3.ScrollBar {
                                }

                                delegate: ColumnLayout {
                                    id: chatRow

                                    required property var modelData
                                    required property int index
                                    readonly property bool shown: historyList.matches(modelData)
                                    readonly property bool isCurrent: modelData.value === root.currentSessionId
                                    readonly property bool renaming: root.editingSessionId === modelData.value
                                    // Archived chats are sorted last; label where they start.
                                    readonly property bool firstArchived: !!modelData.archived && (index === 0 || !root.sessions[index - 1].archived)

                                    width: historyList.width
                                    visible: shown
                                    height: shown ? implicitHeight : 0
                                    spacing: 0

                                    Kirigami.ListSectionHeader {
                                        Layout.fillWidth: true
                                        visible: chatRow.firstArchived
                                        text: i18n("Archived")
                                    }

                                    PC3.ItemDelegate {
                                        Layout.fillWidth: true
                                        highlighted: chatRow.isCurrent
                                        onClicked: {
                                            if (chatRow.renaming)
                                                return;
                                            root.switchSession(chatRow.modelData.value);
                                            root.historyOnlyMode = false;
                                        }

                                        contentItem: RowLayout {
                                            spacing: Kirigami.Units.smallSpacing

                                            Kirigami.Icon {
                                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                                source: chatRow.modelData.source === "opencode" ? "code-context"
                                                    : chatRow.modelData.source === "pi" ? "utilities-terminal" : "dialog-messages"
                                                opacity: chatRow.modelData.archived ? 0.6 : 1
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 0

                                                PC3.TextField {
                                                    id: chatRenameField

                                                    Layout.fillWidth: true
                                                    visible: chatRow.renaming
                                                    text: root.editingSessionDraft
                                                    Accessible.name: i18n("Chat name")
                                                    onTextChanged: if (chatRow.renaming) root.editingSessionDraft = text
                                                    onAccepted: root.saveSessionRename(chatRow.modelData.value)
                                                    Keys.onEscapePressed: root.cancelSessionRename()
                                                    onVisibleChanged: {
                                                        if (visible) {
                                                            forceActiveFocus();
                                                            selectAll();
                                                        }
                                                    }
                                                }

                                                PC3.Label {
                                                    Layout.fillWidth: true
                                                    visible: !chatRow.renaming
                                                    text: root.displayTitle(chatRow.modelData.text)
                                                    font.bold: chatRow.isCurrent
                                                    elide: Text.ElideRight
                                                }

                                                PC3.Label {
                                                    Layout.fillWidth: true
                                                    text: root.sessionSubtitle(chatRow.modelData)
                                                    font: Kirigami.Theme.smallFont
                                                    color: Kirigami.Theme.disabledTextColor
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            PC3.ToolButton {
                                                text: chatRow.renaming ? i18n("Save Name") : i18n("Rename")
                                                icon.name: chatRow.renaming ? "dialog-ok-apply" : "edit-rename"
                                                display: PC3.AbstractButton.IconOnly
                                                QQC2.ToolTip.text: text
                                                QQC2.ToolTip.visible: hovered
                                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                onClicked: {
                                                    if (chatRow.renaming)
                                                        root.saveSessionRename(chatRow.modelData.value);
                                                    else
                                                        root.startSessionRename(chatRow.modelData.value);
                                                }
                                            }

                                            PC3.ToolButton {
                                                visible: !chatRow.renaming
                                                text: chatRow.modelData.archived ? i18n("Unarchive") : i18n("Archive")
                                                icon.name: chatRow.modelData.archived ? "archive-extract" : "archive-insert"
                                                display: PC3.AbstractButton.IconOnly
                                                QQC2.ToolTip.text: text
                                                QQC2.ToolTip.visible: hovered
                                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                onClicked: root.setSessionArchived(chatRow.modelData.value, !chatRow.modelData.archived)
                                            }

                                            PC3.ToolButton {
                                                text: chatRow.renaming ? i18n("Cancel") : i18n("Delete")
                                                icon.name: chatRow.renaming ? "dialog-cancel" : "edit-delete"
                                                display: PC3.AbstractButton.IconOnly
                                                QQC2.ToolTip.text: text
                                                QQC2.ToolTip.visible: hovered
                                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                                onClicked: {
                                                    if (chatRow.renaming)
                                                        root.cancelSessionRename();
                                                    else
                                                        root.deleteSession(chatRow.modelData.value);
                                                }
                                            }
                                        }
                                    }
                                }

                                Kirigami.PlaceholderMessage {
                                    anchors.centerIn: parent
                                    width: parent.width - Kirigami.Units.gridUnit * 4
                                    visible: historyList.query !== "" && !root.sessions.some(function(s) { return historyList.matches(s); })
                                    icon.name: "edit-find"
                                    text: i18n("No chats match “%1”", chatSearch.text.trim())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ChatSettingsDialog {
        id: chatSettingsDialog
        rootRef: root
        hostItem: repRoot
    }

    Kirigami.PromptDialog {
        id: regenerateDialog

        property int messageIndex: -1
        property string variant: ""
        property int laterCount: 0

        title: i18n("Regenerate This Reply?")
        subtitle: i18np("The message after this reply will be removed.", "The %1 messages after this reply will be removed.", laterCount)
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: i18n("Regenerate")
                icon.name: "view-refresh"
                onTriggered: {
                    regenerateDialog.close();
                    root.regenerateResponse(regenerateDialog.messageIndex, regenerateDialog.variant);
                }
            },
            Kirigami.Action {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onTriggered: regenerateDialog.close()
            }
        ]
    }

    Kirigami.PromptDialog {
        id: replaceHistoryDialog

        title: i18n("Start Over with an Empty Chat List?")
        subtitle: i18n("Your stored chats can't be read. Starting over replaces them with a new, empty chat list. This can't be undone.\n\nIf you want to try to recover them first, back up the file ~/.config/plasma-org.kde.plasma.desktop-appletsrc.")
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: i18n("Start Over")
                icon.name: "edit-clear-history"
                onTriggered: {
                    root.resetUnreadableSessionHistory();
                    replaceHistoryDialog.close();
                }
            },
            Kirigami.Action {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onTriggered: replaceHistoryDialog.close()
            }
        ]
    }

    // Keyboard shortcuts while the popup is open.
    Shortcut {
        sequences: [StandardKey.New]
        enabled: root.expanded && !root.loading
        onActivated: root.createSession(true)
    }

    Shortcut {
        sequence: "Ctrl+H"
        enabled: root.expanded
        onActivated: root.historyOnlyMode = !root.historyOnlyMode
    }

    // Escape stops a reply first, then closes panels; with nothing to
    // close it's left to Plasma, which closes the popup.
    Shortcut {
        sequence: "Escape"
        enabled: root.expanded && (root.loading || chatSettingsDialog.visible || root.historyOnlyMode)
        onActivated: {
            if (root.loading)
                root.stopStreaming();
            else if (chatSettingsDialog.visible)
                chatSettingsDialog.requestClose();
            else
                root.historyOnlyMode = false;
        }
    }
}
