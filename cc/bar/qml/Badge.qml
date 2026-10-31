// Badge.qml — pastille de comptage (nombre de fenêtres d'une classe).
// Couleur : accent sur fond de barre, jamais un rouge fixe (brief §3.3).
//
// v4 §4 (densité à 40 px) : la pastille est plus petite (12 px de haut, texte
// 8 px) et se place À L'INTÉRIEUR du bloc (marges 0/1, voir AppIcon) — avant,
// height 14 et rightMargin -3 la sortaient de 3 px du bloc, donc de la colonne.
import QtQuick
import "."

Rectangle {
    id: badge

    property int count: 0
    property int textSize: 8

    visible: count > 0
    width: Math.max(12, label.implicitWidth + 5)
    height: 12
    radius: height / 2
    color: BarPalette.accent
    border.width: 1
    border.color: BarPalette.a(BarPalette.bg, 0.65)

    Text {
        id: label
        text: badge.count > 99 ? "99+" : ("" + badge.count)
        anchors.centerIn: parent
        color: BarPalette.bg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: badge.textSize
        font.bold: true
        renderType: Text.NativeRendering
    }
}
