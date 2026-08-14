// Tile.qml — tuile de section : fond arrondi + titre (optionnel) + contenu.
// Le contenu se met en enfants du Tile (default property) : ils sont empilés
// verticalement sous le titre, avec le même padding que l'ancien code inline.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: tile
    radius: 16
    color: Qt.rgba(1,1,1,0.05)
    border.width: 1
    border.color: Qt.rgba(1,1,1,0.06)

    default property alias content: contentItem.children
    property string title: ""
    property color titleColor: "#a6adc8"    // cTextDim
    property int contentMargins: 12         // la rangée PERFORMANCE utilise 14

    ColumnLayout {
        id: contentItem
        anchors.fill: parent
        anchors.margins: tile.contentMargins
        spacing: 8

        Text {
            text: tile.title
            font.pixelSize: 11
            font.bold: true
            color: tile.titleColor
            visible: tile.title !== ""
        }
    }
}
