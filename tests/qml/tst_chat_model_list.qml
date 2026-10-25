// The per-chat model picker offers the provider's live list, chat models only
// (chat/ChatSettingsDraft.qml, chat/ChatOverridesForm.qml), and notes a model
// the provider settings found retired.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/ProviderCheck.js" as ProviderCheck

Item {
    id: root
    width: 420
    height: 520

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    property var requests: []
    property int listStatus: 200
    function makeXhr() {
        var x = {headers: {}, readyState: 0, status: 0, responseText: ""};
        x.open = function(method, url) { x.method = method; x.url = url; };
        x.setRequestHeader = function(k, v) { x.headers[k] = v; };
        x.send = function() {
            root.requests.push({method: x.method, url: x.url, headers: x.headers});
            Qt.callLater(function() {
                x.status = root.listStatus;
                x.responseText = JSON.stringify({data: [{id: "acme/chat-big"}, {id: "acme/embed-text-1"}, {id: "acme/guard-8b"}, {id: "acme/chat-small"}, {id: "dead/gone-model"}]});
                x.readyState = 4;
                x.onreadystatechange();
            });
        };
        return x;
    }

    QtObject {
        id: chat
        property var plasmoid: ({configuration: {
            provider: "nvidia",
            perChatModelSettings: true,
            providersJson: JSON.stringify([{id: "nvidia", name: "NVIDIA NIM", type: "openai-compat", baseUrl: "https://nim.example/v1", model: "acme/chat-big"}])
        }})
        property var walletApiKeys: ({"nvidia": "good"})
        property var sessions: [{value: "a", text: "Chat", chatProvider: "", chatModel: "dead/gone-model", ownModel: true}]
        property string currentSessionTitle: "Chat"
        function getSessionProperty(id, key, fallback) {
            var s = sessions[0];
            return s[key] !== undefined ? s[key] : fallback;
        }
    }

    Chat.ChatSettingsDraft {
        id: draft
        rootRef: chat
        active: true
        xhrFactory: root.makeXhr
    }

    Chat.ChatOverridesForm {
        id: form
        width: 400
        draft: draft
    }

    HarnessTestCase {
        name: "ChatModelList"

        function test_1_offers_the_live_chat_models_only() {
            draft.load("a");
            tryVerify(function() { return draft.modelCandidates.length > 0; });
            compare(draft.modelCandidates, ["acme/chat-big", "acme/chat-small", "dead/gone-model"]);
            compare(root.requests[0].url, "https://nim.example/v1/models");
            compare(root.requests[0].headers["Authorization"], "Bearer good");
            compare(form.modelCombo.model.length, 3);
        }

        function test_2_notes_a_model_found_retired() {
            var note = findChild(form, "deadModelNote");
            compare(note.visible, false);
            ProviderCheck.markDead("nvidia", "dead/gone-model", "end of life");
            draft.model = "x";
            draft.model = "dead/gone-model";
            compare(note.visible, true);
            verify(note.text.indexOf("end of life") >= 0);
            wait(100);
            screenshot(root, "chat-model-list-dead-model");
            ProviderCheck.clearDead("nvidia", "dead/gone-model");
        }

        function test_3_a_rejected_key_is_reported() {
            root.listStatus = 403;
            draft.refreshModels(true);
            tryVerify(function() { return draft.statusError; });
            verify(draft.status.indexOf("rejected the API key (HTTP 403)") >= 0, draft.status);
            root.listStatus = 200;
        }
    }
}
