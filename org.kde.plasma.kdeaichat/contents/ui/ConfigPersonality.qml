// Settings → Personality: about you (name, avatar, a few lines about you, the tone
// and language you want, always/never notes), the AI (its name, personality
// and avatar) and the extra instructions sent before every chat (the old
// "System prompt" of the Chat page; same settings). The filled-in fields go
// at the start of a direct chat's system prompt (chat/Personality.js); the
// names and avatars show in the chat and in exports. Nothing here is secret.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "config" as Config
import "chat/Personality.js" as Personality

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    property alias cfg_userName: userNameField.text
    property alias cfg_userAbout: aboutArea.text
    property string cfg_userTone: ""
    property alias cfg_userLanguage: languageField.text
    property alias cfg_userNotes: notesArea.text
    property alias cfg_aiName: aiNameField.text
    property string cfg_aiPersonality: ""
    property alias cfg_aiPersonalityCustom: customArea.text
    // A theme icon name, or the absolute path of an image file ("" = none).
    property alias cfg_aiAvatar: aiAvatarPicker.value
    // Your own picture, shown next to your messages (same choices).
    property alias cfg_userAvatar: userAvatarPicker.value
    property alias cfg_enableSystemPrompt: promptCheck.checked
    property alias cfg_systemPrompt: promptArea.text

    // Shown beside the AI's avatar button when a chosen file can't be used.
    readonly property string avatarError: aiAvatarPicker.error

    // Takes a picked file as the AI's avatar (an image file with a safe path).
    function setAvatarFile(url) { aiAvatarPicker.setFile(url); }

    // The preset labels as literal i18n() calls, so they get extracted.
    readonly property var toneOptions: [
        {"text": i18n("No preference"), "value": ""},
        {"text": i18n("Friendly"), "value": "friendly"},
        {"text": i18n("Professional"), "value": "professional"},
        {"text": i18n("Concise"), "value": "concise"},
        {"text": i18n("Playful"), "value": "playful"}
    ]
    readonly property var personalityOptions: [
        {"text": i18n("None"), "value": ""},
        {"text": i18n("Friendly"), "value": "friendly"},
        {"text": i18n("Professional"), "value": "professional"},
        {"text": i18n("Witty"), "value": "witty"},
        {"text": i18n("Mentor"), "value": "mentor"},
        {"text": i18n("Concise"), "value": "concise"},
        {"text": i18n("Custom…"), "value": "custom"}
    ]

    // The row of `value` in a preset list (the first, "nothing", when unknown).
    function indexIn(options, value) {
        for (var i = 0; i < options.length; i++) {
            if (options[i].value === value)
                return i;
        }
        return 0;
    }

    // A multi-line box that grows with the form.
    component Box: QQC2.ScrollView {
        id: box
        property alias text: area.text
        property alias placeholderText: area.placeholderText
        property string accessibleName
        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        implicitHeight: Kirigami.Units.gridUnit * 4
        QQC2.TextArea {
            Keys.onTabPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)
            Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
            id: area
            wrapMode: TextEdit.Wrap
            Accessible.name: box.accessibleName
        }
    }

    Kirigami.FormLayout {
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("You")
        }

        QQC2.TextField {
            Accessible.name: Kirigami.FormData.label
            id: userNameField
            objectName: "userNameField"
            Kirigami.FormData.label: i18n("Your name:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            maximumLength: Personality.LIMITS.userName
            placeholderText: i18n("Shown as \"You\"")
        }

        Config.SettingHelp {
            text: i18n("What the AI calls you, and the name shown above your messages. Leave empty to stay \"You\".")
        }

        Config.AvatarPicker {
            id: userAvatarPicker
            Kirigami.FormData.label: i18n("Your avatar:")
            prefix: "userAvatar"
            buttonName: i18n("Choose your avatar")
            dialogTitle: i18n("Choose a Picture for You")
        }

        Config.SettingHelp {
            text: i18n("A small picture shown next to your messages: an icon from your theme or an image file of your own.")
        }

        Box {
            id: aboutArea
            objectName: "userAboutArea"
            Kirigami.FormData.label: i18n("About you:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            placeholderText: i18n("What you do, what you know well, what you are working on…")
            accessibleName: i18n("About you")
        }

        Config.SettingHelp {
            text: i18n("A few lines about yourself, so answers fit you: your job, what you know well, what you are working on.")
        }

        QQC2.ComboBox {
            Accessible.name: Kirigami.FormData.label
            id: toneCombo
            objectName: "toneCombo"
            Kirigami.FormData.label: i18n("Tone you like:")
            model: page.toneOptions
            textRole: "text"
            valueRole: "value"
            currentIndex: page.indexIn(page.toneOptions, page.cfg_userTone)
            onActivated: page.cfg_userTone = currentValue
        }

        Config.SettingHelp {
            text: i18n("How you like to be spoken to. \"No preference\" leaves it to the AI.")
        }

        QQC2.TextField {
            Accessible.name: Kirigami.FormData.label
            id: languageField
            objectName: "languageField"
            Kirigami.FormData.label: i18n("Reply language:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            maximumLength: Personality.LIMITS.userLanguage
            placeholderText: i18n("Same as my message")
        }

        Config.SettingHelp {
            text: i18n("The language replies are written in, for example \"English\" or \"Deutsch\". Leave empty to get replies in the language you write in.")
        }

        Box {
            id: notesArea
            objectName: "userNotesArea"
            Kirigami.FormData.label: i18n("Always / never:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            placeholderText: i18n("Always give sources. Never use emoji.")
            accessibleName: i18n("Always or never")
        }

        Config.SettingHelp {
            text: i18n("Things the AI should always or never do, one per line. How long replies are is set per chat, in its chat settings.")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("The AI")
        }

        QQC2.TextField {
            Accessible.name: Kirigami.FormData.label
            id: aiNameField
            objectName: "aiNameField"
            Kirigami.FormData.label: i18n("Its name:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            maximumLength: Personality.LIMITS.aiName
            placeholderText: i18n("No name: replies show the model")
        }

        Config.SettingHelp {
            text: i18n("A name for the assistant, shown above its replies. Leave empty to show the name of the model instead.")
        }

        QQC2.ComboBox {
            Accessible.name: Kirigami.FormData.label
            id: personalityCombo
            objectName: "personalityCombo"
            Kirigami.FormData.label: i18n("Personality:")
            model: page.personalityOptions
            textRole: "text"
            valueRole: "value"
            currentIndex: page.indexIn(page.personalityOptions, page.cfg_aiPersonality)
            onActivated: page.cfg_aiPersonality = currentValue
        }

        Config.SettingHelp {
            text: i18n("The character of the assistant: how it talks and how much it says. Choose \"Custom…\" to describe it in your own words.")
        }

        Box {
            id: customArea
            objectName: "customPersonalityArea"
            visible: page.cfg_aiPersonality === "custom"
            Kirigami.FormData.label: i18n("In your words:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            placeholderText: i18n("Calm and patient, like a good teacher…")
            accessibleName: i18n("Custom personality")
        }

        Config.SettingHelp {
            visible: customArea.visible
            text: i18n("Describe the personality you want in a sentence or two.")
        }

        Config.AvatarPicker {
            id: aiAvatarPicker
            Kirigami.FormData.label: i18n("Avatar:")
            prefix: "avatar"
            buttonName: i18n("Choose the AI's avatar")
            dialogTitle: i18n("Choose a Picture for the AI")
        }

        Config.SettingHelp {
            text: i18n("A small picture shown next to the AI's replies: an icon from your theme or an image file of your own.")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            Layout.topMargin: Kirigami.Units.smallSpacing
            wrapMode: Text.Wrap
            color: Kirigami.Theme.disabledTextColor
            text: i18n("What you fill in here is sent at the start of every chat with a provider, unless a chat turns it off in its chat settings. OpenCode and Pi chats keep their own instructions. The names and avatars show in the chat.")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Extra instructions")
        }

        QQC2.CheckBox {
            id: promptCheck
            objectName: "systemPromptCheck"
            Kirigami.FormData.label: i18n("Instructions:")
            text: i18n("Send these instructions before every chat")
            // help: next
        }

        Box {
            id: promptArea
            objectName: "systemPromptArea"
            enabled: promptCheck.checked
            implicitHeight: Kirigami.Units.gridUnit * 8
            placeholderText: i18n("Instructions for the model…")
            accessibleName: i18n("Extra instructions")
        }

        Config.SettingHelp {
            text: i18n("Anything else the AI should know or do in every chat, in your own words. This is sometimes called the \"system prompt\". Turn it off to keep the text without sending it.")
        }
    }
}
