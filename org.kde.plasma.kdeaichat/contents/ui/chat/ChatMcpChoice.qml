// Chat info → "MCP servers for this chat": which of the enabled MCP servers (Settings → Tools) a direct
// chat may use. Unset (the default) means all of them; the choice is the chat's `mcpServers` setting, a list
// of server ids, written with the rest of the panel's settings on Apply (ChatSettingsDialog._save). OpenCode
// and Pi chats have their own tools, so nothing is shown for them. Server names come from mcp.json and are
// shown as plain text.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified
ColumnLayout {
    id: choice

    // chat/ChatSettingsDraft.qml: sessionId, mode, dirty, loaded(), rootRef.
    property var draft: null

    // The enabled servers, [{id, ...}], and which of them are ticked: {id: true}.
    property var servers: []
    property var ticked: ({})

    readonly property bool direct: choice.draft !== null && choice.draft.mode === "provider"
    readonly property var _root: choice.draft ? choice.draft.rootRef : null

    visible: choice.direct && choice.servers.length > 0
    spacing: Kirigami.Units.smallSpacing

    function reload() {
        if (!choice._root || !choice._root.store || !choice._root.store.runHelper)
            return;
        const sessionId = choice.draft.sessionId;
        choice._root.store.runHelper("mcp_list", {}, function(stdout, exitCode) {
            if (choice.draft.sessionId !== sessionId)
                return;
            let list = [];
            try {
                list = exitCode === 0 ? (JSON.parse(stdout).servers || []) : [];
            } catch (e) {
                list = [];
            }
            choice.servers = list.filter(function(s) { return s && s.id && s.enabled !== false; });
            const saved = choice._root.getSessionProperty(sessionId, "mcpServers", null);
            const next = {};
            choice.servers.forEach(function(s) { next[s.id] = !Array.isArray(saved) || saved.indexOf(s.id) >= 0; });
            choice.ticked = next;
        });
    }

    // The value to store: null (all enabled servers) or the ids ticked.
    function value() {
        const ids = choice.servers.filter(function(s) { return choice.ticked[s.id] === true; }).map(function(s) { return s.id; });
        return ids.length === choice.servers.length ? null : ids;
    }

    function save() {
        if (!choice.direct || choice.servers.length === 0 || !choice._root || typeof choice._root.setSessionOverrides !== "function")
            return;
        choice._root.setSessionOverrides(choice.draft.sessionId, {"mcpServers": choice.value()});
    }

    Connections {
        target: choice.draft
        function onLoaded() { choice.reload(); }
    }

    Kirigami.Heading {
        level: 5
        text: i18n("MCP servers for this chat")
        Layout.fillWidth: true
    }

    QQC2.Label {
        text: i18n("The AI can use the tools of the servers ticked here. It asks you before each tool runs. Add or turn off servers in Settings → Tools.")
        wrapMode: Text.WordWrap
        opacity: 0.7
        Layout.fillWidth: true
    }

    Repeater {
        model: choice.servers

        QQC2.CheckBox {
            required property var modelData
            objectName: "mcpChoice-" + modelData.id
            Layout.fillWidth: true
            text: modelData.id
            checked: choice.ticked[modelData.id] === true
            onToggled: {
                const next = Object.assign({}, choice.ticked);
                next[modelData.id] = checked;
                choice.ticked = next;
                choice.draft.dirty = true;
            }
        }
    }
}
