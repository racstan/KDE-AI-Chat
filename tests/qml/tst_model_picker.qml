// components/ModelPicker.qml over 1,000 fake models (an OpenRouter-sized list):
// substring filter, count, keyboard choice, the current model kept, and speed.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/components" as Components
import "../../org.kde.plasma.kdeaichat/contents/ui/components/ModelFilter.js" as ModelFilter

Item {
    id: root
    width: 520
    height: 480

    // Plasma provides i18n() to widget code.
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    // 1,000 ids; 12 contain "free" (spread out, some only in the middle of
    // the id, one in upper case), plus names on some of them.
    function fakeModels() {
        var vendors = ["openai", "anthropic", "meta-llama", "mistralai", "google", "qwen", "deepseek", "cohere"];
        var list = [];
        for (var i = 0; i < 1000; i++) {
            var id = vendors[i % vendors.length] + "/model-" + i + "-" + ["small", "large", "instruct", "chat"][i % 4];
            list.push(i % 5 === 0 ? {"id": id, "name": "Model " + i} : id);
        }
        var free = [37, 90, 144, 251, 333, 408, 512, 601, 777, 850, 901, 999];
        for (var f = 0; f < free.length; f++) {
            var entry = list[free[f]];
            if (typeof entry === "string")
                list[free[f]] = entry + (f === 3 ? ":FREE" : ":free");
            else
                list[free[f]] = {"id": entry.id + ":free", "name": entry.name};
        }
        return list;
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    property string chosen: "openai/model-0-small"
    Components.ModelPicker {
        id: picker
        x: 20
        y: 20
        width: 460
        model: root.fakeModels()
        value: root.chosen
        onPicked: function(id) { root.chosen = id; }
    }

    HarnessTestCase {
        id: testCase
        name: "ModelPicker"

        function init() {
            root.chosen = "openai/model-0-small";
            picker.close();
            picker.filterText = "";
        }

        function openPicker() {
            picker.open();
            tryVerify(function() { return picker.popupOpen; });
            wait(50);
        }

        function type(text) {
            for (var i = 0; i < text.length; i++)
                keyClick(text[i]);
        }

        function test_filter_is_a_case_insensitive_substring_match() {
            compare(picker.totalCount, 1000);
            var entries = ModelFilter.normalize(picker.model);
            compare(ModelFilter.filter(entries, "free").length, 12);
            compare(ModelFilter.filter(entries, "FREE").length, 12);
            // A match in the middle of an id, not only a prefix.
            compare(ModelFilter.filter(entries, "ama/model-90-").length, 1);
            compare(ModelFilter.filter(entries, "Model 5").length > 0, true);   // matches a name
            // Several words must all match.
            compare(ModelFilter.filter(entries, "free anthropic").length, 2);
            compare(ModelFilter.filter(entries, "nothing-like-this").length, 0);
        }

        function test_typing_filters_and_shows_the_count() {
            openPicker();
            compare(picker.countText, "1000 of 1000");
            type("free");
            compare(picker.filterText, "free");
            compare(picker.matchCount, 12);
            compare(picker.countText, "12 of 1000");
            keyClick(Qt.Key_Backspace);
            verify(picker.matchCount >= 12);
            picker.close();
        }

        function test_keyboard_chooses_a_model() {
            openPicker();
            type("free");
            compare(picker.highlightedIndex, 0);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            compare(picker.highlightedIndex, 2);
            keyClick(Qt.Key_Up);
            compare(picker.highlightedIndex, 1);
            var expected = picker.matches[1].id;
            keyClick(Qt.Key_Return);
            compare(root.chosen, expected);
            verify(expected.indexOf("free") >= 0 || expected.indexOf("FREE") >= 0);
            tryVerify(function() { return !picker.popupOpen; });
            testCase.verify(picker.matches.length === 12, "the filter stays until the next time it opens");
        }

        function test_highlight_stops_at_the_ends_and_pages() {
            openPicker();
            type("free");
            keyClick(Qt.Key_Up);
            compare(picker.highlightedIndex, 0);
            keyClick(Qt.Key_PageDown);
            compare(picker.highlightedIndex, 8);
            keyClick(Qt.Key_PageDown);
            compare(picker.highlightedIndex, 11);
            keyClick(Qt.Key_Down);
            compare(picker.highlightedIndex, 11);
            picker.close();
        }

        function test_current_model_is_kept_while_filtering_and_on_escape() {
            root.chosen = "qwen/model-5-large";
            openPicker();
            // Nothing typed: the highlight starts on the current model.
            compare(picker.matches[picker.highlightedIndex].id, "qwen/model-5-large");
            type("free");
            compare(root.chosen, "qwen/model-5-large");
            keyClick(Qt.Key_Escape);
            tryVerify(function() { return !picker.popupOpen; });
            compare(root.chosen, "qwen/model-5-large");
            compare(picker.value, "qwen/model-5-large");
        }

        function test_filter_with_no_match_can_use_the_typed_text() {
            openPicker();
            type("my-own/model");
            compare(picker.matchCount, 0);
            compare(picker.highlightedIndex, -1);
            keyClick(Qt.Key_Return);
            compare(root.chosen, "my-own/model");
        }

        function test_escape_and_reopen_resets_the_filter() {
            openPicker();
            type("free");
            keyClick(Qt.Key_Escape);
            tryVerify(function() { return !picker.popupOpen; });
            openPicker();
            compare(picker.filterText, "");
            compare(picker.matchCount, 1000);
            picker.close();
        }

        function test_typing_in_the_field_accepts_any_id() {
            picker.forceActiveFocus();
            var typed = [];
            picker.picked.connect(function(id) { typed.push(id); });
            // The field is the picker's first TextField.
            var edit = null;
            for (var i = 0; i < picker.children.length && !edit; i++)
                if (picker.children[i] instanceof QQC2.TextField)
                    edit = picker.children[i];
            verify(edit !== null);
            edit.forceActiveFocus();
            edit.text = "";
            keyClick("x");
            verify(typed.length > 0);
            compare(typed[typed.length - 1], "x");
        }

        function test_filtering_a_thousand_models_is_fast() {
            var entries = ModelFilter.normalize(picker.model);
            var queries = ["free", "o", "instruct", "model-9", "ama/", "zzz"];
            var rounds = 50;
            var start = Date.now();
            var found = 0;
            for (var r = 0; r < rounds; r++)
                for (var q = 0; q < queries.length; q++)
                    found += ModelFilter.filter(entries, queries[q]).length;
            var perFilter = (Date.now() - start) / (rounds * queries.length);
            console.log("PERF model filter over 1000 models: " + perFilter.toFixed(3) + " ms per keystroke (matches " + found + ")");
            verify(perFilter < 5, "filter took " + perFilter + " ms");

            // The whole keystroke: filter, rebuild the list, count.
            openPicker();
            var begin = Date.now();
            type("instruct");
            var keystrokes = (Date.now() - begin) / 8;
            console.log("PERF model picker typing: " + keystrokes.toFixed(1) + " ms per keystroke including the list update");
            verify(keystrokes < 60, "typing took " + keystrokes + " ms per key");
            picker.close();
        }

        function test_screenshot_filtered_list() {
            openPicker();
            type("free");
            wait(200);
            var path = screenshotWindow("model-picker-filtered-" + (root.Kirigami.Theme.backgroundColor.hslLightness < 0.5 ? "dark" : "light"));
            verify(path !== "");
            picker.close();
        }

        // The popup lives in the window's overlay, so grab the whole window.
        function screenshotWindow(fileName) {
            var path = screensDir + fileName + ".png";
            var saved = false;
            verify(root.Window.contentItem.grabToImage(function(result) { saved = result.saveToFile(path); }));
            tryVerify(function() { return saved; }, 5000);
            return path;
        }
    }
}
