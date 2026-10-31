// Backend.qml — singleton : SEUL point d'entrée HTTP de la barre (CC 8765).
//
// Brief §5 : un timer unique (~2 s) alimente tous les modules. Aucun module
// n'ouvre de requête ni de timer : il lit les propriétés de ce singleton.
// Brief §10.11 : les routes sont GET ou POST, lues dans cc/server.py :
//   GET  /api/stats              → cpu, ram{used,total,pct}, net{up,down,iface} (Ko/s)
//   GET  /api/system/volume      → {volume, muted}          (PLAT, pas imbriqué)
//   POST /api/system/volume      {"v": 0-100} ou {"mute": bool}
//   GET  /api/system/brightness  → {brightness}
//   POST /api/system/brightness  {"v": 0-100}
//   GET  /api/music/status       → {source, playing, title, artist} (rafraîchi à la demande)
pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: be

    readonly property string apiBase: "http://127.0.0.1:8765"

    // ── État exposé ───────────────────────────────────────────────────────
    property var stats: ({})
    property var volume: ({ volume: 0, muted: false })
    property int brightness: -1
    property var music: ({ playing: false, title: null, artist: null })
    property bool ttlOk: false            // au moins une réponse /api/stats reçue
    property bool volOk: false
    property bool brightOk: false
    property bool dnd: false
    property string lastError: ""
    property var netHistory: []           // dernier débit descendant (Ko/s)

    readonly property real netUp: be.stats && be.stats.net ? (be.stats.net.up || 0) : -1
    readonly property real netDown: be.stats && be.stats.net ? (be.stats.net.down || 0) : -1
    readonly property string netIface: be.stats && be.stats.net ? (be.stats.net.iface || "") : ""
    readonly property real ramPct: be.stats && be.stats.ram ? (be.stats.ram.pct || 0) : -1
    readonly property real cpu: be.stats ? (be.stats.cpu || 0) : -1
    readonly property int volPct: be.volume ? (be.volume.volume || 0) : 0
    readonly property bool muted: be.volume ? !!be.volume.muted : false
    readonly property bool online: be.netIface.length > 0

    // ── HTTP ──────────────────────────────────────────────────────────────
    function get(path, cb) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = 3000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status < 200 || xhr.status >= 300) {
                if (cb) cb(null);
                return;
            }
            var d = null;
            try {
                d = JSON.parse(xhr.responseText);
            } catch (e) {
                d = null;
            }
            if (cb) cb(d);
        };
        xhr.open("GET", be.apiBase + path);
        xhr.send(null);
    }

    function post(path, body, cb) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = 3000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var d = null;
            try {
                d = JSON.parse(xhr.responseText);
            } catch (e) {
                d = null;
            }
            if (cb) cb(d);
        };
        xhr.open("POST", be.apiBase + path);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(JSON.stringify(body || {}));
    }

    // ── Sondes ────────────────────────────────────────────────────────────
    function pollStats() {
        be.get("/api/stats", function (d) {
            if (!d) {
                be.ttlOk = false;
                be.lastError = "stats indisponibles";
                return;
            }
            be.ttlOk = true;
            be.stats = d;
            var h = be.netHistory.slice(0);
            h.push(be.netDown);
            while (h.length > 40)
                h.shift();
            be.netHistory = h;
            be.lastError = "";
        });
    }

    function pollVolume() {
        be.get("/api/system/volume", function (d) {
            if (!d || typeof d.volume !== "number") {
                be.volOk = false;
                return;
            }
            be.volOk = true;
            be.volume = d;
        });
    }

    function pollBrightness() {
        be.get("/api/system/brightness", function (d) {
            if (!d || typeof d.brightness !== "number") {
                be.brightOk = false;
                return;
            }
            be.brightOk = true;
            be.brightness = d.brightness;
        });
    }

    function refreshMusic() {
        be.get("/api/music/status", function (d) {
            if (d) be.music = d;
        });
    }

    // DND : mako est le serveur de notifications de la session (le QML ne
    // déclare PAS de NotificationServer : deux démons se disputeraient
    // org.freedesktop.Notifications). On lit donc l'état avec makoctl.
    property Process dndProc: Process {
        command: ["makoctl", "mode"]
        stdout: StdioCollector {
            onStreamFinished: {
                var txt = this.text || "";
                be.dnd = txt.indexOf("do-not-disturb") >= 0;
            }
        }
    }
    function pollDnd() {
        if (!be.dndProc.running)
            be.dndProc.running = true;
    }
    function toggleDnd() {
        // POST-équivalent local : makoctl mode -t inverse le mode.
        be.dndProc2.running = true;
    }
    property Process dndProc2: Process {
        command: ["makoctl", "mode", "-t", "do-not-disturb"]
        onRunningChanged: if (!running) be.pollDnd()
    }

    // ── Actions ───────────────────────────────────────────────────────────
    function setVolume(v) {
        var val = Math.max(0, Math.min(100, Math.round(v)));
        be.volume = ({ volume: val, muted: be.muted });
        be.post("/api/system/volume", { v: val }, function (d) {
            if (d && typeof d.volume === "number")
                be.volume = d;
        });
    }
    function nudgeVolume(delta) {
        be.setVolume(be.volPct + delta);
    }
    function toggleMute() {
        var m = !be.muted;
        be.volume = ({ volume: be.volPct, muted: m });
        be.post("/api/system/volume", { mute: m }, function (d) {
            if (d && typeof d.volume === "number")
                be.volume = d;
        });
    }
    function setBrightness(v) {
        var val = Math.max(0, Math.min(100, Math.round(v)));
        be.brightness = val;
        be.post("/api/system/brightness", { v: val }, function (d) {
            if (d && typeof d.brightness === "number")
                be.brightness = d.brightness;
        });
    }

    // ── Timer unique (brief §5 / §10.10) ──────────────────────────────────
    property int tickCount: 0
    property Timer tick: Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            be.tickCount += 1;
            be.pollStats();
            be.pollVolume();
            if (be.tickCount % 5 === 0)   // 10 s
                be.pollBrightness();
            if (be.tickCount % 5 === 3)   // 10 s, décalé
                be.pollDnd();
        }
    }
}
