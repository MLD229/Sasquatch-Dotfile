// shell.qml — hôte « fond d'écran » des widgets (brief §5, v1a).
//
// Une surface layer `Background` PAR ÉCRAN (Variants + Quickshell.screens),
// transparente, exclusiveZone 0 : les widgets flottent sur le papier peint,
// sous toutes les fenêtres, sans rien réserver.
//
// Région d'entrée = UNION DES WIDGETS uniquement (mask: Region imbriquées,
// défaut Intersection.Combine) : partout ailleurs les clics traversent la
// surface. Hors édition un widget de fond est inerte, sauf `live` (media,
// clock) où le clic ouvre le CC — c'est WidgetBase qui décide.
//
// Le masque d'entrée est construit à partir des instances RÉELLES
// (BackgroundMask) : pas de plafond d'emplacements, un 9ᵉ widget de fond est
// cliquable, et un emplacement vide n'émet aucun rectangle (brief bugs §1.6).
// Hors édition seuls les widgets `live` captent : les autres laissent passer le
// clic au lieu de l'avaler (brief bugs §3).
// Le placement vient de widgets.json (host: background), jamais d'ici.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Sasquatch.Widgets 1.0

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: bgWin
            required property var modelData

            screen: bgWin.modelData

            // Layer BOTTOM, pas Background : hyprpaper (et tout changeur de fond)
            // remonte SA surface sur la couche `background` à chaque changement
            // de wallpaper et recouvre alors nos widgets (ils disparaissent).
            // Bottom = au-dessus du papier peint, en dessous des fenêtres.
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "sasquatch-background"
            WlrLayershell.exclusiveZone: 0
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Tout le contenu vit dans `board` : c'est l'item qu'une preuve de
            // rendu peut capturer (le contentItem d'une surface layer n'a pas
            // d'engine QML, et sur ce compositeur aucun outil externe ne voit
            // les surfaces layer).
            Item {
                id: board
                anchors.fill: parent

                WidgetHost {
                    id: bgHost
                    anchors.fill: parent
                    host: "background"
                }
            }

            // Preuve de rendu opt-in : SASQUATCH_BG_GRAB=/chemin.png.
            // (Quickshell.env renvoie undefined si la variable est absente :
            // "" + undefined donnerait "undefined", d'où le test de type.)
            readonly property string grabPath: {
                var v = Quickshell.env("SASQUATCH_BG_GRAB");
                return (typeof v === "string") ? v : "";
            }

            Timer {
                interval: 1800
                repeat: false
                running: bgWin.grabPath.length > 0
                onTriggered: {
                    if (bgWin.grabPath.length === 0)
                        return;
                    board.grabToImage(function (res) {
                        console.log("background: rendu écrit =", res.saveToFile(bgWin.grabPath));
                    });
                }
            }

            // Masque d'entrée : un rectangle par widget qui doit capter la
            // souris, aucun nombre codé en dur. Reconstruit quand les
            // instances, le mode édition ou la résolution changent.
            mask: bgMask.region

            BackgroundMask {
                id: bgMask
                rects: bgHost.maskRects
                radius: Theme.radiusCard
            }
        }
    }
}