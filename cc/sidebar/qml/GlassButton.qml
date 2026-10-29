// GlassButton.qml — bouton « verre fumé » de la slide bar.
//
// 4 états (exigence brief B) :
//   repos    → fond fumé, bordure discrète
//   survol   → fond éclairci + bordure accent 0.45 (90 ms)
//   pressé   → scale 0.97 (80 ms)
//   actif    → remplissage accent qui BALAIE (clip animé, 160 ms) + halo accent
//
// Aucune couleur en dur : baseColor / accentColor / fgText sont INJECTÉS par
// shell.qml, qui les calcule depuis /api/palette (Qt.lighter / Qt.darker /
// Qt.rgba). Les variantes survol/pressé sont dérivées ici avec Qt.lighter,
// donc elles suivent aussi le wallpaper.
import QtQuick

Item {
    id: btn

    property string glyph: ""
    property string label: ""
    property bool on: false
    property bool unavailable: false
    property string hint: ""            // raison de l'indisponibilité

    // secours : shell.qml injecte toujours les teintes calculées
    property color baseColor: "#333333"
    property color accentColor: "#666666"
    property color fgText: "white"
    property color fgDim: "#999999"
    property color highlightColor: "white"

    property int radiusPx: 10
    property int padH: 10
    property bool bold: false

    signal clicked()

    readonly property bool hovered: ma.containsMouse
    readonly property bool held: ma.pressed

    implicitHeight: 30
    implicitWidth: Math.max(implicitHeight, row.implicitWidth + padH * 2)
    opacity: unavailable ? 0.35 : 1.0
    scale: held ? 0.97 : 1.0
    transformOrigin: Item.Center

    Behavior on scale {
        NumberAnimation {
            duration: 80
            easing.type: Easing.OutCubic
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    // Halo accent (derrière le verre, donc sous body)
    Rectangle {
        anchors.centerIn: body
        width: body.width + 8
        height: body.height + 8
        radius: btn.radiusPx + 4
        color: Qt.rgba(btn.accentColor.r, btn.accentColor.g,
                       btn.accentColor.b, 0.30)
        opacity: btn.on && !btn.unavailable ? 1.0 : 0.0

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
        radius: btn.radiusPx
        clip: true

        color: btn.unavailable ? Qt.lighter(btn.baseColor, 0.85)
             : btn.on          ? Qt.lighter(btn.baseColor, 1.06)
             : btn.hovered     ? Qt.lighter(btn.baseColor, 1.22)
             : btn.baseColor
        border.width: 1
        border.color: btn.on ? Qt.rgba(btn.accentColor.r, btn.accentColor.g,
                                       btn.accentColor.b, 0.60)
                    : btn.hovered ? Qt.rgba(btn.accentColor.r, btn.accentColor.g,
                                            btn.accentColor.b, 0.45)
                    : Qt.rgba(btn.highlightColor.r, btn.highlightColor.g,
                              btn.highlightColor.b, 0.10)

        Behavior on color {
            ColorAnimation {
                duration: 90
                easing.type: Easing.OutCubic
            }
        }

        // Remplissage actif : balaie de gauche à droite (toggle sweep)
        Rectangle {
            id: sweep

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: btn.on ? parent.width : 0
            radius: btn.radiusPx
            color: Qt.rgba(btn.accentColor.r, btn.accentColor.g,
                           btn.accentColor.b, 0.30)

            Behavior on width {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Liseré clair : c'est ce qui « accroche la lumière » du verre
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            height: 1
            radius: 0.5
            color: Qt.rgba(btn.highlightColor.r, btn.highlightColor.g,
                           btn.highlightColor.b, btn.on ? 0.16 : 0.11)
        }

        Row {
            id: row

            anchors.centerIn: parent
            spacing: btn.glyph !== "" && btn.label !== "" ? 6 : 0

            Text {
                visible: btn.glyph !== ""
                text: btn.glyph
                color: btn.unavailable ? btn.fgDim : btn.fgText
                font.pixelSize: 13
                scale: btn.on ? 1.06 : 1.0
                transformOrigin: Item.Center

                Behavior on scale {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Text {
                visible: btn.label !== ""
                text: btn.label
                color: btn.unavailable ? btn.fgDim : btn.fgText
                font.pixelSize: 10
                font.bold: btn.bold || btn.on
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: ma

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.unavailable ? Qt.ForbiddenCursor : Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
