// WidgetHost.qml — hôte générique (brief §1/§5).
//
// Rôle : lire widgets.json, garder les instances de SON hôte (`cc`, `background`,
// `bar`, `subpage`), et les placer via WidgetCanvas (grille ou libre).
// Un seul hôte sait lire le fichier : les widgets, eux, ne connaissent rien.
//
// Relecture : FileView + watchChanges (un `os.replace` change l'inode → on
// relit le fichier, on ne garde aucun handle), débat 150 ms, et une `revision`
// identique est ignorée (brief §5).
import QtQuick
import Quickshell
import Quickshell.Io
import Sasquatch.Widgets 1.0

Item {
    id: hostRoot

    property string host: "cc"
    property bool editing: false
    readonly property string layout: (hostRoot.host === "cc") ? "grid" : "free"

    property var instances: []
    property int revision: -1
    property bool ready: false
    property string lastError: ""

    // cc/widgets.json, résolu depuis le module (jamais depuis un JSON).
    readonly property url widgetsPath: Qt.resolvedUrl("../../../widgets.json")

    function applyText(txt) {
        if (!txt || txt.trim().length === 0) {
            hostRoot.lastError = "widgets.json vide — instances précédentes conservées";
            return;
        }
        var parsed = null;
        try {
            parsed = JSON.parse(txt);
        } catch (e) {
            hostRoot.lastError = "widgets.json invalide (" + e.message + ")";
            return;
        }
        if (!parsed || !Array.isArray(parsed.instances)) {
            hostRoot.lastError = "widgets.json sans tableau `instances`";
            return;
        }
        var rev = (typeof parsed.revision === "number") ? parsed.revision : 0;
        if (rev === hostRoot.revision)
            return;
        var kept = [];
        for (var i = 0; i < parsed.instances.length; ++i) {
            var it = parsed.instances[i];
            if (!it || typeof it.id !== "string" || typeof it.type !== "string")
                continue;
            if (it.host !== hostRoot.host)
                continue;
            // Pas de filtre « composant livré » ici : le registre se charge en
            // asynchrone, l'ordre n'est pas garanti. Un widget déclaré mais non
            // livré (media en v1a) a simplement une URL de composant vide :
            // WidgetCanvas ne charge alors rien (Loader.source = "").
            kept.push(it);
        }
        hostRoot.revision = rev;
        hostRoot.instances = kept;
        hostRoot.ready = true;
        hostRoot.lastError = "";
        // Trace de relecture : prouve dans le journal qu'une instance ajoutée
        // est prise en compte SANS redémarrer l'hôte (brief bugs §1.4).
        console.log("widgets:", hostRoot.host, "révision", rev, "instances", kept.length);
    }

    // Écriture : jamais dans le fichier, toujours un POST (brief §4).
    function op(obj, cb) {
        Api.post("/api/widgets", obj, function (d) {
            if (!d || d.ok !== true)
                console.warn("widgets:", d ? d.error : "pas de réponse");
            if (cb)
                cb(d);
        });
    }

    // Taille réelle de la surface : le serveur s'en sert pour borner le
    // placement libre (x + w/écran <= 1) et la cascade d'ajout.
    readonly property var screenSize: ({ w: Math.round(canvas.width),
                                         h: Math.round(canvas.height) })

    function add(type, variant, geo) {
        var req = { op: "add", type: type, host: hostRoot.host, variant: variant, geo: geo };
        if (hostRoot.layout !== "grid")
            req.screen = hostRoot.screenSize;
        hostRoot.op(req);
    }

    function removeInstance(id) {
        hostRoot.op({ op: "rm", id: id });
    }

    WidgetCanvas {
        id: canvas
        anchors.fill: parent
        host: hostRoot.host
        layout: hostRoot.layout
        editing: hostRoot.editing
        instances: hostRoot.instances
    }

    readonly property int instanceCount: hostRoot.instances.length
    // Union des zones qui captent la souris (brief bugs §1.6) : lue par
    // BackgroundMask, recalculée à chaque changement d'instance, d'édition ou
    // de taille de surface.
    readonly property var maskRects: canvas.inputRects
    // Hauteur naturelle du contenu (hôte grid) : le conteneur s'y ajuste.
    readonly property real contentHeight: (hostRoot.layout === "grid") ? canvas.contentHeight : 0

    Timer {
        id: debounce
        interval: 150
        repeat: false
        onTriggered: hostRoot.file.reload()
    }

    // Filet de sécurité : `widgets.json` est réécrit par `os.replace`, donc
    // l'inode surveillé disparaît. Si le Compositeur/FileView rate le signal,
    // cette relecture périodique garantit qu'une instance ajoutée apparaît
    // SANS redémarrer l'hôte (brief bugs §1.4). Un fichier de quelques ko :
    // le coût est nul, et `applyText` ignore une révision identique.
    Timer {
        interval: 1500
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: hostRoot.file.reload()
    }

    property FileView file: FileView {
        path: hostRoot.widgetsPath
        watchChanges: true
        blockLoading: true
        printErrors: true
        onFileChanged: debounce.restart()
        onTextChanged: hostRoot.applyText(hostRoot.file.text())
        onLoaded: hostRoot.applyText(hostRoot.file.text())
    }
}
