// Toggle.qml — interrupteur stylé (label + Switch Qt Quick Controls).
// signal toggled(bool value) émis UNIQUEMENT sur interaction utilisateur
// (onClicked du Switch) : jamais de POST parasite au chargement initial.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: tgl
    property string label: ""
    property bool checked: false
    property color accentColor: "#89b4fa"
    property color textColor: "#cdd6f4"
    signal toggled(bool value)
    implicitHeight: 26

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Text {
            text: tgl.label
            color: tgl.textColor
            font.pixelSize: 13
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Switch {
            id: sw
            checked: tgl.checked
            onClicked: tgl.toggled(checked)
            implicitWidth: 38
            implicitHeight: 22

            indicator: Rectangle {
                implicitWidth: 38
                implicitHeight: 22
                radius: 11
                color: sw.checked
                       ? Qt.rgba(tgl.accentColor.r, tgl.accentColor.g, tgl.accentColor.b, 0.85)
                       : Qt.rgba(1, 1, 1, 0.15)
                Behavior on color { ColorAnimation { duration: 120 } }

                Rectangle {
                    x: sw.checked ? parent.width - width - 2 : 2
                    y: 2
                    width: parent.height - 4
                    height: parent.height - 4
                    radius: width / 2
                    color: "#ffffff"
                    Behavior on x { NumberAnimation { duration: 120 } }
                }
            }
        }
    }
}
