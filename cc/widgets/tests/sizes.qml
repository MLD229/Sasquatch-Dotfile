// sizes.qml — vérifie que CHAQUE widget x CHAQUE variante expose bien la taille
// naturelle du registre (brief bugs §2 : `implicitWidth/Height` corrects pour
// les 15 widgets et leurs variantes).
//
// Aucun rendu, aucune capture : le harnais instancie les composants du registre
// et compare `implicitWidth/implicitHeight` à `WidgetRegistry.variantSize()`.
// Sortie texte uniquement (journal qml), utilisable en CI :
//
//   QML_IMPORT_PATH=$HOME/.config/cc/widgets \
//     timeout 25 quickshell -p cc/widgets/tests/sizes.qml
import QtQuick
import Quickshell
import Sasquatch.Widgets 1.0

ShellRoot {
    Item {
        id: root

        property var matrix: []
        property int index: 0
        property int checks: 0
        property int bad: 0

        // Matrice widget x variante, construite depuis le registre (pas en dur).
        function buildMatrix() {
            var out = [];
            var entries = WidgetRegistry.entries;
            for (var i = 0; i < entries.length; ++i) {
                var id = entries[i].id;
                var names = WidgetRegistry.variantNames(id);
                for (var j = 0; j < names.length; ++j)
                    out.push({ type: id, variant: names[j] });
            }
            root.matrix = out;
        }

        Component.onCompleted: buildMatrix()

        // Le registre est lu en asynchrone (FileView) : la matrice se
        // reconstruit dès qu'il devient prêt, sinon elle resterait vide.
        Connections {
            target: WidgetRegistry
            function onReadyChanged() { root.buildMatrix(); }
            function onRevisionChanged() { root.buildMatrix(); }
        }

        Repeater {
            model: root.matrix

            delegate: Loader {
                id: probe
                property var spec: modelData
                source: WidgetRegistry.component(probe.spec ? probe.spec.type : "")
                visible: false

                Binding {
                    target: probe.item
                    property: "variant"
                    value: probe.spec ? probe.spec.variant : "normal"
                    when: probe.status === Loader.Ready
                }
            }
        }

        // Laisse le temps aux Loader (composants + singletons) de se résoudre.
        Timer {
            interval: 1400
            running: true
            repeat: false
            onTriggered: {
                var probes = [];
                for (var i = 0; i < root.children.length; ++i) {
                    if (root.children[i].spec !== undefined)
                        probes.push(root.children[i]);
                }
                for (var k = 0; k < probes.length; ++k) {
                    var p = probes[k];
                    var spec = p.spec;
                    var want = WidgetRegistry.variantSize(spec.type, spec.variant);
                    if (p.status !== Loader.Ready) {
                        console.log("SIZES FAIL", spec.type, spec.variant, "loader", p.status);
                        root.bad += 1;
                        continue;
                    }
                    var ow = Math.round(p.item.implicitWidth);
                    var oh = Math.round(p.item.implicitHeight);
                    root.checks += 1;
                    if (ow !== Math.round(want.w) || oh !== Math.round(want.h)) {
                        console.log("SIZES FAIL", spec.type, spec.variant,
                                    "attendu", want.w + "x" + want.h,
                                    "obtenu", ow + "x" + oh);
                        root.bad += 1;
                    }
                }
                console.log("SIZES", (root.bad === 0 ? "OK" : "KO"),
                            root.checks, "couples widget x variante vérifiés,",
                            root.bad, "écart(s)");
                Qt.quit();
            }
        }
    }
}
