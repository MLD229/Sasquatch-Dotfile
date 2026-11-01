// state-tests.qml — relève l'ÉTAT que lit le widget `toggles`, pour le
// comparer à la réponse HTTP (polish.sh §11). L'interrupteur ne porte pas de
// texte : on prouve donc que la valeur relue par Modes.flag() est exactement
// celle que le serveur vient de renvoyer dans `real`.
//
// Sortie : `STATE modes {"dnd":false,"blur":false,"bluesun":false,"lite":true}`
import QtQuick
import Quickshell
import Sasquatch.Widgets 1.0

ShellRoot {
    id: root

    // Force l'instanciation du singleton au chargement (sinon il n'est créé
    // qu'au premier appel et la première sonde n'a pas encore répondu).
    readonly property bool primed: Modes.env.hyprland === true || Modes.env.hyprland === false

    property int waited: 0

    function emit() {
        var out = {};
        var keys = ["dnd", "blur", "bluesun", "lite"];
        for (var i = 0; i < keys.length; ++i)
            out[keys[i]] = Modes.flag(keys[i]);
        console.log("STATE modes " + JSON.stringify(out));
        console.log("STATE volume " + Env.volume + " " + Env.muted + " " + Env.brightness);
        console.log("STATE battery " + Env.batteryPct + " " + Env.batteryState);
        Qt.quit();
    }

    Timer {
        id: poll
        interval: 400
        repeat: true
        running: true
        onTriggered: {
            root.waited += 400;
            var any = Modes.flag("dnd") !== null || Modes.flag("blur") !== null
                      || Modes.flag("bluesun") !== null || Modes.flag("lite") !== null;
            if (any || root.waited >= 8000) {
                poll.running = false;
                root.emit();
            }
        }
    }
}
