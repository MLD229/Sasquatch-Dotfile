// BarPosition.qml — trois boutons de position de la barre : Gauche / Haut / Droite.
//
// Purement visuel : il AFFICHE l'état réel (`value`, relu depuis bar.json par
// le panneau) et émet `chosen(key)` à l'interaction. Aucune écriture ici : le
// panneau passe par POST /api/bar -> barjson.py --set, qui ne change QUE la
// clé bar.position (indentation et ordre du fichier conservés).
//
// Les trois valeurs sont celles que la barre honore vraiment (left | top |
// right) : un bouton qui ne déplacerait rien serait un piège.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

RowLayout {
    id: pos

    property string value: "left"        // état RÉEL (relu du disque)
    property color accentColor: "#89b4fa"
    property color textColor: "#cdd6f4"
    property bool enabledItems: true

    signal chosen(string key)

    spacing: 6

    Repeater {
        model: [
            { key: "left", label: "Gauche" },
            { key: "top", label: "Haut" },
            { key: "right", label: "Droite" }
        ]

        delegate: Rectangle {
            id: btn

            required property var modelData

            readonly property bool current: pos.value === btn.modelData.key

            Layout.preferredHeight: 30
            Layout.preferredWidth: Math.max(74, btnLabel.implicitWidth + 24)
            radius: 8
            color: btn.current
                   ? Qt.rgba(pos.accentColor.r, pos.accentColor.g, pos.accentColor.b, 0.25)
                   : (btnArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
            border.width: btn.current ? 1 : 0
            border.color: Qt.rgba(pos.accentColor.r, pos.accentColor.g, pos.accentColor.b, 0.6)
            opacity: pos.enabledItems ? 1.0 : 0.5

            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                id: btnLabel
                anchors.centerIn: parent
                text: btn.modelData.label
                color: btn.current ? pos.accentColor : pos.textColor
                font.pixelSize: 11
                font.bold: btn.current
            }

            MouseArea {
                id: btnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: pos.enabledItems
                onClicked: pos.chosen(btn.modelData.key)
            }
        }
    }
}
