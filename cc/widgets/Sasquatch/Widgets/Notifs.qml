// Notifs.qml — singleton : notifications mako (widget `notifications`).
//
// Le widget ne fait AUCUN XMLHttpRequest (contrat §2) : il lit Notifs et
// appelle ses actions. Forme de la charge utile, relue du serveur (jamais
// devinée) :
//   GET /api/notifications → {ok, available, running, tool, install,
//                             items: [{id, app, icon, summary, body,
//                                      urgency, actions[], active}],
//                             count, activeCount, error}
//   POST /api/notifications {op: "dismiss-all"} | {op:"dismiss", id} →
//                             même charge utile + applied {}, état RELU.
// mako absent → available = false + `install` (commande d'installation) : le
// widget affiche un état « indisponible », jamais une carte vide.
pragma Singleton
import QtQuick
import Sasquatch.Widgets 1.0

QtObject {
    id: nt

    property var items: []
    property bool ok: false
    property bool available: false
    property bool running: false
    property int count: 0
    property int activeCount: 0
    property string install: "sudo pacman -S mako"
    property string lastError: ""
    property int polls: 0
    property int posts: 0

    // ── Copy (spec §3) : titre humain, corps nettoyé ──────────────────────
    // Vivait dans le widget ; ici, c'est testable (tests/copy-tests.qml) et
    // réutilisable par la barre. Aucun identifiant technique à l'écran.
    function noteTime(note) {
        if (!note)
            return "";
        var s = [note.summary, note.body, note.icon].join(" ");
        var m = /(\d{8})[_\- ]?(\d{6})/.exec(s);
        if (m)
            return m[2].substring(0, 2) + ":" + m[2].substring(2, 4);
        m = /(\d{4})-(\d{2})-(\d{2})[ _T](\d{2}):(\d{2})/.exec(s);
        if (m)
            return m[4] + ":" + m[5];
        m = /(?:^|\D)(1\d{12})(?:\D|$)/.exec(s);
        if (m) {
            var d = new Date(Number(m[1]));
            var hh = d.getHours();
            var mi = d.getMinutes();
            return (hh < 10 ? "0" : "") + hh + ":" + (mi < 10 ? "0" : "") + mi;
        }
        return "";
    }

    function isTechnical(note) {
        if (!note)
            return false;
        var s = "" + (note.summary || "");
        if (/\.(png|jpe?g|webp)$/i.test(s) || s.indexOf("notify-send") >= 0)
            return true;
        if (/^\d{8}[_\- ]?\d{6}/.test(s))
            return true;
        return s.length > 22 && s.indexOf(" ") < 0;
    }

    // « notify-send-20261031_202801.png » → « Capture d'écran 20:28 ».
    function humanTitle(note) {
        if (!note)
            return "";
        var t = "" + (note.summary || "");
        var blob = ("" + note.app) + " " + t + " " + ("" + (note.body || ""))
                   + " " + ("" + (note.icon || ""));
        var shot = /screenshot|capture/i.test(blob) || /\.(png|jpe?g|webp)/i.test(blob);
        var hhmm = nt.noteTime(note);
        if (shot)
            return hhmm.length > 0 ? "Capture d'écran " + hhmm : "Capture d'écran";
        // Chaîne technique (nom de fichier, identifiant) : jamais affichée telle
        // quelle — titre humain si un horodatage est lisible, sinon générique.
        if (nt.isTechnical(note))
            return hhmm.length > 0 ? "Capture d'écran " + hhmm : "Notification";
        return t.length > 0 ? t : "Notification";
    }

    // Le corps réel, débarrassé d'un nom de fichier en tête.
    function humanBody(note) {
        if (!note)
            return "";
        var b = "" + (note.body || "");
        b = b.replace(/^\s*[\w.\-]+\.(png|jpe?g|webp)\s*[—–-]?\s*/i, "");
        if (/^[\w.\-]+\.(png|jpe?g|webp)$/i.test(b))
            return "";
        return b;
    }

    // Les n plus récentes (visibles d'abord, puis historique — tri serveur).
    function latest(n) {
        var k = Math.max(1, Math.round(n || 3));
        return nt.items.slice(0, k);
    }

    function apply(d) {
        if (!d || typeof d !== "object") {
            if (d === null)
                nt.lastError = "serveur muet — notifications précédentes conservées";
            return;
        }
        nt.items = Array.isArray(d.items) ? d.items : [];
        nt.count = (typeof d.count === "number") ? d.count : nt.items.length;
        nt.activeCount = (typeof d.activeCount === "number") ? d.activeCount : 0;
        nt.available = d.available === true;
        nt.running = d.running === true;
        nt.ok = d.ok === true;
        if (typeof d.install === "string" && d.install.length > 0)
            nt.install = d.install;
        nt.lastError = nt.ok ? "" : (d.error || "mako indisponible");
    }

    function refresh() {
        Api.get("/api/notifications", function (d) {
            nt.polls += 1;
            nt.apply(d);
        });
    }

    function afterAction(d) {
        nt.posts += 1;
        nt.apply(d);
    }

    function dismissAll() {
        Api.post("/api/notifications", { op: "dismiss-all" }, nt.afterAction);
    }

    function dismiss(id) {
        if (id === undefined || id === null)
            return;
        Api.post("/api/notifications", { op: "dismiss", id: id }, nt.afterAction);
    }

    // 4 s : une notification peut arriver à tout moment ; makoctl list -j est
    // bon marché (un process, deux au total avec l'historique).
    property Timer pollTimer: Timer {
        interval: 4000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: nt.refresh()
    }
}
