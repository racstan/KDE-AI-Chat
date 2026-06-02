import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasmoid

Item {
    id: chatBubble

    required property var modelData
    required property int index
    required property var rootRef
    required property real availableWidth
    required property var clipboardHelper
    required property var customStorageDs
    required property var schedulerDs

                                    property bool showDayHeader: index === 0 || rootRef.messageDayKeyAt(index) !== rootRef.messageDayKeyAt(index - 1)

                                    width: availableWidth
                                    implicitHeight: delegateCol.implicitHeight
                                    height: implicitHeight

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
                                                radius: 999
                                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                                                implicitWidth: dayHeaderText.implicitWidth + Kirigami.Units.largeSpacing
                                                implicitHeight: dayHeaderText.implicitHeight + Kirigami.Units.smallSpacing

                                                PC3.Label {
                                                    id: dayHeaderText

                                                    anchors.centerIn: parent
                                                    horizontalAlignment: Text.AlignHCenter
                                                    opacity: 0.78
                                                    text: rootRef.dayDividerLabelForIndex(index)
                                                }

                                            }

                                        }

                                        Item {
                                            width: parent.width
                                            height: bubble.implicitHeight

                                            Rectangle {
                                                id: bubble

                                                width: Math.min(availableWidth * 0.76, 560)
                                                implicitHeight: bubbleCol.implicitHeight + Kirigami.Units.largeSpacing
                                                radius: 10
                                                color: modelData.role === "user" ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2) : modelData.role === "queued" ? Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.18) : modelData.role === "error" ? Kirigami.Theme.negativeBackgroundColor : (modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list") ? Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.12) : Kirigami.Theme.backgroundColor
                                                border.width: modelData.role === "error" || modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list" ? 2 : 1
                                                border.color: modelData.role === "error" ? Kirigami.Theme.negativeTextColor : (modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list") ? Kirigami.Theme.focusColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
                                                anchors.right: modelData.role === "user" || modelData.role === "queued" ? parent.right : undefined
                                                anchors.left: modelData.role === "assistant" || modelData.role === "error" || modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "schedules_list" ? parent.left : undefined

                                                Column {
                                                    // ── end message body ───────────────────────────────────────

                                                    id: bubbleCol

                                                    width: parent.width - Kirigami.Units.largeSpacing
                                                    x: Kirigami.Units.smallSpacing + Kirigami.Units.smallSpacing / 2
                                                    y: Kirigami.Units.smallSpacing + Kirigami.Units.smallSpacing / 2
                                                    spacing: Kirigami.Units.smallSpacing

                                                    Row {
                                                        width: parent.width
                                                        spacing: Kirigami.Units.smallSpacing

                                                        PC3.Label {
                                                            text: modelData.role === "user" ? "You" : modelData.role === "queued" ? "You (Queued)" : modelData.role === "error" ? "Error" : modelData.role === "question_request" ? "OpenCode Interactive Question" : modelData.role === "permission_request" ? "OpenCode Security Request" : modelData.role === "schedules_list" ? "Schedules Manager" : "AI"
                                                            font.bold: true
                                                        }

                                                        PC3.Label {
                                                            text: rootRef.formatMessageTime(modelData, index)
                                                            opacity: 0.7
                                                            visible: text !== ""
                                                        }

                                                        PC3.Label {
                                                            text: modelData.role === "assistant" && modelData.model ? ("(" + modelData.model + ")") : ""
                                                            opacity: 0.6
                                                            visible: text !== ""
                                                        }

                                                    }

                                                    Loader {
                                                        active: rootRef.editingMessageIndex === index && modelData.role !== "error" && modelData.role !== "assistant"
                                                        width: parent.width

                                                        sourceComponent: QQC2.TextArea {
                                                            width: parent ? parent.width : implicitWidth
                                                            text: rootRef.editingDraft
                                                            wrapMode: Text.WordWrap
                                                            onTextChanged: rootRef.editingDraft = text
                                                        }

                                                    }

                                                    // ── Selectable / interactive message body ─────────────────
                                                    Column {
                                                        visible: rootRef.editingMessageIndex !== index || modelData.role === "error"
                                                        width: parent.width
                                                        spacing: 4

                                                        // For error messages just render plain selectable text
                                                        TextEdit {
                                                            visible: modelData.role === "error"
                                                            width: parent.width
                                                            wrapMode: Text.Wrap
                                                            textFormat: Text.PlainText
                                                            text: modelData.content
                                                            color: Kirigami.Theme.negativeTextColor
                                                            readOnly: true
                                                            selectByMouse: true
                                                            selectByKeyboard: true
                                                            selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                            selectionColor: Kirigami.Theme.highlightColor
                                                            font: Kirigami.Theme.defaultFont
                                                        }

                                                        // For non-error messages render block-by-block
                                                        Repeater {
                                                            visible: modelData.role !== "error" && modelData.role !== "schedules_list"
                                                            model: modelData.role !== "error" && modelData.role !== "schedules_list" ? rootRef.parseMessageBlocks(modelData.content) : []

                                                            delegate: Item {
                                                                required property var modelData

                                                                width: parent.width
                                                                implicitHeight: modelData.type === "code" ? codeLoader.implicitHeight : htmlEdit.implicitHeight

                                                                // ── HTML / Markdown text block ───────────────────────
                                                                TextEdit {
                                                                    id: htmlEdit

                                                                    visible: modelData.type === "text"
                                                                    width: parent.width
                                                                    wrapMode: Text.Wrap
                                                                    textFormat: Text.RichText
                                                                    text: rootRef.convertMarkdownToHtml(modelData.content)
                                                                    color: Kirigami.Theme.textColor
                                                                    readOnly: true
                                                                    selectByMouse: true
                                                                    selectByKeyboard: true
                                                                    selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                                    selectionColor: Kirigami.Theme.highlightColor
                                                                    font: Kirigami.Theme.defaultFont
                                                                    onLinkActivated: function(link) {
                                                                        if (link && (link.indexOf("http://") === 0 || link.indexOf("https://") === 0))
                                                                            Qt.openUrlExternally(link);
                                                                    }
                                                                }

                                                                // ── Code block with copy button ───────────────────────
                                                                Item {
                                                                    id: codeLoader

                                                                    visible: modelData.type === "code"
                                                                    width: parent.width
                                                                    implicitHeight: codeContainer.implicitHeight + 2

                                                                    Rectangle {
                                                                        id: codeContainer

                                                                        width: parent.width
                                                                        implicitHeight: codeLangRow.implicitHeight + codeBody.implicitHeight + Kirigami.Units.smallSpacing * 3
                                                                        radius: 6
                                                                        color: rootRef.popupIsDark ? "#2d3139" : "#f0f2f5"
                                                                        border.width: 1
                                                                        border.color: rootRef.popupIsDark ? "#3e4452" : "#d0d4dc"
                                                                        clip: true

                                                                        // Lang label + copy button row
                                                                        Row {
                                                                            id: codeLangRow

                                                                            width: parent.width
                                                                            height: Math.max(langLabel.implicitHeight + Kirigami.Units.smallSpacing, copyCodeBtn.implicitHeight + Kirigami.Units.smallSpacing)
                                                                            spacing: 0

                                                                            PC3.Label {
                                                                                id: langLabel

                                                                                anchors.verticalCenter: parent.verticalCenter
                                                                                leftPadding: Kirigami.Units.smallSpacing + 4
                                                                                text: modelData.lang || "code"
                                                                                font.pointSize: 8
                                                                                font.bold: true
                                                                                color: rootRef.popupIsDark ? "#5c6370" : "#a0a1a7"
                                                                                width: parent.width - copyCodeBtn.width - Kirigami.Units.smallSpacing
                                                                            }

                                                                            PC3.ToolButton {
                                                                                id: copyCodeBtn

                                                                                anchors.verticalCenter: parent.verticalCenter
                                                                                icon.name: "edit-copy"
                                                                                display: PC3.AbstractButton.IconOnly
                                                                                flat: true
                                                                                QQC2.ToolTip.visible: hovered
                                                                                QQC2.ToolTip.text: "Copy code"
                                                                                onClicked: {
                                                                                    clipboardHelper.text = modelData.content;
                                                                                    clipboardHelper.selectAll();
                                                                                    clipboardHelper.copy();
                                                                                }
                                                                            }

                                                                        }

                                                                        // Thin divider
                                                                        Rectangle {
                                                                            y: codeLangRow.height
                                                                            width: parent.width
                                                                            height: 1
                                                                            color: rootRef.popupIsDark ? "#3e4452" : "#d0d4dc"
                                                                        }

                                                                        // Code text
                                                                        TextEdit {
                                                                            id: codeBody

                                                                            y: codeLangRow.height + 1
                                                                            width: parent.width
                                                                            leftPadding: Kirigami.Units.smallSpacing + 4
                                                                            rightPadding: Kirigami.Units.smallSpacing + 4
                                                                            topPadding: Kirigami.Units.smallSpacing
                                                                            bottomPadding: Kirigami.Units.smallSpacing
                                                                            wrapMode: Text.Wrap
                                                                            textFormat: Text.PlainText
                                                                            text: modelData.content
                                                                            color: rootRef.popupIsDark ? "#abb2bf" : "#383a42"
                                                                            font.family: "monospace"
                                                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
                                                                            readOnly: true
                                                                            selectByMouse: true
                                                                            selectByKeyboard: true
                                                                            selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                                            selectionColor: Kirigami.Theme.highlightColor
                                                                        }

                                                                    }

                                                                }

                                                                // ── Markdown table with CSV export button ─────────────
                                                                Item {
                                                                    visible: modelData.type === "table"
                                                                    width: parent.width
                                                                    implicitHeight: tableOuterCol.implicitHeight

                                                                    Column {
                                                                        id: tableOuterCol

                                                                        width: parent.width
                                                                        spacing: 2

                                                                        // Export button row
                                                                        Row {
                                                                            width: parent.width
                                                                            layoutDirection: Qt.RightToLeft

                                                                            PC3.ToolButton {
                                                                                icon.name: "document-export"
                                                                                display: PC3.AbstractButton.IconOnly
                                                                                flat: true
                                                                                QQC2.ToolTip.visible: hovered
                                                                                QQC2.ToolTip.text: "Export table as CSV"
                                                                                onClicked: {
                                                                                    var csv = rootRef.tableMarkdownToCsv(modelData.content);
                                                                                    var ts = new Date().getTime();
                                                                                    var path = "/tmp/kdeaichat-table-" + ts + ".csv";
                                                                                    var escaped = path.replace(/'/g, "'\\''");
                                                                                    clipboardHelper.text = csv;
                                                                                    clipboardHelper.selectAll();
                                                                                    clipboardHelper.copy();
                                                                                    customStorageDs.connectSource("bash -c \"printf '%s' '" + csv.replace(/'/g, "'\\''") + "' > '" + escaped + "' && xdg-open '" + escaped + "'\" #csv-export-" + ts);
                                                                                }
                                                                            }

                                                                        }

                                                                        // Table rendered as HTML
                                                                        TextEdit {
                                                                            width: parent.width
                                                                            wrapMode: Text.Wrap
                                                                            textFormat: Text.RichText
                                                                            text: rootRef.convertMarkdownToHtml(modelData.content)
                                                                            color: Kirigami.Theme.textColor
                                                                            readOnly: true
                                                                            selectByMouse: true
                                                                            selectByKeyboard: true
                                                                            selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                                            selectionColor: Kirigami.Theme.highlightColor
                                                                            font: Kirigami.Theme.defaultFont
                                                                        }

                                                                    }

                                                                }

                                                            }

                                                        }

                                                    }

                                                    Row {
                                                        visible: modelData.role === "error"
                                                        spacing: Kirigami.Units.smallSpacing

                                                        PC3.Button {
                                                            text: rootRef.translate("Open Settings")
                                                            icon.name: "configure"
                                                            onClicked: {
                                                                 rootRef.triggerConfigure();
                                                             }
                                                        }

                                                    }

                                                    Flow {
                                                        width: parent.width
                                                        visible: modelData.attachments && modelData.attachments.length > 0
                                                        spacing: Kirigami.Units.smallSpacing

                                                        Repeater {
                                                            model: modelData.attachments || []

                                                            delegate: Rectangle {
                                                                width: Math.min(150, msgFilenameLabel.implicitWidth + 36)
                                                                height: Kirigami.Units.gridUnit * 1.25
                                                                radius: 6
                                                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                                                                border.width: 1
                                                                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)

                                                                RowLayout {
                                                                    anchors.fill: parent
                                                                    anchors.margins: Kirigami.Units.smallSpacing
                                                                    spacing: Kirigami.Units.smallSpacing

                                                                    Item {
                                                                        Layout.preferredWidth: 16
                                                                        Layout.preferredHeight: 16

                                                                        Image {
                                                                            anchors.fill: parent
                                                                            visible: modelData.type === "image"
                                                                            source: "file://" + modelData.path
                                                                            fillMode: Image.PreserveAspectCrop
                                                                            clip: true
                                                                        }

                                                                        Kirigami.Icon {
                                                                            anchors.fill: parent
                                                                            visible: modelData.type !== "image"
                                                                            source: rootRef.fileIconName(modelData.name)
                                                                        }

                                                                    }

                                                                    PC3.Label {
                                                                        id: msgFilenameLabel

                                                                        Layout.fillWidth: true
                                                                        text: modelData.name
                                                                        elide: Text.ElideRight
                                                                        font.pointSize: 8
                                                                        color: Kirigami.Theme.textColor
                                                                    }

                                                                }

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    QQC2.ToolTip.visible: hovered
                                                                    QQC2.ToolTip.text: "Open: " + modelData.path
                                                                    onClicked: Qt.openUrlExternally("file://" + modelData.path)
                                                                }

                                                            }

                                                        }

                                                    }

                                                    Row {
                                                        visible: modelData.role === "permission_request"
                                                        width: parent.width
                                                        spacing: Kirigami.Units.largeSpacing
                                                        Layout.topMargin: Kirigami.Units.smallSpacing

                                                        PC3.Button {
                                                            visible: modelData.status === "pending"
                                                            text: "Allow"
                                                            icon.name: "dialog-ok-apply"
                                                            onClicked: rootRef.respondToPermission(modelData.permissionId, true)
                                                        }

                                                        PC3.Button {
                                                            visible: modelData.status === "pending"
                                                            text: "Reject"
                                                            icon.name: "dialog-cancel"
                                                            onClicked: rootRef.respondToPermission(modelData.permissionId, false)
                                                        }

                                                        PC3.Label {
                                                            visible: modelData.status !== "pending"
                                                            text: modelData.status === "allowed" ? "Approved ✅" : modelData.status === "denied" ? "Rejected ❌" : modelData.status === "allowing..." ? "Approving..." : "Rejecting..."
                                                            font.bold: true
                                                            color: modelData.status === "allowed" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                                                        }

                                                    }

                                                    Column {
                                                        id: questionCol

                                                        property string qId: modelData.questionId || ""
                                                        property var qQuestions: modelData.questions || []
                                                        property bool qAllowCustom: modelData.allowCustom !== false
                                                        property string qStatus: modelData.status || ""

                                                        visible: modelData.role === "question_request"
                                                        width: parent.width
                                                        spacing: Kirigami.Units.smallSpacing

                                                        // Per-question sections when structured options are available
                                                        Repeater {
                                                            model: (questionCol.qStatus === "pending" && questionCol.qQuestions.length > 0) ? questionCol.qQuestions : []

                                                            delegate: Column {
                                                                id: questionItemCol

                                                                required property var modelData
                                                                required property int index
                                                                property bool qMultiple: modelData.multiple || false

                                                                width: parent.width
                                                                spacing: Kirigami.Units.smallSpacing

                                                                // Question header chip
                                                                Rectangle {
                                                                    visible: (modelData.header || "") !== ""
                                                                    width: qHeaderLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                                                                    height: qHeaderLabel.implicitHeight + Kirigami.Units.smallSpacing
                                                                    radius: 999
                                                                    color: Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.18)

                                                                    PC3.Label {
                                                                        id: qHeaderLabel

                                                                        anchors.centerIn: parent
                                                                        text: modelData.header || ""
                                                                        font.bold: true
                                                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                                                        color: Kirigami.Theme.focusColor
                                                                    }

                                                                }

                                                                // Clickable option buttons
                                                                Flow {
                                                                    width: parent.width
                                                                    spacing: Kirigami.Units.smallSpacing
                                                                    visible: modelData.options && modelData.options.length > 0

                                                                    Repeater {
                                                                        model: modelData.options || []

                                                                        delegate: Rectangle {
                                                                            id: optionBtn

                                                                            required property var modelData
                                                                            required property int index
                                                                            property bool selected: false

                                                                            width: optBtnLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                                                                            height: optBtnLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                                                                            radius: 6
                                                                            color: selected ? Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.3) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                                                            border.width: selected ? 2 : 1
                                                                            border.color: selected ? Kirigami.Theme.focusColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                                                                            QQC2.ToolTip.visible: optionMa.containsMouse && (optionBtn.modelData.description || "") !== ""
                                                                            QQC2.ToolTip.text: optionBtn.modelData.description || ""

                                                                            PC3.Label {
                                                                                id: optBtnLabel

                                                                                anchors.centerIn: parent
                                                                                text: (optionBtn.selected ? "✓ " : "") + (optionBtn.modelData.label || "")
                                                                                font.bold: optionBtn.selected
                                                                                color: optionBtn.selected ? Kirigami.Theme.focusColor : Kirigami.Theme.textColor
                                                                            }

                                                                            MouseArea {
                                                                                id: optionMa

                                                                                anchors.fill: parent
                                                                                hoverEnabled: true
                                                                                cursorShape: Qt.PointingHandCursor
                                                                                onClicked: {
                                                                                    optionBtn.selected = !optionBtn.selected;
                                                                                    // For non-multiple questions, submit immediately on click
                                                                                    if (!questionItemCol.qMultiple && optionBtn.selected)
                                                                                        rootRef.respondToQuestion(questionCol.qId, optionBtn.modelData.label || "", false);

                                                                                }
                                                                            }

                                                                        }

                                                                    }

                                                                }

                                                                // Separator between questions
                                                                Rectangle {
                                                                    visible: index < (parent.model ? parent.model.length - 1 : 0)
                                                                    width: parent.width
                                                                    height: 1
                                                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                                                                }

                                                            }

                                                        }

                                                        // Custom answer text field (shown when custom is allowed or no options exist)
                                                        PC3.Label {
                                                            text: (questionCol.qQuestions.length > 0) ? "Or type a custom answer:" : "Your Answer:"
                                                            font.bold: true
                                                            visible: questionCol.qStatus === "pending" && questionCol.qAllowCustom
                                                        }

                                                        PC3.TextField {
                                                            id: questionReplyField

                                                            visible: questionCol.qStatus === "pending" && questionCol.qAllowCustom
                                                            width: parent.width
                                                            placeholderText: rootRef.translate("Type your answer here...")
                                                            onAccepted: {
                                                                if (text.trim() !== "")
                                                                    rootRef.respondToQuestion(questionCol.qId, text, false);

                                                            }
                                                        }

                                                        Row {
                                                            width: parent.width
                                                            spacing: Kirigami.Units.largeSpacing

                                                            PC3.Button {
                                                                visible: questionCol.qStatus === "pending"
                                                                text: "Submit"
                                                                icon.name: "mail-send"
                                                                onClicked: rootRef.submitQuestionAnswer(questionCol.qId, questionCol.qQuestions, questionReplyField)
                                                            }

                                                            PC3.Button {
                                                                visible: questionCol.qStatus === "pending"
                                                                text: "Dismiss"
                                                                icon.name: "dialog-cancel"
                                                                onClicked: rootRef.respondToQuestion(questionCol.qId, "", true)
                                                            }

                                                            PC3.Label {
                                                                visible: questionCol.qStatus !== "pending"
                                                                text: questionCol.qStatus === "answered" ? "Answered: \"" + (modelData.submittedAnswer || "") + "\" ✅" : questionCol.qStatus === "dismissed" ? "Dismissed ❌" : questionCol.qStatus === "answering..." ? "Submitting..." : "Dismissing..."
                                                                font.bold: true
                                                                color: questionCol.qStatus === "answered" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                                                            }

                                                        }

                                                    }

                                                    ColumnLayout {
                                                        visible: modelData.role === "schedules_list"
                                                        width: parent.width
                                                        spacing: Kirigami.Units.largeSpacing

                                                        PC3.Label {
                                                            text: "📅 Active Schedules in this Chat"
                                                            font.bold: true
                                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                                                            color: Kirigami.Theme.highlightColor
                                                        }

                                                        Column {
                                                            width: parent.width
                                                            spacing: Kirigami.Units.smallSpacing

                                                            // Repeater over schedules belonging to rootRef.currentSessionId
                                                            Repeater {
                                                                model: rootRef.getSchedulesForSession(rootRef.currentSessionId)

                                                                delegate: Rectangle {
                                                                    width: parent.width
                                                                    implicitHeight: rowCol.implicitHeight + Kirigami.Units.largeSpacing
                                                                    color: (modelData.enabled !== false) ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.02)
                                                                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                                                                    radius: 6
                                                                    opacity: (modelData.enabled !== false) ? 1 : 0.6

                                                                    ColumnLayout {
                                                                        id: rowCol

                                                                        anchors.fill: parent
                                                                        anchors.margins: Kirigami.Units.largeSpacing
                                                                        spacing: Kirigami.Units.smallSpacing

                                                                        RowLayout {
                                                                            Layout.fillWidth: true
                                                                            spacing: Kirigami.Units.smallSpacing

                                                                            Kirigami.Icon {
                                                                                source: "appointment-new"
                                                                                implicitWidth: Kirigami.Units.iconSizes.small
                                                                                implicitHeight: Kirigami.Units.iconSizes.small
                                                                            }

                                                                            PC3.Label {
                                                                                text: (modelData.label ? modelData.label : "Untitled Schedule") + ((modelData.enabled !== false) ? "" : " (Paused)")
                                                                                font.bold: true
                                                                                Layout.fillWidth: true
                                                                                elide: Text.ElideRight
                                                                            }

                                                                            PC3.Button {
                                                                                icon.name: (modelData.enabled !== false) ? "media-playback-pause" : "media-playback-start"
                                                                                text: (modelData.enabled !== false) ? "Pause" : "Resume"
                                                                                QQC2.ToolTip.text: (modelData.enabled !== false) ? "Pause this schedule" : "Resume this schedule"
                                                                                QQC2.ToolTip.visible: hovered
                                                                                onClicked: {
                                                                                    rootRef.toggleScheduleEnabled(modelData.id, !(modelData.enabled !== false));
                                                                                }
                                                                            }

                                                                            PC3.Button {
                                                                                icon.name: "edit-delete"
                                                                                text: "Delete"
                                                                                QQC2.ToolTip.text: "Delete this schedule"
                                                                                QQC2.ToolTip.visible: hovered
                                                                                onClicked: {
                                                                                    var schedId = modelData.id;
                                                                                    var py = "import json, os; p=os.path.expanduser('~/.local/share/kdeaichat/schedules.json'); " + "data=json.load(open(p)) if os.path.exists(p) else {'version':1,'schedules':[]}; " + "if isinstance(data, list): data={'version':1,'schedules':data}; " + "data['schedules'] = [s for s in data.get('schedules', []) if s.get('id') != '" + schedId + "']; " + "json.dump(data, open(p,'w'), indent=2)";
                                                                                    schedulerDs.connectSource("sh -lc 'python3 -c \"" + py + "\" && pkill -HUP -f kde-ai-scheduler.py' #sched-delete-" + Date.now());
                                                                                    // Remove immediately from UI to be responsive!
                                                                                    var copy = rootRef.schedulesList.slice();
                                                                                    rootRef.schedulesList = copy.filter(function(s) {
                                                                                        return s.id !== schedId;
                                                                                    });
                                                                                    rootRef.appendSystemMessage("🗑️ Schedule deleted successfully.");
                                                                                }
                                                                            }

                                                                        }

                                                                        PC3.Label {
                                                                            text: "Message: " + modelData.message
                                                                            wrapMode: Text.Wrap
                                                                            Layout.fillWidth: true
                                                                            opacity: 0.85
                                                                            font.italic: true
                                                                        }

                                                                        PC3.Label {
                                                                            text: "⏰ " + modelData.humanText
                                                                            color: Kirigami.Theme.highlightColor
                                                                            font.bold: true
                                                                        }

                                                                    }

                                                                }

                                                            }

                                                            PC3.Label {
                                                                visible: rootRef.getSchedulesForSession(rootRef.currentSessionId).length === 0
                                                                text: "No active schedules for this chat."
                                                                font.italic: true
                                                                opacity: 0.7
                                                            }

                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: Kirigami.Units.largeSpacing

                                                            PC3.Button {
                                                                text: "Create Schedule"
                                                                icon.name: "appointment-new"
                                                                highlighted: true
                                                                onClicked: {
                                                                     plasmoid.configuration.preselectedChatId = rootRef.currentSessionId;
                                                                     plasmoid.configuration.preselectedChatName = rootRef.currentSessionTitle || "Current Chat";
                                                                     rootRef.triggerConfigure();
                                                                 }
                                                            }

                                                        }

                                                    }

                                                    Rectangle {
                                                        visible: rootRef.editingMessageIndex === index && modelData.role !== "error"
                                                        width: parent.width
                                                        height: editWarn.implicitHeight + Kirigami.Units.smallSpacing * 2
                                                        radius: 6
                                                        color: Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.1)

                                                        PC3.Label {
                                                            id: editWarn

                                                            anchors.fill: parent
                                                            anchors.margins: Kirigami.Units.smallSpacing
                                                            wrapMode: Text.Wrap
                                                            text: "Saving this edit will remove all messages below this one and make this the latest message."
                                                        }

                                                    }

                                                    PC3.Label {
                                                        visible: modelData.role === "assistant" && modelData.tokens !== undefined
                                                        width: parent.width
                                                        horizontalAlignment: Text.AlignRight
                                                        text: rootRef.formatTokensUsage(modelData.tokens, modelData.cost)
                                                        font.pointSize: 8
                                                        opacity: 0.55
                                                        elide: Text.ElideRight
                                                    }

                                                    // Context items (tool invocations) display
                                                    Column {
                                                        visible: modelData.role === "assistant" && modelData.contextItems !== undefined && modelData.contextItems.length > 0
                                                        width: parent.width
                                                        spacing: 2

                                                        Row {
                                                            spacing: Kirigami.Units.smallSpacing

                                                            PC3.Label {
                                                                text: "📂 Context (" + (modelData.contextItems ? modelData.contextItems.length : 0) + ")"
                                                                font.pointSize: 7
                                                                font.bold: true
                                                                opacity: 0.6
                                                            }

                                                            PC3.Label {
                                                                id: contextToggle

                                                                property bool expanded: false

                                                                text: expanded ? "▲ hide" : "▼ show"
                                                                font.pointSize: 7
                                                                opacity: 0.5

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: contextToggle.expanded = !contextToggle.expanded
                                                                }

                                                            }

                                                        }

                                                        Flow {
                                                            visible: contextToggle.expanded
                                                            width: parent.width
                                                            spacing: 3

                                                            Repeater {
                                                                model: modelData.contextItems || []

                                                                delegate: Rectangle {
                                                                    required property string modelData

                                                                    width: ctxLabel.implicitWidth + 10
                                                                    height: ctxLabel.implicitHeight + 4
                                                                    radius: 999
                                                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)

                                                                    PC3.Label {
                                                                        id: ctxLabel

                                                                        anchors.centerIn: parent
                                                                        text: modelData
                                                                        font.pointSize: 7
                                                                        opacity: 0.6
                                                                        elide: Text.ElideMiddle
                                                                        maximumLineCount: 1
                                                                    }

                                                                }

                                                            }

                                                        }

                                                    }

                                                    Row {
                                                        width: parent.width
                                                        spacing: Kirigami.Units.smallSpacing

                                                        PC3.ToolButton {
                                                            visible: rootRef.editingMessageIndex !== index && modelData.role !== "error" && modelData.role !== "assistant"
                                                            icon.name: "document-edit"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: modelData.role === "queued" ? "Edit queued message" : "Edit message"
                                                            onClicked: {
                                                                rootRef.editingMessageIndex = index;
                                                                rootRef.editingDraft = modelData.content;
                                                            }
                                                        }

                                                        PC3.ToolButton {
                                                            visible: rootRef.editingMessageIndex === index && modelData.role !== "error" && modelData.role !== "assistant"
                                                            icon.name: "dialog-ok-apply"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: "Apply edit"
                                                            onClicked: rootRef.saveEditedMessage()
                                                        }

                                                        PC3.ToolButton {
                                                            visible: rootRef.editingMessageIndex === index && modelData.role !== "error" && modelData.role !== "assistant"
                                                            icon.name: "dialog-cancel"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: "Cancel edit"
                                                            onClicked: {
                                                                rootRef.editingMessageIndex = -1;
                                                                rootRef.editingDraft = "";
                                                            }
                                                        }

                                                        PC3.ToolButton {
                                                            icon.name: "edit-copy"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: "Copy message"
                                                            onClicked: {
                                                                // Use an invisible text input to copy to clipboard in QML
                                                                clipboardHelper.text = modelData.content || "";
                                                                clipboardHelper.selectAll();
                                                                clipboardHelper.copy();
                                                            }
                                                        }

                                                        PC3.ToolButton {
                                                            icon.name: "edit-delete"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: modelData.role === "queued" ? "Delete queued message" : "Delete message"
                                                            onClicked: rootRef.deleteMessage(index)
                                                        }

                                                    }

                                                }

                                            }

                                        }

                                        Rectangle {
                                            width: parent.width
                                            implicitHeight: 1
                                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.14)
                                        }

                                    }

                                }
