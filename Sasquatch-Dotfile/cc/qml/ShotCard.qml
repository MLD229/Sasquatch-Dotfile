// Sasquatch Control Center — ShotCard.qml
// Screenshot Wayland (grim/slurp) — 3 modes. Le serveur ferme le CC avant la capture.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    color: Palette.card
    radius: 14
    border.color: Palette.accent2

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Text { text: "📸 Screenshot"; font.pixelSize: 13; font.bold: true; color: Palette.text }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ShotBtn { label: "⬚\nZone"; mode: "area" }
            ShotBtn { label: "🖥️\nPlein écran"; mode: "full" }
            ShotBtn { label: "🗔\nFenêtre"; mode: "window" }
        }

        Text {
            Layout.fillWidth: true
            text: "Copié dans le presse-papier · sauvegardé dans ~/Pictures/Screenshots"
            font.pixelSize: 9; color: Palette.textDim
            wrapMode: Text.WordWrap
        }
    }

    component ShotBtn: Rectangle {
        id: btn
        property string label: ""
        property string mode: "area"
        Layout.fillWidth: true
        Layout.preferredHeight: 64
        radius: 10
        color: Palette.bgSolid
        border.color: Palette.accent2
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: btn.label
            font.pixelSize: 11; color: Palette.text
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 1.4
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: Api.post("/api/screenshot?mode=" + btn.mode)
            onEntered: btn.color = Palette.accent2
            onExited: btn.color = Palette.bgSolid
        }
    }
}
