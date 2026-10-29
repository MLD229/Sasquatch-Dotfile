// Pill.qml — bouton de mode (toggle) de la slide bar, en verre fumé.
//
// États (brief B) : repos / survol / pressé / actif, plus « indisponible »
// (hyprsunset manquant, mako arrêté, session Hyprland absente) : opacité 0.35,
// curseur interdit et bulle d'aide qui dit POURQUOI — jamais un bouton qui ne
// répond pas en silence.
//
// Aucune couleur en dur : baseColor / accentColor / fgText sont INJECTÉS par
// shell.qml depuis /api/palette.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: pill

    property string glyph: ""
    property string label: ""
    property bool on: false
    property bool unavailable: false
    property string hint: ""          // raison de l'indisponibilité

    // secours : shell.qml injecte toujours les couleurs de /api/palette
    property color baseColor: "#333333"
    property color accentColor: "#666666"
    property color fgText: "white"
    property color fgDim: "#999999"
    property color warnColor: "#f9e2af"
    property color highlightColor: "white"

    signal toggled()

    Layout.fillWidth: true
    implicitHeight: 44
    opacity: unavailable ? 0.35 : 1.0
    scale: ma.pressed ? 0.97 : 1.0
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

    // Halo accent derrière le verre quand le mode est actif
    Rectangle {
        anchors.centerIn: body
        width: body.width + 6
        height: body.height + 6
        radius: body.radius + 3
        color: Qt.rgba(pill.accentColor.r, pill.accentColor.g,
                       pill.accentColor.b, 0.30)
        opacity: pill.on && !pill.unavailable ? 1.0 : 0.0

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
        radius: 11
        clip: true

        color: pill.unavailable ? Qt.lighter(pill.baseColor, 0.85)
             : pill.on          ? Qt.lighter(pill.baseColor, 1.06)
             : ma.containsMouse ? Qt.lighter(pill.baseColor, 1.22)
             : pill.baseColor
        border.width: 1
        border.color: pill.on ? Qt.rgba(pill.accentColor.r, pill.accentColor.g,
                                        pill.accentColor.b, 0.60)
                    : ma.containsMouse ? Qt.rgba(pill.accentColor.r, pill.accentColor.g,
                                                 pill.accentColor.b, 0.45)
                    : Qt.rgba(pill.highlightColor.r, pill.highlightColor.g,
                              pill.highlightColor.b, 0.10)

        Behavior on color {
            ColorAnimation {
                duration: 90
                easing.type: Easing.OutCubic
            }
        }

        // Toggle : le remplissage accent balaie de gauche à droite
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: pill.on ? parent.width : 0
            radius: body.radius
            color: Qt.rgba(pill.accentColor.r, pill.accentColor.g,
                           pill.accentColor.b, 0.30)

            Behavior on width {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Liseré clair (verre)
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            height: 1
            radius: 0.5
            color: Qt.rgba(pill.highlightColor.r, pill.highlightColor.g,
                           pill.highlightColor.b, pill.on ? 0.16 : 0.11)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 7

            Text {
                text: pill.glyph
                font.pixelSize: 13
                scale: pill.on ? 1.06 : 1.0
                transformOrigin: Item.Center

                Behavior on scale {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: pill.label
                elide: Text.ElideRight
                color: pill.unavailable ? pill.warnColor : pill.fgText
                font.pixelSize: 11
                font.bold: pill.on
            }
            Text {
                visible: pill.unavailable
                text: "!"
                color: pill.warnColor
                font.pixelSize: 11
                font.bold: true
            }
        }
    }

    MouseArea {
        id: ma

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pill.unavailable ? Qt.ForbiddenCursor : Qt.PointingHandCursor
        onClicked: pill.toggled()
    }

    // Detection du survol au niveau de l'Item (le ToolTip enfant s'affiche
    // quand son parent est survolé ; la MouseArea ne suffit pas).
    HoverHandler {
        id: hh
    }

    // Bulle d'aide stylée (verre) : le style Golden par défaut de Qt jure avec
    // le panneau. Elle ne sert qu'au cas « indisponible ».
    ToolTip {
        id: tip

        visible: pill.unavailable && pill.hint !== "" && hh.hovered
        delay: 200
        text: pill.hint
        contentItem: Text {
            text: tip.text
            color: pill.fgText
            font.pixelSize: 10
        }
        background: Rectangle {
            radius: 8
            color: pill.baseColor
            border.width: 1
            border.color: Qt.rgba(pill.accentColor.r, pill.accentColor.g,
                                  pill.accentColor.b, 0.45)
        }
    }
}
