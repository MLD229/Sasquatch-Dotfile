// TasksWidget.qml — widget `tasks` (catalogue §6 / tranche v1d).
//
// Variantes :
//   compact  220x64   compteur « fait / total » + première tâche en cours
//   normal   360x180  liste cochable + champ d'ajout + compteur
//
// Source : Env.tasks (poll 5 s) → GET /api/tasks {items:[{id,text,done,at}],
// total, done}. Écriture : POST /api/tasks avec le format EXACT du serveur
// (cc/server.py, do_POST) : {"action":"add","text":"..."} et
// {"action":"toggle","id":...}. La réponse est la liste complète : Env la pose
// telle quelle, donc l'affichage suit toujours le fichier du serveur.
// Aucun XMLHttpRequest ici : le widget appelle Env (brief §2).
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "tasks"

    readonly property var items: (Env.tasks && Array.isArray(Env.tasks.items))
                                 ? Env.tasks.items : []
    readonly property int total: (Env.tasks && typeof Env.tasks.total === "number")
                                 ? Env.tasks.total : root.items.length
    readonly property int doneCount: (Env.tasks && typeof Env.tasks.done === "number")
                                     ? Env.tasks.done : root.countDone()

    function countDone() {
        var n = 0;
        for (var i = 0; i < root.items.length; ++i) {
            if (root.items[i] && root.items[i].done === true)
                n += 1;
        }
        return n;
    }

    readonly property int maxItems: Math.max(2, Math.min(8,
                                         (root.options && typeof root.options.maxItems === "number")
                                         ? Math.round(root.options.maxItems) : 4))
    readonly property bool showAdd: !(root.options && root.options.showAdd === false)

    // Tâches visibles : les non faites d'abord (c'est ce qu'on veut faire),
    // puis les faites, plafonnées par `maxItems`.
    readonly property var visibleItems: {
        var pending = [];
        var done = [];
        for (var i = 0; i < root.items.length; ++i) {
            var it = root.items[i];
            if (!it)
                continue;
            if (it.done === true)
                done.push(it);
            else
                pending.push(it);
        }
        return pending.concat(done).slice(0, root.maxItems);
    }

    // Spec copy : le compteur dit ce qu'il RESTE (« 2 restantes »), pas un
    // ratio technique « 2/5 ».
    readonly property int pendingCount: Math.max(0, root.total - root.doneCount)
    readonly property string progressText: root.pendingCount === 0
                                           ? (root.total === 0 ? "—" : "tout est fait")
                                           : (root.pendingCount + (root.pendingCount > 1 ? " restantes"
                                                                                        : " restante"))
    readonly property bool loading: Env.tasksPolls === 0
    readonly property bool offline: !root.loading && !Env.tasksOk

    readonly property real innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property real headSize: Math.max(9, Math.min(14, Math.round(root.innerH * 0.11)))
    readonly property real rowSize: Math.max(9, Math.min(13, Math.round(root.innerH * 0.095)))
    readonly property real rowH: Math.max(18, Math.round(root.innerH * 0.15))
    readonly property real addH: Math.max(26, Math.round(root.innerH * 0.20))

    function commitAdd() {
        var t = ("" + addInput.text).trim();
        if (t.length === 0)
            return;
        addInput.text = "";
        Env.addTask(t);
    }

    // ── compact : compteur + première tâche en cours ──────────────────────
    Column {
        visible: root.compact
        anchors.fill: parent
        spacing: 2

        Row {
            width: parent.width
            height: Math.round(parent.height * 0.44)
            spacing: 6

            Text {
                text: "Mes tâches"
                color: root.ink
                font.pixelSize: root.headSize
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: root.loading ? "Chargement…" : root.progressText
                color: root.offline ? Theme.warn : Theme.vizA
                font.pixelSize: root.headSize
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }

        Text {
            width: parent.width
            height: Math.round(parent.height * 0.5)
            text: {
                if (root.loading)
                    return "Chargement…";
                if (root.offline)
                    return "Tâches indisponibles";
                if (root.visibleItems.length === 0)
                    return root.total === 0 ? "Aucune tâche" : "Tout est fait";
                return root.visibleItems[0].text;
            }
            color: root.inkDim
            font.pixelSize: root.rowSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignVCenter
        }
    }

    // ── normal : liste cochable + ajout ───────────────────────────────────
    Column {
        visible: !root.compact
        anchors.fill: parent
        // Marge intérieure : sans elle le compteur « 0/2 » et la barre de
        // progression touchaient le bord arrondi de la carte (v1c-1).
        anchors.margins: root.pad
        spacing: Math.max(3, Math.round(root.innerH * 0.035))

        Item {
            id: head
            width: parent.width
            height: Math.round(root.innerH * 0.13)

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Mes tâches"
                color: root.ink
                font.pixelSize: root.headSize
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.loading ? "Chargement…" : root.progressText
                color: root.offline ? Theme.warn : root.inkDim
                font.pixelSize: root.headSize
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Barre de progression : 2 px, rayon 1, fond rgba(text, 0.12).
        Rectangle {
            width: parent.width
            height: 2
            radius: 1
            color: Theme.a(root.ink, 0.12)

            Rectangle {
                width: parent.width * (root.total > 0 ? root.doneCount / root.total : 0)
                height: parent.height
                radius: 1
                color: Theme.vizA
                Behavior on width {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Liste : la hauteur disponible est partagée, jamais de débordement.
        Column {
            id: list
            width: parent.width
            height: Math.max(0, parent.height - head.height - addField.height
                             - 2 * parent.spacing - 2)
            spacing: 1
            clip: true

            // État vide : une carte sans contenu ne doit pas ressembler à un bug.
            Text {
                width: list.width
                height: list.height
                visible: root.visibleItems.length === 0
                text: root.loading ? "Chargement…"
                      : (root.offline ? "Tâches indisponibles"
                                      : (root.total === 0 ? "Aucune tâche" : "Tout est fait"))
                color: root.offline ? Theme.warn : root.inkDim
                font.pixelSize: root.rowSize
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Repeater {
                model: root.visibleItems

                delegate: Item {
                    id: row
                    width: list.width
                    height: Math.min(root.rowH, Math.max(16,
                                      list.height / Math.max(1, root.visibleItems.length)))

                    property var item: modelData
                    readonly property bool checked: !!(row.item && row.item.done === true)

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusBtn * 0.5
                        color: rowHover.containsMouse ? Theme.a(Theme.ink, 0.06) : "transparent"
                    }

                    // Case à cocher (cible de clic = toute la ligne).
                    Rectangle {
                        id: box
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(14, row.height - 6)
                        height: width
                        radius: 3
                        color: row.checked ? Theme.a(Theme.vizA, 0.85) : "transparent"
                        border.width: 1
                        border.color: row.checked ? Theme.vizA : Theme.a(root.ink, 0.35)

                        Text {
                            anchors.centerIn: parent
                            visible: row.checked
                            text: "✓"
                            color: Theme.ink
                            font.pixelSize: Math.round(box.height * 0.78)
                        }
                    }

                    Text {
                        anchors.left: box.right
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: (row.item && row.item.text) ? row.item.text : ""
                        color: row.checked ? root.inkDim : root.ink
                        font.pixelSize: root.rowSize
                        font.strikeout: row.checked
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        verticalAlignment: Text.AlignVCenter
                    }

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.interactive
                        onClicked: {
                            if (row.item && row.item.id !== undefined)
                                Env.toggleTask(row.item.id);
                        }
                    }
                }
            }
        }

        // Ajout : champ EXPLICITE (placeholder + bouton « + »), Entrée valide
        // aussi. POST /api/tasks {"action":"add"}.
        Row {
            id: addField
            width: parent.width
            height: root.addH
            spacing: 6
            visible: root.showAdd

            Rectangle {
                id: addBox
                width: Math.max(0, addField.width - addField.height - addField.spacing)
                height: addField.height
                radius: Theme.radiusBtn
                // Champ discret : fond à 12 % (pas de plaque grise) + trait bas.
                color: Theme.a(Theme.text, 0.12)
                border.width: 1
                border.color: addInput.activeFocus ? Theme.halo : Theme.border

                TextInput {
                    id: addInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    enabled: root.interactive
                    color: root.ink
                    selectionColor: Theme.halo
                    selectedTextColor: root.ink
                    font.pixelSize: root.rowSize
                    clip: true
                    onAccepted: root.commitAdd()

                    Text {
                        anchors.fill: parent
                        visible: addInput.text.length === 0
                        text: "Ajouter une tâche…"
                        color: root.inkDim
                        font.pixelSize: addInput.font.pixelSize
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Rectangle {
                id: addBtn
                width: addField.height
                height: addField.height
                radius: Theme.radiusBtn
                color: addBtnArea.containsMouse ? Theme.a(Theme.vizA, 0.55)
                                                : Theme.a(Theme.glassBtn, Theme.alphaBtn)
                border.width: 1
                border.color: addBtnArea.containsMouse ? Theme.halo : Theme.border
                opacity: ("" + addInput.text).trim().length > 0 ? 1.0 : 0.55

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: root.ink
                    font.pixelSize: Math.round(addBtn.height * 0.55)
                }

                MouseArea {
                    id: addBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.interactive
                    onClicked: root.commitAdd()
                }
            }
        }
    }
}
