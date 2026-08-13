// Sasquatch Control Center — FinderCard.qml
// Music Finder (Shazam) : micro → songrec → titre/artiste.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    color: Palette.card
    radius: 14
    border.color: Palette.accent2

    property var result: ({})
    property bool busy: false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        // ── header ──
        RowLayout {
            Layout.fillWidth: true
            Text { text: "🎵 Find Music"; font.pixelSize: 13; font.bold: true; color: Palette.text }
            Item { Layout.fillWidth: true }
            Text {
                text: "Shazam"
                font.pixelSize: 8; color: Palette.textDim
            }
        }

        Item { Layout.fillHeight: true }

        // ── état / résultat ──
        Text {
            id: statusTxt
            Layout.fillWidth: true
            text: {
                if (root.busy) return "🎙️ Écoute du micro… (6 s)";
                if (root.result.title) return "✔ " + root.result.title;
                return "Reconnais le morceau qui joue grâce au micro (Shazam).";
            }
            font.pixelSize: 11
            color: root.busy ? Palette.warn : (root.result.title ? Palette.good : Palette.textDim)
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }
        Text {
            Layout.fillWidth: true
            text: root.result.artist || (root.result.error ? "⚠ " + root.result.error : "")
            font.pixelSize: 10; color: root.result.error ? Palette.hot : Palette.textDim
            elide: Text.ElideRight
        }

        Btn {
            label: root.busy ? "⏳…" : "🎙️ Identifier"
            big: true
            Layout.preferredWidth: 140
            Layout.alignment: Qt.AlignHCenter
            enabled: !root.busy
            onClicked: {
                root.busy = true;
                root.result = {};
                statusTxt.color = Palette.warn;
                Api.post("/api/music/finder", {}, function(r) {
                    root.busy = false;
                    if (r && r.ok && r.title) {
                        root.result = r;
                    } else if (r && r.error) {
                        root.result = { error: r.error };
                        statusTxt.text = "Reconnaissance impossible";
                    } else {
                        statusTxt.text = "Aucun résultat";
                        statusTxt.color = Palette.hot;
                    }
                });
            }
        }
    }
}
