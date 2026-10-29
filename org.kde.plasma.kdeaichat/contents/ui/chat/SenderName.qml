// Who a message is from, in its header (chat/MessageDelegate.qml): your name
// or "You" with your avatar, the AI's name with its avatar and the model in small type, or the
// model alone when the AI has no name (Settings → Personality,
// chat/Personality.js). Errors and agent requests have their own headings.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "Personality.js" as Personality
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

RowLayout {
    id: sender

    property var chat: null
    property string role: ""
    property string model: ""
    // A message a schedule sent: its name, shown small after yours.
    property string scheduleName: ""
    // The longest the name may get.
    property real maximumWidth: 200

    readonly property var cfg: chat && chat.plasmoid ? chat.plasmoid.configuration : ({})
    readonly property bool mine: role === "user" || role === "queued"
    readonly property string userName: mine ? Personality.userLabel(cfg) : ""
    readonly property string aiName: role === "assistant" ? Personality.aiLabel(cfg) : ""
    readonly property var avatar: mine ? Personality.userAvatar(cfg) : role === "assistant" ? Personality.avatar(cfg) : ({"kind": "", "source": ""})

    spacing: Kirigami.Units.smallSpacing
    layoutDirection: mine ? Qt.RightToLeft : Qt.LeftToRight

    AvatarView {
        id: avatarIcon
        objectName: "senderAvatar"
        visible: sender.avatar.kind !== "" && valid
        kind: sender.avatar.kind
        source: sender.avatar.source
        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
    }

    PC3.Label {
        id: nameLabel
        objectName: "senderName"
        textFormat: Text.PlainText
        text: sender.role === "user" ? (sender.userName || i18n("You"))
            : sender.role === "queued" ? (sender.userName ? i18n("%1 · queued", sender.userName) : i18n("You · queued"))
            : sender.role === "error" ? i18n("Something went wrong")
            : sender.role === "question_request" ? i18n("Question")
            : sender.role === "permission_request" ? i18n("Permission request")
            : (sender.aiName || sender.model || i18n("Assistant"))
        font.bold: true
        elide: Text.ElideRight
        Layout.alignment: Qt.AlignBaseline
        Layout.maximumWidth: sender.maximumWidth - (avatarIcon.visible ? avatarIcon.width + sender.spacing : 0)
                             - (modelLabel.visible ? Math.min(modelLabel.implicitWidth, sender.maximumWidth / 2) + sender.spacing : 0)
    }

    PC3.Label {
        objectName: "senderScheduled"
        textFormat: Text.PlainText
        visible: sender.mine && sender.scheduleName !== ""
        text: i18n("Scheduled: %1", sender.scheduleName)
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        elide: Text.ElideRight
        Layout.alignment: Qt.AlignBaseline
        Layout.maximumWidth: sender.maximumWidth / 2
    }

    // The model, kept small next to the AI's own name.
    PC3.Label {
        id: modelLabel
        objectName: "senderModel"
        visible: sender.aiName !== "" && sender.model !== ""
        text: sender.model
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        elide: Text.ElideRight
        Layout.alignment: Qt.AlignBaseline
        Layout.maximumWidth: sender.maximumWidth / 2
    }
}
