// Sasquatch Control Center — Btn.qml
// Bouton simple stylé (Rectangle + MouseArea).
import QtQuick

Rectangle {
    id: root
    property string label: ""
    property bool big: false
    property bool enabled: true
    signal clicked

    width: big ? 38 : 30
    height: big ? 38 : 30
    radius: 8
    color: Palette.accent2
    border.color: Palette.accent2
    opacity: root.enabled ? 1 : 0.45

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        anchors.centerIn: parent
        text: root.label
        font.pixelSize: root.big ? 14 : 12
        color: Palette.text
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        onClicked: root.clicked()
        onEntered: if (root.enabled) root.color = Palette.accent
        onExited: root.color = Palette.accent2
    }
}
