// TogglesWidget.qml — widget `toggles` : DND, flou, lumière chaude, allégé.
//
// Variantes :
//   compact  220x64   quatre pilules (DND · flou · nuit · léger)
//   normal   360x180  quatre lignes : libellé, interrupteur, état réel
//
// AUCUN moteur de modes ici : le singleton Modes lit GET /api/modes et poste
// POST /api/modes, que cc/server.py délègue à cc/sidebar/modes.py (le moteur
// unique, partagé avec la sidebar). L'état affiché est `real` — la valeur RELUE
// après application (makoctl / hyprctl / procs), jamais une supposition.
// Outil absent → ligne grisée + commande d'installation ; hyprsunset non
// installé n'empêche donc pas les trois autres toggles de fonctionner.
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "toggles"

    readonly property int innerH: Math.max(8, root.height - 2 * root.pad)

    // Les 4 toggles, dans l'ordre d'affichage. `mode` = clé envoyée au serveur.
    // `short` = libellé FIXE du mode compact : un mot entier, jamais coupé
    // (la taille de police est ajustée à la pilule, pas l'inverse).
    readonly property var defs: [
        { mode: "dnd", label: "Ne pas déranger", short: "Silence", detail: "mako" },
        { mode: "blur", label: "Flou", short: "Flou", detail: "hyprland" },
        { mode: "bluesun", label: "Mode nuit", short: "Nuit", detail: "hyprsunset" },
        { mode: "lite", label: "Mode léger", short: "Léger", detail: "animations + ombres" }
    ]

    function stateOf(mode) {
        return Modes.flag(mode);
    }

    function installOf(def) {
        var cmd = Modes.installFor(def.mode);
        return cmd.length > 0 ? cmd : ("sudo pacman -S " + def.detail);
    }

    // ── compact : quatre pilules ──────────────────────────────────────────
    Row {
        id: pills
        visible: root.compact
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: 4

        Repeater {
            model: root.defs

            Rectangle {
                id: pill
                width: (pills.width - 3 * pills.spacing) / 4
                height: pills.height
                radius: Theme.radiusBtn
                readonly property var def: modelData
                readonly property bool on: root.stateOf(pill.def.mode) === true
                readonly property bool avail: Modes.available(pill.def.mode)
                // Police ajustée à la place réelle (≈0.58 em par caractère) :
                // le libellé tient en entier même sur une carte étroite — c'est
                // ce qui évite le « flo » coupé du rendu précédent.
                readonly property real fitSize: Math.max(7, Math.min(
                    Math.max(9, Math.round(root.innerH * 0.21)),
                    (pill.width - 10) / Math.max(1, pill.def.short.length * 0.58)))
                color: pill.on ? Theme.a(Theme.vizA, Theme.alphaBtn * 0.6)
                               : Theme.a(Theme.glassBtn, 0.40)
                border.width: 1
                border.color: pill.on ? Theme.halo : Theme.border
                opacity: pill.avail ? 1.0 : 0.45

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 6
                    text: pill.def.short
                    color: pill.on ? root.ink : root.inkDim
                    font.pixelSize: Math.round(pill.fitSize)
                    font.weight: pill.on ? Font.DemiBold : Font.Normal
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.NoWrap
                    elide: Text.ElideNone
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.interactive && pill.avail && Modes.pending.length === 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Modes.toggle(pill.def.mode)
                }
            }
        }
    }

    // ── normal : quatre lignes ────────────────────────────────────────────
    Column {
        id: rows
        visible: !root.compact
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(2, Math.round(root.innerH * 0.02))
        clip: true

        // Titre de la carte (spec copy) : « Modes rapides ».
        Item {
            id: rowsHead
            width: rows.width
            height: Math.round(root.innerH * 0.14)

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Modes rapides"
                color: root.ink
                font.pixelSize: Math.max(9, Math.min(14, Math.round(root.innerH * 0.10)))
                font.weight: Font.Medium
            }
        }

        Repeater {
            model: root.defs

            Item {
                id: row
                width: rows.width
                height: Math.max(26, Math.round((rows.height - rowsHead.height) / 4) - 2)
                readonly property var def: modelData
                readonly property var modeState: root.stateOf(row.def.mode)
                readonly property bool avail: Modes.available(row.def.mode)
                readonly property bool on: row.modeState === true
                readonly property bool pending: Modes.pending === row.def.mode

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusBtn
                    color: rowHover.containsMouse && row.avail
                           ? Theme.a(root.ink, 0.05) : "transparent"
                }

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: sw.left
                    anchors.rightMargin: 8
                    text: row.def.label
                    color: row.avail ? root.ink : root.inkDim
                    font.pixelSize: Math.max(9, Math.min(14, Math.round(root.innerH * 0.085)))
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                // État : vrai / faux / indisponible, plus la commande d'install.
                Text {
                    visible: !row.avail || row.modeState === null
                    anchors.left: parent.left
                    anchors.right: sw.left
                    anchors.rightMargin: 8
                    anchors.bottom: parent.bottom
                    text: {
                        if (!row.avail)
                            return "Indisponible · " + root.installOf(row.def);
                        return "Indisponible · " + row.def.detail + " ne répond pas";
                    }
                    color: Theme.warn
                    font.pixelSize: Math.max(7, Math.round(root.innerH * 0.055))
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Text {
                    visible: row.avail && row.pending
                    anchors.right: sw.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Activation…"
                    color: root.inkDim
                    font.pixelSize: Math.max(8, Math.round(root.innerH * 0.075))
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                // Interrupteur : piste + bouton, animation OutCubic 160 ms.
                Rectangle {
                    id: sw
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(34, Math.round(root.innerH * 0.22))
                    height: Math.max(18, Math.round(width * 0.52))
                    radius: height / 2
                    color: {
                        if (!row.avail)
                            return Theme.a(Theme.glassBtn, 0.30);
                        return row.on ? Theme.a(Theme.vizA, Theme.alphaBtn)
                                      : Theme.a(Theme.glassBtn, 0.55);
                    }
                    border.width: 1
                    border.color: row.on ? Theme.halo : Theme.border

                    Rectangle {
                        id: knob
                        width: Math.round(sw.height - 6)
                        height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: row.on ? (sw.width - sw.height + 3) : 3
                        color: row.on ? root.ink : Theme.a(root.inkDim, 0.85)
                        Behavior on x {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                MouseArea {
                    id: rowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.interactive && row.avail && !row.pending
                    cursorShape: row.avail ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Modes.toggle(row.def.mode)
                }
            }
        }
    }
}
