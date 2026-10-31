// AppIndex.qml — singleton : index des .desktop produit par ../appindex.py.
//
// Au démarrage : lecture du cache appindex.json (icônes immédiates), puis
// rafraîchissement par `appindex.py --json` (Process). Le lancement d'une app
// passe par `appindex.py --launch <id>` : la substitution %f/%u et le
// détachement du processus sont faits côté Python (brief §4).
pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: ai

    property var apps: ({})
    property var classes: ({})
    property bool ready: false
    property string lastError: ""

    readonly property string scriptPath: {
        var u = Qt.resolvedUrl("../appindex.py").toString();
        u = u.replace("file://", "");
        return decodeURIComponent(u);
    }

    function norm(s) {
        return ("" + (s || "")).toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    function idForClass(cls) {
        var k = ai.norm(cls);
        if (!k) return "";
        if (ai.classes[k]) return ai.classes[k];
        return "";
    }
    function entryForClass(cls) {
        var id = ai.idForClass(cls);
        if (!id) return null;
        return ai.apps[id] || null;
    }
    function iconFor(cls) {
        var e = ai.entryForClass(cls);
        return e ? (e.icon || "") : "";
    }
    function pretty(cls) {
        // Nom lisible pour une classe sans .desktop (jeux Wine : explorer.exe,
        // plariumplay.exe, raid.exe…) : jamais « explorer.exe » à l'écran.
        var s = ("" + cls).trim();
        s = s.replace(/\.exe$/i, "").replace(/[._-]+/g, " ").replace(/\s+/g, " ");
        if (s.length === 0)
            return "Application";
        return s.charAt(0).toUpperCase() + s.slice(1);
    }
    function nameFor(cls) {
        var e = ai.entryForClass(cls);
        return e ? (e.name || pretty(cls)) : pretty(cls);
    }
    function iconForId(id) {
        var e = ai.apps[id];
        return e ? (e.icon || "") : "";
    }
    function hasId(id) {
        return !!(ai.apps && ai.apps[id]);
    }

    function applyJson(txt) {
        var d = null;
        try {
            d = JSON.parse(txt);
        } catch (e) {
            ai.lastError = "appindex: JSON invalide";
            return;
        }
        if (!d || !d.apps) {
            ai.lastError = "appindex: réponse vide";
            return;
        }
        ai.apps = d.apps;
        ai.classes = d.classes || ({});
        ai.ready = true;
        ai.lastError = "";
    }

    // Cache lu avant la première exécution : les icônes sont là dès l'affichage.
    property FileView cacheFile: FileView {
        path: Qt.resolvedUrl("../appindex.json")
        watchChanges: false
        printErrors: false
        onLoaded: ai.applyJson(ai.cacheFile.text())
    }

    property Process scan: Process {
        command: ["/usr/bin/python3", ai.scriptPath, "--json"]
        stdout: StdioCollector {
            onStreamFinished: ai.applyJson(this.text || "")
        }
    }

    property Process launcher: Process {
        command: ["/usr/bin/python3", ai.scriptPath, "--launch", ""]
    }

    function refresh() {
        if (!ai.scan.running)
            ai.scan.running = true;
    }

    function launch(id) {
        if (!id) {
            ai.lastError = "appindex: id vide";
            return false;
        }
        if (ai.launcher.running) {
            ai.lastError = "appindex: lancement déjà en cours";
            return false;
        }
        ai.launcher.command = ["/usr/bin/python3", ai.scriptPath, "--launch", id];
        ai.launcher.running = true;
        return true;
    }

    Component.onCompleted: ai.refresh()
}
