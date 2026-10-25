// Changing messages of the open chat: delete, edit and resend, retry,
// regenerate, and answering permission and question cards (sent to the agent
// that asked). `chat` is the widget root (main.qml).
import QtQuick
import "TimeFormat.js" as TimeFormat

QtObject {
    id: edits

    property var chat: null
    property var openCodeRef: null  // chat/OpenCodeMode.qml
    property var piAgentRef: null   // chat/PiMode.qml
    property var directToolsRef: null  // chat/DirectToolRounds.qml

    function deleteMessage(index) {
        var copy = chat.messages.slice();
        if (index < 0 || index >= copy.length)
            return ;

        copy.splice(index, 1);
        chat.messages = copy;
        chat.editingMessageIndex = -1;
        chat.editingDraft = "";
        chat.clearCurrentOpenCodeSessionIfNeeded();
        chat.saveCurrentSessionState(true);
    }

    function saveEditedMessage() {
        var i = chat.editingMessageIndex;
        if (i < 0 || i >= chat.messages.length)
            return ;

        if ((chat.messages[i].role || "") === "error") {
            chat.editingMessageIndex = -1;
            chat.editingDraft = "";
            return ;
        }
        // Cancel any active streaming/loading requests first
        chat.stopStreaming();
        var role = chat.messages[i].role || "";
        var isQueued = role === "queued";
        var copy = isQueued ? chat.messages.slice() : chat.messages.slice(0, i + 1);
        var item = Object.assign({}, copy[i]);
        item.content = chat.editingDraft;
        item.at = Date.now();
        item.time = TimeFormat.nowTime(item.at);
        copy[i] = item;
        chat.messages = copy;
        chat.editingMessageIndex = -1;
        chat.editingDraft = "";
        chat.clearCurrentOpenCodeSessionIfNeeded();
        chat.saveCurrentSessionState(true);
        // Re-run from edited user prompt so assistant response reflects the new text.
        if (role === "user") {
            chat.userScrolledUp = false;
            chat.sendMessageByIndex(i);
        }
    }

    function retryFailedMessage(index) {
        if (index < 0 || index >= chat.messages.length) return;
        var role = chat.messages[index].role || "";
        if (role !== "error") return;
        
        var lastUserIdx = -1;
        for (var i = index - 1; i >= 0; i--) {
            var r = chat.messages[i].role || "";
            if (r === "user" || r === "queued") {
                lastUserIdx = i;
                break;
            }
        }
        
        if (lastUserIdx >= 0) {
            chat.stopStreaming();
            var copy = chat.messages.slice(0, lastUserIdx + 1);
            chat.messages = copy;
            chat.clearCurrentOpenCodeSessionIfNeeded();
            chat.saveCurrentSessionState(true);
            chat.userScrolledUp = false;
            chat.sendMessageByIndex(lastUserIdx);
        }
    }

    // Asks again from the user message at `index` (or before the reply there); later messages are dropped, undoably.
    function regenerateResponse(index, promptModifier) {
        if (index < 0 || index >= chat.messages.length) return;
        var role = chat.messages[index].role || "";
        var reply = role === "assistant" || role === "opencode_assistant";
        var lastUserIdx = reply ? index - 1 : index;
        var userRole = lastUserIdx >= 0 ? (chat.messages[lastUserIdx].role || "") : "";
        if (userRole !== "user" && userRole !== "queued") return;
        chat.stopStreaming();
        var before = chat.messages;
        var copy = before.slice(0, lastUserIdx + 1);
        if (promptModifier) {
            var item = Object.assign({}, copy[lastUserIdx]);
            item.content = item.content + "\n\n" + promptModifier;
            item.at = Date.now();
            item.time = TimeFormat.nowTime(item.at);
            copy[lastUserIdx] = item;
        }
        chat.messages = copy;
        if (before.length > copy.length) chat.messagesDropped(chat.currentSessionId, before);
        chat.clearCurrentOpenCodeSessionIfNeeded();
        chat.saveCurrentSessionState(true);
        chat.userScrolledUp = false;
        chat.sendMessageByIndex(lastUserIdx);
    }

    // The agent (OpenCode or Pi) or direct-mode model that asked a permission or question.
    function harnessFor(role, idField, id) {
        var index = chat.findRequestMessage(role, idField, id);
        var harness = index >= 0 ? chat.messages[index].harness : "";
        return harness === "pi" ? edits.piAgentRef : harness === "direct" ? edits.directToolsRef : edits.openCodeRef;
    }

    // always: also allow it from now on (OpenCode only).
    function respondToPermission(permissionId, approved, always) {
        edits.harnessFor("permission_request", "permissionId", permissionId).respondToPermission(permissionId, approved, always === true);
    }

    function respondToQuestion(questionId, answerValue, isReject) {
        edits.harnessFor("question_request", "questionId", questionId).respondToQuestion(questionId, answerValue, isReject);
    }

    function _questionMessageIndex(questionId) {
        for (var i = 0; i < chat.messages.length; i++)
            if (chat.messages[i].role === "question_request" && chat.messages[i].questionId === questionId)
                return i;
        return -1;
    }

    function questionOptionSelected(questionId, questionIndex, label) {
        var idx = edits._questionMessageIndex(questionId);
        if (idx < 0) return false;
        var selected = chat.messages[idx].selectedAnswers || [];
        var row = selected[questionIndex];
        return Array.isArray(row) && row.indexOf(String(label || "")) >= 0;
    }

    function toggleQuestionOption(questionId, questionIndex, label, multiple) {
        var idx = edits._questionMessageIndex(questionId);
        if (idx < 0) return;
        var copy = chat.messages.slice();
        var item = Object.assign({}, copy[idx]);
        var selected = Array.isArray(item.selectedAnswers) ? item.selectedAnswers.slice() : [];
        var row = Array.isArray(selected[questionIndex]) ? selected[questionIndex].slice() : [];
        var value = String(label || "");
        if (multiple) {
            var existing = row.indexOf(value);
            if (existing >= 0) row.splice(existing, 1); else row.push(value);
        } else {
            row = [value];
        }
        selected[questionIndex] = row;
        item.selectedAnswers = selected;
        copy[idx] = item;
        chat.messages = copy;
        chat.saveCurrentSessionState(true);
    }

    // Collect selected options from the question UI and submit the answer.
    function submitQuestionAnswer(questionId, questions, customField) {
        var idx = edits._questionMessageIndex(questionId);
        if (idx < 0) return;
        var customText = customField ? String(customField.text || "").trim() : "";
        if (!questions || questions.length === 0) {
            if (customText) edits.respondToQuestion(questionId, customText, false);
            return;
        }
        var selected = chat.messages[idx].selectedAnswers || [];
        var answers = [];
        var hasAnswer = false;
        var firstEmpty = -1;
        for (var i = 0; i < questions.length; i++) {
            var row = Array.isArray(selected[i]) ? selected[i].slice() : [];
            if (row.length > 0) hasAnswer = true;
            else if (firstEmpty < 0) firstEmpty = i;
            answers.push(row);
        }
        if (customText) {
            if (firstEmpty >= 0) answers[firstEmpty] = [customText];
            else if (answers.length > 0) answers[answers.length - 1].push(customText);
            hasAnswer = true;
        }
        if (hasAnswer)
            edits.respondToQuestion(questionId, answers, false);
    }
}
