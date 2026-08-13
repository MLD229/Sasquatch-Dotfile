// Sasquatch Control Center — TranslateCard.qml
// Traduction depuis l'écran : zone → OCR → Google Translate → notification.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    color: Palette.card
    radius: 14
    border.color: Palette.accent2

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text { text: "🌐 Translate from Screen"; font.pixelSize: 13; font.bold: true; color: Palette.text }
            Text {
                Layout.fillWidth: true
                text: "Sélectionne une zone → OCR → traduction (vers le français) → notification + presse-papier."
                font.pixelSize: 9; color: Palette.textDim
                wrapMode: Text.WordWrap
            }
        }

        Btn {
            label: "🖱️ Sélectionner une zone"
            big: true
            Layout.preferredWidth: 180
            Layout.preferredHeight: 40
            onClicked: Api.post("/api/translate", {})
        }
    }
}
