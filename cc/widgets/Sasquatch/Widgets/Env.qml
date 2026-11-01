// Env.qml — singleton : environnement local partagé par tous les widgets.
//
// Brief v1a §7.1 : « Env (horloge locale ok) ». Les autres sondes du brief
// (météo 10 min, stats 2 s, tâches 5 s, batterie) sont déjà branchées ici pour
// que les widgets de v1d n'aient aucun timer à créer : un widget LIT, il ne
// sonde pas.
// Aucun widget n'ouvre de requête : tout passe par Api.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Sasquatch.Widgets 1.0

QtObject {
    id: env

    // ── Horloge locale (une seule source de temps pour tout le shell) ─────
    property date now: new Date()
    property int tick: 0

    // ── Données distantes ────────────────────────────────────────────────
    property var weather: ({})
    property var stats: ({})
    property var tasks: ({ items: [], total: 0, done: 0 })
    property bool tasksOk: false
    // Compteurs de sondes : un widget distingue « chargement » (0 sonde
    // revenue) de « indisponible » (sonde revenue vide). Aucune invention.
    property int weatherPolls: 0
    property int statsPolls: 0
    property int tasksPolls: 0
    property int soundPolls: 0
    property int batteryPolls: 0

    // ── Noms de jours / mois (français, sans dépendre de la locale du
    // processus : une session lancée par systemd/cron hérite souvent de LANG=C).
    readonly property var dayShort: ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
    readonly property var monthShort: ["janv.", "févr.", "mars", "avr.", "mai", "juin",
                                       "juil.", "août", "sept.", "oct.", "nov.", "déc."]
    // Mois en toutes lettres : le sous-titre du calendrier dit « novembre 2026 ».
    readonly property var monthLong: ["janvier", "février", "mars", "avril", "mai", "juin",
                                      "juillet", "août", "septembre", "octobre", "novembre",
                                      "décembre"]

    // ── Batterie (portable : BAT0 existe, brief §0.5) ─────────────────────
    // Lecture directe de sysfs (aucune route API n'existe pour ça) via un
    // Process : capacity / status / power_now / energy_now / energy_full.
    // Machine sans BAT0 : toutes les valeurs restent neutres, jamais de crash.
    property int batteryPct: -1
    property string batteryState: ""
    property real batteryPower: 0        // µW (0 = inconnu ou absent)
    property real batteryEnergy: 0       // µWh
    property real batteryEnergyFull: 0   // µWh

    readonly property bool charging: env.batteryState === "Charging" || env.batteryState === "Full"
    readonly property bool batteryKnown: env.batteryPct >= 0
    readonly property real batteryWatts: env.batteryPower / 1000000
    // Autonomie estimée (min) : uniquement si la consommation est mesurée.
    readonly property int batteryMinutes: (env.batteryPower > 0 && env.batteryEnergy > 0)
                                          ? Math.round(env.batteryEnergy / env.batteryPower * 60) : -1

    // ── Son (wpctl) + luminosité (brightnessctl) ──────────────────────────
    // -1 = inconnu (serveur muet) : les sliders restent inertes, pas de saut.
    property int volume: -1
    property bool muted: false
    property int brightness: -1

    // ── Horloge ───────────────────────────────────────────────────────────
    property Timer clockTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            env.now = new Date();
            env.tick += 1;
        }
    }

    // ── Sondes ────────────────────────────────────────────────────────────
    function pollWeather() {
        Api.get("/api/weather", function (d) {
            env.weatherPolls += 1;
            if (d && typeof d === "object")
                env.weather = d;
        });
    }

    function pollStats() {
        Api.get("/api/stats", function (d) {
            env.statsPolls += 1;
            if (d && typeof d === "object")
                env.stats = d;
        });
    }

    function pollTasks() {
        Api.get("/api/tasks", function (d) {
            env.tasksPolls += 1;
            if (d && typeof d === "object") {
                env.tasks = d;
                env.tasksOk = true;
            } else {
                env.tasksOk = false;
            }
        });
    }

    // ── Actions tâches (POST /api/tasks) ──────────────────────────────────
    // Format exact du serveur : {action: "add"|"toggle"|"remove"|"clear"}.
    // La réponse est la liste complète : on la pose telle quelle (aucune
    // écriture locale, la vérité reste le fichier du serveur).
    function applyTasks(d) {
        if (d && Array.isArray(d.items)) {
            env.tasks = d;
            env.tasksOk = true;
            return true;
        }
        return false;
    }

    function addTask(text) {
        var t = ("" + (text || "")).trim();
        if (t.length === 0)
            return;
        Api.post("/api/tasks", { action: "add", text: t }, function (d) {
            env.applyTasks(d);
        });
    }

    function toggleTask(id) {
        Api.post("/api/tasks", { action: "toggle", id: id }, function (d) {
            env.applyTasks(d);
        });
    }

    function removeTask(id) {
        Api.post("/api/tasks", { action: "remove", id: id }, function (d) {
            env.applyTasks(d);
        });
    }

    // ── Actions son / luminosité (POST, jamais d'écriture directe) ────────
    function pollSound() {
        Api.get("/api/system/volume", function (d) {
            env.soundPolls += 1;
            if (d && typeof d.volume === "number") {
                env.volume = Math.round(d.volume);
                env.muted = d.muted === true;
            }
        });
        Api.get("/api/system/brightness", function (d) {
            if (d && typeof d.brightness === "number")
                env.brightness = Math.round(d.brightness);
        });
    }

    // Valeur optimiste pendant le drag, puis confirmation par la réponse.
    function setVolume(v) {
        var n = Math.max(0, Math.min(100, Math.round(v)));
        env.volume = n;
        Api.post("/api/system/volume", { v: n }, function (d) {
            if (d && typeof d.volume === "number") {
                env.volume = Math.round(d.volume);
                env.muted = d.muted === true;
            }
        });
    }

    function toggleMute() {
        var m = !env.muted;
        env.muted = m;
        Api.post("/api/system/volume", { mute: m }, function (d) {
            if (d && typeof d.volume === "number") {
                env.volume = Math.round(d.volume);
                env.muted = d.muted === true;
            }
        });
    }

    function setBrightness(v) {
        var n = Math.max(0, Math.min(100, Math.round(v)));
        env.brightness = n;
        Api.post("/api/system/brightness", { v: n }, function (d) {
            if (d && typeof d.brightness === "number")
                env.brightness = Math.round(d.brightness);
        });
    }

    function readBattery(txt) {
        var lines = (txt || "").split("\n").map(function (s) {
            return s.trim();
        }).filter(function (s) {
            return s.length > 0;
        });
        function num(i) {
            var v = parseFloat(lines[i]);
            return isFinite(v) ? v : 0;
        }
        env.batteryPolls += 1;
        var pct = parseInt(lines[0], 10);
        env.batteryPct = isNaN(pct) ? -1 : pct;
        env.batteryState = lines.length > 1 ? lines[1] : "";
        env.batteryPower = (lines.length > 2) ? num(2) : 0;
        env.batteryEnergy = (lines.length > 3) ? num(3) : 0;
        env.batteryEnergyFull = (lines.length > 4) ? num(4) : 0;
    }

    property Process batteryProc: Process {
        command: ["/bin/sh", "-c",
                  "cat /sys/class/power_supply/BAT0/capacity 2>/dev/null; " +
                  "cat /sys/class/power_supply/BAT0/status 2>/dev/null; " +
                  "cat /sys/class/power_supply/BAT0/power_now 2>/dev/null; " +
                  "cat /sys/class/power_supply/BAT0/energy_now 2>/dev/null; " +
                  "cat /sys/class/power_supply/BAT0/energy_full 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: env.readBattery(this.text || "")
        }
    }

    property Timer weatherTimer: Timer {
        interval: 600000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: env.pollWeather()
    }

    property Timer statsTimer: Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: env.pollStats()
    }

    property Timer tasksTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: env.pollTasks()
    }

    // Son + luminosité : 4 s (deux GET légers), assez pour suivre un réglage
    // fait au clavier sans écraser un drag en cours (le POST confirme).
    property Timer soundTimer: Timer {
        interval: 4000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: env.pollSound()
    }

    property Timer batteryTimer: Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!env.batteryProc.running)
                env.batteryProc.running = true;
        }
    }
}
