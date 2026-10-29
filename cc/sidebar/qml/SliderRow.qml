// SliderRow.qml — ligne « label + slider + valeur » (volume, luminosité,
// température hyprsunset) en verre.
// Slider construit à la main (track + poignée) : les styles par défaut de
// QtQuick.Controls imposent leurs propres couleurs, ce qui casserait la règle
// « aucune couleur en dur ».
//
// Piste : dégradé accent → accent2 (brief C). Poignée : grossit au survol et
// pendant le drag (OutCubic 120 ms).
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: row

    property string label: ""
    property string suffix: ""
    property real from: 0
    property real to: 100
    property real value: 0
    property bool enabledControl: true
    property color fgText: "white"
    // secours : shell.qml injecte toujours les couleurs de /api/palette
    property color fgDim: "#999999"
    property color accentColor: "#888888"
    property color accentColor2: "#999999"

    signal moved(real value)

    Layout.fillWidth: true
    spacing: 3

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
            Layout.fillWidth: true
            text: row.label
            color: row.fgDim
            font.pixelSize: 10
            elide: Text.ElideRight
        }
        Text {
            text: Math.round(row.value) + row.suffix
            color: row.enabledControl ? row.fgText : row.fgDim
            font.pixelSize: 10
            font.bold: true
        }
    }

    Item {
        id: track

        Layout.fillWidth: true
        implicitHeight: 16
        opacity: row.enabledControl ? 1.0 : 0.4

        readonly property real ratio: (row.to > row.from)
            ? Math.max(0, Math.min(1, (row.value - row.from) / (row.to - row.from)))
            : 0
        // survol de la poignée OU drag en cours
        readonly property bool hot: ma.containsMouse || ma.pressed

        // Piste (creux de verre)
        Rectangle {
            id: groove

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 5
            radius: 2.5
            color: Qt.rgba(row.fgDim.r, row.fgDim.g, row.fgDim.b, 0.22)
        }

        // Remplissage : dégradé accent → accent2
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, track.ratio * groove.width)
            height: 5
            radius: 2.5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(row.accentColor.r, row.accentColor.g,
                                   row.accentColor.b, 0.95)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(row.accentColor2.r, row.accentColor2.g,
                                   row.accentColor2.b, 0.95)
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: 90
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Poignée : grossit au survol / drag
        Rectangle {
            id: knob

            x: Math.max(0, Math.min(track.width - width, track.ratio * track.width - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            radius: 6
            color: row.fgText
            border.width: 2
            border.color: Qt.rgba(row.accentColor.r, row.accentColor.g,
                                  row.accentColor.b, 0.9)
            scale: track.hot ? 1.3 : 1.0
            transformOrigin: Item.Center

            Behavior on scale {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }

            // liseré clair sur la poignée
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 1
                anchors.leftMargin: 3
                anchors.rightMargin: 3
                height: 1
                radius: 0.5
                color: Qt.rgba(row.fgText.r, row.fgText.g, row.fgText.b, 0.5)
            }
        }

        MouseArea {
            id: ma

            anchors.fill: parent
            anchors.topMargin: -4
            anchors.bottomMargin: -4
            enabled: row.enabledControl
            hoverEnabled: true
            preventStealing: true
            cursorShape: row.enabledControl ? Qt.PointingHandCursor : Qt.ArrowCursor

            function setFromX(px) {
                var r = Math.max(0, Math.min(1, px / Math.max(1, track.width)));
                row.moved(row.from + r * (row.to - row.from));
            }
            onPressed: function (mouse) {
                setFromX(mouse.x);
            }
            onPositionChanged: function (mouse) {
                if (pressed)
                    setFromX(mouse.x);
            }
        }
    }
}
