// PlLibRow — ligne de résultat de recherche bibliothèque (panneau playlist).
// Clic = ajouter le morceau à la playlist (et le jouer).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: row

    signal addClicked(string file)

    required property string file
    required property string title
    required property string sub

    property color accent: "#89b4fa"
    property color textColor: "#cdd6f4"
    property color dimColor: "#a6adc8"
    property color cardColor: Qt.rgba(0.09, 0.10, 0.12, 0.9)

    Layout.fillWidth: true
    Layout.preferredHeight: 34
    radius: 8
    color: row.hovered ? Qt.rgba(accent.r, accent.g, accent.b, 0.12) : cardColor

    property bool hovered: false

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 10

        Text {
            text: "＋"
            font.pixelSize: 14
            font.bold: true
            color: row.accent
            Layout.preferredWidth: 20
        }
        Text {
            text: row.title
            font.pixelSize: 12
            color: row.textColor
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            text: row.sub
            font.pixelSize: 11
            color: row.dimColor
            elide: Text.ElideRight
            Layout.preferredWidth: 200
            visible: row.sub.length > 0
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: row.hovered = true
        onExited: row.hovered = false
        onClicked: row.addClicked(row.file)
    }
}
