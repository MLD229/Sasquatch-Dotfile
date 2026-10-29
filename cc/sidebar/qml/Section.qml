// Section.qml — carte de section « verre dépoli » de la slide bar.
//
// Toutes les couleurs sont INJECTÉES par shell.qml (elles viennent de
// /api/palette → cc/qml/Palette.qml → theme-apply.py, relu toutes les 2 s).
// Aucune valeur en dur ici : c'est ce qui garantit que le panneau suit le
// wallpaper.
//
// Hiérarchie de verre (brief A) :
//   glassColor porte déjà son alpha → le panneau est plus opaque, les cartes
//   plus transparentes, le bloc TEMPS (hero) le plus léger.
//   order pilote l'apparition en cascade (fade + 8 px, 180 ms, 40 ms d'écart).
import QtQuick
import QtQuick.Layouts

Item {
    id: sec

    property string title: ""
    property color fgText: "white"
    // secours : shell.qml injecte toujours les couleurs de /api/palette
    property color fgDim: "#999999"
    property color glassColor: "#222222"
    property color borderColor: "#444444"
    property color shadowColor: "#000000"
    property bool hero: false
    property int order: 0
    property int innerMargins: 12
    property int radiusPx: 14

    default property alias content: col.children

    Layout.fillWidth: true
    // hauteur pilotée par le CONTENU (pas par glass, qui remplit la Section :
    // ce serait une dépendance circulaire → cartes de hauteur 0)
    implicitHeight: col.implicitHeight + innerMargins * 2
    opacity: 0
    transform: Translate {
        id: shift

        y: 8
    }

    // Dégradé vertical : haut plus clair (lumière) → bas plus dense.
    // hero = pièce « héro » : écart plus marqué pour qu'elle respire.
    readonly property color glassTop: Qt.lighter(sec.glassColor,
                                                sec.hero ? 1.30 : 1.12)
    readonly property color glassBottom: Qt.darker(sec.glassColor,
                                                  sec.hero ? 1.10 : 1.02)

    // Ombre douce sous la carte (détache du fond)
    Rectangle {
        anchors.fill: glass
        anchors.topMargin: 2
        anchors.leftMargin: -2
        anchors.rightMargin: -2
        anchors.bottomMargin: -4
        radius: sec.radiusPx + 3
        color: Qt.rgba(sec.shadowColor.r, sec.shadowColor.g,
                       sec.shadowColor.b, 0.22)
    }

    Rectangle {
        id: glass

        anchors.fill: parent
        radius: sec.radiusPx
        gradient: Gradient {
            GradientStop { position: 0.0; color: sec.glassTop }
            GradientStop { position: 1.0; color: sec.glassBottom }
        }
        border.width: 1
        border.color: Qt.rgba(sec.borderColor.r, sec.borderColor.g,
                              sec.borderColor.b, 0.26)

        // Liseré clair en haut de CHAQUE surface de verre
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: sec.radiusPx
            anchors.rightMargin: sec.radiusPx
            height: 1
            color: Qt.rgba(sec.fgText.r, sec.fgText.g, sec.fgText.b,
                           sec.hero ? 0.18 : 0.12)
        }

        ColumnLayout {
            id: col

            anchors.fill: parent
            anchors.margins: sec.innerMargins
            spacing: 8

            Text {
                Layout.fillWidth: true
                visible: sec.title !== ""
                text: sec.title
                color: sec.fgDim
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.2
            }
        }
    }

    // Cascade à l'ouverture : fade + translation, une seule courbe (OutCubic)
    SequentialAnimation {
        id: intro

        running: false
        PauseAnimation { duration: 60 + sec.order * 40 }
        ParallelAnimation {
            NumberAnimation {
                target: sec
                property: "opacity"
                from: 0
                to: 1
                duration: 180
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: shift
                property: "y"
                from: 8
                to: 0
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
    }

    Component.onCompleted: intro.start()
}
