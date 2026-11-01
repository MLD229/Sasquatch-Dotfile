// WorkspacesWidget.qml — widget `workspaces` (catalogue §6).
//
// Variantes :
//   compact  220x64   10 pastilles (5 × 2), numéro + compte, actif marqué
//   normal   360x180  en-tête (total de fenêtres) + mêmes pastilles, plus grandes
//
// Données : Quickshell.Hyprland — `Hyprland.workspaces.values` (id, focused,
// lastIpcObject.windows) et `Hyprland.toplevels.values` (repli de comptage
// par `lastIpcObject.workspace.id`) : aucun parsing `hyprctl` en boucle,
// exactement comme la barre (cc/bar/modules/Workspaces.qml).
// Clic = `Hyprland.dispatch("workspace N")`.
// Aucune couleur en dur : tout vient de Theme.
import QtQuick
import Quickshell.Hyprland
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "workspaces"

    // Nombre de bureaux affichés (1..N). Le registre borne 5..10.
    readonly property int count: {
        var v = (root.options && typeof root.options.count === "number")
                ? Math.round(root.options.count) : 10;
        return Math.max(1, Math.min(10, v));
    }
    readonly property bool showCount: !(root.options && root.options.showCount === false)

    readonly property var wsValues: {
        var m = Hyprland.workspaces;
        return (m && m.values) ? m.values : [];
    }
    readonly property var tops: {
        var m = Hyprland.toplevels;
        return (m && m.values) ? m.values : [];
    }

    readonly property int focusedId: {
        var list = root.wsValues;
        for (var i = 0; i < list.length; ++i) {
            if (list[i] && list[i].focused === true)
                return list[i].id;
        }
        return -1;
    }

    function wsOf(id) {
        var list = root.wsValues;
        for (var i = 0; i < list.length; ++i) {
            if (list[i] && list[i].id === id)
                return list[i];
        }
        return null;
    }

    // Fenêtres d'un bureau : `lastIpcObject.windows` du workspace quand il
    // existe, sinon comptage des toplevels de ce bureau.
    function winCount(id) {
        var ws = root.wsOf(id);
        var ipc = ws ? ws.lastIpcObject : null;
        if (ipc && typeof ipc.windows === "number")
            return Math.max(0, Math.round(ipc.windows));
        var n = 0;
        var list = root.tops;
        for (var i = 0; i < list.length; ++i) {
            var o = list[i] ? list[i].lastIpcObject : null;
            if (o && o.workspace && o.workspace.id === id)
                n += 1;
        }
        return n;
    }

    readonly property int totalWindows: {
        var n = 0;
        for (var id = 1; id <= root.count; ++id)
            n += root.winCount(id);
        return n;
    }

    function focusWs(id) {
        Hyprland.dispatch("workspace " + id);
    }

    // ── En-tête (normal) ──────────────────────────────────────────────────
    readonly property real innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property real headSize: Math.max(9, Math.min(14, Math.round(root.innerH * 0.11)))
    readonly property real headH: root.compact ? 0 : Math.round(root.innerH * 0.15)
    readonly property real gap: root.compact ? 4 : Math.max(4, Math.round(root.innerH * 0.04))

    Item {
        id: head
        visible: !root.compact
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.pad
        height: root.headH

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Bureaux"
            color: root.ink
            font.pixelSize: root.headSize
            font.weight: Font.Medium
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.wsValues.length === 0
                  ? "Bureaux indisponibles"
                  : (root.totalWindows === 0
                     ? "Aucune fenêtre"
                     : (root.totalWindows + (root.totalWindows > 1 ? " fenêtres" : " fenêtre")))
            color: root.wsValues.length === 0 ? Theme.warn : root.inkDim
            font.pixelSize: root.headSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    // ── Pastilles 1..N ────────────────────────────────────────────────────
    Grid {
        id: grid
        columns: 5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.pad
        anchors.topMargin: root.compact ? root.pad : 0
        anchors.top: root.compact ? parent.top : head.bottom
        spacing: root.gap

        readonly property real cellW: (grid.width - (grid.columns - 1) * grid.spacing) / grid.columns
        // Deux rangées pleines : même hauteur de cellule, jamais de ligne
        // orpheline (10 bureaux = 5 × 2).
        readonly property int rows: Math.ceil(root.count / grid.columns)
        readonly property real cellH: (grid.height - Math.max(0, grid.rows - 1) * grid.spacing)
                                      / Math.max(1, grid.rows)

        Repeater {
            model: root.count

            delegate: Rectangle {
                id: cell

                required property int index

                readonly property int wsId: cell.index + 1
                readonly property bool active: root.focusedId === cell.wsId
                readonly property int wins: root.winCount(cell.wsId)
                readonly property bool occupied: cell.wins > 0

                width: grid.cellW
                height: grid.cellH
                radius: Theme.radiusBtn * 0.7
                color: {
                    if (cell.active)
                        return Theme.a(Theme.vizA, Theme.alphaBtn);
                    if (hoverArea.containsMouse)
                        return Theme.a(root.ink, 0.10);
                    if (cell.occupied)
                        return Theme.a(Theme.glassBtn, 0.55);
                    return Theme.a(Theme.glassBtn, 0.30);
                }
                border.width: cell.active ? 2 : 1
                border.color: cell.active ? Theme.vizA : Theme.border
                opacity: (root.wsValues.length === 0) ? 0.6 : 1.0

                Behavior on color {
                    ColorAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 4
                    text: "" + cell.wsId
                    color: cell.active ? Theme.ink : (cell.occupied ? root.ink : root.inkDim)
                    font.pixelSize: root.compact ? Math.max(9, Math.round(cell.height * 0.5))
                                                 : Math.max(11, Math.round(cell.height * 0.30))
                    font.weight: cell.active ? Font.DemiBold : Font.Normal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                // Compteur de fenêtres (lastIpcObject) : pastille discrète en
                // bas-droite, jamais un « 0 » inutile.
                Text {
                    visible: root.showCount && cell.wins > 0
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: Math.max(2, Math.round(parent.width * 0.10))
                    anchors.bottomMargin: Math.max(1, Math.round(parent.height * 0.04))
                    text: "" + cell.wins
                    color: cell.active ? root.ink : root.inkDim
                    font.pixelSize: Math.max(7, Math.round(parent.height
                                        * (root.compact ? 0.30 : 0.17)))
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.interactive
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.focusWs(cell.wsId)
                }
            }
        }
    }
}
