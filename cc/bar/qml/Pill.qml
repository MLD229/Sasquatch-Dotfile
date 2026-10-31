// Pill.qml — surface arrondie de base (bloc / pilule).
//
// Purement visuelle : AUCUNE MouseArea ici. Le module hôte possède sa
// MouseArea et pilote `hovered` / `active` — c'est ce qui évite les conflits
// d'événements entre le fond et les enfants cliquables.
// Couleurs : uniquement des tokens de Palette (brief §9).
// Brief v2 §3 : bordure visible SEULEMENT au survol / actif (sinon rien),
// et c'est le fond qui remonte (hoverAlpha), pas le texte.
import QtQuick
import "."

Rectangle {
    id: pill

    property bool hovered: false
    property bool active: false
    property bool flat: false                  // true = pas de fond au repos
    property color fillColor: "transparent"    // vide = couleurs par défaut
    property color strokeColor: "transparent"
    // v4 §3 : MÊME rayon pour toutes les pilules de la barre (Config.pillRadius),
    // un module ne peut le changer que s'il le justifie (aucun ne le fait).
    property int radiusDefault: Config.pillRadius
    property int strokeWidth: 1

    radius: radiusDefault
    color: {
        if (pill.fillColor.a > 0)
            return pill.fillColor;
        if (pill.active && !pill.flat)
            return BarPalette.blockActive;
        if (pill.hovered && !pill.flat)
            return BarPalette.blockHover;
        return BarPalette.block;
    }
    // Au repos : aucune bordure (alpha 0) ; au survol : 1 px lisible ; à l'état
    // actif : contour d'ACCENT (brief v3 §4 — le fond seul ne suffit pas à
    // distinguer 0.34 d'un panneau à 0.24).
    border.width: (pill.hovered || pill.active || pill.strokeColor.a > 0)
                  ? pill.strokeWidth : 0
    border.color: pill.strokeColor.a > 0 ? pill.strokeColor
                  : (pill.active ? BarPalette.accentBar : BarPalette.borderHover)

    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on border.width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on radius { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
}
