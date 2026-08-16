// PlRow — ligne de la playlist courante (panneau Sasquatch Playlist).
// Clic = jouer la piste ; ✕ = la retirer ; surlignage de la piste courante.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: row

    signal playClicked(int pos)
    signal removeClicked(int pos)

    required property int pos
    required property string title
    required property string sub
    required property int dur
    required property bool current

    property color accent: "#89b4fa"
    property color textColor: "#cdd6f4"
    property color dimColor: "#a6adc8"
    property color cardColor: Qt.rgba(0.09, 0.10, 0.12, 0.9)

    Layout.fillWidth: true
    Layout.preferredHeight: 38
    radius: 9
    color: hovered || current
           ? Qt.rgba(accent.r, accent.g, accent.b, current ? 0.18 : 0.09)
           : cardColor
    border.width: current ? 1 : 0
    border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.5)

    property bool hovered: false

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        spacing: 10

        Text {
            text: row.current ? "▶" : (row.pos + 1)
            font.pixelSize: 11
            font.bold: row.current
            color: row.current ? row.accent : row.dimColor
            Layout.preferredWidth: 26
        }
        Text {
            text: row.title
            font.pixelSize: 12
            font.bold: row.current
            color: row.textColor
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            text: row.sub
            font.pixelSize: 11
            color: row.dimColor
            elide: Text.ElideRight
            Layout.preferredWidth: 180
            visible: row.sub.length > 0
        }
        Text {
            text: row.fmtDur(row.dur)
            font.pixelSize: 11
            color: row.dimColor
            Layout.preferredWidth: 44
            horizontalAlignment: Text.AlignRight
        }
        Text {
            text: "✕"
            font.pixelSize: 13
            color: rmArea.rmHover ? "#f38ba8" : row.dimColor
            Layout.preferredWidth: 24
            horizontalAlignment: Text.AlignHCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: row.hovered = true
        onExited: row.hovered = false
        onClicked: row.playClicked(row.pos)
    }
    MouseArea {
        // Zone ✕ (détachée du clic principal)
        id: rmArea
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 34
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        property bool rmHover: false
        onEntered: rmHover = true
        onExited: rmHover = false
        onClicked: row.removeClicked(row.pos)
    }

    function fmtDur(s) {
        if (!s || s <= 0) return "";
        var m = Math.floor(s / 60);
        var sec = Math.floor(s % 60);
        return m + ":" + (sec < 10 ? "0" : "") + sec;
    }
}
