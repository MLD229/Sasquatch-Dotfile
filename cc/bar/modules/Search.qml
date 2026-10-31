// Search.qml — module 1 : loupe → LANCEUR DU DOTFILE (brief v3 §1).
//
// La v2 lançait `/usr/bin/rofi -show drun` : rofi NU, sans thème, sans le mode
// combi (apps + calculatrice) et sans le PATH corrigé pour qalc. Le lanceur du
// dotfile est ~/.config/rofi/scripts/launcher.sh (thème sasquatch.rasi) ; il
// est appelé par `hyprctl dispatch exec` (même style que le module Settings :
// chemin absolu, Process, code de sortie journalisé) pour que Hyprland détache
// le processus de la barre.
//
// Replis, dans l'ordre, tous VISIBLES :
//   1. launcher.sh présent      → hyprctl dispatch exec (thème + combi) ;
//   2. launcher.sh absent       → /usr/bin/rofi -show drun -theme sasquatch.rasi ;
//   3. ni l'un ni l'autre       → glyphe chaud + point d'alerte + infobulle
//                                 « lanceur introuvable » (jamais un clic muet).
import QtQuick
import Quickshell
import Quickshell.Io
import "../qml"

Item {
    id: mod

    implicitHeight: Config.caseH
    // Carré dans les deux orientations : une case de Config.block.
    implicitWidth: Config.block
    width: Config.block

    readonly property string launcherTilde: "~/.config/rofi/scripts/launcher.sh"
    readonly property string launcherAbs: Quickshell.env("HOME") + "/.config/rofi/scripts/launcher.sh"
    readonly property string themeAbs: Quickshell.env("HOME") + "/.config/rofi/themes/sasquatch.rasi"
    readonly property string rofiAbs: "/usr/bin/rofi"

    property bool launcherOk: false
    property bool rofiOk: false
    property bool themeOk: false
    property bool launcherProbed: false
    property bool rofiProbed: false
    property bool failed: false

    readonly property bool probed: mod.launcherProbed && mod.rofiProbed
    readonly property bool unavailable: mod.probed && !mod.launcherOk && !mod.rofiOk
    readonly property bool trouble: mod.unavailable || mod.failed

    readonly property string hint: {
        if (mod.unavailable)
            return "Lanceur introuvable (" + mod.launcherTilde + " et " + mod.rofiAbs + ")";
        if (mod.failed)
            return "Lanceur : échec au dernier clic (voir journal)";
        if (mod.launcherOk)
            return "Rechercher (Super)";
        return "Rechercher — repli rofi drun" + (mod.themeOk ? " (thème sasquatch)" : " sans thème");
    }

    IconButton {
        name: "search"
        anchors.centerIn: parent
        glyph: "\uf002"
        glyphSize: Config.iconSize
        dimmed: mod.trouble
        glyphColor: mod.trouble ? BarPalette.hot : BarPalette.text
        tipText: mod.hint
        onClicked: mod.openLauncher()
    }

    // Marqueur d'erreur visible (le point d'alerte ne dépend pas du survol).
    Rectangle {
        visible: mod.trouble
        width: 5
        height: 5
        radius: 2.5
        color: BarPalette.hot
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 5
        anchors.topMargin: 5
    }

    // ── Sondes de démarrage (aucun timer) ────────────────────────────────
    Process {
        id: testLauncher
        command: ["/usr/bin/test", "-x", mod.launcherAbs]
        onExited: function (code, status) {
            mod.launcherOk = (code === 0);
            mod.launcherProbed = true;
            mod.checkProbed();
        }
    }

    Process {
        id: testRofi
        command: ["/usr/bin/test", "-x", mod.rofiAbs]
        onExited: function (code, status) {
            mod.rofiOk = (code === 0);
            mod.rofiProbed = true;
            mod.checkProbed();
        }
    }

    Process {
        id: testTheme
        command: ["/usr/bin/test", "-f", mod.themeAbs]
        onExited: function (code, status) { mod.themeOk = (code === 0) }
    }

    function checkProbed() {
        if (!mod.probed)
            return;
        if (!mod.launcherOk && !mod.rofiOk)
            console.warn("bar: aucun lanceur (ni " + mod.launcherTilde + " ni " + mod.rofiAbs + ")");
    }

    // ── Lancement ────────────────────────────────────────────────────────
    Process {
        id: dispatchProc
        command: ["/usr/bin/true"]     // remplacée au clic
        onExited: function (code, status) {
            if (code === 0) {
                mod.failed = false;
                Hypr.note("lanceur → " + mod.launcherTilde + " (hyprctl exec)");
                return;
            }
            mod.failed = true;
            console.warn("bar: hyprctl dispatch exec launcher.sh → code " + code);
            Hypr.miss("le lanceur n'a pas pu être lancé (code " + code + ")");
        }
    }

    Process {
        id: fallbackProc
        command: ["/usr/bin/true"]     // remplacée au clic
        onExited: function (code, status) {
            // rofi reste ouvert tant qu'il tourne : un code non nul = échec réel.
            if (code !== 0) {
                mod.failed = true;
                console.warn("bar: rofi (repli) → code " + code);
                Hypr.miss("rofi (repli) a échoué (code " + code + ")");
            } else {
                mod.failed = false;
                Hypr.note("lanceur → repli rofi drun");
            }
        }
    }

    function openLauncher() {
        if (mod.probed && mod.unavailable) {
            Hypr.miss("lanceur introuvable : " + mod.launcherTilde
                      + " et " + mod.rofiAbs + " sont absents");
            return;
        }
        if (mod.launcherOk) {
            if (dispatchProc.running)
                return;
            dispatchProc.command = ["/usr/bin/hyprctl", "dispatch", "exec", mod.launcherTilde];
            dispatchProc.running = true;
            return;
        }
        if (fallbackProc.running)
            return;
        fallbackProc.command = mod.themeOk
                ? [mod.rofiAbs, "-show", "drun", "-theme", mod.themeAbs]
                : [mod.rofiAbs, "-show", "drun"];
        fallbackProc.running = true;
    }

    Component.onCompleted: {
        testLauncher.running = true;
        testRofi.running = true;
        testTheme.running = true;
        Ui.registerAction("search", function () { mod.openLauncher() });
    }
}
