// An agent's question (a question_request message): option buttons per
// question, an optional typed answer, Submit / Dismiss, then the outcome.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

ColumnLayout {
    id: card

    property var chat: null
    property var message: ({})

    readonly property string questionId: message.questionId || ""
    readonly property var questions: message.questions || []
    readonly property string status: message.status || ""
    readonly property bool pending: status === "pending"

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: card.pending ? card.questions : []

        delegate: ColumnLayout {
            id: question

            required property var modelData
            required property int index

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                visible: (question.modelData.header || "") !== ""
                text: question.modelData.header || ""
                font.bold: true
            }

            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: (question.modelData.options || []).length > 0

                Repeater {
                    model: question.modelData.options || []

                    delegate: PC3.Button {
                        required property var modelData
                        readonly property string label: modelData.label || ""

                        checkable: true
                        checked: card.chat.questionOptionSelected(card.questionId, question.index, label)
                        text: label
                        QQC2.ToolTip.visible: hovered && (modelData.description || "") !== ""
                        QQC2.ToolTip.text: modelData.description || ""
                        onClicked: {
                            var multiple = question.modelData.multiple === true;
                            card.chat.toggleQuestionOption(card.questionId, question.index, label, multiple);
                            // A single-choice question is answered by picking an option.
                            if (!multiple && card.questions.length === 1)
                                card.chat.respondToQuestion(card.questionId, label, false);
                        }
                    }
                }
            }
        }
    }

    PC3.TextField {
        id: customAnswer
        visible: card.pending && card.message.allowCustom !== false
        Layout.fillWidth: true
        placeholderText: card.questions.length > 0 ? i18n("Or type your own answer…") : i18n("Type your answer…")
        onAccepted: if (text.trim() !== "") card.chat.respondToQuestion(card.questionId, text, false)
    }

    RowLayout {
        visible: card.pending
        spacing: Kirigami.Units.smallSpacing

        PC3.Button {
            text: i18n("Submit")
            icon.name: "mail-send"
            onClicked: card.chat.submitQuestionAnswer(card.questionId, card.questions, customAnswer)
        }

        PC3.Button {
            text: i18n("Dismiss")
            icon.name: "dialog-cancel"
            onClicked: card.chat.respondToQuestion(card.questionId, "", true)
        }
    }

    PC3.Label {
        visible: !card.pending
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: card.status === "answered" ? i18n("Answered: %1", String(card.message.submittedAnswer || ""))
            : card.status === "dismissed" ? i18n("Dismissed") : i18n("Sending answer…")
        color: card.status === "answered" ? Kirigami.Theme.positiveTextColor
             : card.status === "dismissed" ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor
    }
}
