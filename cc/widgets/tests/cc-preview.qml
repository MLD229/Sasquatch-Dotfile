// cc-preview.qml — PREUVE des tranches v1c-1 et v1c-2 (brief §8 : jamais le
// CC plein écran). PanelWindow 1200x760, layer Top, exclusiveZone 0, namespace
// sasquatch-cc-preview, quatre onglets :
//   1 Accueil  → HomePage  (hôte `cc` réel : lit cc/widgets.json)
//   2 Système  → SystemPage (copie du bloc perf)
//   3 Outils   → ToolsPage  (copie des blocs capture/OCR/recherche/traduction)
//   4 Studio   → StudioPage (l'espace widget : catalogue, aperçu 16:9 du fond,
//                panneau de style — lit le vrai wallpaper et le vrai widgets.json)
//
// Rendu autonome : SASQUATCH_HARNESS_GRAB=/chemin/base.png écrit QUATRE PNG
// (base-1.png … base-4.png), un par onglet — sur ce compositeur les surfaces
// layer ne sont pas capturables de l'extérieur.
//
// Lancement :
//   QML_IMPORT_PATH="$HOME/.config/cc/widgets:$HOME/.config/cc" \
//     timeout 20 quickshell -p cc/widgets/tests/cc-preview.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import Sasquatch.Widgets 1.0
import pages 1.0

ShellRoot {
    PanelWindow {
        id: win

        implicitWidth: 1200
        implicitHeight: 760

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "sasquatch-cc-preview"
        WlrLayershell.exclusiveZone: 0
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            left: true
        }
        margins {
            top: 40
            left: 40
        }

        property int tab: 0

        // Tout le contenu vit dans `board` : c'est l'item capturé (le
        // contentItem d'une surface layer n'a pas d'engine QML).
        Item {
            id: board
            anchors.fill: parent

            // Fond opaque : simule le papier peint derrière le verre.
            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusPanel
                color: Theme.a(Theme.bgSolid, 1.0)
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusPanel
                color: Theme.panelFill(Theme.alphaPanel)
                border.width: 1
                border.color: Theme.border
            }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacing
                spacing: Theme.spacing

                // ── barre d'onglets + état réel ───────────────────────────
                Row {
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: [
                            { k: 0, t: "Accueil · HomePage" },
                            { k: 1, t: "Système · SystemPage" },
                            { k: 2, t: "Outils · ToolsPage" },
                            { k: 3, t: "Studio · StudioPage" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: tabLabel.implicitWidth + 24
                            height: 30
                            radius: Theme.radiusBtn
                            color: win.tab === modelData.k
                                   ? Theme.a(Theme.accent, 0.85)
                                   : Theme.a(Theme.text, 0.06)
                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: modelData.t
                                font.pixelSize: 11
                                color: win.tab === modelData.k ? Theme.ink : Theme.inkDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.tab = modelData.k
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "api: " + (Api.online ? "ok" : "hors ligne")
                              + " · registre: " + WidgetRegistry.entries.length
                              + " · fond clair: " + (Theme.lightWallpaper ? "oui" : "non")
                        color: Api.online ? Theme.inkDim : Theme.hot
                        font.pixelSize: 11
                    }
                }

                // ── pages (une seule visible : mêmes instances que le CC) ──
                Item {
                    width: parent.width
                    height: parent.height - 44

                    HomePage {
                        anchors.fill: parent
                        visible: win.tab === 0
                    }
                    SystemPage {
                        anchors.fill: parent
                        visible: win.tab === 1
                    }
                    ToolsPage {
                        anchors.fill: parent
                        visible: win.tab === 2
                    }
                    StudioPage {
                        id: studioPreview
                        anchors.fill: parent
                        visible: win.tab === 3
                    }
                }
            }
        }

        // ── rendu autonome (même variable que le harnais v1a/v1b) ─────────
        readonly property string grabBase: {
            var v = Quickshell.env("SASQUATCH_HARNESS_GRAB");
            return (typeof v === "string") ? v : "";
        }
        property int grabIndex: 0

        function nextGrab() {
            if (win.grabIndex > 3) {
                console.log("preview: 4 rendus écrits — fin");
                return;
            }
            win.tab = win.grabIndex;
            grabTick.start();
        }

        Timer {
            id: warmup
            interval: 2500
            repeat: false
            running: win.grabBase.length > 0
            onTriggered: win.nextGrab()
        }

        // Rendu de preuve : on sélectionne la PREMIÈRE instance du fond pour que
        // le panneau de style apparaisse rempli (valeurs relues de
        // widgets.json). Aucun id en dur : il change à chaque ajout.
        // Actif uniquement en mode capture — l'usage interactif n'est pas
        // pré-sélectionné.
        Timer {
            interval: 1800
            repeat: false
            running: win.grabBase.length > 0
            onTriggered: {
                var list = studioPreview.bgInstances;
                if (list.length > 0)
                    studioPreview.select(list[0].id);
            }
        }

        Timer {
            id: grabTick
            interval: 1100
            repeat: false
            onTriggered: {
                var idx = win.grabIndex;
                var base = win.grabBase;
                var path = (base.slice(-4) === ".png")
                           ? base.substring(0, base.length - 4) + "-" + (idx + 1) + ".png"
                           : base + "-" + (idx + 1) + ".png";
                board.grabToImage(function (res) {
                    console.log("preview: rendu", idx + 1, "onglet", win.tab,
                                "→", res.saveToFile(path));
                    win.grabIndex = idx + 1;
                    win.nextGrab();
                });
            }
        }
    }
}
