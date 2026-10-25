// "Give this chat its own model settings": the per-chat opt-in in the Chat
// info panel (only shown while chats may have their own model settings).
import org.kde.plasma.components as PC3

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

PC3.CheckBox {
    text: i18n("Give this chat its own model settings")
}
