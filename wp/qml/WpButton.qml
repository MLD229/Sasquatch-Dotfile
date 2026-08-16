// WpButton — bouton du sélecteur de fonds d'écran (style dotfile).
// Composant séparé (comme cc/qml/IconButton.qml) : la palette est passée par
// l'appelant car le thème est dynamique (fg, bg, accentColor, border).
import QtQuick
import QtQuick.Controls

Rectangle {
    id: btn

    signal clicked
    required property string label
    property color fg: "#cdd6f4"
    property color bg: Qt.rgba(0.09, 0.10, 0.12, 0.92)
    property color borderColor: Qt.rgba(0.65, 0.65, 0.75, 0.25)
    property bool accent: false
    property color accentColor: "#89b4fa"
    property bool disabled: false

    implicitWidth: txt.implicitWidth + 28
    implicitHeight: 38
    radius: 11
    color: accent ? accentColor : bg
    border.width: accent ? 0 : 1
    border.color: borderColor
    opacity: disabled ? 0.45 : 1.0

    Text {
        id: txt
        anchors.centerIn: parent
        text: btn.label
        color: btn.accent ? Qt.rgba(0.06, 0.06, 0.08, 0.9) : btn.fg
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !btn.disabled
        onClicked: btn.clicked()
    }
}
