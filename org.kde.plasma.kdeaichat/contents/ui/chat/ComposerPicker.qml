// The quick picker behind the composer bar: change this chat's model (and its
// variant: the model's reasoning level, which only the models that report
// variants have; OpenCode's agent) without opening the Chat
// info panel. It goes through the same machinery as that panel: a
// ChatSettingsDraft is loaded for the chat, one field is changed, and save()
// writes it with setSessionOverrides. So the same rules apply: the chat keeps
// its mode (shown here, never offered), nothing is written unless "Let chats
// have their own model settings" is on (otherwise the picker says so and
// offers the settings), and when the main settings win (Settings -> Chat) the
// picker says that its choice has no effect instead of closing as if it had.
//
// The direct model list is the provider's live, chat-only list
// (ProviderCheck.js, through the draft's refreshModels).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "EffectiveConfig.js" as EffectiveConfig
import "../Variants.js" as Variants
import "../components/ModelFilter.js" as ModelFilter
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.Popup {
    id: picker

    property var chat: null
    // Replaces XMLHttpRequest in tests.
    property alias xhrFactory: draft.xhrFactory
    readonly property alias draft: draft

    readonly property string sessionId: chat ? chat.currentSessionId : ""
    readonly property var cfg: chat && chat.plasmoid ? chat.plasmoid.configuration : ({})
    readonly property bool perChat: cfg.perChatModelSettings === true
    readonly property var effective: chat && typeof chat.effectiveConfig === "function"
        ? chat.effectiveConfig(sessionId) : ({"mode": "provider", "provider": "", "model": "", "agent": "", "thinking": ""})
    readonly property string mode: effective.mode
    readonly property string modeName: mode === "opencode" ? "OpenCode" : mode === "pi" ? "Pi" : i18n("Direct")

    property string filterText: ""
    // Why the last choice did not take effect, if it did not.
    property string note: ""

    // Model ids for this chat's mode and provider, the current one first.
    readonly property var modelList: {
        var list = [];
        if (mode === "opencode") {
            var prefix = effective.provider ? effective.provider + "/" : "";
            var all = chat ? (chat.openCodeModelsList || []) : [];
            for (var i = 0; i < all.length; i++) {
                if (prefix === "")
                    list.push(all[i]);
                else if (String(all[i]).indexOf(prefix) === 0)
                    list.push(String(all[i]).substring(prefix.length));
            }
        } else if (mode === "pi") {
            list = (draft.piModelMap || {})[effective.provider] || [];
        } else {
            list = draft.modelCandidates || [];
        }
        return effective.model && list.indexOf(effective.model) < 0 ? [effective.model].concat(list) : list;
    }
    readonly property var matches: ModelFilter.filter(ModelFilter.normalize(modelList), filterText)

    // [{value, text}] of OpenCode's agents; empty for the other modes.
    readonly property var agentOptions: {
        var options = [];
        if (mode === "opencode") {
            var agents = draft.names(chat ? chat.openCodeAgentsList : [], "").slice(1);
            for (var j = 0; j < agents.length; j++)
                options.push({"value": agents[j], "text": agents[j]});
        }
        return options;
    }
    // The variants of the chat's model, from the mode's own report (Variants.js):
    // the provider's model list (direct), OpenCode's catalogue, Pi's list (thinking
    // models only, Pi's own levels). Empty: this model has none, so no chips.
    readonly property var variantList: {
        var key = effective.provider + "/" + effective.model;
        if (mode === "opencode")
            return Variants.fromOpenCodeNames(((chat && chat.openCodeVariants) || {})[key]);
        if (mode === "pi")
            return Variants.fromPi(EffectiveConfig.PI_THINKING_LEVELS, ((chat && chat.piThinkingModels) || {})[key] === true);
        return draft.directVariants;
    }
    // [{value, text}]: "default" (no variant) first, then the model's variants.
    readonly property var variantOptions: {
        var options = [];
        for (var i = 0; i < variantList.length; i++)
            options.push({"value": variantList[i].id, "text": variantList[i].label});
        return options.length > 0 ? [{"value": "", "text": i18n("default")}].concat(options) : options;
    }
    readonly property string currentVariant: effective.variant || ""

    signal chatInfoRequested()

    // Makes the draft start from what the chat uses now, so that a chat
    // without its own settings gets a copy of them plus the one change.
    function adopt() {
        if (draft.ownModel)
            return;
        var e = effective;
        var globalProvider = cfg.provider || "openai";
        if (e.mode === "opencode") {
            draft.ocProvider = e.provider;
            draft.ocModel = e.model;
            draft.ocAgent = e.agent;
            draft.ocVariant = e.variant;
        } else if (e.mode === "pi") {
            draft.piProvider = e.provider;
            draft.piModel = e.model;
            draft.piThinking = e.thinking;
        } else {
            draft.provider = e.provider === globalProvider ? "" : e.provider;
            draft.model = e.model;
            draft.variant = e.variant;
        }
    }

    function refresh() {
        // The variants are looked up for the model the chat really uses.
        draft.variantProvider = effective.provider;
        draft.variantModel = effective.model;
        if (mode === "opencode")
            draft.refreshOpenCode(function() { draft.refreshAgents(); });
        else if (mode === "pi")
            draft.refreshPi();
        else
            draft.refreshModels(false);
    }

    // kind: "model", "variant" or "agent". Saves, then closes if the chat now uses it.
    function choose(kind, value) {
        if (!perChat || !chat)
            return;
        draft.ownModel = true;
        if (kind === "model") {
            if (mode === "pi") {
                draft.piModel = value;
            } else {
                draft.variantModel = value;
                draft.changeModel(value, true);
            }
        } else if (kind === "agent") {
            draft.ocAgent = value;
        } else {
            draft.setVariantId(value);
        }
        draft.save();
        var after = chat.effectiveConfig(sessionId);
        var got = kind === "model" ? after.model : kind === "agent" ? after.agent : after.variant;
        if (got !== value) {
            note = i18n("Saved for this chat, but the main settings win over a chat's own (Settings → Chat), so it still uses %1.", got || i18n("the default"));
            return;
        }
        close();
    }

    x: 0
    y: -height - Kirigami.Units.smallSpacing
    width: parent ? Math.min(parent.width, Kirigami.Units.gridUnit * 26) : Kirigami.Units.gridUnit * 20
    padding: Kirigami.Units.smallSpacing
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

    onAboutToShow: {
        note = "";
        filterText = "";
        if (!chat)
            return;
        draft.load(sessionId);
        if (perChat) {
            adopt();
            refresh();
        }
    }
    onOpened: {
        if (perChat)
            filterField.forceActiveFocus();
    }
    onClosed: {
        draft.invalidate();
        if (chat && typeof chat.focusInput === "function")
            chat.focusInput();
    }

    ChatSettingsDraft {
        id: draft
        rootRef: picker.chat
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            objectName: "pickerMode"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18n("Mode: %1 (fixed: a chat keeps the mode it was started in)", picker.modeName)
            font: Kirigami.Theme.smallFont
            opacity: 0.75
        }

        // The "per chat" switch is off: say why nothing can be picked here.
        PC3.Label {
            objectName: "perChatOffNote"
            visible: !picker.perChat
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18n("Every chat uses the main settings. To pick a model for just this chat, turn on “Let chats have their own model settings” in Settings → Chat.")
        }

        PC3.Button {
            objectName: "openSettingsButton"
            visible: !picker.perChat
            icon.name: "configure"
            text: i18n("Open settings")
            onClicked: {
                picker.close();
                if (picker.chat && typeof picker.chat.openSettings === "function")
                    picker.chat.openSettings();
            }
        }

        QQC2.TextField {
            id: filterField
            objectName: "pickerFilter"
            visible: picker.perChat
            Layout.fillWidth: true
            text: picker.filterText
            placeholderText: i18n("Filter models")
            selectByMouse: true
            Accessible.name: i18n("Filter models")
            onTextEdited: picker.filterText = text
            Keys.onDownPressed: list.incrementCurrentIndex()
            Keys.onUpPressed: list.decrementCurrentIndex()
            onAccepted: {
                if (list.currentIndex >= 0 && list.currentIndex < picker.matches.length)
                    picker.choose("model", picker.matches[list.currentIndex].id);
                else if (picker.filterText.trim() !== "")
                    picker.choose("model", picker.filterText.trim());
            }
        }

        PC3.Label {
            objectName: "pickerStatus"
            visible: picker.perChat && text !== ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            color: picker.draft.statusError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
            text: picker.draft.statusError ? picker.draft.status
                : picker.matches.length > 0 ? i18n("%1 of %2", picker.matches.length, picker.modelList.length)
                : picker.draft.busy ? picker.draft.status : i18n("No model matches. Press Enter to use “%1”.", picker.filterText.trim())
        }

        ListView {
            id: list
            objectName: "pickerList"
            visible: picker.perChat
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 10)
            clip: true
            model: picker.perChat ? picker.matches : []
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

            delegate: QQC2.ItemDelegate {
                id: entry

                required property var modelData
                required property int index

                objectName: "modelRow"
                width: ListView.view.width
                highlighted: ListView.isCurrentItem
                onClicked: picker.choose("model", entry.modelData.id)
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "emblem-ok-symbolic"
                        opacity: entry.modelData.id === picker.effective.model ? 1 : 0
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: entry.modelData.id
                        elide: Text.ElideMiddle
                        color: entry.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    }
                }
            }
        }

        // OpenCode's agent.
        PC3.Label {
            visible: agentFlow.visible
            Layout.fillWidth: true
            text: i18n("Agent")
            font: Kirigami.Theme.smallFont
            opacity: 0.75
        }

        Flow {
            id: agentFlow
            objectName: "agentChoices"
            visible: picker.perChat && picker.agentOptions.length > 0
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: picker.agentOptions

                delegate: PC3.Button {
                    required property var modelData

                    objectName: "agentChoice"
                    text: modelData.text
                    checkable: true
                    checked: modelData.value === picker.effective.agent
                    onClicked: picker.choose("agent", modelData.value)
                }
            }
        }

        // The model's variants (reasoning levels), only when it has any: Pi's
        // thinking level for a thinking model, OpenCode's and the direct
        // provider's own list for theirs.
        PC3.Label {
            visible: variantFlow.visible
            Layout.fillWidth: true
            text: picker.mode === "pi" ? i18n("Thinking") : i18n("Variant")
            font: Kirigami.Theme.smallFont
            opacity: 0.75
        }

        Flow {
            id: variantFlow
            objectName: "variantChoices"
            visible: picker.perChat && picker.variantOptions.length > 0
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: picker.variantOptions

                delegate: PC3.Button {
                    required property var modelData

                    objectName: "variantChoice"
                    text: modelData.text
                    checkable: true
                    checked: modelData.value === picker.currentVariant
                    onClicked: picker.choose("variant", modelData.value)
                }
            }
        }

        PC3.Label {
            objectName: "pickerHint"
            visible: picker.perChat && !picker.draft.ownModel && picker.note === ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Choosing gives this chat its own model settings. The main settings stay as they are.")
        }

        PC3.Label {
            objectName: "pickerNote"
            visible: picker.note !== ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.neutralTextColor
            text: picker.note
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        PC3.ToolButton {
            objectName: "moreSettingsButton"
            Layout.fillWidth: true
            icon.name: "configure"
            text: i18n("More chat settings…")
            onClicked: {
                picker.close();
                picker.chatInfoRequested();
            }
        }
    }
}
