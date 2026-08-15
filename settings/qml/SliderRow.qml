// SliderRow.qml — label + slider + valeur numérique (minutes).
// signal changed(int value) émis sur onMoved (interaction utilisateur uniquement).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: srow
    property string label: ""
    property int value: 0
    property int from: 0
    property int to: 100
    property color accentColor: "#89b4fa"
    property color textColor: "#cdd6f4"
    property color textDimColor: "#a6adc8"
    signal changed(int value)
    implicitHeight: 24

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Text {
            text: srow.label
            color: srow.textColor
            font.pixelSize: 12
            Layout.preferredWidth: 110
            elide: Text.ElideRight
        }

        Slider {
            id: sl
            Layout.fillWidth: true
            from: srow.from
            to: srow.to
            value: srow.value
            stepSize: 1
            snapMode: Slider.SnapAlways
            onMoved: srow.changed(sl.value)
            implicitHeight: 18

            background: Rectangle {
                x: sl.leftPadding
                y: sl.topPadding + sl.availableHeight / 2 - height / 2
                width: sl.availableWidth
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.15)

                Rectangle {
                    width: sl.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: Qt.rgba(srow.accentColor.r, srow.accentColor.g, srow.accentColor.b, 0.8)
                }
            }

            handle: Rectangle {
                x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
                y: sl.topPadding + sl.availableHeight / 2 - height / 2
                width: 14
                height: 14
                radius: 7
                color: sl.pressed ? "#ffffff" : srow.accentColor
                border.width: 2
                border.color: Qt.rgba(1, 1, 1, 0.3)
            }
        }

        Text {
            text: sl.value
            color: srow.textDimColor
            font.pixelSize: 12
            Layout.preferredWidth: 28
            horizontalAlignment: Text.AlignRight
        }
    }
}
