// Apps.qml — singleton : favoris / mini-lanceur (widget `apps`).
//
// L'INDEX N'EST PAS RÉÉCRIT ICI : il vient de cc/bar/appindex.py (le même
// script que la barre), lancé une fois au démarrage — `--json` imprime
// {generated, apps:{id:{name,icon,exec,argv,class,terminal,system}}, classes}.
// Le cache cc/bar/appindex.json est lu d'abord (icônes immédiates), puis le
// scan le remplace. Lancement : `appindex.py --launch <id>` (substitution
// %f/%u + détachement faits côté Python, comme la barre).
//
// Favoris = bar.json → apps[] (id, desktop, class, enabled). Une app absente
// de l'index n'est jamais cachée : le widget affiche une pastille initiale +
// son nom (jamais une case vide).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: apps

    property var index: ({})          // apps de appindex.py
    property var classes: ({})        // classe normalisée → id desktop
    property var pinned: []           // bar.json apps[] brut
    property bool ready: false
    property string lastError: ""
    property int launches: 0
    property int scans: 0

    // Chemins résolus depuis CE fichier (module ~/.config/cc/widgets/…).
    readonly property string scriptPath: {
        var u = Qt.resolvedUrl("../../../bar/appindex.py").toString();
        return decodeURIComponent(u.replace("file://", ""));
    }
    readonly property url barJsonPath: Qt.resolvedUrl("../../../bar/bar.json")
    readonly property url cachePath: Qt.resolvedUrl("../../../bar/appindex.json")

    function norm(s) {
        return ("" + (s || "")).toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    function entry(id) {
        return (id && apps.index && apps.index[id]) ? apps.index[id] : null;
    }

    function hasId(id) {
        return !!(id && apps.index && apps.index[id]);
    }

    function idForClass(cls) {
        var k = apps.norm(cls);
        if (!k)
            return "";
        return (apps.classes && apps.classes[k]) ? apps.classes[k] : "";
    }

    function iconFor(id) {
        var e = apps.entry(id);
        return e ? ("" + (e.icon || "")) : "";
    }

    function nameFor(id) {
        var e = apps.entry(id);
        if (e && e.name)
            return apps.displayName(e.name);
        // App absente de l'index : le nom vient de l'identifiant, nettoyé par
        // la même règle (« explorer.exe » → « Explorer »).
        return apps.displayName(id);
    }

    // Nom PROPRE (spec copy) : « explorer.exe » → « Explorer », jamais un
    // identifiant de fichier à l'écran.
    function displayName(name) {
        var s = ("" + (name || "")).replace(/\.(exe|desktop|appimage)$/i, "").trim();
        // Identifiant à points (« org.kde.krita ») : c'est le dernier segment
        // qui porte le nom lisible.
        if (s.indexOf(".") >= 0) {
            var seg = s.split(".");
            s = seg[seg.length - 1];
        }
        s = s.replace(/[_-]+/g, " ").trim();
        if (s.length === 0)
            return "Application";
        var words = s.split(/\s+/);
        for (var i = 0; i < words.length; ++i) {
            if (words[i].length > 1)
                words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1);
        }
        return words.join(" ");
    }

    // Pastille de repli : première lettre du nom, jamais une case vide.
    function initial(name) {
        var s = ("" + (name || "")).trim();
        return s.length > 0 ? s.charAt(0).toUpperCase() : "?";
    }

    function applyJson(txt) {
        var d = null;
        try {
            d = JSON.parse("" + (txt || ""));
        } catch (e) {
            apps.lastError = "appindex : JSON invalide";
            return;
        }
        if (!d || !d.apps) {
            apps.lastError = "appindex : réponse vide";
            return;
        }
        apps.index = d.apps;
        apps.classes = d.classes || ({});
        apps.ready = true;
        apps.lastError = "";
    }

    function applyBar(txt) {
        var d = null;
        try {
            d = JSON.parse("" + (txt || ""));
        } catch (e) {
            apps.lastError = "bar.json : JSON invalide";
            return;
        }
        apps.pinned = (d && Array.isArray(d.apps)) ? d.apps : [];
    }

    // ── Favoris résolus (id desktop + nom + icône) ────────────────────────
    // 1) les apps épinglées de bar.json (dans l'ordre de la barre) ;
    // 2) si bar.json n'en a aucune : les 8 premières apps visibles de l'index
    //    (mini-lanceur utile, jamais une carte vide).
    readonly property var favorites: {
        var out = [];
        var seen = ({});
        var list = apps.pinned || [];
        for (var i = 0; i < list.length && out.length < 12; ++i) {
            var p = list[i];
            if (!p || p.enabled === false)
                continue;
            var did = ("" + (p.desktop || p.id || "")).replace(/\.desktop$/, "");
            var id = apps.hasId(did) ? did : (apps.idForClass(p.class || p.id) || did);
            if (!id || seen[apps.norm(id)])
                continue;
            seen[apps.norm(id)] = true;
            out.push({
                id: id,
                name: apps.nameFor(id),
                icon: apps.iconFor(id),
                cls: "" + (p.class || id),
                known: apps.hasId(id)
            });
        }
        if (out.length === 0 && apps.index) {
            var keys = Object.keys(apps.index);
            var pool = [];
            for (var k = 0; k < keys.length; ++k) {
                var e = apps.index[keys[k]];
                if (!e || e.system === true || !e.exec)
                    continue;
                pool.push({ id: keys[k], name: "" + (e.name || keys[k]) });
            }
            pool.sort(function (a, b) { return a.name.localeCompare(b.name) });
            for (var j = 0; j < pool.length && out.length < 8; ++j) {
                out.push({
                    id: pool[j].id,
                    name: pool[j].name,
                    icon: apps.iconFor(pool[j].id),
                    cls: apps.entry(pool[j].id) ? ("" + (apps.entry(pool[j].id).class || "")) : "",
                    known: true
                });
            }
        }
        return out;
    }

    // ── Retrait d'un favori introuvable (spec copy : action « Retirer ») ──
    // bar.json appartient à la barre : on le modifie ATOMIQUEMENT (tmp +
    // rename) puis le FileView surveillé recharge la liste. Jamais de
    // suppression silencieuse : c'est l'utilisateur qui clique.
    readonly property string barJsonFile: {
        var u = ("" + apps.barJsonPath);
        return decodeURIComponent(u.indexOf("file://") === 0 ? u.substring(7) : u);
    }
    property string lastRemoved: ""

    function removeFavorite(id) {
        var did = ("" + (id || "")).replace(/\.desktop$/, "");
        if (did.length === 0)
            return false;
        apps.lastRemoved = did;
        apps.remover.command = ["/usr/bin/python3", "-c", apps.removeScript,
                                apps.barJsonFile, did];
        apps.remover.running = true;
        return true;
    }

    readonly property string removeScript: "import json, sys, os\n" +
        "p, sid = sys.argv[1], sys.argv[2]\n" +
        "d = json.load(open(p))\n" +
        "def key(a):\n" +
        "    return ('' + str(a.get('desktop') or a.get('id') or '')).replace('.desktop', '')\n" +
        "before = len(d.get('apps') or [])\n" +
        "d['apps'] = [a for a in (d.get('apps') or []) if key(a) != sid]\n" +
        "tmp = p + '.tmp'\n" +
        "json.dump(d, open(tmp, 'w'), indent=4, ensure_ascii=False)\n" +
        "os.replace(tmp, p)\n" +
        "print(before - len(d['apps']))\n"

    function refresh() {
        if (!apps.scan.running) {
            apps.scans += 1;
            apps.scan.running = true;
        }
    }

    function launch(id) {
        if (!id) {
            apps.lastError = "appindex : id vide";
            return false;
        }
        if (!apps.hasId(id)) {
            apps.lastError = "app introuvable : " + id;
            return false;
        }
        if (apps.launcher.running) {
            apps.lastError = "lancement déjà en cours";
            return false;
        }
        apps.launcher.command = ["/usr/bin/python3", apps.scriptPath, "--launch", id];
        apps.launcher.running = true;
        apps.launches += 1;
        apps.lastError = "";
        return true;
    }

    // Cache du dernier scan : icônes disponibles avant la fin du process.
    property FileView cacheFile: FileView {
        path: apps.cachePath
        watchChanges: false
        printErrors: false
        onLoaded: apps.applyJson(apps.cacheFile.text())
    }

    // Favoris : bar.json (la barre l'écrit déjà ; on ne fait que LIRE).
    property FileView barFile: FileView {
        path: apps.barJsonPath
        watchChanges: true
        printErrors: false
        onFileChanged: apps.barFile.reload()
        onTextChanged: apps.applyBar(apps.barFile.text())
        onLoaded: apps.applyBar(apps.barFile.text())
    }

    property Process scan: Process {
        command: ["/usr/bin/python3", apps.scriptPath, "--json"]
        stdout: StdioCollector {
            onStreamFinished: apps.applyJson(this.text || "")
        }
        onExited: {
            if (!apps.ready)
                apps.lastError = "appindex : aucun index produit";
        }
    }

    property Process remover: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                apps.lastError = "";
                apps.barFile.reload();
            }
        }
        onExited: function (code) {
            if (code !== 0)
                apps.lastError = "retrait refusé (code " + code + ")";
        }
    }

    property Process launcher: Process {
        command: ["/usr/bin/python3", apps.scriptPath, "--launch", ""]
        onExited: function (code) {
            if (code !== 0)
                apps.lastError = "lancement refusé (code " + code + ")";
        }
    }

    Component.onCompleted: apps.refresh()
}
