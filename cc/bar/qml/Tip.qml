// Tip.qml — singleton : état de l'infobulle partagée.
//
// Une seule infobulle pour toute la barre : c'est shell.qml qui possède la
// fenêtre (PanelWindow dédiée, exclusiveZone 0). Un module ne fait
// qu'appeler Tip.show(texte, yEcran) au survol — aucune fenêtre par module.
// Masquage différé de 90 ms pour éviter le clignotement quand on passe d'une
// cible à l'autre.
pragma Singleton
import QtQuick

QtObject {
    id: tip

    property bool visible: false
    property string text: ""
    property int y: 0            // y écran du centre de l'infobulle
    property int arrows: 0       // 0 = aucun, 1 = gauche (popup), 2 = bas

    function show(txt, yScreen) {
        if (!txt || txt.length === 0) {
            tip.hideTimer.stop();
            tip.visible = false;
            return;
        }
        tip.hideTimer.stop();
        tip.text = txt;
        // En barre HAUTE (position top) l'infobulle est ancrée SOUS la barre :
        // l'ordonnée envoyée par les modules (position verticale de la cible)
        // n'a plus de sens, on la garde telle quelle et shell.qml l'ignore.
        if (!Config.horizontal && typeof yScreen === "number")
            tip.y = yScreen;
        tip.visible = true;
    }

    function hide() {
        if (!tip.visible)
            return;
        tip.hideTimer.restart();
    }

    function hideNow() {
        tip.hideTimer.stop();
        tip.visible = false;
    }

    property Timer hideTimer: Timer {
        interval: 90
        repeat: false
        onTriggered: {
            tip.visible = false;
            tip.text = "";
        }
    }
}
