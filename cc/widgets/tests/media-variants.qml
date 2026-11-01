// media-variants.qml — preuve des 4 variantes du widget média + bornes de
// placement libre + arrêt des sondes (brief v1b). Ne remplace pas le harnais
// (hosts réels) : il complète, avec les 4 variantes côte à côte et des
// assertions imprimées dans la console.
//
// Lancement :
//   QML_IMPORT_PATH=$HOME/.config/cc/widgets \
//   SASQUATCH_HARNESS_GRAB=/tmp/media-variants.png \
//   timeout 12 quickshell -p cc/widgets/tests/media-variants.qml
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
        WlrLayershell.namespace: "sasquatch-media-variants"
        WlrLayershell.exclusiveZone: 0
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            left: true
        }
        margins {
            top: 80
            left: 80
        }

        readonly property string grabPath: {
            var v = Quickshell.env("SASQUATCH_HARNESS_GRAB");
            return (typeof v === "string") ? v : "";
        }

        // Variante = Loader sur le composant du REGISTRE (le module n'expose
        // pas MediaWidget comme type : le chemin vient de WidgetRegistry).
        component Variant: Loader {
            id: v

            property string varName: "normal"
            property var styleObj: ({ alpha: 0.24, accent: "auto", blur: 9, radius: 16 })

            source: WidgetRegistry.component("media")

            onLoaded: {
                v.item.instanceId = "chk-" + v.varName;
                v.item.host = "cc";
                v.item.variant = v.varName;
                v.item.editing = false;
                v.item.style = v.styleObj;
                v.item.options = ({ bars: 28, showSource: v.varName !== "visualizer" });
            }
        }

        Item {
            id: board
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusPanel
                color: Theme.a(Theme.bgSolid, 1.0)
            }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacing
                spacing: 10

                Text {
                    width: parent.width
                    text: "média — variantes (données réelles) · source: " + Music.sourceLabel
                          + " · cava visibles: " + Music.vizRefs
                          + " · polls status " + Music.statusPolls + " / viz " + Music.vizPolls
                    color: Theme.inkDim
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                Row {
                    spacing: 10

                    Variant {
                        width: 360
                        height: 180
                        varName: "normal"
                    }

                    Variant {
                        width: 220
                        height: 64
                        varName: "compact"
                        styleObj: ({ alpha: 0.24, accent: "auto", blur: 9, radius: 16 })
                    }
                }

                Variant {
                    width: 560
                    height: 260
                    varName: "hero"
                    styleObj: ({ alpha: 0.15, accent: "auto", blur: 9, radius: 16 })
                }

                Variant {
                    width: 360
                    height: 96
                    varName: "visualizer"
                    styleObj: ({ alpha: 0.15, accent: "auto", blur: 9, radius: 16 })
                }
            }
        }

        // ── Sonde de placement libre : canvas 900x620, hors écran ──────────
        // Rendue donc « visible » pour Music, mais positionnée hors de la
        // surface : elle ne pollue pas le rendu.
        WidgetCanvas {
            id: probe
            x: -4000
            width: 900
            height: 620
            host: "background"
            layout: "free"
            surfaceKey: "probe"
            instances: [{ id: "probe-clock", type: "clock",
                          geo: { x: 0.62, y: 0.08, w: 420, h: 200 } }]
        }

        // Valeurs cava SYNTHÉTIQUES pour la preuve de géométrie (aucun son ne
        // joue sur la machine au moment du test : les vraies valeurs sont à 0).
        Timer {
            interval: 700
            running: true
            repeat: false
            onTriggered: {
                // Sans ça le poll 60 ms réécrase les valeurs par les vraies
                // (toutes à 0 : rien ne joue sur la machine pendant le test).
                Music.vizTimer.running = false;
                var vals = [];
                for (var i = 0; i < 20; ++i)
                    vals.push(Math.abs(Math.sin(i * 0.7)) * 0.85 + 0.05);
                Music.vizVals = vals;
                console.log("CHECK cava : poll viz gelé + valeurs synthétiques injectées ("
                            + Music.vizVals.length + ")");
            }
        }

        Timer {
            interval: 1200
            running: true
            repeat: false
            onTriggered: {
                var r = probe.rectFor(probe.instances[0]);
                console.log("CHECK clamp 0.62 / 420 px sur canvas 900 px :");
                console.log("  fraction retenue = " + probe.freeX(0.62, 420)
                            + " (0.62 brut dépassait 1 - 420/900 = "
                            + (1 - 420 / 900) + ")");
                console.log("  x = " + r.x + " px, x + w = " + (r.x + r.w)
                            + " (doit être <= 900)");
                console.log("  move à 0.9 -> fraction persistée = " + probe.freeX(0.9, 420));
                console.log("CHECK bornes basses : freeX(-3, 420) = " + probe.freeX(-3, 420)
                            + ", freeX(2.5, 420) = " + probe.freeX(2.5, 420));
                console.log("CHECK timers ON : surfaceVisible=" + Music.surfaceVisible
                            + " vizActive=" + Music.vizActive
                            + " polls status=" + Music.statusPolls + " viz=" + Music.vizPolls);
            }
        }

        Timer {
            interval: 1600
            running: true
            repeat: false
            onTriggered: {
                if (win.grabPath.length === 0)
                    return;
                board.grabToImage(function (res) {
                    console.log("media-variants: rendu écrit =", res.saveToFile(win.grabPath));
                });
            }
        }

        // Surface cachée : les deux timers de Music doivent s'arrêter.
        Timer {
            interval: 2600
            running: true
            repeat: false
            onTriggered: {
                console.log("CHECK avant masquage : polls status=" + Music.statusPolls
                            + " viz=" + Music.vizPolls);
                probe.visible = false;
                win.afterHide = { s: Music.statusPolls, v: Music.vizPolls };
            }
        }

        property var afterHide: ({})

        Timer {
            interval: 4600
            running: true
            repeat: false
            onTriggered: {
                console.log("CHECK après masquage (2 s) : surfaceVisible=" + Music.surfaceVisible
                            + " vizActive=" + Music.vizActive
                            + " polls status=" + Music.statusPolls + " viz=" + Music.vizPolls
                            + " | delta status=" + (Music.statusPolls - win.afterHide.s)
                            + " delta viz=" + (Music.vizPolls - win.afterHide.v));
                console.log("CHECK cava enregistrés : refs=" + Music.vizRefs
                            + " clés=" + JSON.stringify(Object.keys(Music.vizKeys)));
                console.log("CHECK arrêt : le poll 60 ms ne repart pas"
                            + " (delta status = 0, delta viz <= 1 = requête déjà en vol)");
            }
        }
    }
}
