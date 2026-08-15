// ColorSwatch.qml — carré de couleur cliquable (grille APPARENCE).
// signal picked(string colorHex) ; état selected avec bordure accent.
import QtQuick

Rectangle {
    id: swatch
    property string colorHex: "#ffffff"
    property bool selected: false
    property color accentColor: "#89b4fa"
    signal picked(string color)
    width: 26
    height: 26
    radius: 6
    color: swatch.colorHex
    border.width: swatch.selected ? 2 : 1
    border.color: swatch.selected ? swatch.accentColor : Qt.rgba(1, 1, 1, 0.2)
    Behavior on border.color { ColorAnimation { duration: 100 } }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: swatch.picked(swatch.colorHex)
    }
}
