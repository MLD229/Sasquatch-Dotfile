// Settings.qml — module 9 : engrenage → SASQUATCH SETTINGS (le vrai panneau).
//
// Brief v2 §6 : l'ancien bouton lançait ~/.config/cc/cc.sh (Control Center),
// ce n'est PAS le panneau de réglages. Le panneau du dotfile est
// ~/.config/settings/settings.sh (fenêtre « Sasquatch Settings », backend
// HTTP 8770, raccourci Super+I) : c'est lui qui écrit keybinds-user.conf,
// settings.json, hypridle.conf. Le Control Center reste accessible ailleurs
// (Super+E / rofi), il n'est simplement plus derrière cet engrenage.
//
// Lancement par `hyprctl dispatch exec` : Hyprland étend ~ (le chemin reste
// lisible) et détache le processus de la barre. Le script est un TOGGLE : si
// le panneau est déjà ouvert, ce clic le ferme — c'est voulu.
import QtQuick
import Quickshell
import Quickshell.Io
import "../qml"

Item {
    id: mod

    readonly property string target: "~/.config/settings/settings.sh"
    // Chemin absolu pour le test d'existence (le shell n'étend pas ~).
    readonly property string absTarget: Quickshell.env("HOME")
                                        + "/.config/settings/settings.sh"

    property bool missing: false
    property bool failed: false

    implicitHeight: Config.caseH
    // Carré dans les deux orientations : une case de Config.block.
    implicitWidth: Config.block
    width: Config.block

    IconButton {
        name: "settings"
        anchors.centerIn: parent
        glyph: "\uf013"
        glyphSize: Config.iconSize
        clickable: !mod.missing
        dimmed: mod.missing || mod.failed
        glyphColor: (mod.missing || mod.failed) ? BarPalette.hot : BarPalette.text
        tipText: mod.missing
                 ? "Sasquatch Settings introuvable (" + mod.target + ")"
                 : (mod.failed ? "Sasquatch Settings : échec du lancement (voir journal)"
                               : "Réglages (Super+I)")
        onClicked: mod.openSettings()
    }

    Process {
        id: whichProc
        command: ["/usr/bin/test", "-x", mod.absTarget]
        onExited: function (code, status) {
            mod.missing = (code !== 0);
            if (mod.missing)
                console.warn("bar: " + mod.target + " absent ou non exécutable");
        }
    }

    Process {
        id: setProc
        command: ["/usr/bin/hyprctl", "dispatch", "exec", "~/.config/settings/settings.sh"]
        onExited: function (code, status) {
            mod.failed = (code !== 0);
            if (mod.failed) {
                console.warn("bar: hyprctl dispatch exec settings.sh → code " + code);
                Quickshell.execDetached(["notify-send", "-a", "Barre Sasquatch", "-t", "4000",
                                         "Barre Sasquatch",
                                         "Sasquatch Settings n'a pas pu être lancé (code "
                                         + code + ")"]);
            }
        }
    }

    function openSettings() {
        if (mod.missing) {
            Quickshell.execDetached(["notify-send", "-a", "Barre Sasquatch", "-t", "4000",
                                     "Barre Sasquatch",
                                     "Sasquatch Settings introuvable : " + mod.target]);
            return;
        }
        if (setProc.running)
            return;
        setProc.running = true;
    }

    Component.onCompleted: {
        whichProc.running = true;
        Ui.registerAction("settings", function () { mod.openSettings() });
    }
}
