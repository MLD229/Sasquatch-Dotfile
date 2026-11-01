// HomePage.qml — page d'accueil du CC (brief widgets v1c-1).
//
// Le contenu ne vient PAS d'ici : la page ne fait que poser l'hôte `cc` sur
// la grille 12 colonnes (ligne 96 px, écart 14). Chaque carte est une
// instance de widgets.json, placée par WidgetCanvas, composant résolu par le
// registre. Ajouter/déplacer une carte = POST /api/widgets, jamais un
// changement de ce fichier (brief §4/§5).
import QtQuick
import Sasquatch.Widgets 1.0

Item {
    id: homePage

    // La page prend la hauteur de SON contenu : le board du CC s'ajuste au
    // nombre de lignes réellement posées (plus de moitié vide sous le board).
    implicitHeight: host.contentHeight
    implicitWidth: 400

    WidgetHost {
        id: host
        anchors.fill: parent
        host: "cc"
    }
}
