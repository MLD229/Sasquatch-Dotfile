// Workspaces.qml — module 2 : points verticaux des workspaces (v4 §1/§9).
//
// Données : Quickshell.Hyprland.workspaces (aucun parsing hyprctl en boucle).
//
// v4 — TROIS CHANGEMENTS
// 1. LA PILULE EST COMPACTE. Sa hauteur vaut exactement
//       nbPoints × pas + 2 × padding    (pas = Config.wsStep, padding = Config.pad)
//    et ne dépend plus de la place disponible : un groupe ne s'étire pas, donc
//    l'espace libre ne rentre JAMAIS dans une pilule (il va entre les groupes,
//    voir shell.qml).
// 2. POINTS PERSISTANTS (bar.json : bar.persistentWorkspaces, défaut 10) :
//    les workspaces qui n'existent pas encore ont un point ATTÉNUÉ et
//    CLIQUABLE (clic = dispatch workspace N). 0 = ancien comportement (seuls
//    les workspaces existants). Rechargement à chaud : la valeur vient de
//    Config, qui surveille bar.json.
// 3. La pilule a un FOND (comme les autres blocs) : c'est l'uniformité
//    « de partie en partie » (même rayon, même padding).
//
// v5b — ORIENTATION : en barre HAUTE (position top) les MÊMES points
// s'alignent horizontalement (Flow LeftToRight) et le module ne fait qu'une
// case de haut ; l'axe de lecture (indexAt) suit `Config.horizontal`, donc
// clic / survol / molette visent toujours le bon workspace. Aucun point n'est
// dupliqué : c'est le même Repeater.
//
// Le modèle du Repeater est un NOMBRE (le nombre de points), pas un tableau
// d'objets : en mode persistant le nombre ne change jamais, donc les points ne
// sont pas détruits/recréés à chaque événement Hyprland (pas de clignotement,
// pas de churn dans Ui.track). L'état de chaque point se lit par `infoAt(i)`.
//
// Zone de molette : un seul MouseArea sur tout le bloc (jamais d'angle mort
// entre deux points) — clic routé par l'ordonnée, molette = ws précédent/suivant.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../qml"

Item {
    id: mod

    // Pas vertical d'un point (13 px à 40/4/32 : padding 4, point 11 max).
    readonly property int pitch: Config.wsStep
    readonly property int pad: Config.pad
    readonly property int persist: Config.persistentWorkspaces
    readonly property var live: Hypr.workspaces.values || []

    // Nombre de points affichés : N fixes (persistant) ou les existants.
    readonly property int points: mod.persist > 0 ? mod.persist : mod.live.length

    // HAUTEUR COMPACTE : nbPoints × pas + 2 × padding — la règle du §1.
    // v5b : la même somme devient la LARGEUR en barre haute (une case de haut).
    implicitWidth: Config.horizontal
                   ? (mod.points * mod.pitch + 2 * mod.pad)
                   : Config.block
    implicitHeight: Config.horizontal
                    ? Config.caseH
                    : Math.max(Config.caseH, mod.points * mod.pitch + 2 * mod.pad)

    function wsAt(i) {
        if (mod.persist > 0) {
            for (var k = 0; k < mod.live.length; k++) {
                if (mod.live[k] && mod.live[k].id === i + 1)
                    return mod.live[k];
            }
            return null;
        }
        return mod.live[i] ? mod.live[i] : null;
    }

    // État d'un point : id réel, libellé, existence, nb de fenêtres.
    function infoAt(i) {
        var ws = mod.wsAt(i);
        if (mod.persist > 0) {
            return {
                id: i + 1,
                label: ws ? ("" + ws.name) : ("" + (i + 1)),
                exists: ws !== null,
                focused: ws !== null && ws.focused === true,
                windows: (ws && ws.lastIpcObject) ? (ws.lastIpcObject.windows || 0) : 0
            };
        }
        if (!ws)
            return { id: -1, label: "?", exists: false, focused: false, windows: 0 };
        return {
            id: ws.id,
            label: "" + ws.name,
            exists: true,
            focused: ws.focused === true,
            windows: ws.lastIpcObject ? (ws.lastIpcObject.windows || 0) : 0
        };
    }

    property int hoverIdx: -1

    function indexAt(y) {
        if (mod.points === 0)
            return -1;
        var i = Math.floor((y - mod.pad) / mod.pitch);
        if (i < 0 || i >= mod.points)
            return -1;
        return i;
    }

    function focusedIndex() {
        for (var i = 0; i < mod.points; i++) {
            if (mod.infoAt(i).focused === true)
                return i;
        }
        return -1;
    }

    // Molette haut = workspace précédent (delta +1), bas = suivant. On ne
    // parcourt que les workspaces EXISTANTS : atterrir sur un workspace vide
    // ferait « disparaître » les fenêtres au lieu de cycler entre elles.
    function cycle(delta) {
        var idx = [];
        for (var i = 0; i < mod.points; i++) {
            if (mod.infoAt(i).exists)
                idx.push(i);
        }
        if (idx.length < 2)
            return;
        var cur = mod.focusedIndex();
        var pos = idx.indexOf(cur);
        if (pos < 0)
            pos = 0;
        var next = (pos + (delta > 0 ? -1 : 1) + idx.length) % idx.length;
        Hypr.goWorkspace(mod.infoAt(idx[next]).id);
    }

    function hoverAt(y) {
        var i = mod.indexAt(y);
        if (i === mod.hoverIdx)
            return;
        mod.hoverIdx = i;
        if (i < 0) {
            Tip.hide();
            return;
        }
        var ws = mod.infoAt(i);
        var n = ws.windows;
        // Coordonnée du point survolé : verticale en colonne, horizontale en
        // ligne (l'infobulle est ancrée sous la barre en mode haut).
        var p = Config.horizontal
                ? mod.mapToItem(null, mod.pad + i * mod.pitch + mod.pitch / 2, mod.height / 2)
                : mod.mapToItem(null, 0, mod.pad + i * mod.pitch + mod.pitch / 2);
        Tip.show(ws.exists
                 ? "workspace " + ws.label + " — " + n + (n > 1 ? " fenêtres" : " fenêtre")
                 : "workspace " + ws.label + " — inexistant (clic : y aller)",
                 p.y);
    }

    // Fond de pilule : même rayon et même padding que tous les blocs (§3).
    Pill {
        id: bg
        anchors.fill: parent
        hovered: area.containsMouse
    }

    // Les points eux-mêmes : un Flow dont la direction suit l'orientation
    // (colonne en barre verticale, ligne en barre haute). Un Flow et non un
    // Row/Column : mêmes enfants, mêmes positions, aucune duplication.
    Flow {
        id: dots
        flow: Config.horizontal ? Flow.LeftToRight : Flow.TopToBottom
        x: Config.horizontal ? mod.pad : 0
        y: Config.horizontal ? 0 : mod.pad
        width: parent.width
        spacing: 0

        Repeater {
            model: mod.points

            delegate: Item {
                id: dotSlot

                required property int index

                // `info` est une liaison : elle suit Hyprland.workspaces.
                readonly property var info: mod.infoAt(dotSlot.index)
                readonly property bool active: dotSlot.info.focused === true
                readonly property bool present: dotSlot.info.exists === true
                readonly property bool occupied: dotSlot.present && dotSlot.info.windows > 0
                // Longueur / épaisseur du point selon l'orientation.
                readonly property int dotLong: dotSlot.active ? 11 : (dotSlot.occupied ? 8 : 5)
                readonly property int dotShort: dotSlot.active ? 3 : 5

                width: Config.horizontal ? mod.pitch : mod.width
                height: Config.horizontal ? mod.height : mod.pitch

                Pill {
                    id: dot
                    anchors.centerIn: parent
                    radiusDefault: 3
                    hovered: mod.hoverIdx === dotSlot.index
                    active: dotSlot.active
                    // Actif : trait d'accent 3 × 11 (11 × 3 en barre haute).
                    // Occupé : 5 × 8. Existant vide : 5 × 5. Inexistant
                    // (persistant) : 5 × 5 très atténué, mais CLIQUABLE (même
                    // cible que les autres).
                    width: Config.horizontal ? dotSlot.dotLong : dotSlot.dotShort
                    height: Config.horizontal ? dotSlot.dotShort : dotSlot.dotLong
                    fillColor: {
                        if (dotSlot.active)
                            return BarPalette.accent;
                        if (!dotSlot.present)
                            return BarPalette.a(BarPalette.text, 0.18);
                        return BarPalette.a(BarPalette.text,
                                            dotSlot.info.windows > 0 ? 0.85 : 0.32);
                    }
                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }

                // Mesure + action (tests IPC : même code que le clic).
                // La clé est l'ID (unique) : deux workspaces ne peuvent pas
                // partager un nom après un rename, un id si.
                Component.onCompleted: {
                    var wsid = dotSlot.info.id;
                    Ui.track("ws:" + wsid, dotSlot, dotSlot);
                    Ui.registerAction("ws:" + wsid, function () { Hypr.goWorkspace(wsid) });
                }
                Component.onDestruction: Ui.untrack(dotSlot)
            }
        }
    }

    // LA zone de clic + molette du module : tout le bloc, un seul gestionnaire.
    // v5b : l'axe lu suit l'orientation (y en colonne, x en ligne).
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Coordonnée le long du chapelet de points.
        readonly property real axisPos: Config.horizontal ? area.mouseX : area.mouseY
        onClicked: {
            Tip.hideNow();
            var i = mod.indexAt(area.axisPos);
            if (i >= 0)
                Hypr.goWorkspace(mod.infoAt(i).id);
        }
        onWheel: function (wheel) {
            var d = wheel.angleDelta.y > 0 ? 1 : (wheel.angleDelta.y < 0 ? -1 : 0);
            if (d === 0)
                return;
            wheel.accepted = true;
            mod.cycle(d);
        }
        onPositionChanged: mod.hoverAt(area.axisPos)
        onEntered: mod.hoverAt(area.axisPos)
        onExited: {
            mod.hoverIdx = -1;
            Tip.hide();
        }
        Component.onCompleted: Ui.trackWheel("workspaces", area)
        Component.onDestruction: Ui.untrackWheel(area)
    }

    // Aucun workspace renvoyé par Hyprland : état d'erreur visible.
    BarIcon {
        visible: mod.points === 0
        width: Config.block
        height: Config.caseH
        text: "\uf071"
        size: 14
        tint: BarPalette.warn
    }
}
