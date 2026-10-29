// Sasquatch Subpage — cadre décoratif de la sub page (scratchpad Hyprland, Super+S)
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
// ── REFONTE (2026-09-18) ────────────────────────────────────────────────
// Bug v1 : le cadre dessinait un Rectangle PLEIN écran (alpha ~0.06). Même
// quasi transparent, Hyprland calcule le flou/rendu sur TOUTE la surface de
// la fenêtre — pas seulement les pixels visibles. Résultat : un voile flouté
// couvrant tout l'écran, qui cachait les apps ouvertes dans la sub page.
// En plus, cette fenêtre garde sa propre bordure/ombre Hyprland (côté
// rules.conf / decoration.conf) ET dessinait un second contour arrondi
// 12px plus loin → effet « une page dans une page ».
//
// v2 change trois choses :
//   1. Plus AUCUN pavé plein : juste 4 coins en L (façon viseur d'appareil
//      photo) + une étiquette. Une forme ouverte ne peut pas donner
//      l'impression de "boîte dans une boîte".
//   2. HyprlandWindow.visibleMask restreint le rendu ET le flou du
//      compositeur à la zone des coins (Quickshell.Hyprland). C'est LA
//      correction du bug "page blur" : sans ça Hyprland floute toute la
//      fenêtre même là où il n'y a rien à voir.
//   3. `mask` restreint les clics à cette même zone : le centre de l'écran
//      laisse 100% passer la souris vers les apps du special workspace.
//      (send.sh/subpage.sh n'ont pas besoin de changer : le titre de la
//      fenêtre reste "Sasquatch Subpage".)
//
// IMPORTANT — à vérifier côté hypr/conf.d/rules.conf (non fourni ici) :
// cette fenêtre ne doit PAS avoir de bordure / ombre / rounding gérés par
// Hyprland lui-même, sinon ça redessine un rectangle plein écran visible
// malgré visibleMask (qui ne s'applique qu'au CONTENU rendu par Quickshell,
// pas à la décoration ajoutée par le compositeur). Ajouter quelque chose
// comme (à adapter à la syntaxe hyprlang/lua réellement utilisée) :
//   windowrule = noborder, title:^(Sasquatch Subpage)$
//   windowrule = noshadow, title:^(Sasquatch Subpage)$
//   windowrule = rounding 0, title:^(Sasquatch Subpage)$
// Si après ce fichier la page a encore un contour indésirable, c'est très
// probablement là — envoie-moi rules.conf pour que je l'ajuste précisément.
//
// ── FIX (petit carré flouté en haut à gauche) ───────────────────────────
// v2 utilisait le coin ENTIER (le carré 56x56 du composant Corner) comme
// zone de Region, pas juste les 2 traits. HyprlandWindow.visibleMask ne
// fait pas de test pixel par pixel : il traite tout le rectangle qu'on lui
// donne comme "zone à rendre/flouter". Si `blur` est actif pour cette
// fenêtre côté rules.conf, Hyprland floutait donc tout le carré 56x56,
// pas juste le L — d'où le petit carré visible. v3 construit la Region à
// partir des 2 traits (hBar/vBar) de chaque coin individuellement : la
// zone rendue/floutée se réduit à l'épaisseur du trait (3px), donc même si
// le flou reste actif quelque part, il colle au trait au lieu de former un
// carré. Le vrai fix propre reste `noblur` sur cette fenêtre (voir plus haut).

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland

FloatingWindow {
    id: root
    title: "Sasquatch Subpage"
    implicitWidth: Screen.width
    implicitHeight: Screen.height - 42   // sous la waybar (42px réservés en haut)
    visible: true
    color: "transparent"

    // Palette — fallback Catppuccin Mocha (si on veut la palette dynamique
    // plus tard, poller /api/palette comme wp/main.qml)
    property color cAccent: "#89b4fa"
    property color cTextDim: "#a6adc8"

    property int stroke: 3        // épaisseur des traits des coins
    property int armLength: 56    // longueur d'un bras de coin
    property int edgeMargin: 10   // décalage par rapport au bord d'écran

    // ── Coin réutilisable : deux traits en L, jamais un pavé fermé ──────
    component Corner: Item {
        id: cornerRoot
        property bool alignRight: false
        property bool alignBottom: false
        // alias vers les 2 traits : permet à la Region plus bas de cibler
        // uniquement leur zone (fine) plutôt que le carré cornerRoot entier
        property alias hBar: hRect
        property alias vBar: vRect
        width: root.armLength
        height: root.armLength

        Rectangle {
            id: hRect
            color: root.cAccent
            opacity: 0.85
            width: root.armLength
            height: root.stroke
            x: 0
            y: cornerRoot.alignBottom ? cornerRoot.height - root.stroke : 0
        }
        Rectangle {
            id: vRect
            color: root.cAccent
            opacity: 0.85
            width: root.stroke
            height: root.armLength
            y: 0
            x: cornerRoot.alignRight ? cornerRoot.width - root.stroke : 0
        }
    }

    Corner {
        id: cTL
        anchors.top: root.top
        anchors.left: root.left
        anchors.margins: root.edgeMargin
    }
    Corner {
        id: cTR
        anchors.top: root.top
        anchors.right: root.right
        anchors.margins: root.edgeMargin
        alignRight: true
    }
    Corner {
        id: cBL
        anchors.bottom: root.bottom
        anchors.left: root.left
        anchors.margins: root.edgeMargin
        alignBottom: true
    }
    Corner {
        id: cBR
        anchors.bottom: root.bottom
        anchors.right: root.right
        anchors.margins: root.edgeMargin
        alignRight: true
        alignBottom: true
    }

    // ── Étiquette discrète, juste sous le coin haut-gauche ──────────────
    Text {
        id: label
        anchors.top: root.top
        anchors.left: root.left
        anchors.topMargin: root.edgeMargin + root.armLength + 8
        anchors.leftMargin: root.edgeMargin
        text: "サブページ"
        font.pixelSize: 12
        color: Qt.rgba(root.cTextDim.r, root.cTextDim.g, root.cTextDim.b, 0.7)
    }

    // ── Région active = uniquement les 8 traits + l'étiquette ───────────
    // Utilisée à la fois pour les clics (mask) et pour le rendu/flou du
    // compositeur (HyprlandWindow.visibleMask). On cible les traits eux-
    // mêmes (hBar/vBar), pas le carré cornerRoot entier : sinon Hyprland
    // rend/floute tout le carré 56x56 du coin (visible comme un petit
    // carré flouté), au lieu de coller juste au trait de 3px.
    Region {
        id: activeRegion
        item: cTL.hBar
        Region { item: cTL.vBar }
        Region { item: cTR.hBar }
        Region { item: cTR.vBar }
        Region { item: cBL.hBar }
        Region { item: cBL.vBar }
        Region { item: cBR.hBar }
        Region { item: cBR.vBar }
        Region { item: label }
    }

    // La mask limite les clics aux traits et à l’étiquette.
    // Pas de visibleMask : il peut provoquer un bloc rectangulaire/flouté au coin supérieur gauche.
    mask: activeRegion

    // Escape = fermer le cadre (le special workspace reste — subpage.sh gère le toggle)
    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
}
