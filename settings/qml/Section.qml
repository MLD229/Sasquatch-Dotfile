// Section.qml — tuile de section : fond translucide arrondi + titre + contenu.
// Le contenu se met en enfants de la Section (default property) : il est
// empilé verticalement sous le titre (même look que Tile.qml du CC).
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: sec
    radius: 14
    color: Qt.rgba(1, 1, 1, 0.06)
    // Hauteur implicite = contenu empilé + marges (14+14) : sans ça le
    // Rectangle fait 0px et toutes les sections se chevauchent.
    implicitHeight: contentItem.implicitHeight + 28
    implicitWidth: 200

    default property alias content: contentItem.children
    property string title: ""
    property color titleColor: "#a6adc8"    // cTextDim

    ColumnLayout {
        id: contentItem
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Text {
            text: sec.title
            font.pixelSize: 11
            font.bold: true
            color: sec.titleColor
            visible: sec.title !== ""
        }
    }
}
