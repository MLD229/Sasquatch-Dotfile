// Music.qml — singleton : état du lecteur + spectre cava (brief v1b).
//
// Règles :
//   - un widget Média ne fait AUCUN XMLHttpRequest : il lit Music (brief §2) ;
//   - /api/music/status toutes les 1 s ;
//   - /api/viz toutes les 60 ms SEULEMENT si un cava est visible : chaque
//     widget qui affiche un cava s'enregistre (`wantViz(key, true)`) et se
//     désenregistre quand il cache son cava ; le timer ne tourne que si au
//     moins un cava est visible ET que la surface n'est pas cachée ;
//   - surface cachée (fond d'écran masqué, CC fermé) : les deux timers
//     s'arrêtent, et l'état est relu dès le retour de la surface.
pragma Singleton
import QtQuick
import Sasquatch.Widgets 1.0

QtObject {
    id: music

    // ── État brut du serveur ──────────────────────────────────────────────
    property var status: ({})
    property var vizVals: []
    property var sources: []
    property string pinned: ""
    property string lastError: ""
    property int statusPolls: 0
    property int vizPolls: 0

    // ── État dérivé (ce que lisent les widgets) ───────────────────────────
    readonly property string source: (music.status && typeof music.status.source === "string")
                                      ? music.status.source : "none"
    readonly property string player: (music.status && typeof music.status.player === "string")
                                      ? music.status.player : ""
    readonly property bool playing: !!(music.status && music.status.playing === true)
    readonly property bool paused: !!(music.status && music.status.paused === true)
    readonly property string title: (music.status && typeof music.status.title === "string")
                                    ? music.status.title : ""
    readonly property string artist: (music.status && typeof music.status.artist === "string")
                                     ? music.status.artist : ""
    readonly property string album: (music.status && typeof music.status.album === "string")
                                    ? music.status.album : ""
    readonly property bool hasTrack: music.title.length > 0
    readonly property real elapsed: (music.status && typeof music.status.elapsed === "number")
                                    ? music.status.elapsed : 0
    readonly property real duration: (music.status && typeof music.status.duration === "number")
                                     ? music.status.duration : 0
    readonly property real progress: {
        if (music.duration <= 0)
            return 0;
        return Math.max(0, Math.min(1, music.elapsed / music.duration));
    }

    // Pochette : le serveur renvoie déjà un chemin relatif (/albumart?...).
    readonly property string artPath: (music.status && typeof music.status.art === "string")
                                      ? music.status.art : ""
    readonly property string artUrl: (music.artPath.length === 0) ? ""
                                     : (music.artPath.charAt(0) === "/" ? Api.base + music.artPath
                                                                        : music.artPath)

    // ── Vocabulaire : jamais « MPRIS » / « Pulse » à l'écran (spec copy §1)
    // Un lecteur se nomme par ce que l'utilisateur voit : « Brave », « MPD »,
    // « Audio système ». `kind` vient du serveur, `detail` porte le nom brut.
    function prettyName(s) {
        var t = ("" + (s || "")).replace(/\.desktop$/i, "").replace(/[._-]+/g, " ").trim();
        if (t.length === 0)
            return "";
        return t.charAt(0).toUpperCase() + t.slice(1);
    }

    function readerLabel(kind, detail) {
        switch (kind) {
        case "mpris":
            var n = music.prettyName(detail);
            return n.length > 0 ? n : "Lecteur";
        case "mpd":
            return "MPD";
        case "pulse":
            return "Audio système";
        case "web":
            return "Navigateur";
        }
        return "Aucun lecteur";
    }

    // État d'une source en français, jamais `playing` / `idle`.
    function stateLabel(state) {
        switch ("" + state) {
        case "playing":
            return "en lecture";
        case "paused":
            return "en pause";
        case "idle":
            return "prêt";
        case "stopped":
            return "arrêté";
        }
        return "";
    }

    // Nom du lecteur actif (pilule du widget média).
    readonly property string sourceLabel: music.readerLabel(music.source, music.player)
    readonly property string sourceDetail: (music.player.length > 0) ? music.prettyName(music.player)
                                                                   : music.sourceLabel

    // Menu de choix des sources : noms humains + état, « Auto » en tête.
    readonly property var sourceChoices: {
        var out = [];
        var list = music.sources || [];
        for (var i = 0; i < list.length; ++i) {
            var s = list[i];
            if (!s)
                continue;
            var label = music.readerLabel(s.kind, s.detail);
            var st = music.stateLabel(s.state);
            out.push({ name: "" + s.name, label: label,
                       detail: st.length > 0 ? st : "" });
        }
        return out;
    }

    function clock(seconds) {
        var s = Math.max(0, Math.floor(seconds || 0));
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    // ── Cava : enregistrement des visualiseurs visibles ────────────────────
    // Clé = identité stable du widget (instanceId + rôle). `wantViz` est
    // idempotent : un widget peut l'appeler à chaque changement de visibilité.
    property var vizKeys: ({})
    property int vizRefs: 0
    // Surfaces d'accueil visibles (clé = hôte). Aucune surface enregistrée =
    // on sonde quand même (un hôte qui n'appelle pas setSurface garde
    // l'ancien comportement).
    property var surfaceKeys: ({})
    property int surfaceTotal: 0
    property int surfaceShown: 0
    readonly property bool surfaceVisible: (music.surfaceTotal === 0) ? true : (music.surfaceShown > 0)
    readonly property bool vizActive: music.vizRefs > 0 && music.surfaceVisible

    function _count(map) {
        var n = 0;
        for (var k in map)
            n += 1;
        return n;
    }

    function setSurface(key, on) {
        var k = "" + key;
        var m = music.surfaceKeys;
        if (m[k] === !!on)
            return;
        var copy = {};
        for (var a in m)
            copy[a] = m[a];
        copy[k] = !!on;
        var shown = 0;
        for (var b in copy) {
            if (copy[b])
                shown += 1;
        }
        music.surfaceKeys = copy;
        music.surfaceTotal = music._count(copy);
        music.surfaceShown = shown;
    }

    function wantViz(key, on) {
        var k = "" + key;
        var m = music.vizKeys;
        var has = m[k] === true;
        if (on && !has) {
            var copy = {};
            for (var a in m)
                copy[a] = m[a];
            copy[k] = true;
            music.vizKeys = copy;
        } else if (!on && has) {
            var copy2 = {};
            for (var b in m) {
                if (b !== k)
                    copy2[b] = m[b];
            }
            music.vizKeys = copy2;
        } else {
            return;
        }
        music.vizRefs = music._count(music.vizKeys);
    }

    // ── Sondes ────────────────────────────────────────────────────────────
    function pollStatus() {
        Api.get("/api/music/status", function (d) {
            music.statusPolls += 1;
            if (d && typeof d === "object" && typeof d.source === "string") {
                music.status = d;
                music.lastError = "";
            } else {
                music.lastError = "status indisponible — état précédent conservé";
            }
        });
    }

    function pollViz() {
        Api.get("/api/viz", function (d) {
            music.vizPolls += 1;
            if (d && Array.isArray(d.vals))
                music.vizVals = d.vals;
        });
    }

    function refreshSources() {
        Api.get("/api/music/sources", function (d) {
            if (d && Array.isArray(d.sources)) {
                music.sources = d.sources;
                music.pinned = (typeof d.pinned === "string") ? d.pinned : "";
            }
        });
    }

    // Épinglage : "" = retour à l'auto (le serveur persiste dans
    // ~/.config/cc/music.json et active_source() le respecte).
    function pinSource(name) {
        Api.post("/api/music/source", { name: "" + name }, function (d) {
            if (!d || d.ok !== true) {
                music.lastError = (d && d.error) ? d.error : "épinglage refusé";
                return;
            }
            music.pinned = (typeof d.pinned === "string") ? d.pinned : "";
            if (Array.isArray(d.sources))
                music.sources = d.sources;
            music.lastError = "";
            music.pollStatus();
        });
    }

    // ── Transport (le widget appelle Music, jamais XHR — brief §2) ────────
    function toggle() {
        Api.post("/api/music/toggle", {}, function () {
            music.actionTimer.restart();
        });
    }

    function next() {
        Api.post("/api/music/next", {}, function () {
            music.actionTimer.restart();
        });
    }

    function prev() {
        Api.post("/api/music/prev", {}, function () {
            music.actionTimer.restart();
        });
    }

    // ── Timers ────────────────────────────────────────────────────────────
    // 1 s : le statut (arrêté quand la surface est cachée).
    property Timer statusTimer: Timer {
        interval: 1000
        repeat: true
        running: music.surfaceVisible
        triggeredOnStart: true
        onTriggered: music.pollStatus()
    }

    // 60 ms : le spectre, uniquement si un cava est visible.
    property Timer vizTimer: Timer {
        interval: 60
        repeat: true
        running: music.vizActive
        onTriggered: music.pollViz()
    }

    // Riposte d'un transport : le serveur renvoie l'état, relu juste après.
    property Timer actionTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: music.pollStatus()
    }

    // Liste des sources (pilule) : rafraîchie lentement, elle bouge peu.
    property Timer sourcesTimer: Timer {
        interval: 5000
        repeat: true
        running: music.surfaceVisible
        triggeredOnStart: true
        onTriggered: music.refreshSources()
    }

    onSurfaceVisibleChanged: {
        if (music.surfaceVisible)
            music.pollStatus();
    }
}
