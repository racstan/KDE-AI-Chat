// Runs the composer's slash commands (Commands.js lists and parses them) and
// feeds the list under the input. Not visible; Composer.qml owns one.
//
// A command is never sent to the model. /model and /variant go through the
// composer picker's apply path (ComposerPicker.qml: a ChatSettingsDraft, saved
// with setSessionOverrides), so the per-chat settings switch is respected
// exactly as there. /mode only changes the MAIN setting (useOpenCode / usePi)
// for chats created later: the open chat keeps its mode (EffectiveConfig.js).
// What a command did is said in `notice`, which the status line shows.
pragma ComponentBehavior: Bound

import QtQuick
import "Commands.js" as Commands
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Item {
    id: runner

    property var chat: null
    // The composer's ComposerPicker and the text box.
    property var picker: null
    property var input: null
    property string notice: ""
    // The picker's draft was loaded for the "/" being typed.
    property bool prepared: false

    readonly property var variantIds: {
        var ids = [];
        var options = picker ? picker.variantOptions : [];
        for (var i = 0; i < options.length; i++)
            ids.push(options[i].value === "" ? "default" : options[i].value);
        return ids;
    }
    // What Commands.suggest() needs to list the arguments.
    readonly property var context: ({
        "hasVariants": variantIds.length > 0,
        "variants": variantIds,
        "perChat": !!picker && picker.perChat,
        "models": picker ? (picker.modelList || []).map(function(m) { return String(m); }) : []
    })

    // The text of the box changed: while it starts with "/", the picker's
    // lists (models, variants) are loaded for this chat, once.
    function track(text) {
        if (text !== "")
            notice = "";
        if (text.charAt(0) !== "/") {
            prepared = false;
        } else if (!prepared && picker && picker.perChat) {
            prepare(true);
        }
    }

    function prepare(fetch) {
        picker.note = "";
        picker.draft.load(picker.sessionId);
        picker.adopt();
        if (fetch)
            picker.refresh();
        prepared = true;
    }

    function show(text) {
        notice = text;
        noticeTimer.restart();
    }

    function clearInput() {
        if (input)
            input.text = "";
        prepared = false;
    }

    // Enter on the list: an argument runs its command, a command typed out in
    // full runs, anything else is completed (Tab does the same).
    function activate(entry, text) {
        if (!entry)
            return;
        if (entry.kind === "option")
            run(entry.insert);
        else if (entry.kind === "notice")
            openSettings();
        else if (entry.kind === "command" && text.trim() === "/" + entry.name)
            run(text);
        else
            complete(entry);
    }

    // The per-chat notice (Commands.suggest): Settings → Chat has the switch.
    function openSettings() {
        clearInput();
        show(i18n("Every chat uses the main settings. To change it for just this chat, turn on “Let chats have their own model settings” in Settings → Chat."));
        if (typeof chat.openSettings === "function")
            chat.openSettings();
    }

    function complete(entry) {
        if (!entry || !input)
            return;
        input.text = entry.insert;
        input.cursorPosition = input.length;
    }

    // Runs the line when it is a built-in command and returns true (the box is
    // cleared unless the command could not run as typed); false: it is a
    // message, send it.
    function run(text) {
        var found = Commands.resolve(text);
        if (!found)
            return false;
        var name = found.command.name;
        var arg = found.arg;
        if (name === "new" && arg !== "") {
            show(i18n("/new takes no argument."));
            return true;
        }
        if (name === "model" && arg === "") {
            clearInput();
            picker.open();
        } else if (name === "new") {
            clearInput();
            chat.createSession(true);
            show(i18n("Started a new chat."));
        } else if (name === "mode") {
            runMode(arg);
        } else if (name === "variant") {
            runVariant(arg);
        } else if (name === "image") {
            runImage(arg);
        } else if (name === "remember") {
            runRemember(arg);
        } else if (name === "memories") {
            runMemories(arg);
        } else {
            apply("model", arg);
        }
        return true;
    }

    function runMode(arg) {
        if (Commands.MODES.indexOf(arg) < 0) {
            show(i18n("Use /mode direct, /mode opencode or /mode pi."));
            return;
        }
        var config = chat.plasmoid.configuration;
        config.useOpenCode = arg === "opencode";
        config.usePi = arg === "pi";
        var open = chat.effectiveConfig(chat.currentSessionId).mode;
        show(i18n("New chats will use %1. This chat stays %2.", Commands.modeName(arg), Commands.modeName(open === "provider" ? "direct" : open)));
        clearInput();
    }

    // /image <prompt>: a picture from the default image service, as the reply to this line. The line
    // stays in the box when it can't run, so it can be fixed.
    function runImage(arg) {
        if (chat.effectiveConfig(chat.currentSessionId).mode !== "provider") {
            show(i18n("/image works in direct chats only."));
        } else if (arg === "") {
            show(i18n("Write what to draw, like /image a red fox in the snow."));
        } else if (chat.loading) {
            show(i18n("Wait for the current reply to finish, or press Stop, then try again."));
        } else {
            var result = chat.sendImageCommand(arg);
            if (result.ok)
                clearInput();
            else
                show(result.code === "none" ? i18n("Add an image service first: Settings → Connection → Add provider → AI Horde or Pollinations.") : result.problem);
        }
    }

    // /remember [chat:|project:] <text>: saves a memory (chat/Memory.qml), sends
    // nothing; the Undo notice confirms it. Kept in the box when it can't run.
    function runRemember(arg) {
        var parsed = Commands.rememberArg(arg);
        var project = chat.memory.projectOf(chat.currentSessionId);
        if (chat.incognito && chat.incognito.active) {
            show(i18n("Nothing is remembered from an incognito chat."));
        } else if (parsed.text === "") {
            show(i18n("Write what to remember, like /remember I prefer metric units. Start with chat: or project: to keep it to this chat or its project."));
        } else if (parsed.scope === "project" && !project) {
            show(i18n("This chat is in no project. Use /remember or /remember chat:."));
        } else if (chat.memory.remember(parsed.text, parsed.scope, chat.currentSessionId, null)) {
            clearInput();
        } else {
            show(i18n("Memories are not available."));
        }
    }

    // /memories [question]: the question (or, without one, the next message)
    // goes with all this chat's memories, not only those that match it.
    function runMemories(arg) {
        var id = chat.currentSessionId;
        if (!chat.memory || !chat.memory.store) {
            show(i18n("Memories are not available."));
        } else if (!chat.memory.activeFor(id)) {
            show(i18n("Memory is off for this chat. Turn it on in Chat info (or in Settings → Memory)."));
        } else if (chat.memory.applicableFor(id).length === 0) {
            show(i18n("You have no memories for this chat yet. Save one with /remember."));
        } else {
            chat.memory.sendAllNext(id);
            if (arg === "") {
                clearInput();
                show(i18n("Your next message will go with all your memories."));
            } else {
                chat.chatInputText = arg;
                chat.sendMessage();
            }
        }
    }

    function runVariant(arg) {
        var ids = variantIds;
        if (picker.perChat && ids.length === 0) {
            show(i18n("This model has no variants."));
        } else if (picker.perChat && arg === "") {
            show(i18n("Variants: %1. Use /variant <name>.", ids.join(", ")));
        } else if (picker.perChat && ids.indexOf(arg) < 0) {
            // Kept in the box, to correct it.
            show(i18n("This model has no variant “%1”. It has: %2.", arg, ids.join(", ")));
            return;
        } else {
            apply("variant", arg === "default" ? "" : arg);
            return;
        }
        clearInput();
    }

    // The picker's own apply path; says what happened.
    function apply(kind, value) {
        clearInput();
        if (!picker.perChat) {
            show(i18n("Every chat uses the main settings. To change it for just this chat, turn on “Let chats have their own model settings” in Settings → Chat."));
            return;
        }
        prepare(false);
        picker.choose(kind, value);
        prepared = false;
        show(picker.note !== "" ? picker.note : i18n("This chat now uses %1.", value === "" ? i18n("the default variant") : value));
    }

    Timer {
        id: noticeTimer
        interval: 8000
        onTriggered: runner.notice = ""
    }
}
