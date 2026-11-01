// CalendarWidget.qml — widget `calendar` : mois courant + tâches datées.
//
// Variantes :
//   normal  360x180  mois + grille 7x6, aujourd'hui marqué, un point par tâche
//   hero    560x260  idem, plus grand, + les prochaines tâches datées listées
//
// Données : Env.now (horloge locale) et Env.tasks → GET /api/tasks, dont chaque
// item porte `at` = "YYYY-MM-DD HH:MM" (cc/sysinfo.py). Une tâche est posée sur
// son jour ; celles qui tombent hors du mois affiché ne sont pas dessinées.
//
// AUCUN événement inventé : il n'existe pas de route d'agenda dans le backend
// (pas de /api/events dans cc/server.py), donc la grille ne montre que le mois
// et les tâches datées. Rien d'autre — pas de placeholder, pas de faux rendez-vous.
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "calendar"

    readonly property int innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property var taskItems: (Env.tasks && Array.isArray(Env.tasks.items))
                                     ? Env.tasks.items : []

    // Clé du jour : ne change qu'à minuit (pas de reconstruction par seconde).
    readonly property string todayKey: {
        var d = Env.now;
        return d.getFullYear() + "-" + root.pad2(d.getMonth() + 1) + "-" + root.pad2(d.getDate());
    }

    function pad2(n) {
        return (n < 10 ? "0" : "") + n;
    }

    // "YYYY-MM-DD HH:MM" (ou ISO) → "YYYY-MM-DD", sinon "".
    function dayKeyOf(at) {
        if (typeof at !== "string" || at.length < 10)
            return "";
        return at.substring(0, 10);
    }

    // ── Modèle du mois : 42 cellules, lundi en premier ────────────────────
    function buildCells(todayKey, items) {
        var parts = (todayKey || "").split("-");
        var y = parseInt(parts[0], 10);
        var m = parseInt(parts[1], 10) - 1;
        if (!isFinite(y) || !isFinite(m)) {
            var d0 = Env.now;
            y = d0.getFullYear();
            m = d0.getMonth();
        }
        // Tâches par jour, seulement celles qui portent une date.
        var byDay = {};
        for (var t = 0; t < items.length; ++t) {
            var it = items[t];
            if (!it)
                continue;
            var k = root.dayKeyOf(it.at);
            if (k.length === 0)
                continue;
            if (!byDay[k])
                byDay[k] = [];
            byDay[k].push(it);
        }
        var first = new Date(y, m, 1);
        var lead = (first.getDay() + 6) % 7;          // lundi = 0
        var out = [];
        for (var i = 0; i < 42; ++i) {
            var d = new Date(y, m, 1 - lead + i);
            var key = d.getFullYear() + "-" + root.pad2(d.getMonth() + 1) + "-"
                      + root.pad2(d.getDate());
            out.push({
                day: d.getDate(),
                inMonth: d.getMonth() === m,
                today: key === todayKey,
                key: key,
                tasks: byDay[key] ? byDay[key] : []
            });
        }
        return out;
    }

    readonly property var cells: root.buildCells(root.todayKey, root.taskItems)

    readonly property var monthLabel: {
        var p = root.todayKey.split("-");
        var mi = parseInt(p[1], 10) - 1;
        var name = (mi >= 0 && mi < 12) ? Env.monthLong[mi] : "";
        return name + " " + p[0];
    }

    // Tâches datées du mois affiché, triées : les prochaines d'abord.
    readonly property var monthTasks: {
        var out = [];
        var prefix = root.todayKey.substring(0, 7);
        for (var i = 0; i < root.taskItems.length; ++i) {
            var it = root.taskItems[i];
            if (!it || !it.at)
                continue;
            if (root.dayKeyOf(it.at).substring(0, 7) !== prefix)
                continue;
            out.push(it);
        }
        out.sort(function (a, b) {
            return ("" + a.at) < ("" + b.at) ? -1 : 1;
        });
        return out;
    }

    readonly property int todayTasks: {
        for (var i = 0; i < root.cells.length; ++i) {
            if (root.cells[i].today)
                return root.cells[i].tasks.length;
        }
        return 0;
    }

    readonly property real headSize: Math.max(10, Math.min(root.hero ? 20 : 15,
                                                          Math.round(root.innerH * 0.10)))
    readonly property real subSize: Math.max(8, Math.round(root.headSize * 0.72))
    readonly property real cellNumSize: Math.max(8, Math.min(root.hero ? 15 : 11,
                                                            Math.round(root.innerH * 0.075)))
    readonly property real headH: Math.round(root.innerH * (root.hero ? 0.12 : 0.16))
    readonly property real dowH: Math.round(root.innerH * (root.hero ? 0.09 : 0.11))
    // En hero, la liste des tâches datées ne réserve de la place que s'il y a
    // des tâches : sinon la grille prend toute la carte (pas de zone morte).
    readonly property real listH: (root.hero && root.showList && root.monthTasks.length > 0)
                                  ? Math.round(root.innerH * 0.26) : 0
    readonly property bool showList: !(root.options && root.options.showList === false)

    // Pied d'état (chargement / indisponible / rien de prévu) : hauteur
    // réservée pour que la grille ne passe jamais dessous.
    readonly property real footH: Math.round(root.subSize * 1.6)
    // État explicite, une seule fois (spec copy) : jamais de message trompeur
    // quand le mois est vide.
    readonly property string stateText: {
        if (Env.tasksPolls === 0)
            return "Chargement…";
        if (!Env.tasksOk)
            return "Calendrier indisponible";
        if (root.monthTasks.length === 0)
            return "Rien de prévu";
        return "";
    }

    readonly property real gridH: Math.max(24, root.innerH - root.headH - root.dowH
                                               - root.footH - root.listH
                                               - (root.hero ? 12 : 4))
    readonly property real cellW: Math.max(10, (root.width - 2 * root.pad) / 7)
    readonly property real cellH: Math.max(8, root.gridH / 6)

    // ── En-tête : mois + compteur de tâches du mois ───────────────────────
    Item {
        id: head
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.topMargin: root.pad
        height: root.headH

        Text {
            id: headTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Calendrier"
            color: root.ink
            font.pixelSize: root.headSize
            font.weight: Font.Medium
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        // Sous-titre : le mois affiché (« novembre 2026 »).
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.monthLabel
            color: root.inkDim
            font.pixelSize: root.subSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    // ── Jours de la semaine (lundi → dimanche) ────────────────────────────
    Row {
        id: dow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: head.bottom
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.topMargin: root.hero ? 6 : 2
        height: root.dowH

        Repeater {
            model: 7

            Text {
                width: root.cellW
                height: dow.height
                text: ["L", "M", "M", "J", "V", "S", "D"][index]
                color: root.inkDim
                font.pixelSize: Math.round(root.subSize * 0.92)
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }
    }

    // ── Grille du mois (Repeater → aucune image, aucun Canvas externe) ────
    Grid {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: dow.bottom
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        columns: 7
        rows: 6
        clip: true

        Repeater {
            model: root.cells

            Item {
                id: cell
                width: root.cellW
                height: root.cellH

                readonly property var info: modelData

                // Aujourd'hui : cercle RÉELLEMENT tracé (contour accent +
                // remplissage léger), le seul repère fort de la grille.
                Rectangle {
                    visible: cell.info.today
                    anchors.centerIn: parent
                    width: Math.min(cell.width - 2, cell.height - 2)
                    height: width
                    radius: width / 2
                    color: Theme.a(Theme.vizA, 0.22)
                    border.width: Math.max(1, Math.round(width * 0.07))
                    border.color: Theme.vizA
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: cell.info.tasks.length > 0 ? -2 : 0
                    text: cell.info.day
                    color: root.ink
                    opacity: cell.info.inMonth ? 1.0 : 0.55
                    font.pixelSize: root.cellNumSize
                    font.weight: cell.info.today ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                // Points des tâches datées : un par tâche (3 max, le reste en « + »).
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    spacing: 2
                    visible: cell.info.tasks.length > 0

                    Repeater {
                        model: Math.min(3, cell.info.tasks.length)

                        Rectangle {
                            width: 4
                            height: 4
                            radius: 2
                            color: {
                                var t = cell.info.tasks[index];
                                return (t && t.done === true) ? Theme.a(root.inkDim, 0.55) : Theme.vizA;
                            }
                        }
                    }

                    Text {
                        visible: cell.info.tasks.length > 3
                        text: "+"
                        color: root.inkDim
                        font.pixelSize: Math.round(root.cellNumSize * 0.62)
                    }
                }
            }
        }
    }

    // ── Pied : état explicite (chargement / indisponible / rien de prévu) ──
    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.bottomMargin: root.pad
        height: root.footH
        visible: root.stateText.length > 0
        text: root.stateText
        color: (root.stateText === "Calendrier indisponible") ? Theme.warn : root.inkDim
        font.pixelSize: root.subSize
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        verticalAlignment: Text.AlignBottom
    }

    // ── Hero : les tâches datées du mois, sous la grille ──────────────────
    Column {
        id: list
        visible: root.hero && root.showList
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.bottomMargin: root.pad + root.footH
        height: root.listH
        spacing: 2

        Repeater {
            model: Math.min(4, root.monthTasks.length)

            Item {
                width: list.width
                height: Math.max(14, Math.round((root.listH - 6) / 4))

                readonly property var task: root.monthTasks[index]

                Text {
                    id: stamp
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(parent.width * 0.20)
                    text: parent.task && parent.task.at ? parent.task.at.substring(5, 10) : ""
                    color: root.inkDim
                    font.pixelSize: root.subSize
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Text {
                    anchors.left: stamp.right
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.task ? (parent.task.text || "") : ""
                    color: (parent.task && parent.task.done === true)
                           ? Theme.a(root.inkDim, 0.65) : root.ink
                    font.pixelSize: root.subSize
                    font.strikeout: parent.task && parent.task.done === true
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
            }
        }

    }
}
