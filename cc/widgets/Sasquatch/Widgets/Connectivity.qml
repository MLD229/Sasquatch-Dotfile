// Connectivity.qml — singleton : réseau + Bluetooth + périphérique audio
// (widget `connectivity`, brief v1d).
//
// Trois sources, trois niveaux de dégradation — jamais de crash :
//   1. réseau   → Quickshell.Networking, chargé via NetProbe.qml SI le module
//                 existe sur le disque. Backend absent (ex. iwd, pas de
//                 NetworkManager) → état « backend indisponible » explicite,
//                 plus un repli lu dans `ip -br link` (vraies interfaces).
//   2. Bluetooth → Quickshell.Bluetooth via BtProbe.qml, même condition.
//                 BlueZ répond en ~1-2 s : les propriétés sont des liaisons.
//   3. audio    → `wpctl status` (parse du bloc Audio, entrée marquée `*`).
//                 wpctl absent → audioOk faux, le widget affiche la commande
//                 d'installation.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Sasquatch.Widgets 1.0

QtObject {
    id: conn

    // ── Modules présents ? (test fichier, pas d'import risqué ici) ────────
    property bool checked: false
    property bool hasNetworking: false
    property bool hasBluetooth: false
    property bool hasWpctl: false
    property string probeError: ""

    property var netProbe: null
    property var btProbe: null

    // ── Audio (wpctl status) ──────────────────────────────────────────────
    property bool audioOk: false
    property string sinkName: ""
    property int sinkVolume: -1
    property bool sinkMuted: false
    property string sourceName: ""
    property int sourceVolume: -1

    // ── Repli réseau quand Quickshell.Networking ne peut pas travailler ───
    // Lu dans `ip -br link`. Marqué « repli » par le widget : ce n'est pas la
    // même source que Networking, on ne fait pas semblant.
    property var ifaces: []

    // ── Réseau : ce que lit le widget ─────────────────────────────────────
    readonly property bool netModule: conn.hasNetworking && conn.netProbe !== null
    readonly property bool netReady: conn.netModule && conn.netProbe !== null && conn.netProbe.ready
    readonly property string netBackend: conn.netModule && conn.netProbe !== null
                                         ? conn.netProbe.backendLabel : "module absent"
    readonly property var netDevices: conn.netModule && conn.netProbe !== null
                                      ? conn.netProbe.devices : []
    readonly property var netActive: conn.netModule && conn.netProbe !== null
                                     ? conn.netProbe.active : null
    readonly property string netConnLabel: conn.netModule && conn.netProbe !== null
                                           ? conn.netProbe.connectivityLabel() : "indisponible"
    readonly property bool wifiOn: conn.netModule && conn.netProbe !== null
                                   && conn.netProbe.wifiEnabled
    // Ligne principale : SSID / interface filaire / repli / indisponible.
    readonly property string netMain: {
        if (conn.netReady && conn.netActive !== null) {
            var a = conn.netActive;
            if (a.kind === "wifi")
                return (a.ssid.length > 0) ? a.ssid : a.name;
            return a.name;
        }
        if (conn.netReady)
            return "aucune interface connectée";
        var f = conn.firstIface();
        if (f !== null)
            return f.name + " (" + f.state.toLowerCase() + ") · repli ip";
        return conn.hasNetworking ? "backend réseau indisponible" : "module Networking absent";
    }
    readonly property string netSub: {
        if (conn.netReady)
            return conn.netBackend + " · " + conn.netConnLabel;
        return conn.hasNetworking ? "NetworkManager requis" : "Quickshell.Networking non installé";
    }

    function firstIface() {
        for (var i = 0; i < conn.ifaces.length; ++i) {
            if (conn.ifaces[i].up)
                return conn.ifaces[i];
        }
        return conn.ifaces.length > 0 ? conn.ifaces[0] : null;
    }

    // ── Bluetooth : ce que lit le widget ──────────────────────────────────
    readonly property bool btModule: conn.hasBluetooth && conn.btProbe !== null
    readonly property bool btPresent: conn.btModule && conn.btProbe !== null && conn.btProbe.present
    readonly property bool btOn: conn.btPresent && conn.btProbe.enabled
    readonly property int btConnected: conn.btPresent ? conn.btProbe.connectedCount : 0
    readonly property string btStateLabel: !conn.hasBluetooth ? "module absent"
                                          : (conn.btProbe === null ? "chargement…"
                                             : conn.btProbe.stateLabel())
    readonly property string btMain: {
        if (!conn.btPresent)
            return "aucun adaptateur";
        var d = conn.btProbe.firstConnected;
        if (d !== null)
            return d.name;
        return conn.btOn ? (conn.btProbe.adapterName.length > 0 ? conn.btProbe.adapterName
                                                                : "activé") : "désactivé";
    }
    readonly property string btSub: {
        if (!conn.hasBluetooth)
            return "Quickshell.Bluetooth non installé";
        if (!conn.btPresent)
            return "bluez absent ?";
        if (conn.btConnected > 0)
            return conn.btConnected + " connecté" + (conn.btConnected > 1 ? "s" : "");
        return conn.btProbe.stateLabel();
    }

    // ── Audio : ce que lit le widget ──────────────────────────────────────
    readonly property string audioMain: conn.audioOk && conn.sinkName.length > 0
                                        ? conn.sinkName : "périphérique inconnu"
    readonly property string audioSub: {
        if (!conn.hasWpctl)
            return "wpctl non installé";
        if (!conn.audioOk)
            return "PipeWire indisponible";
        var v = (conn.sinkVolume >= 0) ? (conn.sinkVolume + "%") : "vol ?";
        return conn.sinkMuted ? (v + " · muet") : v;
    }

    // ── Chargement des sondes ─────────────────────────────────────────────
    function loadProbes() {
        if (conn.hasNetworking && conn.netProbe === null)
            conn.netProbe = conn._make("NetProbe.qml");
        if (conn.hasBluetooth && conn.btProbe === null)
            conn.btProbe = conn._make("BtProbe.qml");
    }

    // Création dynamique : un import cassé donne Component.Error, pas un
    // shell mort. L'erreur est conservée et affichée, l'objet reste null.
    function _make(file) {
        var comp = Qt.createComponent(Qt.resolvedUrl(file));
        if (comp.status !== Component.Ready) {
            conn.probeError = file + ": " + comp.errorString();
            return null;
        }
        var obj = comp.createObject(conn);
        if (!obj) {
            conn.probeError = file + ": création refusée";
            return null;
        }
        return obj;
    }

    function applyProbe(txt) {
        var lines = ("" + (txt || "")).split("\n");
        for (var i = 0; i < lines.length; ++i) {
            var l = lines[i].trim();
            if (l === "net")
                conn.hasNetworking = true;
            else if (l === "bt")
                conn.hasBluetooth = true;
            else if (l === "wpctl")
                conn.hasWpctl = true;
        }
        conn.checked = true;
        conn.loadProbes();
    }

    // ── Parse `wpctl status` ──────────────────────────────────────────────
    // Blocs « Sinks: » / « Sources: » : la ligne marquée `*` est le défaut.
    //   │  *   52. Audio interne Stéréo analogique   [vol: 0.51]
    function applyWpctl(txt) {
        var lines = ("" + (txt || "")).split("\n");
        var section = "";
        var found = false;
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i].trim();
            if (line.length === 0)
                continue;
            if (line.indexOf("Sinks:") >= 0) {
                section = "sink";
                continue;
            }
            if (line.indexOf("Sources:") >= 0) {
                section = "source";
                continue;
            }
            if (line.indexOf("Filters:") >= 0 || line.indexOf("Devices:") >= 0
                    || line.indexOf("Clients:") >= 0) {
                section = "";
                continue;
            }
            // La ligne par défaut commence par le glyphe d'arbre puis « * » :
            // « │  *   52. Audio interne … ». On teste le * où qu'il soit en tête.
            if ((section !== "sink" && section !== "source") || !/^\W*\*/.test(line))
                continue;
            var s = line.replace(/^[^*]*\*/, "").replace(/^\s*\d+\.\s*/, "");
            var vol = -1;
            var m = /\[vol:\s*([0-9.]+)\]/.exec(s);
            if (m)
                vol = Math.round(parseFloat(m[1]) * 100);
            var muted = s.indexOf("[MUTED]") >= 0;
            s = s.replace(/\[[^\]]*\]/g, "").replace(/\s+/g, " ").trim();
            if (section === "sink") {
                conn.sinkName = s;
                conn.sinkVolume = vol;
                conn.sinkMuted = muted;
            } else {
                conn.sourceName = s;
                conn.sourceVolume = vol;
            }
            found = true;
        }
        conn.audioOk = found;
    }

    // ── Parse `ip -br link` (repli) ───────────────────────────────────────
    // Le nom et l'état réels des interfaces ; on écarte le bruit (lo, ponts,
    // veth, tailscale) pour ne garder que ce qui ressemble à une vraie carte.
    function applyIfaces(txt) {
        var lines = ("" + (txt || "")).split("\n");
        var out = [];
        for (var i = 0; i < lines.length; ++i) {
            var f = lines[i].trim().split(/\s+/);
            if (f.length < 2)
                continue;
            var name = f[0];
            if (name === "lo" || name.indexOf("docker") === 0 || name.indexOf("br-") === 0
                    || name.indexOf("veth") === 0 || name.indexOf("tailscale") === 0)
                continue;
            out.push({ name: name, state: f[1], up: f[1] === "UP" });
        }
        conn.ifaces = out;
    }

    // ── Sondes système ────────────────────────────────────────────────────
    property Process checkProc: Process {
        command: ["/bin/sh", "-c",
                  "test -f /usr/lib/qt6/qml/Quickshell/Networking/qmldir && echo net; " +
                  "test -f /usr/lib/qt6/qml/Quickshell/Bluetooth/qmldir && echo bt; " +
                  "command -v wpctl >/dev/null 2>&1 && echo wpctl"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: conn.applyProbe(this.text || "")
        }
    }

    property Process wpctlProc: Process {
        command: ["wpctl", "status"]
        stdout: StdioCollector {
            onStreamFinished: conn.applyWpctl(this.text || "")
        }
    }

    property Process ipProc: Process {
        command: ["ip", "-br", "link"]
        stdout: StdioCollector {
            onStreamFinished: conn.applyIfaces(this.text || "")
        }
    }

    property Timer audioTimer: Timer {
        interval: 8000
        repeat: true
        running: conn.hasWpctl
        triggeredOnStart: true
        onTriggered: {
            if (!conn.wpctlProc.running)
                conn.wpctlProc.running = true;
        }
    }

    // 10 s : uniquement tant que le repli sert (module absent ou backend muet).
    property Timer ipTimer: Timer {
        interval: 10000
        repeat: true
        running: conn.checked && !conn.netReady
        triggeredOnStart: true
        onTriggered: {
            if (!conn.ipProc.running)
                conn.ipProc.running = true;
        }
    }
}
