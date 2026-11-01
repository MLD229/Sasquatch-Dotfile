// BackgroundMask.qml — masque d'entrée du fond, construit sur les instances RÉELLES.
//
// Correctif brief bugs §1.6 : le masque de `background/shell.qml` déclarait 8
// emplacements fixes, donc un 9ᵉ widget de fond n'avait aucune zone cliquable.
// Ici aucun plafond : on reçoit `rects` (un rectangle par instance qui doit
// capter la souris) et on reconstruit une Region = UNION de ces rectangles.
// Un rectangle vide (w ou h <= 0) n'est pas émis du tout — jamais de « région
// nulle » à traîner dans l'union.
//
// Pourquoi une Region construite par `Qt.createQmlObject` : `Region.regions`
// est une liste QML (`default property`) qui n'accepte QUE des enfants déclarés
// à la compilation ; un `Repeater` ne peut pas l'alimenter (testé : le parent
// passé à createQmlObject n'ajoute rien à la liste). La seule façon d'avoir un
// nombre d'entrées variable est de générer le source de la Region — ce fichier
// est l'endroit unique où cette génération vit.
import QtQuick
import Quickshell

QtObject {
    id: root

    // [{x, y, w, h}] en pixels, relatifs à la surface (coin haut-gauche).
    property var rects: []
    // Rayon par rectangle (0 = coins droits).
    property int radius: 0

    // Région courante : c'est elle qu'on pose sur `PanelWindow.mask`.
    property var region: null

    // Anciennes régions encore référencées par la surface : on les garde un
    // court instant après le remplacement (le compositeur applique la nouvelle
    // en asynchrone) puis on les détruit.
    property var _retired: []

    onRectsChanged: root.rebuild()
    onRadiusChanged: root.rebuild()
    Component.onCompleted: root.rebuild()

    function buildSource() {
        var list = root.rects || [];
        var parts = [];
        for (var i = 0; i < list.length; ++i) {
            var r = list[i];
            if (!r)
                continue;
            var w = Math.round(r.w);
            var h = Math.round(r.h);
            if (!(w > 0) || !(h > 0))
                continue;                       // emplacement vide : ne capte rien
            var one = "Region { x: " + Math.round(r.x) + "; y: " + Math.round(r.y)
                    + "; width: " + w + "; height: " + h;
            if (root.radius > 0)
                one += "; radius: " + root.radius;
            parts.push(one + " }");
        }
        return "import Quickshell\nRegion {\n" + parts.join("\n") + "\n}";
    }

    function rebuild() {
        var fresh = null;
        try {
            fresh = Qt.createQmlObject(root.buildSource(), root, "background-mask");
        } catch (e) {
            console.warn("BackgroundMask: région impossible —", e);
            return;
        }
        var previous = root.region;
        root.region = fresh;
        if (previous) {
            var keep = root._retired.slice();
            keep.push(previous);
            root._retired = keep;
            retireTimer.restart();
        }
    }

    property Timer retireTimer: Timer {
        interval: 1500
        repeat: false
        onTriggered: {
            var old = root._retired;
            root._retired = [];
            for (var i = 0; i < old.length; ++i) {
                if (old[i])
                    old[i].destroy();
            }
        }
    }
}
