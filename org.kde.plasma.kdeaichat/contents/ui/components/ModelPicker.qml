// A model chooser for long lists (hundreds of models): an editable field
// showing the current model id, and a drop-down with a filter box. Typing
// "free" in the filter lists every model whose id or name contains it
// (anywhere, any case; several words must all match), with a count such as
// "12 of 340", Up/Down/PageUp/PageDown to move, Enter to choose, Esc to close.
// The current model keeps its check mark whatever the filter shows.
//
// API:
//   model            list of ids (strings) or {id, name} objects
//   value            the current model id (bind it; the picker never writes it)
//   picked(value)    emitted when the user chooses a model, or types an id
//                    into the field when allowCustom is true
//   allowCustom      true (default): any id can be typed, and Enter with no
//                    match uses the filter text; false: list choices only
//   placeholderText  hint in the empty field
//   filterText       the filter box's text (read/write)
//   matchCount, totalCount, countText   what the list shows, e.g. "12 of 340"
//   highlightedIndex index in the filtered list that Enter would choose
//   open() / close() / pick(id) / popupOpen
//
// It needs only QtQuick, Controls and Kirigami, so chat/ can use it too.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "ModelFilter.js" as ModelFilter

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Item {
    id: picker

    property var model: []
    property string value: ""
    property bool allowCustom: true
    property string placeholderText: ""
    property string filterText: ""

    readonly property var entries: ModelFilter.normalize(model)
    readonly property var matches: ModelFilter.filter(entries, filterText)
    readonly property int totalCount: entries.length
    readonly property int matchCount: matches.length
    readonly property string countText: i18n("%1 of %2", matchCount, totalCount)
    readonly property bool popupOpen: popup.opened
    readonly property int highlightedIndex: list.currentIndex

    signal picked(string value)

    implicitWidth: field.implicitWidth
    implicitHeight: field.implicitHeight

    function open() {
        filterText = "";
        popup.open();
    }

    function close() {
        popup.close();
    }

    function pick(id) {
        picked(id);
        popup.close();
        field.forceActiveFocus();
    }

    // Moves the highlight; used by the filter box's arrow keys.
    function moveHighlight(delta) {
        if (matches.length === 0)
            return;
        list.currentIndex = Math.max(0, Math.min(matches.length - 1, list.currentIndex + delta));
    }

    // Chooses the highlighted model, or the typed text when nothing matches.
    function acceptHighlighted() {
        if (list.currentIndex >= 0 && list.currentIndex < matches.length)
            pick(matches[list.currentIndex].id);
        else if (allowCustom && filterText.trim() !== "")
            pick(filterText.trim());
    }

    // With nothing typed the highlight starts on the current model; with a
    // filter it starts on the first match, so Enter takes the best hit.
    function resetHighlight() {
        var at = filterText === "" ? ModelFilter.indexOfId(matches, value) : -1;
        list.currentIndex = at >= 0 ? at : (matches.length > 0 ? 0 : -1);
        if (list.currentIndex >= 0)
            list.positionViewAtIndex(list.currentIndex, ListView.Center);
    }

    onMatchesChanged: resetHighlight()

    QQC2.TextField {
        id: field
        anchors.fill: parent
        text: picker.value
        placeholderText: picker.placeholderText
        readOnly: !picker.allowCustom
        rightPadding: arrow.width + Kirigami.Units.smallSpacing
        selectByMouse: true
        Accessible.name: i18n("Model")
        onTextEdited: picker.picked(text)
        Keys.onDownPressed: picker.open()
        TapHandler {
            enabled: !picker.allowCustom
            onTapped: picker.open()
        }
    }

    QQC2.ToolButton {
        id: arrow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height - 2
        icon.name: "arrow-down"
        focusPolicy: Qt.NoFocus
        onClicked: popup.opened ? popup.close() : picker.open()
        Accessible.name: i18n("Choose a model from the list")
    }

    QQC2.Popup {
        id: popup
        y: picker.height
        width: Math.max(picker.width, Kirigami.Units.gridUnit * 22)
        height: Kirigami.Units.gridUnit * 18
        padding: Kirigami.Units.smallSpacing
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
        onOpened: {
            filterField.forceActiveFocus();
            picker.resetHighlight();
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: filterField
                Layout.fillWidth: true
                text: picker.filterText
                placeholderText: i18n("Filter models, e.g. free")
                selectByMouse: true
                Accessible.name: i18n("Filter models")
                onTextEdited: picker.filterText = text
                Keys.onDownPressed: picker.moveHighlight(1)
                Keys.onUpPressed: picker.moveHighlight(-1)
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_PageDown) {
                        picker.moveHighlight(8);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageUp) {
                        picker.moveHighlight(-8);
                        event.accepted = true;
                    }
                }
                onAccepted: picker.acceptHighlighted()
            }

            QQC2.Label {
                Layout.fillWidth: true
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
                text: picker.matchCount > 0 ? picker.countText
                    : picker.allowCustom && picker.filterText.trim() !== "" ? i18n("No model matches. Press Enter to use “%1”.", picker.filterText.trim())
                    : i18n("No model matches.")
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: picker.matches
                reuseItems: true
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                delegate: QQC2.ItemDelegate {
                    id: entry
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    highlighted: ListView.isCurrentItem
                    rightPadding: Kirigami.Units.gridUnit
                    onClicked: picker.pick(entry.modelData.id)
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            source: "emblem-ok-symbolic"
                            opacity: entry.modelData.id === picker.value ? 1 : 0
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: entry.modelData.id
                            elide: Text.ElideMiddle
                            color: entry.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        }
                        QQC2.Label {
                            visible: entry.modelData.name !== ""
                            Layout.maximumWidth: list.width / 2
                            text: entry.modelData.name
                            elide: Text.ElideRight
                            opacity: 0.7
                            font: Kirigami.Theme.smallFont
                            color: entry.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        }
                    }
                }
            }
        }
    }
}
