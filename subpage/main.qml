// Sasquatch Subpage — cadre de la sub page (scratchpad Hyprland, Super+S)
//
// La « sub page » est un special workspace Hyprland (scratchpad natif) :
//   hyprctl dispatch togglespecialworkspace subpage
// Comportement (voulu par momo 2026-08-20) :
//   - Super+S → la page apparaît (cadre + apps du workspace spécial)
//   - les apps lancées PENDANT que la page est active s'y ouvrent (le special
//     workspace est le workspace actif → comportement natif Hyprland)
//   - re-Super+S → la page disparaît MAIS les apps restent ouvertes (le
//     special workspace se cache, pas de kill)
//
// Ce fichier = le CADRE décoratif : fenêtre flottante pleine écran,
// transparente (on voit le wallpaper), avec un contour arrondi accentué.
// Elle vit DANS le special workspace (windowrule dans hypr/conf.d/rules.conf)
// et suit le toggle : lancée à l'activation, closewindow à la désactivation.

import QtQuick
import QtQuick.Window
import Quickshell

FloatingWindow {
    id: root
    title: "Sasquatch Subpage"
    implicitWidth: Screen.width
    implicitHeight: Screen.height - 42   // sous la waybar (42px réservés en haut)
    visible: true
    color: "transparent"

    // Palette — fallback Catppuccin Mocha (le cadre suit le thème ; si on veut
    // la palette dynamique, poller /api/palette comme wp/main.qml)
    property color cAccent: "#89b4fa"
    property color cTextDim: "#a6adc8"

    // ── Liseré arrondi (look léger) ────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.margins: 12
        radius: 18
        // Voile TRÈS léger : les apps restent bien visibles derrière,
        // le cadre se détache juste du wallpaper (alpha ~0.06)
        color: Qt.rgba(0.05, 0.06, 0.1, 0.06)
        border.width: 2
        border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.65)

        // Étiquette discrète (haut gauche)
        Text {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 12
            text: "サブページ"
            font.pixelSize: 12
            color: Qt.rgba(root.cTextDim.r, root.cTextDim.g, root.cTextDim.b, 0.7)
        }
    }

    // Escape = fermer le cadre (le special workspace reste — subpage.sh gère le toggle)
    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
}
