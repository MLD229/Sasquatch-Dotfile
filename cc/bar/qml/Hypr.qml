// Hypr.qml — singleton : helpers au-dessus de Quickshell.Hyprland.
//
// Brief §4 : l'état affiché (workspaces, fenêtres) vient de Quickshell.Hyprland
// — aucun parsing `hyprctl` en boucle.
//
// Brief v2 §1 — « clic sur une app = m'amener là-bas » :
//   La v1 lisait une adresse dans un cache puis la rejouait. Deux défauts
//   mesurés au journal : (a) l'API QML expose l'adresse SANS le préfixe 0x,
//   que Hyprland refuse (« No such window found ») ; (b) ce cache ne se
//   rafraîchit pas au changement de focus, donc « la plus récente » était
//   fausse. Le clic lit donc maintenant, AU MOMENT DU CLIC, `hyprctl clients -j`
//   (une exécution par clic, aucun timer, aucune boucle) :
//     1. fenêtres de la classe → la plus récemment active (focusHistoryID min) ;
//     2. `workspace <ws>` puis `focuswindow address:0x…` ;
//     3. si l'adresse a disparu entre l'analyse et le dispatch → repli unique
//        (nouvelle lecture + nouvelle adresse).
//   `Hyprland.toplevels` sert à l'affichage (badges, groupes) et de repli si
//   `hyprctl` est indisponible.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

QtObject {
    id: hypr

    readonly property var workspaces: Hyprland.workspaces
    readonly property var toplevels: Hyprland.toplevels

    // Journal des derniers clics (diagnostic : IPC `clicks`). Petit, borné.
    property var clickLog: []

    function note(msg) {
        var e = [new Date().toISOString().substr(11, 12), "" + msg];
        var l = hypr.clickLog.slice(-19);
        l.push(e);
        hypr.clickLog = l;
        console.info("bar: " + msg);
    }

    function norm(s) {
        return ("" + (s || "")).toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    // ── Lecture de l'état (affichage) ─────────────────────────────────────
    // `lastIpcObject` est le JSON renvoyé par hyprctl pour cette fenêtre : il
    // contient `class`, que l'API QML 0.3.2 n'expose pas en propriété dédiée.
    function classOf(t) {
        if (!t)
            return "";
        var o = t.lastIpcObject;
        if (o && o.class)
            return "" + o.class;
        return "";
    }

    function titleOf(t) {
        return t ? (t.title || "") : "";
    }

    function addressOf(t) {
        return t ? (t.address || "") : "";
    }

    function ipc(t) {
        var o = t ? t.lastIpcObject : null;
        return (o && typeof o === "object") ? o : ({});
    }

    function wsIdOf(t) {
        var o = hypr.ipc(t);
        if (o.workspace && typeof o.workspace.id === "number")
            return o.workspace.id;
        return -1;
    }

    // 0 = fenêtre la plus récemment focalisée ; 9999 = inconnue.
    function histOf(t) {
        var v = hypr.ipc(t).focusHistoryID;
        return (typeof v === "number") ? v : 9999;
    }

    function focusedWsId() {
        var list = hypr.workspaces.values || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].focused === true)
                return list[i].id;
        }
        return -1;
    }

    // Hyprland n'accepte `focuswindow address:` qu'avec le préfixe 0x ; l'API
    // QML expose l'adresse SANS ce préfixe (« 562308d11000 ») — cause réelle
    // des « WARN … No such window found » de la v1.
    function addr0x(a) {
        var s = "" + (a || "");
        if (s.length === 0)
            return "";
        return s.indexOf("0x") === 0 ? s : "0x" + s;
    }

    // ── Fenêtres (affichage) ──────────────────────────────────────────────
    function windowsOf(cls) {
        var k = hypr.norm(cls);
        var out = [];
        if (!k)
            return out;
        var list = hypr.toplevels.values || [];
        for (var i = 0; i < list.length; i++) {
            if (hypr.norm(hypr.classOf(list[i])) === k)
                out.push(list[i]);
        }
        return out;
    }

    function countOf(cls) {
        return hypr.windowsOf(cls).length;
    }

    // ── App épinglée : classe ↔ .desktop (brief v3 §4) ────────────────────
    // bar.json écrit la classe « à la main » ("Spotify", "org.kde.dolphin") et
    // les fenêtres exposent la leur ("spotify", "dolphin") : comparer les deux
    // chaînes telles quelles rate l'état actif. On normalise donc les DEUX
    // côtés (norm) et on ajoute l'id .desktop comme seconde clé, dans les deux
    // sens (classe → id via AppIndex.classes, id → classe via l'index).
    function appKeys(cls, desktopId) {
        var out = ({});
        function add(v) {
            var k = hypr.norm(v);
            if (k.length > 0)
                out[k] = true;
        }
        var did = ("" + (desktopId || "")).replace(/\.desktop$/, "");
        add(cls);
        add(did);
        var byId = AppIndex.apps ? AppIndex.apps[did] : null;
        if (byId)
            add(byId.class);
        var idFromCls = AppIndex.idForClass(cls);
        if (idFromCls) {
            add(idFromCls);
            var byCls = AppIndex.apps ? AppIndex.apps[idFromCls] : null;
            if (byCls)
                add(byCls.class);
        }
        return out;
    }

    function appWindows(cls, desktopId) {
        var keys = hypr.appKeys(cls, desktopId);
        var out = [];
        var list = hypr.toplevels.values || [];
        for (var i = 0; i < list.length; i++) {
            var c = hypr.classOf(list[i]);
            var k = hypr.norm(c);
            if (keys[k]) {
                out.push(list[i]);
                continue;
            }
            var id = AppIndex.idForClass(c);
            if (id && keys[hypr.norm(id)])
                out.push(list[i]);
        }
        return out;
    }

    function countOfApp(cls, desktopId) {
        return hypr.appWindows(cls, desktopId).length;
    }

    function isOpenApp(cls, desktopId) {
        return hypr.countOfApp(cls, desktopId) > 0;
    }

    // Toutes les clés normalisées des apps épinglées actives : le cluster
    // « en cours » s'en sert pour ne pas répéter une app épinglée.
    function pinnedKeys() {
        var out = ({});
        var apps = Config.apps || [];
        for (var i = 0; i < apps.length; i++) {
            var a = apps[i];
            if (!a || a.enabled === false)
                continue;
            var keys = hypr.appKeys(a.class || a.id, a.desktop || a.id);
            for (var k in keys)
                out[k] = true;
        }
        return out;
    }

    function isPinnedClass(cls) {
        var keys = hypr.pinnedKeys();
        if (keys[hypr.norm(cls)])
            return true;
        var id = AppIndex.idForClass(cls);
        return !!(id && keys[hypr.norm(id)]);
    }

    // Preuve lisible par commande (`bar state` → pinnedOpen) : pour chaque app
    // épinglée de bar.json, l'état calculé exactement comme l'affiche AppDock.
    function pinnedState() {
        var out = ({});
        var apps = Config.apps || [];
        for (var i = 0; i < apps.length; i++) {
            var a = apps[i];
            if (!a)
                continue;
            var id = "" + (a.id || a.class || "");
            if (id.length === 0)
                continue;
            out[id] = hypr.isOpenApp(a.class || a.id, a.desktop || a.id);
        }
        return out;
    }

    function bestWindow(cls) {
        var w = hypr.windowsOf(cls);
        var best = null;
        var bestH = 1e9;
        for (var i = 0; i < w.length; i++) {
            var h = hypr.histOf(w[i]);
            if (h < bestH) {
                bestH = h;
                best = w[i];
            }
        }
        return best;
    }

    function addressExists(addr) {
        var want = hypr.norm(addr);
        if (want.length === 0)
            return false;
        var list = hypr.toplevels.values || [];
        for (var i = 0; i < list.length; i++) {
            if (hypr.norm(hypr.addressOf(list[i])) === want)
                return true;
        }
        return false;
    }

    function goWorkspace(idOrName) {
        Hyprland.dispatch("workspace " + idOrName);
    }

    // ── Résolution fraîche au clic ────────────────────────────────────────
    // Une seule lecture `hyprctl clients -j` par clic. La requête est mémorisée
    // le temps de la lecture (aucun timer, aucune boucle).
    property var req: null
    property bool busy: false
    property var lastClients: []

    property Process clientsProc: Process {
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: hypr.onClients(this.text || "")
        }
    }

    function request(r) {
        hypr.req = r;
        if (!hypr.busy)
            hypr.pump();
    }

    function pump() {
        if (hypr.req === null) {
            hypr.busy = false;
            return;
        }
        hypr.busy = true;
        clientsProc.running = true;
    }

    function onClients(txt) {
        hypr.busy = false;
        var r = hypr.req;
        hypr.req = null;
        var d = null;
        try {
            d = JSON.parse(txt);
        } catch (e) {
            d = null;
        }
        if (!d || !Array.isArray(d) || d.length === 0) {
            if (r)
                hypr.fallback(r);          // hyprctl absent : repli Quickshell
            return;
        }
        hypr.lastClients = d;
        if (r)
            hypr.handle(r, d);
        if (hypr.req !== null)
            hypr.pump();
    }

    // Fenêtres de la classe, triées par récence (focusHistoryID croissant).
    function pick(list, cls) {
        var k = hypr.norm(cls);
        var out = [];
        for (var i = 0; i < list.length; i++) {
            if (hypr.norm(list[i].class) === k) {
                var h = (typeof list[i].focusHistoryID === "number")
                        ? list[i].focusHistoryID : 9999;
                out.push({ win: list[i], hist: h });
            }
        }
        out.sort(function (a, b) { return a.hist - b.hist });
        return out;
    }

    function handle(r, list) {
        var found = hypr.pick(list, r.cls);
        if (r.kind === "cycle" && found.length > 1) {
            var idx = r.delta > 0 ? 1 : found.length - 1;
            var t = found[idx % found.length].win;
            hypr.apply(t.address, t.workspace ? t.workspace.id : -1, r.cls, "cycle");
            return;
        }
        if (found.length === 0) {
            if (r.kind === "activate" && ("" + (r.desktop || "")).length > 0) {
                hypr.note("launch " + r.desktop + " (classe " + r.cls + " fermée)");
                AppIndex.launch(r.desktop);
                return;
            }
            hypr.miss(r.cls + " : aucune fenêtre ouverte");
            return;
        }
        var w = found[0].win;
        hypr.apply(w.address, w.workspace ? w.workspace.id : -1, r.cls, "focus");
    }

    // Repli sans hyprctl : on relit les toplevels Quickshell.
    function fallback(r) {
        var w = hypr.bestWindow(r.cls);
        if (!w) {
            if (r.kind === "activate" && ("" + (r.desktop || "")).length > 0) {
                AppIndex.launch(r.desktop);
                return;
            }
            hypr.miss(r.cls + " : aucune fenêtre ouverte");
            return;
        }
        hypr.apply(hypr.addressOf(w), hypr.wsIdOf(w), r.cls, "repli QML");
    }

    // Dispatch effectif : workspace cible puis focus de l'adresse (0x…).
    function apply(addr, ws, cls, why) {
        var cur = hypr.focusedWsId();
        if (ws > 0 && ws !== cur)
            Hyprland.dispatch("workspace " + ws);
        Hyprland.dispatch("focuswindow address:" + hypr.addr0x(addr));
        hypr.note(why + " " + cls + " → " + hypr.addr0x(addr)
                  + " (ws " + ws + ", depuis ws " + cur + ")");
        hypr.check(hypr.addr0x(addr), cls, true);
    }

    // ── Vérification différée (repli unique) ──────────────────────────────
    // Pas un timer de données : une seule vérification 250 ms après un clic.
    property string pendingAddr: ""
    property string pendingCls: ""
    property bool retryAllowed: false

    function check(addr, cls, allowRetry) {
        hypr.pendingAddr = hypr.addr0x(addr);
        hypr.pendingCls = cls || "";
        hypr.retryAllowed = allowRetry !== false;
        hypr.retryTimer.restart();
    }

    function alive(addr) {
        if (hypr.addressExists(addr))
            return true;
        var want = hypr.norm(addr);
        var list = hypr.lastClients || [];
        for (var i = 0; i < list.length; i++) {
            if (hypr.norm(list[i].address) === want)
                return true;
        }
        return false;
    }

    function afterCheck() {
        var addr = hypr.pendingAddr;
        var cls = hypr.pendingCls;
        if (addr.length === 0 || hypr.alive(addr))
            return;                                   // cible vivante : terminé
        if (cls.length === 0 || !hypr.retryAllowed)
            return;
        hypr.retryAllowed = false;
        hypr.note("cible disparue (" + addr + ") → nouvelle résolution " + cls);
        hypr.request({ kind: "focus", cls: cls });
    }

    property QtObject retryTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: hypr.afterCheck()
    }

    // ── API utilisée par les modules ──────────────────────────────────────
    // Adresse connue (liste des fenêtres) : on la revalide juste avant.
    function focusWindow(addr) {
        if (!addr) {
            hypr.miss("adresse de fenêtre vide");
            return false;
        }
        Hyprland.dispatch("focuswindow address:" + hypr.addr0x(addr));
        hypr.note("focuswindow " + hypr.addr0x(addr));
        hypr.check(addr, "", false);
        return true;
    }

    // Chemin principal d'un clic d'app (résolution fraîche au clic).
    function focusClass(cls) {
        hypr.request({ kind: "focus", cls: cls });
        return true;
    }

    // Clic sur une app : focus si ouverte, sinon lancement (brief v2 §1).
    function activate(cls, desktopId) {
        hypr.request({ kind: "activate", cls: cls, desktop: desktopId || "" });
        return true;
    }

    // Molette sur une app : fenêtre suivante / précédente de la classe.
    function cycle(cls, delta) {
        hypr.request({ kind: "cycle", cls: cls, delta: delta });
        return true;
    }

    // Idem, mais depuis une app épinglée : on repart de la classe RÉELLE des
    // fenêtres trouvées (bar.json peut écrire « Spotify » là où la fenêtre
    // expose « spotify »). Moins de deux fenêtres → rien à cycler.
    function cycleApp(cls, desktopId, delta) {
        var wins = hypr.appWindows(cls, desktopId);
        if (wins.length < 2)
            return false;
        hypr.cycle(hypr.classOf(wins[0]), delta);
        return true;
    }

    // Cible introuvable : on le DIT (notification + journal), jamais un clic
    // silencieux (brief v2 §2).
    function miss(msg) {
        hypr.note("introuvable: " + msg);
        Quickshell.execDetached(["notify-send", "-a", "Barre Sasquatch",
                                 "-t", "3000", "Barre Sasquatch", msg]);
    }

    // Vue brute des toplevels Quickshell (diagnostic : `qs ipc call bar windows`).
    function dumpWindows() {
        var list = hypr.toplevels.values || [];
        var out = [];
        for (var i = 0; i < list.length; i++) {
            out.push({
                cls: hypr.classOf(list[i]),
                title: hypr.titleOf(list[i]),
                addr: hypr.addressOf(list[i]),
                ws: hypr.wsIdOf(list[i]),
                hist: hypr.histOf(list[i])
            });
        }
        return out;
    }

    // Liste [{cls, title, addr}] dédoublonnée par classe normalisée, dans
    // l'ordre d'apparition des fenêtres.
    function groups() {
        var list = hypr.toplevels.values || [];
        var seen = ({});
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var c = hypr.classOf(list[i]);
            var k = hypr.norm(c);
            if (!k || seen[k])
                continue;
            seen[k] = true;
            var wins = hypr.windowsOf(c);
            out.push({
                cls: c,
                key: k,
                count: wins.length,
                first: wins.length > 0 ? hypr.addressOf(wins[0]) : "",
                best: wins.length > 0 ? hypr.addressOf(hypr.bestWindow(c)) : "",
                ws: wins.length > 0 ? hypr.wsIdOf(hypr.bestWindow(c)) : -1,
                title: hypr.titleOf(list[i])
            });
        }
        return out;
    }
}
