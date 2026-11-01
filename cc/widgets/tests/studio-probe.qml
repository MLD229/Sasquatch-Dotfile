// studio-probe.qml — preuve « ajout visible dans l'aperçu SANS redémarrage ».
//
// Jamais le CC plein écran (brief v1 §9) : une surface layer Top 1200x760 qui
// ne contient QUE StudioPage (donc le vrai aperçu, le vrai registre, le vrai
// widgets.json et le vrai POST /api/widgets).
//
// Scénario, sans restart et sans clic :
//   1. t≈2,5 s  relevé AVANT  → instances de fond, rendu prêt/en attente
//   2. t≈2,7 s  studio.addWidget(<type>) — même code que le bouton « + »
//   3. t≈4,7 s  relevé APRÈS → l'instance ajoutée est là ET dessinée
//   4. t≈4,9 s  rendu PNG de l'aperçu (SASQUATCH_STUDIO_GRAB)
//   5. t≈5,7 s  retrait de l'instance : le fichier ressort comme il est entré
//
// Les compteurs `previewReady` / `previewPending` viennent du canvas lui-même
// (chaque Loader publie son statut) : « posé = dessiné » est donc mesuré, pas
// supposé.
//
// Variables : SASQUATCH_STUDIO_ADD (type à ajouter, « calendar » par défaut),
//             SASQUATCH_STUDIO_GRAB (chemin PNG du rendu de l'aperçu).
import QtQuick
import Quickshell
import Quickshell.Wayland
import Sasquatch.Widgets 1.0
import pages 1.0

ShellRoot {
    id: probe

    readonly property string addType: {
        var v = Quickshell.env("SASQUATCH_STUDIO_ADD");
        return (typeof v === "string" && v.length > 0) ? v : "calendar";
    }
    readonly property string grabPath: {
        var v = Quickshell.env("SASQUATCH_STUDIO_GRAB");
        return (typeof v === "string") ? v : "";
    }

    property int before: -1
    property int beforeReady: -1
    property int after: -1
    property int afterReady: -1
    property int afterPending: -1

    function ids() {
        var out = [];
        for (var i = 0; i < studio.bgInstances.length; ++i)
            out.push(studio.bgInstances[i].id);
        return out.join(",");
    }

    function report(tag) {
        console.log("STUDIO-PROBE", tag,
                    "| instances", studio.bgInstances.length, "[" + probe.ids() + "]",
                    "| rendu", studio.previewReady + "/" + studio.bgInstances.length,
                    "en attente", studio.previewPending,
                    "| revision", studio.revision,
                    "POST", studio.postCount,
                    "err", studio.lastError);
    }

    PanelWindow {
        id: win

        implicitWidth: 1200
        implicitHeight: 760

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "sasquatch-studio-probe"
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

        Item {
            id: board
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusPanel
                color: Theme.a(Theme.bgSolid, 1.0)
            }

            StudioPage {
                id: studio
                anchors.fill: parent
                anchors.margins: Theme.spacing
            }

            // Cadence unique (250 ms), aucun timer orphelin.
            property int tick: 0

            Timer {
                interval: 250
                repeat: true
                running: true
                onTriggered: {
                    board.tick += 1;
                    if (board.tick === 10) {
                        probe.before = studio.bgInstances.length;
                        probe.beforeReady = studio.previewReady;
                        probe.report("AVANT");
                        studio.addWidget(probe.addType);
                    } else if (board.tick === 20) {
                        probe.after = studio.bgInstances.length;
                        probe.afterReady = studio.previewReady;
                        probe.afterPending = studio.previewPending;
                        probe.report("APRES");
                        if (probe.grabPath.length > 0) {
                            board.grabToImage(function (res) {
                                console.log("STUDIO-PROBE rendu →", res.saveToFile(probe.grabPath));
                            });
                        }
                    } else if (board.tick === 24) {
                        // Nettoyage : on retire l'instance ajoutée par la sonde.
                        for (var i = studio.bgInstances.length - 1; i >= 0; --i) {
                            var it = studio.bgInstances[i];
                            if (it && it.type === probe.addType)
                                studio.removeWidget(it.id);
                        }
                    } else if (board.tick === 28) {
                        console.log("STUDIO-PROBE FIN ajoutés", probe.after - probe.before,
                                    "| dessinés", probe.afterReady - probe.beforeReady,
                                    "| en attente", probe.afterPending,
                                    "| reste", studio.bgInstances.length);
                        Qt.quit();
                    }
                }
            }
        }
    }
}
