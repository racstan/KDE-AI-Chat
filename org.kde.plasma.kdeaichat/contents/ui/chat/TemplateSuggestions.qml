// The list of slash commands and prompt templates that pops up above the
// composer's input when the text starts with "/" (Commands.js builds the
// entries). The input keeps the focus; it calls handleKey() for the arrow
// keys, Tab (chosen: put the entry in the box), Enter (activated: run it or
// complete it, CommandRunner.qml) and Esc.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.Popup {
    id: popup

    // [{kind, name, usage, description, insert}], best match first.
    property var entries: []
    property int current: 0
    // Set by Esc; cleared when the text changes.
    property bool dismissed: false

    signal chosen(var entry)
    signal activated(var entry)

    readonly property var currentEntry: entries.length > 0 ? entries[Math.min(current, entries.length - 1)] : null

    readonly property string noticeTitle: i18n("Every chat uses the main model")

    // Command descriptions go through i18n() here (Commands.js is plain JS).
    function describe(entry) {
        if (entry.kind === "notice")
            return i18n("Turn on “Let chats have their own model settings” in Settings → Chat. Enter opens the settings.");
        if (entry.kind !== "command")
            return entry.description;
        return entry.name === "model" ? i18n("Change this chat's model")
            : entry.name === "variant" ? i18n("Change this chat's variant (reasoning level)")
            : entry.name === "new" ? i18n("Start a new chat")
            : entry.name === "image" ? i18n("Make a picture with the default image service")
            : entry.name === "remember" ? i18n("Save a memory for every chat")
            : entry.name === "mode" ? i18n("Mode for NEW chats only; this chat keeps its mode") : entry.description;
    }

    function next() { current = Math.min(current + 1, entries.length - 1); }
    function previous() { current = Math.max(current - 1, 0); }

    // Arrow keys move, Tab picks, Enter activates, Esc hides (until the text changes).
    function handleKey(key) {
        if (key === Qt.Key_Down)
            next();
        else if (key === Qt.Key_Up)
            previous();
        else if (key === Qt.Key_Tab)
            chosen(currentEntry);
        else if (key === Qt.Key_Return || key === Qt.Key_Enter)
            activated(currentEntry);
        else if (key === Qt.Key_Escape)
            dismissed = true;
        else
            return false;
        return true;
    }

    onEntriesChanged: current = 0

    // Whether the list is wanted (`visible` lags behind while it fades out).
    readonly property bool active: entries.length > 0 && !dismissed

    visible: active
    closePolicy: QQC2.Popup.NoAutoClose
    focus: false
    y: -height - Kirigami.Units.smallSpacing
    padding: Kirigami.Units.smallSpacing
    implicitWidth: parent ? parent.width : Kirigami.Units.gridUnit * 20
    implicitHeight: Math.min(list.contentHeight, Kirigami.Units.gridUnit * 10) + padding * 2

    contentItem: ListView {
        id: list
        objectName: "templateList"
        clip: true
        model: popup.entries
        currentIndex: popup.current
        boundsBehavior: Flickable.StopAtBounds
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: QQC2.ItemDelegate {
            id: item

            required property var modelData
            required property int index

            width: ListView.view.width
            highlighted: index === popup.current
            Accessible.name: modelData.kind === "command" ? i18n("Command %1", modelData.name) : modelData.kind === "template" ? i18n("Template %1", modelData.name)
                : modelData.kind === "notice" ? popup.noticeTitle + ": " + popup.describe(modelData) : modelData.name
            onClicked: { popup.current = index; popup.chosen(modelData); }

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                PC3.Label {
                    text: item.modelData.kind === "option" ? item.modelData.name : item.modelData.kind === "notice" ? popup.noticeTitle : "/" + item.modelData.name
                    font.bold: true
                }

                PC3.Label {
                    visible: text !== ""
                    text: item.modelData.usage
                    opacity: 0.7
                }

                PC3.Label {
                    Layout.fillWidth: true
                    text: popup.describe(item.modelData)
                    // The notice is advice to read whole; the rest is a hint.
                    elide: item.modelData.kind === "notice" ? Text.ElideNone : Text.ElideRight
                    wrapMode: item.modelData.kind === "notice" ? Text.Wrap : Text.NoWrap
                    opacity: 0.7
                }
            }
        }
    }
}
