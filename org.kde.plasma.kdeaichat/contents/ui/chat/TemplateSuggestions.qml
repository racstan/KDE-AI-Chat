// The list of prompt templates that pops up above the composer's input when
// the text starts with "/". The input keeps the focus; it calls next(),
// previous() and accept() for the arrow keys and Enter/Tab.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.Popup {
    id: popup

    // [{name, prompt}], best match first.
    property var templates: []
    property int current: 0
    // Set by Esc; cleared when the text changes.
    property bool dismissed: false

    signal chosen(var template)

    function next() { current = Math.min(current + 1, templates.length - 1); }
    function previous() { current = Math.max(current - 1, 0); }
    function accept() { if (templates.length > 0) chosen(templates[Math.min(current, templates.length - 1)]); }

    onTemplatesChanged: current = 0

    // Whether the list is wanted (`visible` lags behind while it fades out).
    readonly property bool active: templates.length > 0 && !dismissed

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
        model: popup.templates
        currentIndex: popup.current
        boundsBehavior: Flickable.StopAtBounds
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: QQC2.ItemDelegate {
            id: item

            required property var modelData
            required property int index

            width: ListView.view.width
            highlighted: index === popup.current
            Accessible.name: i18n("Template %1", modelData.name)
            onClicked: popup.chosen(modelData)

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                PC3.Label {
                    text: "/" + item.modelData.name
                    font.bold: true
                }

                PC3.Label {
                    Layout.fillWidth: true
                    text: item.modelData.prompt.replace(/\s+/g, " ")
                    elide: Text.ElideRight
                    opacity: 0.7
                }
            }
        }
    }
}
