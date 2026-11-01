// Modes.qml — singleton : toggles DND / flou / nuit / allégé (widget `toggles`).
//
// AUCUN moteur de modes ici : le serveur CC expose GET/POST /api/modes et
// délègue à cc/sidebar/modes.py (moteur unique, partagé avec la sidebar).
// Ce singleton ne fait que lire et poster.
//
// Charge utile (cc/server.py) :
//   GET  /api/modes → {ok, modes{}, real{dnd,blur,animations,shadow,hyprland,
//                        bluesun,lite}, env{hyprland,hyprsunset,makoctl,...},
//                        kelvin, missing[{mode,tool,install}], state_file}
//   POST /api/modes {mode: dnd|lite|bluesun|blur, on: bool, kelvin?}
//        → même charge utile + applied{} ; `real` est l'état RELU après
//          application, c'est lui (et lui seul) que le widget affiche.
pragma Singleton
import QtQuick
import Sasquatch.Widgets 1.0

QtObject {
    id: modes

    property var state: ({})
    property bool ok: false
    property string lastError: ""
    property int polls: 0
    property int posts: 0
    // Mode en cours d'application : le widget grise la ligne, puis relit.
    property string pending: ""

    readonly property var real: (modes.state && modes.state.real) ? modes.state.real : ({})
    readonly property var env: (modes.state && modes.state.env) ? modes.state.env : ({})
    readonly property var missing: (modes.state && Array.isArray(modes.state.missing))
                                   ? modes.state.missing : []

    // État réel : true/false, ou null quand l'outil ne répond pas.
    function flag(key) {
        var v = modes.real ? modes.real[key] : null;
        return (v === true) ? true : (v === false) ? false : null;
    }

    // Disponibilité : le module existe ET l'outil répond réellement.
    function available(key) {
        if (key === "bluesun")
            return modes.env.hyprsunset === true;
        if (key === "dnd")
            return modes.env.makoctl === true && modes.flag("dnd") !== null;
        return modes.env.hyprland === true && modes.real.hyprland === true;
    }

    function installFor(key) {
        for (var i = 0; i < modes.missing.length; ++i) {
            if (modes.missing[i].mode === key)
                return modes.missing[i].install;
        }
        return "";
    }

    function apply(d) {
        if (!d || typeof d !== "object") {
            modes.lastError = "réponse muette — état précédent conservé";
            return;
        }
        modes.state = d;
        modes.ok = d.ok === true;
        modes.lastError = modes.ok ? "" : (d.error || "application refusée");
    }

    function refresh() {
        Api.get("/api/modes", function (d) {
            modes.polls += 1;
            if (d && typeof d === "object" && d.real) {
                modes.state = d;
                modes.ok = true;
                modes.lastError = "";
            } else if (d === null) {
                modes.lastError = "serveur muet — état précédent conservé";
            }
        });
    }

    // Bascule : POST, puis l'état affiché vient de la réponse (`real`), et une
    // seconde relecture confirme (un outil peut refuser silencieusement).
    function set(key, on) {
        modes.pending = key;
        modes.posts += 1;
        Api.post("/api/modes", { mode: key, on: on === true }, function (d) {
            modes.pending = "";
            modes.apply(d);
            modes.confirmTimer.restart();
        });
    }

    function toggle(key) {
        var cur = modes.flag(key);
        modes.set(key, cur !== true);
    }

    property Timer pollTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: modes.refresh()
    }

    property Timer confirmTimer: Timer {
        interval: 300
        repeat: false
        onTriggered: modes.refresh()
    }
}
