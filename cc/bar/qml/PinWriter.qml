// PinWriter.qml — singleton : écriture de bar.json (épingler / détacher).
//
// Le QML ne réécrit JAMAIS le JSON lui-même : il appelle barjson.py, qui
// remplace uniquement le tableau `apps` (le reste du fichier est recopié octet
// pour octet), conserve l'indentation et l'ordre, réactive une app déjà
// présente au lieu de la dupliquer, et écrit de façon atomique (temporaire +
// rename). Refus explicite si le fichier est en lecture seule ou invalide.
//
// Sortie du script : une ligne JSON sur stdout, toujours.
//   {"ok": true,  "action": "pin", "id": "spotify", "changed": true, ...}
//   {"ok": false, "error": "bar.json en lecture seule ..."}
// `pragma Singleton` est OBLIGATOIRE ici : qml/qmldir le déclare
// `singleton PinWriter`. Sans lui, Quickshell refuse de charger TOUT le shell
// (« qmldir defines type as singleton, but no pragma Singleton found ») et le
// service meurt en boucle — c'est arrivé au premier restart de la v3.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: pw

    property bool busy: false
    property bool gotOutput: false
    property string lastError: ""
    property string lastResult: ""
    property int revision: 0            // incrémenté à chaque écriture réussie

    property string pendingAction: ""
    property string pendingId: ""

    readonly property string scriptPath: {
        var u = Qt.resolvedUrl("../barjson.py").toString();
        u = u.replace("file://", "");
        return decodeURIComponent(u);
    }

    function run(action, id) {
        if (!id || ("" + id).length === 0) {
            pw.lastError = "identifiant d'application vide";
            return false;
        }
        if (pw.busy) {
            pw.lastError = "écriture déjà en cours";
            return false;
        }
        pw.busy = true;
        pw.gotOutput = false;
        pw.lastError = "";
        pw.pendingAction = action;
        pw.pendingId = "" + id;
        pw.proc.command = ["/usr/bin/python3", pw.scriptPath, action, "" + id];
        pw.proc.running = true;
        return true;
    }

    function pin(id) { return pw.run("--pin", id); }
    function unpin(id) { return pw.run("--unpin", id); }

    function say(msg) {
        Hypr.note(msg);
        Quickshell.execDetached(["notify-send", "-a", "Barre Sasquatch",
                                 "-t", "2500", "Barre Sasquatch", msg]);
    }

    function onOutput(txt) {
        pw.gotOutput = true;
        pw.lastResult = txt || "";
        var d = null;
        try {
            d = JSON.parse(pw.lastResult);
        } catch (e) {
            d = null;
        }
        pw.busy = false;
        if (!d) {
            pw.lastError = "barjson.py : réponse illisible";
            pw.say(pw.lastError);
            return;
        }
        if (!d.ok) {
            pw.lastError = "" + (d.error || "écriture refusée");
            pw.say(pw.lastError);
            return;
        }
        pw.lastError = "";
        pw.revision += 1;
        var verb = (pw.pendingAction === "--unpin") ? "détachée" : "épinglée";
        if (d.changed === true)
            pw.say(pw.pendingId + " " + verb);
        else
            pw.say(pw.pendingId + " : déjà " + verb);
    }

    property Process proc: Process {
        // Commande inerte : elle est remplacée avant chaque `running = true`.
        command: ["/usr/bin/true"]
        stdout: StdioCollector {
            onStreamFinished: pw.onOutput(this.text || "")
        }
        onExited: function (code, status) {
            if (!pw.gotOutput) {
                pw.busy = false;
                pw.lastError = "barjson.py : code " + code + " sans réponse";
                pw.say(pw.lastError);
            }
        }
    }
}
