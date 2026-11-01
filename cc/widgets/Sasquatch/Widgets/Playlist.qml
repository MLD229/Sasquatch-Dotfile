// Playlist.qml — singleton : file d'attente MPD (brief v1d, widget `playlist`).
//
// Le widget ne fait AUCUN XMLHttpRequest (contrat §2) : il lit Playlist et
// appelle ses actions. Les formes de charge utile sont celles du serveur, pas
// devinées :
//   GET /api/playlist/status → {ok, state, random, repeat, single, consume,
//                               volume, song, playlistlength, elapsed, duration}
//   GET /api/playlist/list   → {ok, tracks: [{pos, file, title, artist, album,
//                                            duration, current}]}
//   POST /api/playlist/play   {pos}
//   POST /api/playlist/remove {pos}
//   POST /api/playlist/shuffle / playtoggle / next / prev  {}
// Toute action relit le serveur (250 ms) : l'affichage suit MPD, jamais une
// supposition optimiste. MPD injoignable → ok reste faux, aucune exception.
pragma Singleton
import QtQuick
import Sasquatch.Widgets 1.0

QtObject {
    id: pl

    property var status: ({})
    property var tracks: []
    property bool ok: false
    property string lastError: ""
    property int polls: 0
    property int posts: 0

    // ── État dérivé ───────────────────────────────────────────────────────
    readonly property bool mpdOk: !!(pl.status && pl.status.ok === true)
    readonly property string state: (pl.mpdOk && typeof pl.status.state === "string")
                                    ? pl.status.state : "stop"
    readonly property bool playing: pl.state === "play"
    readonly property bool paused: pl.state === "pause"
    readonly property bool shuffleOn: !!(pl.mpdOk && pl.status.random === true)
    readonly property int count: pl.tracks.length
    readonly property int declaredCount: (pl.mpdOk && typeof pl.status.playlistlength === "number")
                                         ? pl.status.playlistlength : pl.count
    readonly property int currentPos: {
        if (!pl.mpdOk)
            return -1;
        for (var i = 0; i < pl.tracks.length; ++i) {
            if (pl.tracks[i] && pl.tracks[i].current === true)
                return pl.tracks[i].pos;
        }
        return (typeof pl.status.song === "number") ? pl.status.song : -1;
    }

    function fmt(sec) {
        var s = Math.max(0, Math.round(sec || 0));
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    // ── Lecture ───────────────────────────────────────────────────────────
    function applyStatus(d) {
        if (d && typeof d === "object") {
            pl.status = d;
            pl.ok = d.ok === true;
            pl.lastError = pl.ok ? "" : (d.error || "MPD injoignable");
        } else if (d === null) {
            pl.ok = false;
            pl.lastError = "serveur muet — file précédente conservée";
        }
    }

    function applyList(d) {
        if (d && Array.isArray(d.tracks)) {
            pl.tracks = d.tracks;
            return;
        }
        if (d === null)
            pl.lastError = "liste indisponible — file précédente conservée";
    }

    function refresh() {
        Api.get("/api/playlist/status", function (d) {
            pl.polls += 1;
            pl.applyStatus(d);
        });
        Api.get("/api/playlist/list", function (d) {
            pl.applyList(d);
        });
    }

    // ── Actions (POST puis relecture) ─────────────────────────────────────
    function _afterAction(d) {
        pl.posts += 1;
        if (d && typeof d === "object") {
            if (d.ok === false)
                pl.lastError = d.error || "action refusée";
            else
                pl.lastError = "";
        }
        pl.actionTimer.restart();
    }

    function play(pos) {
        Api.post("/api/playlist/play", { pos: pos }, pl._afterAction);
    }

    function remove(pos) {
        Api.post("/api/playlist/remove", { pos: pos }, pl._afterAction);
    }

    function shuffle() {
        Api.post("/api/playlist/shuffle", {}, pl._afterAction);
    }

    function toggle() {
        Api.post("/api/playlist/playtoggle", {}, pl._afterAction);
    }

    function next() {
        Api.post("/api/playlist/next", {}, pl._afterAction);
    }

    function prev() {
        Api.post("/api/playlist/prev", {}, pl._afterAction);
    }

    // ── Sondes ────────────────────────────────────────────────────────────
    // 2 s : la file peut bouger côté MPD (ajout d'un dossier, fin de piste).
    property Timer pollTimer: Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: pl.refresh()
    }

    property Timer actionTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: pl.refresh()
    }
}
