// Notes.qml — singleton : notes courtes persistées (widget `notes`).
//
// Le widget ne fait AUCUN XMLHttpRequest (contrat §2) : il lit Notes et
// appelle ses actions. Forme relue du serveur (cc/server.py → cc/notes.py) :
//   GET  /api/notes → {ok, notes: [{id, text, at}], count, file}
//   POST /api/notes {op: "add", text} | {op: "rm", id} | {op: "clear"}
//        → même charge utile, liste RELUE du fichier ~/.config/cc/notes.json
//          (écriture atomique côté serveur).
pragma Singleton
import QtQuick
import Sasquatch.Widgets 1.0

QtObject {
    id: notes

    property var items: []
    property bool ok: false
    property int count: 0
    property string file: ""
    property string lastError: ""
    property int polls: 0
    property int posts: 0

    function latest(n) {
        var k = Math.max(1, Math.round(n || 4));
        return notes.items.slice(0, k);
    }

    function apply(d) {
        if (!d || typeof d !== "object") {
            if (d === null)
                notes.lastError = "serveur muet — notes précédentes conservées";
            return;
        }
        notes.items = Array.isArray(d.notes) ? d.notes : [];
        notes.count = (typeof d.count === "number") ? d.count : notes.items.length;
        notes.ok = d.ok === true;
        if (typeof d.file === "string")
            notes.file = d.file;
        notes.lastError = notes.ok ? "" : (d.error || "notes indisponibles");
    }

    function refresh() {
        Api.get("/api/notes", function (d) {
            notes.polls += 1;
            notes.apply(d);
        });
    }

    function afterAction(d) {
        notes.posts += 1;
        notes.apply(d);
    }

    // Ajout : texte non vide seulement (le serveur refuse aussi le vide).
    function add(text) {
        var t = ("" + (text || "")).trim();
        if (t.length === 0)
            return false;
        Api.post("/api/notes", { op: "add", text: t }, notes.afterAction);
        return true;
    }

    function rm(id) {
        if (id === undefined || id === null)
            return;
        Api.post("/api/notes", { op: "rm", id: id }, notes.afterAction);
    }

    property Timer pollTimer: Timer {
        interval: 6000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: notes.refresh()
    }
}
