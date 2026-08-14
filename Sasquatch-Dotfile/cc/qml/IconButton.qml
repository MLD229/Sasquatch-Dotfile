// IconButton.qml — bouton rond, glyph centré, hover animé.
// Paramétrable : glyph, taille de police (0 = défaut système), couleurs base/hover.
import QtQuick

Rectangle {
    id: btn

    property string glyph: ""
    property color glyphColor: "#cdd6f4"                 // cText
    property color baseColor: Qt.rgba(1,1,1,0.06)
    property color hoverColor: Qt.rgba(1,1,1,0.12)
    property int fontSize: 0                             // 0 = défaut système
    signal clicked()

    radius: width / 2
    color: ma.containsMouse ? hoverColor : baseColor
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        anchors.centerIn: parent
        text: btn.glyph
        color: btn.glyphColor
        font.pixelSize: btn.fontSize > 0 ? btn.fontSize : 12
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: btn.clicked()
    }
}
