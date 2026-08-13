// Sasquatch Control Center — main.qml
// Overlay plein écran : le desktop reste visible derrière, assombri
// par un voile semi-transparent (Palette.overlay). Le dashboard est
// centré, en cartes indépendantes, responsive.
// Se ferme : bouton ✕, Escape, clic sur le voile, Super+G (toggle).
import Quickshell
import QtQuick
import QtQuick.Layouts

FloatingWindow {
    id: root
    title: "Sasquatch CC"
    implicitWidth: Screen.width
    implicitHeight: Screen.height
    visible: true
    color: "transparent"

    // fermeture : prévient le serveur (il s'auto-arrête) puis quitte
    function quit() {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:8765/api/close");
        xhr.send();
        Qt.quit();
    }
    // si Hyprland ferme la fenêtre (toggle Super+G, screenshot, OCR…) → quitter
    onVisibleChanged: if (!visible) root.quit()

    Shortcut { sequence: "Escape"; onActivated: root.quit() }

    // ── voile plein écran : desktop assombri + clic dehors = fermer ──
    Rectangle {
        id: dim
        anchors.fill: parent
        color: Palette.overlay
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Component.onCompleted: opacity = 1

        MouseArea {
            anchors.fill: parent
            onClicked: root.quit()
        }
    }

    // ── dashboard centré ──
    Item {
        anchors.fill: parent
        anchors.margins: 40

        Rectangle {
            id: dash
            anchors.centerIn: parent
            width: Math.min(1180, parent.width)
            height: Math.min(800, parent.height)
            color: Palette.bg
            radius: 18
            border.color: Palette.accent2
            border.width: 1
            clip: true

            opacity: 0
            scale: 0.98
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Component.onCompleted: { opacity = 1; scale = 1; }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                // ── header ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32

                    Text { text: "⚡"; font.pixelSize: 24 }
                    ColumnLayout {
                        spacing: 0
                        Text { text: "Sasquatch Control Center"; font.pixelSize: 17; font.bold: true; color: Palette.text }
                        Text {
                            id: subStatus
                            text: "initialisation…"
                            font.pixelSize: 9; color: Palette.textDim
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        id: clockText
                        font.pixelSize: 15; font.bold: true; color: Palette.text
                    }
                    Btn { label: "✕"; onClicked: root.quit() }
                }

                // ── rangée 1 : performance + musique ──
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 2
                    columnSpacing: 14
                    rowSpacing: 14

                    PerfCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 240
                    }
                    MusicCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 240
                    }
                }

                // ── rangée 2 : screenshot + finder + recherche d'images ──
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 3
                    columnSpacing: 14
                    rowSpacing: 14

                    ShotCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 170
                    }
                    FinderCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 170
                    }
                    ImgSearchCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 170
                    }
                }

                // ── rangée 3 : traduction depuis l'écran ──
                TranslateCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 96
                }

                // ── footer ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 14
                    Text {
                        id: statusText
                        text: "Serveur prêt ✓"
                        font.pixelSize: 9; color: Palette.good
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Esc / ✕ / clic dehors pour fermer"
                        font.pixelSize: 9; color: Palette.textDim
                    }
                }
            }
        }
    }

    // ── horloge + sous-statut ──
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var d = new Date();
            var hh = ("0" + d.getHours()).slice(-2);
            var mm = ("0" + d.getMinutes()).slice(-2);
            clockText.text = hh + ":" + mm;
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            Api.get("/api/stats", function(s) {
                if (!s) {
                    statusText.text = "serveur injoignable…";
                    statusText.color = Palette.hot;
                    return;
                }
                subStatus.text = s.hostname + " · " + s.refresh + " Hz · "
                        + (s.ram ? s.ram.pct + "% RAM" : "");
            });
        }
    }
}
