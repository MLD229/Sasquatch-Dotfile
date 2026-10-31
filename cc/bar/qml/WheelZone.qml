// WheelZone.qml — zone de molette d'un module (v4 §5), SANS aucun risque de clic.
//
// HISTORIQUE : en v3 c'était un `MouseArea { acceptedButtons: Qt.NoButton }`.
// Ça marchait, mais c'était une garantie fragile : un MouseArea reste un
// preneur d'événements souris (il peut capturer le survol, et toute évolution
// du z-order peut le poser au-dessus d'un bloc et rendre ce bloc muet au clic).
//
// v4 : plus de MouseArea du tout, un `WheelHandler`. Un handler de molette ne
// traite QUE l'événement de molette : il n'a aucun bouton à accepter, donc il
// ne peut pas intercepter un appui, un relâchement ou un survol. Un clic passe
// toujours — ce n'est plus une promesse, c'est une impossibilité technique.
// Le module garde son propre MouseArea pour les clics, sans chevauchement.
//
// Conséquence de conception : la zone ne publie plus `lastY` (position du
// geste). Un module qui a besoin de savoir QUELLE ligne est survolée pose son
// onWheel sur son propre MouseArea (c'est le cas des apps : chaque icône a la
// sienne) ; une zone plein bloc ne sert donc qu'aux gestes indépendants de la
// position (défilement d'une liste).
import QtQuick
import "."

Item {
    id: zone

    property string name: ""        // identifiant pour `bar wheels`
    property int lastStep: 0        // dernier delta appliqué (diagnostic)

    signal wheeled(int delta)

    WheelHandler {
        id: handler

        // Souris et pavé tactile uniquement.
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        onWheel: function (event) {
            var d = event.angleDelta.y > 0 ? 1 : (event.angleDelta.y < 0 ? -1 : 0);
            if (d === 0)
                return;
            event.accepted = true;
            zone.lastStep = d;
            zone.wheeled(d);
        }
    }

    Component.onCompleted: if (zone.name.length > 0) Ui.trackWheel(zone.name, zone)
    Component.onDestruction: Ui.untrackWheel(zone)
}
