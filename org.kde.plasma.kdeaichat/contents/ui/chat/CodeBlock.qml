// A fenced code block in a message: language label, copy button, and the
// code in a monospace box that scrolls instead of wrapping.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Rectangle {
    id: codeBlock
    objectName: "codeBlock"

    property var chat: null
    property string language: ""
    property string code: ""
    // The copy button is built by `builder` after the first frame (see
    // MessageActions.qml); buttonHeight keeps room for it.
    property var builder: null
    property real buttonHeight: 0
    property bool buttonBuilt: !builder

    function buildStep() {
        buttonBuilt = true;
        return false;
    }
    Component.onCompleted: if (builder) builder.add(codeBlock)
    Component.onDestruction: if (builder) builder.remove(codeBlock)

    signal selectionMade(string text)

    // The code colours from Settings → Appearance (chat/Prefs.js codeThemes),
    // or null: the Plasma colours.
    readonly property var theme: chat && chat.prefs ? chat.prefs.codeTheme : null

    implicitHeight: column.implicitHeight
    radius: Kirigami.Units.cornerRadius
    color: theme ? theme.background : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)
    border.width: 1
    border.color: theme ? theme.border : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing

            PC3.Label {
                Layout.fillWidth: true
                text: codeBlock.language && codeBlock.language !== "code" ? codeBlock.language : i18n("Code")
                font: Kirigami.Theme.smallFont
                color: codeBlock.theme ? codeBlock.theme.label : Kirigami.Theme.textColor
                opacity: codeBlock.theme ? 1 : 0.7
            }

            Loader {
                active: codeBlock.buttonBuilt
                Layout.minimumHeight: codeBlock.buttonHeight
                sourceComponent: PC3.ToolButton {
                    icon.name: copied.running ? "checkmark" : "edit-copy"
                    display: PC3.AbstractButton.IconOnly
                    icon.color: codeBlock.theme ? codeBlock.theme.text : "transparent"
                    text: copied.running ? i18n("Copied") : i18n("Copy code")
                    Accessible.name: text
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text
                    onClicked: {
                        codeBlock.chat.copyTextToClipboard(codeBlock.code);
                        copied.restart();
                    }
                }
            }

            Timer {
                id: copied
                interval: 1500
            }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(codeText.implicitHeight, Kirigami.Units.gridUnit * 18)
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AsNeeded

            TextEdit {
                id: codeText
                text: codeBlock.code
                textFormat: Text.PlainText
                font: codeBlock.chat && codeBlock.chat.prefs ? codeBlock.chat.prefs.scaledFont(Kirigami.Theme.fixedWidthFont) : Kirigami.Theme.fixedWidthFont
                color: codeBlock.theme ? codeBlock.theme.text : Kirigami.Theme.textColor
                selectionColor: Kirigami.Theme.highlightColor
                selectedTextColor: Kirigami.Theme.highlightedTextColor
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                wrapMode: Text.NoWrap
                onSelectedTextChanged: codeBlock.selectionMade(selectedText)
            }
        }
    }
}
