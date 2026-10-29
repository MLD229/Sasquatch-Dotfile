// GlassButton.qml — bouton « verre fumé » de la sidebar 愛子.
// Même langage visuel que cc/sidebar/qml/GlassButton.qml, version resserrée :
//   4 états — repos / survol / pressé / actif — animations OutCubic sobres.
// Aucune couleur en dur : les teintes sont injectées par shell.qml, calculées
// depuis /api/palette (donc le panneau suit le wallpaper).
import QtQuick
import QtQuick.Controls

Item {
    id: btn

    property string glyph: ""
    property string label: ""
    property bool on: false
    property bool busy: false
    property bool compact: false
    property string hint: ""

    property color baseColor: "#333333"
    property color accentColor: "#666666"
    property color fgText: "#ffffff"
    property color fgDim: "#999999"
    property color borderColor: "#555555"

    signal clicked()

    readonly property bool hovered: ma.containsMouse
    readonly property bool held: ma.pressed
    readonly property int padH: compact ? 8 : 11

    implicitHeight: compact ? 24 : 28
    implicitWidth: Math.max(implicitHeight, row.implicitWidth + padH * 2)
    scale: held ? 0.96 : 1.0
    opacity: busy ? 0.75 : 1.0
    transformOrigin: Item.Center

    Behavior on scale {
        NumberAnimation {
            duration: 80
            easing.type: Easing.OutCubic
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    // Halo accent, derrière le corps
    Rectangle {
        anchors.fill: body
        anchors.margins: -2
        radius: body.radius + 2
        color: btn.accentColor
        opacity: btn.on ? 0.22 : (btn.hovered ? 0.10 : 0.0)
        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        id: body

        anchors.fill: parent
        radius: 8
        color: btn.on ? Qt.rgba(btn.accentColor.r, btn.accentColor.g,
                                btn.accentColor.b, 0.30)
                      : Qt.rgba(btn.baseColor.r, btn.baseColor.g,
                                btn.baseColor.b, btn.hovered ? 0.85 : 0.62)
        border.width: 1
        border.color: btn.on ? btn.accentColor
                             : (btn.hovered ? Qt.rgba(btn.accentColor.r,
                                                      btn.accentColor.g,
                                                      btn.accentColor.b, 0.55)
                                            : btn.borderColor)
        Behavior on color {
            ColorAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        Row {
            id: row

            anchors.centerIn: parent
            spacing: btn.label.length > 0 && btn.glyph.length > 0 ? 6 : 0

            Text {
                visible: btn.glyph.length > 0
                text: btn.glyph
                color: btn.on ? btn.fgText : btn.fgDim
                font.pixelSize: btn.compact ? 10 : 11
                font.bold: btn.on
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: btn.label.length > 0
                text: btn.label
                color: btn.on ? btn.fgText : btn.fgDim
                font.pixelSize: btn.compact ? 10 : 11
                font.letterSpacing: 0.4
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    MouseArea {
        id: ma

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }

    ToolTip {
        visible: btn.hovered && btn.hint.length > 0
        text: btn.hint
        delay: 500
    }
}
