// Memory in the Chat info panel (ChatSettingsDialog.qml): whether this chat
// uses memories (its session property memoryOff, inverted) and which ones
// went with its latest request (memoryUsedIds, kept by chat/Memory.qml),
// resolved through chat.memoryStore.
//
// The switch takes effect at once, like the model picker in the panel: it is
// not part of the panel's draft, so Apply and Reset leave it alone.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: info

    property var chat: null
    property string sessionId: ""

    readonly property var store: chat ? chat.memoryStore || null : null
    readonly property bool globalOn: !!store && store.enabled
    readonly property var session: {
        var list = chat ? chat.sessions || [] : [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].value === sessionId)
                return list[i];
        }
        return null;
    }
    // An incognito chat (chat/Incognito.qml) never uses memories.
    readonly property bool incognito: !!session && session.incognito === true
    readonly property bool chatOn: !!session && session.memoryOff !== true && !incognito
    // The memories of the latest request that are still saved.
    readonly property var used: {
        var ids = session && Array.isArray(session.memoryUsedIds) ? session.memoryUsedIds : [];
        var all = store ? store.list : [];
        return all.filter(function(m) { return ids.indexOf(m.id) >= 0; });
    }

    function preview(text) {
        var t = String(text || "").replace(/\s+/g, " ").trim();
        return t.length > 140 ? t.substring(0, 140).trim() + "…" : t;
    }

    spacing: Kirigami.Units.smallSpacing
    visible: !!store

    Kirigami.Heading {
        level: 4
        font.bold: true
        text: i18n("Memory")
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
    }

    PC3.Switch {
        objectName: "chatMemorySwitch"
        Layout.fillWidth: true
        text: i18n("Use memories in this chat")
        enabled: !!info.session && !info.incognito
        checked: info.chatOn
        onToggled: info.chat.setSessionProperty(info.sessionId, "memoryOff", !checked)
    }

    PC3.Label {
        objectName: "memoryIncognitoNote"
        visible: info.incognito
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        text: i18n("An incognito chat uses no memories and adds none.")
    }

    PC3.Label {
        objectName: "memoryGlobalOffNote"
        visible: !info.globalOn
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.neutralTextColor
        text: i18n("Memory is turned off for every chat in Settings → Memory.")
    }

    PC3.Label {
        objectName: "memoryUsedTitle"
        visible: info.globalOn && info.chatOn
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        text: info.used.length > 0
            ? i18np("The latest message was sent with 1 memory:", "The latest message was sent with %1 memories:", info.used.length)
            : i18n("The latest message was sent with no memories.")
    }

    Repeater {
        model: info.globalOn && info.chatOn ? info.used : []

        delegate: RowLayout {
            id: usedRow
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignTop
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                source: usedRow.modelData.pinned ? "pin" : "bookmark-new"
            }
            PC3.Label {
                textFormat: Text.PlainText
                objectName: "usedMemory"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: info.preview(usedRow.modelData.text)
                QQC2.ToolTip.visible: usedHover.hovered && truncated
                QQC2.ToolTip.text: usedRow.modelData.text
                HoverHandler {
                    id: usedHover
                }
            }
        }
    }
}
