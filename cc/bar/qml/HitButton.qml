// HitButton.qml — bouton glyphe avec cible cliquable 38 × 38 (brief v2 §2).
//
// Sert aux commandes des popups (fermer, mois précédent/suivant, effacer).
// La zone cliquable couvre exactement le carré dessiné : aucune zone morte,
// aucun décalage entre le survol et le clic.
import QtQuick
import "."

Item {
    id: btn

    property string name: ""                   // préfixe « popup: » dans Ui
    property string glyph: "\uf00d"            // croix par défaut
    property int glyphSize: 14                 // glyphe petit, cible grande
    property color glyphColor: BarPalette.textDim
    property color hoverColor: BarPalette.hot
    property string tipText: ""

    signal clicked()

    implicitWidth: Config.hitMin
    implicitHeight: Config.hitMin

    BarIcon {
        anchors.centerIn: parent
        text: btn.glyph
        size: btn.glyphSize
        tint: area.containsMouse ? btn.hoverColor : btn.glyphColor
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
        onEntered: if (btn.tipText.length > 0) {
            var p = btn.mapToItem(null, 0, btn.height / 2);
            Tip.show(btn.tipText, p.y);
        }
        onExited: Tip.hide()
    }

    Component.onCompleted: if (btn.name.length > 0) Ui.track("popup:" + btn.name, btn, area)
    Component.onDestruction: Ui.untrack(btn)
}
