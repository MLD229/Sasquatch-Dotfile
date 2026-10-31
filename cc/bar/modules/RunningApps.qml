// RunningApps.qml — module 7 : applications en cours (hors apps épinglées).
//
// v3 (brief §2) : plus de pastille « +N » figée. Le cluster affiche une
// FENÊTRE GLISSANTE de `maxVisible` apps et la molette fait défiler la liste :
//   - molette haut/bas  → remonte / descend la liste (tout le bloc, y compris
//                         l'écart entre deux icônes : WheelZone sous le contenu,
//                         molette des icônes renvoyée au même gestionnaire) ;
//   - indicateur de position à droite (piste + curseur) : on VOIT qu'il y a du
//     contenu au-delà, jamais un scroll caché ;
//   - clic        → focus de la fenêtre la plus récente de la classe ;
//   - clic droit  → menu : « Épingler » (bar.json) + « Fenêtres » ;
//   - clic milieu → liste des fenêtres.
// La hauteur est celle de `maxVisible` blocs : faire défiler ne déplace donc
// jamais les modules du dessous (pas de saut de mise en page).
import QtQuick
import Quickshell
import "../qml"

Item {
    id: mod

    // Piloté par bar.json (runningApps.maxVisible) via le panneau Settings.
    readonly property int maxVisible: Config.maxVisible

    // Classes épinglées : elles ne doivent pas être répétées ici. La
    // comparaison passe par Hypr (norm des deux côtés + repli id .desktop).
    readonly property var allGroups: {
        var g = Hypr.groups();
        var out = [];
        for (var i = 0; i < g.length; i++) {
            if (!Hypr.isPinnedClass(g[i].cls))
                out.push(g[i]);
        }
        return out;
    }

    property int offset: 0
    readonly property int total: mod.allGroups.length
    readonly property int visibleCount: Math.max(1, Math.min(mod.total, mod.maxVisible))
    readonly property int shown: Math.max(0, Math.min(mod.maxVisible, mod.total - mod.offset))
    readonly property int maxOffset: Math.max(0, mod.total - mod.maxVisible)

    // v4 §3 : hauteurs de case communes (Config.caseH = Config.block).
    // v5b : en barre HAUTE la fenêtre glissante s'aligne en ligne ; le nombre
    // d'apps visibles (runningApps.maxVisible) ne change pas.
    implicitWidth: Config.horizontal
                   ? (mod.visibleCount * Config.block
                      + (mod.visibleCount - 1) * Config.spacing)
                   : Config.block
    implicitHeight: Config.horizontal
                    ? Config.caseH
                    : (mod.visibleCount * Config.caseH
                       + (mod.visibleCount - 1) * Config.spacing)

    onTotalChanged: mod.clampOffset()

    function clampOffset() {
        mod.offset = Math.max(0, Math.min(mod.offset, mod.maxOffset));
    }

    // Molette haut (d > 0) = remonter la liste.
    function scrollList(d) {
        if (mod.maxOffset === 0)
            return;
        var next = Math.max(0, Math.min(mod.maxOffset, mod.offset - d));
        if (next === mod.offset)
            return;
        mod.offset = next;
        var last = Math.min(mod.total, mod.offset + mod.maxVisible);
        var p = mod.mapToItem(null, 0, mod.height / 2);
        Tip.show("apps " + (mod.offset + 1) + "–" + last + " sur " + mod.total
                 + " (molette : faire défiler)", p.y);
    }

    // v4 §5 : la zone de molette n'est plus un MouseArea mais un WheelHandler
    // (qml/WheelZone.qml) : elle ne peut pas intercepter un clic. Le geste ne
    // dépend pas de la ligne survolée (on fait défiler la liste), donc elle
    // couvre tout le bloc, écarts compris.
    WheelZone {
        id: wheelZone
        name: "running"
        anchors.fill: parent
        onWheeled: function (delta) { mod.scrollList(delta) }
    }

    Flow {
        anchors.top: parent.top
        flow: Config.horizontal ? Flow.LeftToRight : Flow.TopToBottom
        width: parent.width
        spacing: Config.spacing

        Repeater {
            model: mod.allGroups.slice(mod.offset, mod.offset + mod.maxVisible)

            delegate: AppIcon {
                id: item

                required property var modelData

                readonly property string deskId: AppIndex.idForClass(item.modelData.cls)

                name: "run:" + item.modelData.key
                width: Config.block
                height: Config.block
                iconPath: AppIndex.iconFor(item.modelData.cls)
                windows: item.modelData.count
                active: true                 // une app du cluster est ouverte par définition
                label: AppIndex.nameFor(item.modelData.cls)
                tipText: AppIndex.nameFor(item.modelData.cls)
                         + " — " + item.modelData.count
                         + (item.modelData.count > 1 ? " fenêtres" : " fenêtre")

                // Résolution fraîche par classe : l'adresse du groupe peut être
                // morte (fenêtre fermée depuis la construction du modèle).
                onClicked: Hypr.focusClass(item.modelData.cls)
                onRightClicked: Ui.openAppMenu("running", item.deskId,
                                               item.modelData.cls, item.deskId,
                                               AppIndex.nameFor(item.modelData.cls))
                onMiddleClicked: Ui.openWindows(item.modelData.cls, item.tipText)
                onScrolled: function (d) { mod.scrollList(d) }

                Component.onCompleted: {
                    var c2 = item.modelData.cls;
                    Ui.registerAction("run:" + item.modelData.key,
                                      function () { Hypr.focusClass(c2) });
                }
            }
        }
    }

    // ── Indicateur de position : SUPPRIMÉ (2026-10-31, demande momo) ───────
    // La molette fait toujours défiler (mod.scrollList), mais plus aucune piste
    // ni curseur : le visuel reste propre, aucun élément décoratif à droite.
    // Conséquence assumée : on ne « voit » plus qu'il y a du contenu au-delà —
    // c'est le survol (infobulle « N apps ») et la molette qui le disent.

    // État vide : rien à afficher (pas d'icône d'erreur, ce n'est pas une panne).
    BarIcon {
        visible: mod.total === 0
        width: parent.width
        height: Config.caseH
        text: "\u00b7"
        size: 10
        tint: BarPalette.textDim
    }
}
