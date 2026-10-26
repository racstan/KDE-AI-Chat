// The "Describe when" box above the rules: a sentence, a button, and the
// model's clarifying question with its options and a free answer. The rules
// it produces replace the editor's rules for review (see ScheduleDescriber).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: box

    required property ScheduleDescriber describer
    // Shown after rules were filled in, until the sentence changes.
    property string filledText: ""

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        QQC2.TextField {
            id: sentence
            objectName: "describeField"
            Layout.fillWidth: true
            enabled: box.describer.available && box.describer.phase !== "busy"
            placeholderText: i18n("Describe when (e.g. weekdays at 9 and Sunday at noon)")
            onAccepted: box.describer.start(text)
            onTextEdited: box.filledText = ""
        }
        QQC2.Button {
            objectName: "describeButton"
            text: i18n("Fill in")
            icon.name: "tools-wizard"
            enabled: box.describer.available && box.describer.phase !== "busy" && sentence.text.trim() !== ""
            onClicked: box.describer.start(sentence.text)
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Ask %1 to turn the sentence into rules. You can check them before saving.", box.describer.providerName)
        }
    }

    QQC2.Label {
        objectName: "describeHint"
        Layout.fillWidth: true
        visible: !box.describer.available
        wrapMode: Text.Wrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("To describe it in words, choose a provider with a model in Settings → Connection. OpenCode and Pi are not used for this.")
    }

    RowLayout {
        visible: box.describer.phase === "busy"
        QQC2.BusyIndicator {
            running: visible
            implicitWidth: Kirigami.Units.iconSizes.medium
            implicitHeight: implicitWidth
        }
        QQC2.Label { text: i18n("Asking %1…", box.describer.providerName) }
        QQC2.ToolButton {
            text: i18n("Cancel")
            onClicked: box.describer.cancel()
        }
    }

    // The model's question: an option button each, or a free answer.
    QQC2.Frame {
        objectName: "describeQuestion"
        visible: box.describer.phase === "question"
        Layout.fillWidth: true
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                objectName: "describeQuestionText"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.bold: true
                text: box.describer.question
            }
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: box.describer.options
                    delegate: QQC2.Button {
                        required property string modelData
                        objectName: "describeOption"
                        text: modelData
                        onClicked: box.describer.answer(modelData)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                QQC2.TextField {
                    id: freeAnswer
                    objectName: "describeAnswer"
                    Layout.fillWidth: true
                    placeholderText: i18n("Or type your answer")
                    onAccepted: {
                        box.describer.answer(text);
                        text = "";
                    }
                }
                QQC2.Button {
                    text: i18n("Answer")
                    enabled: freeAnswer.text.trim() !== ""
                    onClicked: {
                        box.describer.answer(freeAnswer.text);
                        freeAnswer.text = "";
                    }
                }
                QQC2.ToolButton {
                    icon.name: "dialog-cancel"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Cancel")
                    onClicked: box.describer.cancel()
                }
            }
        }
    }

    QQC2.Label {
        objectName: "describeError"
        Layout.fillWidth: true
        visible: box.describer.phase === "error"
        wrapMode: Text.Wrap
        color: Kirigami.Theme.negativeTextColor
        text: box.describer.error
    }

    QQC2.Label {
        objectName: "describeFilled"
        Layout.fillWidth: true
        visible: box.filledText !== "" && box.describer.phase === "idle"
        wrapMode: Text.Wrap
        color: Kirigami.Theme.positiveTextColor
        text: i18n("Filled in: %1. Check the rules and the next runs below, then save.", box.filledText)
    }
}
