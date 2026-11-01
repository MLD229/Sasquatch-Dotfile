// polish-harness.qml — harnais de vérification d'UN widget (tranche polish §5.3).
//
// Jamais le CC plein écran (brief §9) : une petite surface layer Top, sans
// zone exclusive, qui dessine un seul widget de registre.
//
// Variables d'environnement :
//   SASQUATCH_WIDGET   type de registre (weather, media, tasks…)
//   SASQUATCH_VARIANT  variante (normal par défaut)
//   SASQUATCH_GRAB     chemin PNG du rendu (facultatif)
//
// Sortie : une ligne `POLISH-TEXT <texte>` par texte VISIBLE du widget, plus
// `POLISH-DONE <n>` à la fin. Le script polish.sh compare ces textes à la
// réponse HTTP de la route du widget : c'est la preuve « valeur affichée =
// valeur servie », sans capture d'écran à interpréter.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Sasquatch.Widgets 1.0

ShellRoot {
    id: harness

    readonly property string widgetType: {
        var v = Quickshell.env("SASQUATCH_WIDGET");
        return (typeof v === "string" && v.length > 0) ? v : "clock";
    }
    readonly property string variant: {
        var v = Quickshell.env("SASQUATCH_VARIANT");
        return (typeof v === "string" && v.length > 0) ? v : "normal";
    }
    readonly property string grabPath: {
        var v = Quickshell.env("SASQUATCH_GRAB");
        return (typeof v === "string") ? v : "";
    }

    readonly property var vSize: WidgetRegistry.variantSize(harness.widgetType, harness.variant)

    // Parcours récursif : tout `Text` visible et non vide, dans l'ordre de pose.
    function collect(item, out) {
        if (!item)
            return;
        var kids = item.children;
        for (var i = 0; i < kids.length; ++i) {
            var k = kids[i];
            if (!k)
                continue;
            if (typeof k.text === "string" && k.text.length > 0 && k.visible === true
                    && k.opacity > 0.05)
                out.push(k.text);
            harness.collect(k, out);
        }
    }

    PanelWindow {
        id: win

        implicitWidth: harness.vSize.w + 2 * Theme.spacing
        implicitHeight: harness.vSize.h + 2 * Theme.spacing

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "sasquatch-widgets-polish"
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

            Item {
                id: slot
                anchors.centerIn: parent
                width: harness.vSize.w
                height: harness.vSize.h

                Loader {
                    id: loader
                    anchors.fill: parent
                    source: WidgetRegistry.component(harness.widgetType)
                    asynchronous: false

                    onLoaded: {
                        var it = loader.item;
                        if (!it)
                            return;
                        it.instanceId = "polish-" + harness.widgetType;
                        it.widgetType = harness.widgetType;
                        it.host = "cc";
                        it.variant = harness.variant;
                        it.style = WidgetRegistry.defaultStyle(harness.widgetType, harness.variant);
                        it.options = WidgetRegistry.defaultOptions(harness.widgetType);
                    }
                }
            }
        }

        // 2,5 s : les sondes (2 s pour stats, 1 s pour le média) ont répondu.
        Timer {
            interval: 2500
            repeat: false
            running: true
            onTriggered: {
                var out = [];
                harness.collect(board, out);
                for (var i = 0; i < out.length; ++i)
                    console.log("POLISH-TEXT " + out[i]);
                console.log("POLISH-DONE " + out.length);
                if (harness.grabPath.length > 0) {
                    board.grabToImage(function (res) {
                        console.log("POLISH-GRAB " + res.saveToFile(harness.grabPath));
                        Qt.quit();
                    });
                } else {
                    Qt.quit();
                }
            }
        }
    }
}
