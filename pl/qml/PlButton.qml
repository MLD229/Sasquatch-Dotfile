// PlButton — bouton du panneau playlist (style dotfile, comme WpButton).
// `active` = état "on" (bordure accent + fond teinté) pour les toggles.
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
    property bool active: false
    property bool disabled: false

    implicitWidth: txt.implicitWidth + 28
    implicitHeight: 38
    radius: 11
    color: accent ? accentColor
                  : (active ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.16)
                            : bg)
    border.width: accent || active ? 2 : 1
    border.color: active ? accentColor : borderColor
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
