// AppDock.qml — module 6 : applications épinglées (bar.json.apps) + bouton « + ».
//
// Clic gauche : focus de la fenêtre la plus récente (launch si fermée).
// Clic droit   : menu de l'app — « Détacher » (écrit bar.json), « Fenêtres ».
// Clic milieu  : liste des fenêtres (raccourci, l'ancien clic droit).
// Molette      : fenêtre suivante / précédente de l'app. v4 §5 : la molette
//                est portée par le MouseArea de CHAQUE icône (aucune zone
//                superposée : un clic ne peut plus être avalé par une zone de
//                molette). L'écart de 8 px entre deux icônes ne fait rien —
//                c'est sans conséquence, et c'est la solution la plus simple.
// Bouton « + » : popup « Ajouter une app » (appindex.py --json, écriture par
//                barjson.py : atomique, seule la section apps bouge).
// Badge        : NOMBRE DE FENÊTRES (pas de processus, brief §8).
//
// État actif (brief v3 §4) : Hypr.countOfApp() normalise les deux côtés
// (norm) + repli sur l'id .desktop, sinon « Spotify » (bar.json) ne
// correspondait jamais à « spotify » (fenêtre).
import QtQuick
import "../qml"

Item {
    id: mod

    readonly property var pinned: Config.apps.filter(function (a) {
        return a && a.enabled !== false
    })
    readonly property int rows: mod.pinned.length
    readonly property int bh: Config.caseH

    // n blocs + (n-1) espaces + le bouton « + » (même gabarit que les blocs).
    // v5b : en barre HAUTE la même liste s'aligne en ligne (même ordre, « + »
    // en dernier).
    implicitWidth: Config.horizontal
                   ? ((mod.rows + 1) * mod.bh + mod.rows * Config.spacing)
                   : Config.block
    implicitHeight: Config.horizontal
                    ? mod.bh
                    : ((mod.rows + 1) * mod.bh + mod.rows * Config.spacing)

    function countOf(entry) {
        return Hypr.countOfApp(entry.class || entry.id, entry.desktop || entry.id);
    }

    // Molette sur une app : fenêtre suivante / précédente. Fermée → rien.
    function cycleEntry(entry, delta) {
        if (!entry)
            return;
        if (mod.countOf(entry) < 2)
            return;                      // 0 = fermée (l'infobulle le dit), 1 = rien à cycler
        Hypr.cycleApp(entry.class || entry.id, entry.desktop || entry.id, delta);
    }

    Flow {
        anchors.top: parent.top
        flow: Config.horizontal ? Flow.LeftToRight : Flow.TopToBottom
        width: parent.width
        spacing: Config.spacing

        Repeater {
            model: mod.pinned

            delegate: AppIcon {
                id: item

                required property var modelData
                required property int index

                readonly property string appId: "" + (item.modelData.id || item.modelData.class || "")
                readonly property string desktopId: ("" + (item.modelData.desktop
                                                           || item.modelData.id || ""))
                                                    .replace(/\.desktop$/, "")
                readonly property string cls: "" + (item.modelData.class || item.modelData.id || "")
                readonly property int wins: Hypr.countOfApp(item.cls, item.desktopId)
                readonly property string prettyName: AppIndex.nameFor(item.cls) || item.cls

                name: "app:" + item.appId
                width: Config.block
                height: Config.block
                iconPath: AppIndex.iconFor(item.cls).length > 0
                          ? AppIndex.iconFor(item.cls)
                          : AppIndex.iconForId(item.desktopId)
                windows: item.wins
                active: item.wins > 0
                label: item.prettyName
                tipText: item.prettyName + (item.wins > 0
                         ? " — " + item.wins + (item.wins > 1 ? " fenêtres" : " fenêtre")
                           + " (molette : fenêtre suivante)"
                         : " — fermée (clic : lancer)")

                // Un seul chemin de code, celui testé par l'IPC : Hypr.activate
                // résout l'adresse AU MOMENT DU CLIC (brief v2 §1).
                onClicked: Hypr.activate(item.cls, item.desktopId)
                onRightClicked: Ui.openAppMenu("pinned", item.appId, item.cls,
                                               item.desktopId, item.prettyName)
                onMiddleClicked: Ui.openWindows(item.cls, item.tipText)
                onScrolled: function (d) { mod.cycleEntry(item.modelData, d) }

                Component.onCompleted: {
                    var cls2 = item.cls;
                    var desk2 = item.desktopId;
                    Ui.registerAction("app:" + item.appId,
                                      function () { Hypr.activate(cls2, desk2) });
                }
            }
        }

        // ── Bouton « + » : épingler une app depuis la barre ────────────────
        IconButton {
            name: "addapp"
            glyph: "\u002b"
            glyphSize: Config.iconSize
            active: Ui.isOpen("addapp")
            tipText: "Ajouter une application (épingler)"
            onClicked: Ui.openAddApp()
        }
    }

    // Le bouton « + » est le seul contenu quand rien n'est épinglé : pas de
    // texte d'appoint qui se chevaucherait avec lui.
    // Action IPC : `qs ipc call bar action addapp` (même code que le clic).
    Component.onCompleted: Ui.registerAction("addapp", function () { Ui.openAddApp() })
}
