// Sasquatch Control Center — ShortcutsCard.qml
// Rappel des raccourcis du dotfile.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    color: Palette.card
    radius: 14
    border.color: Palette.accent2

    property var shortcuts: [
        { key: "Super+G", desc: "Control Center" },
        { key: "Super+V", desc: "Presse-papier" },
        { key: "Super+C", desc: "Calculatrice" },
        { key: "Ctrl+Shift+1", desc: "IME japonais" },
        { key: "Super+PrtSc", desc: "Screenshot zone" },
        { key: "PrtSc", desc: "Screenshot plein écran" }
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        Text { text: "⌨️ Raccourcis"; font.pixelSize: 13; font.bold: true; color: Palette.text }

        Repeater {
            model: root.shortcuts
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 110
                    Layout.preferredHeight: 20
                    radius: 6
                    color: Palette.accent2
                    Text {
                        anchors.centerIn: parent
                        text: modelData.key
                        font.pixelSize: 9; color: Palette.accent
                    }
                }
                Text {
                    text: modelData.desc
                    font.pixelSize: 10; color: Palette.text
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }
}
