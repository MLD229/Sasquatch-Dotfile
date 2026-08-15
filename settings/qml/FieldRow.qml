// FieldRow.qml — label + champ texte stylé (validation sur Entrée).
// signal submitted(string text) ; focusActive remonté pour le Shortcut Escape.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: frow
    property string label: ""
    property string text: ""
    property color accentColor: "#89b4fa"
    property color textColor: "#cdd6f4"
    property color textDimColor: "#a6adc8"
    property bool focusActive: false
    signal submitted(string text)
    implicitHeight: 30

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Text {
            text: frow.label
            color: frow.textColor
            font.pixelSize: 12
            Layout.preferredWidth: 130
            elide: Text.ElideRight
        }

        TextField {
            id: tf
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: frow.text
            color: frow.textColor
            font.pixelSize: 12
            selectByMouse: true
            padding: 8
            verticalAlignment: Text.AlignVCenter
            selectionColor: Qt.rgba(frow.accentColor.r, frow.accentColor.g, frow.accentColor.b, 0.3)
            onAccepted: frow.submitted(tf.text)
            onActiveFocusChanged: frow.focusActive = tf.activeFocus

            background: Rectangle {
                radius: 8
                color: tf.activeFocus ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.08)
                border.width: tf.activeFocus ? 1 : 0
                border.color: Qt.rgba(frow.accentColor.r, frow.accentColor.g, frow.accentColor.b, 0.5)
            }
        }
    }
}
