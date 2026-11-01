// harness.qml — harnais de test 900x620 (brief §1/§7 point 6).
//
// Jamais le CC plein écran : cette surface de 900x620, layer Top, exclusiveZone
// 0, montre 1 horloge `host: cc` (grille) + 1 horloge `host: background`
// (placement libre) et l'état réel du registre / du serveur.
//
// Preuve visuelle autonome : SASQUATCH_HARNESS_GRAB=/chemin.png écrit un rendu
// du harnais (sur ce compositeur les outils de capture n'exposent pas les
// surfaces layer — le harnais se rend donc lui-même avec grabToImage).
import QtQuick
import Quickshell
import Quickshell.Wayland
import Sasquatch.Widgets 1.0

ShellRoot {
    PanelWindow {
        id: win

        implicitWidth: 900
        implicitHeight: 620

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "sasquatch-widgets-harness"
        WlrLayershell.exclusiveZone: 0
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            left: true
        }
        margins {
            top: 60
            left: 60
        }

        // Tout le contenu vit dans `board` : c'est l'item que le rendu autonome
        // capture (le contentItem d'une surface layer n'a pas d'engine QML).
        Item {
            id: board
            anchors.fill: parent

            // Fond opaque du harnais : simule le papier peint derrière les
            // widgets, pour que le rendu autonome (grabToImage, sans alpha)
            // montre exactement ce que la couche verre donnera à l'écran.
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

                Row {
                    spacing: 18

                    Text {
                        text: "harnais widgets v1b — 900x620"
                        color: Theme.ink
                        font.pixelSize: 13
                    }
                    Text {
                        text: "registre: " + WidgetRegistry.entries.length
                              + " · api: " + (Api.online ? "ok" : "hors ligne")
                              + " · révision cc: " + ccHost.revision
                              + " · fond: " + bgHost.revision
                              + " · masque fond: " + bgHost.maskRects.length
                              + " · fond clair: " + (Theme.lightWallpaper ? "oui" : "non")
                        color: Theme.inkDim
                        font.pixelSize: 12
                    }
                }

                Text {
                    // Preuve vivante du contrat v1b : la source lue, et les
                    // compteurs de sondes (viz 60 ms uniquement si un cava est
                    // visible).
                    width: parent.width
                    text: "média: " + Music.sourceLabel
                          + (Music.hasTrack ? " — " + Music.title : " (rien)")
                          + " · polls status " + Music.statusPolls + " / viz " + Music.vizPolls
                          + " · cava visibles " + Music.vizRefs
                          + (Music.lastError.length > 0 ? " · " + Music.lastError : "")
                    color: Music.lastError.length > 0 ? Theme.hot : Theme.inkDim
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                // 1) Horloge host: cc — board 12 colonnes, ligne 96 px, écart 14.
                Rectangle {
                    width: parent.width
                    height: 288
                    radius: Theme.radiusCard
                    color: Theme.fill(0.08)
                    border.width: 1
                    border.color: Theme.a(Theme.accent, 0.18)

                    WidgetHost {
                        id: ccHost
                        anchors.fill: parent
                        anchors.margins: Theme.spacing
                        host: "cc"
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 6
                        text: "host: cc (grille 12 col · row 96 · gap 14)"
                        color: Theme.inkDim
                        font.pixelSize: 10
                    }
                }

                // 2) Horloge host: background — placement libre en fractions.
                Rectangle {
                    width: 620
                    height: 224
                    radius: Theme.radiusCard
                    color: Theme.fill(0.06)
                    border.width: 1
                    border.color: Theme.a(Theme.accent, 0.18)

                    WidgetHost {
                        id: bgHost
                        anchors.fill: parent
                        anchors.margins: Theme.spacing
                        host: "background"
                        // EN ÉDITION dans le harnais : prouve d'un coup le masque
                        // d'entrée construit sur TOUTES les instances (plus de
                        // plafond à 8, brief bugs §1.6) et les affordances de
                        // l'édition (contour accent, poignée de resize, drag).
                        // Hors édition, le même masque ne garde que les widgets
                        // `live` (le reste laisse passer le clic).
                        editing: true
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 6
                        text: "host: background — masque " + bgHost.maskRects.length
                              + "/" + bgHost.instances.length + " (édition)"
                        color: Theme.inkDim
                        font.pixelSize: 10
                    }
                }
            }
        }

        // Preuve visuelle autonome : SASQUATCH_HARNESS_GRAB=/chemin.png écrit un
        // rendu du harnais (sur ce compositeur les outils de capture n'exposent
        // pas les surfaces layer — le harnais se rend donc lui-même).
        // Quickshell.env renvoie undefined si la variable est absente :
        // "" + undefined donnerait "undefined", d'où le test de type.
        readonly property string grabPath: {
            var v = Quickshell.env("SASQUATCH_HARNESS_GRAB");
            return (typeof v === "string") ? v : "";
        }

        Timer {
            interval: 1800
            repeat: false
            running: win.grabPath.length > 0
            onTriggered: {
                if (win.grabPath.length === 0)
                    return;
                board.grabToImage(function (res) {
                    console.log("harness: rendu écrit =", res.saveToFile(win.grabPath));
                });
            }
        }
    }
}
