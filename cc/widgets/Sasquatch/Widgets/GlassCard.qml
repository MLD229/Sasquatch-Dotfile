// GlassCard.qml — carte de verre réutilisable pour les PAGES (Système, Outils).
//
// Mêmes tokens que WidgetBase : après ce passage, un bloc de page et une carte
// du board doivent être indiscernables (brief polish §3).
// Transparence sans flou (brief transparence) : aucun MultiEffect, aucun halo,
// aucun contour au repos — un remplissage très léger seulement.
// Les enfants déclarés dans la carte vont dans la colonne `body`.
import QtQuick
import QtQuick.Layouts
import Sasquatch.Widgets 1.0

Item {
    id: card

    property string title: ""
    property string subtitle: ""
    property real cardAlpha: Theme.alphaCard
    property int radius: Theme.radiusCard
    // Padding identique à celui d'un widget de board (`WidgetBase.pad`) pour
    // qu'une carte de page et une carte du board soient indiscernables.
    property int padding: 16
    default property alias content: body.data

    implicitWidth: 320
    implicitHeight: col.implicitHeight + 2 * card.padding

    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: Theme.fill(card.cardAlpha)
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: card.padding
        spacing: 6

        Text {
            visible: card.title.length > 0
            text: card.title
            color: Theme.ink
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Text {
            visible: card.subtitle.length > 0
            text: card.subtitle
            color: Theme.inkDim
            font.pixelSize: 10
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            // Le corps utilise la hauteur qu'on lui DONNE (carte à hauteur
            // imposée, ex. la jauge de la page Système) mais n'en réclame
            // jamais : `implicitHeight` reste la somme du contenu, donc une
            // carte posée dans une Column garde sa hauteur naturelle. C'est
            // l'empilement des pages qui décide, pas la carte.
            Layout.fillHeight: true
            spacing: 8
        }
    }
}
