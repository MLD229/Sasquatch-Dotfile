// Sasquatch Control Center — ImgSearchCard.qml
// Recherche d'images : depuis l'écran (OCR) ou par texte saisi.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: Palette.card
    radius: 14
    border.color: Palette.accent2

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        // ── header ──
        RowLayout {
            Layout.fillWidth: true
            Text { text: "🔎 Image Search"; font.pixelSize: 13; font.bold: true; color: Palette.text }
            Item { Layout.fillWidth: true }
            Text {
                text: "DuckDuckGo"
                font.pixelSize: 8; color: Palette.textDim
            }
        }

        // ── recherche depuis l'écran ──
        Btn {
            label: "🖥️ Depuis l'écran (OCR)"
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            onClicked: Api.post("/api/imgsearch", {})
        }

        // ── recherche par texte ──
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: Palette.cardSolid
                border.color: Palette.accent2

                TextField {
                    id: searchField
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 10
                    rightPadding: 10
                    color: Palette.text
                    font.pixelSize: 11
                    clip: true
                    selectByMouse: true
                    placeholderText: "texte à chercher…"
                    placeholderTextColor: Palette.textDim
                    background: null
                }
            }
            Btn {
                label: "🔎"
                Layout.preferredWidth: 40
                Layout.fillHeight: true
                onClicked: {
                    var q = searchField.text.trim();
                    if (q) Api.post("/api/imgsearch", { q: q });
                }
            }
        }
    }
}
