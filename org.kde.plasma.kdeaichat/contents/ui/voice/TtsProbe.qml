// Which read-aloud engines can run here, and the voices of the system voice, for
// Settings → Voice. The system voice (a Qt engine) counts when its plugin loads
// and has voices; Speech Note and a speech server are always offered (they're
// whatever the user installed or points to).
import QtQuick
import QtTextToSpeech
import "TtsEngines.js" as Engines

Item {
    id: probe

    property var pluginOverride: ({})

    property bool probing: false
    property var available: []    // engine ids, in TtsEngines.js order
    property var voices: ({})     // engine id -> [{name, locale, language}]

    property var _instances: []
    property bool _qtDone: false

    function pluginFor(spec) {
        return (pluginOverride && pluginOverride[spec.id]) || spec.plugin;
    }

    function refresh() {
        probing = true;
        _qtDone = false;
        var installed = [];
        var first = ttsComponent.createObject(probe, {"engine": pluginFor(Engines.engine("system"))});
        if (first) {
            installed = first.availableEngines();
            first.destroy();
        }
        var made = [];
        for (var i = 0; i < Engines.engines.length; i++) {
            var spec = Engines.engines[i];
            if (spec.kind === "qt" && installed.indexOf(pluginFor(spec)) >= 0) {
                var tts = ttsComponent.createObject(probe, {"engine": pluginFor(spec)});
                if (tts)
                    made.push({"id": spec.id, "tts": tts});
            }
        }
        _instances = made;
        settle.restart();
    }

    function _collect() {
        var found = {};
        for (var i = 0; i < _instances.length; i++) {
            var tts = _instances[i].tts;
            var list = [];
            if (tts.state !== TextToSpeech.Error) {
                var vs = tts.availableVoices();
                for (var j = 0; j < vs.length; j++) {
                    var localeName = vs[j].locale ? vs[j].locale.name : "";
                    list.push({"name": vs[j].name, "locale": localeName,
                               "language": localeName ? Qt.locale(localeName).nativeLanguageName : ""});
                }
            }
            if (list.length > 0)
                found[_instances[i].id] = list;
            tts.destroy();
        }
        _instances = [];
        voices = found;
        _qtDone = true;
        _finish();
    }

    function _finish() {
        if (!_qtDone)
            return;
        var ids = [];
        for (var i = 0; i < Engines.engines.length; i++) {
            var spec = Engines.engines[i];
            if (spec.kind === "qt" ? !!voices[spec.id] : true)
                ids.push(spec.id);
        }
        available = ids;
        probing = false;
    }

    // Languages of an engine's voices: [{value, text}], "" (the engine's choice) first.
    function languages(engineId, defaultText) {
        var seen = {};
        var out = [{"value": "", "text": defaultText}];
        var list = voices[engineId] || [];
        for (var i = 0; i < list.length; i++) {
            var loc = list[i].locale;
            if (loc && !seen[loc]) {
                seen[loc] = true;
                var l = Qt.locale(loc);
                out.push({"value": loc, "text": l.nativeLanguageName + (l.nativeTerritoryName ? " (" + l.nativeTerritoryName + ")" : "")});
            }
        }
        return [out[0]].concat(out.slice(1).sort(function(a, b) { return a.text.localeCompare(b.text); }));
    }

    // Voices of an engine, in one language ("" = all): [{value, text}], default
    // first. espeak-ng's variants ("English+Linda") are left out, except `keep`.
    function voiceChoices(engineId, language, defaultText, keep) {
        var out = [{"value": "", "text": defaultText}];
        var list = voices[engineId] || [];
        for (var i = 0; i < list.length; i++) {
            if ((!language || list[i].locale === language) && Engines.plainVoice(list[i].name, keep))
                out.push({"value": list[i].name, "text": list[i].name});
        }
        return out;
    }

    Component {
        id: ttsComponent
        TextToSpeech {}
    }

    // Plugins load their voices right away or within a moment.
    Timer {
        id: settle
        interval: 400
        onTriggered: probe._collect()
    }
}
