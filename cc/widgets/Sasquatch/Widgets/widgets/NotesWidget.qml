// NotesWidget.qml — widget `notes` : notes courtes persistées (catalogue §6).
//
// Variante :
//   normal  360x180  en-tête (compte) + liste (max 4) + champ d'ajout
//
// Source : Notes (singleton) → GET /api/notes ; écriture POST /api/notes
// {op:"add"} / {op:"rm"} → cc/server.py → cc/notes.py (fichier
// ~/.config/cc/notes.json, écriture ATOMIQUE, réponse = liste relue).
// Texte toujours tronqué proprement (elide), jamais coupé au milieu d'un mot
// affiché : c'est `Text.ElideRight` qui gère, pas une sous-chaîne.
// Aucun XMLHttpRequest ici (contrat §2).
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "notes"

    readonly property int maxNotes: {
        var v = (root.options && typeof root.options.maxNotes === "number")
                ? Math.round(root.options.maxNotes) : 4;
        return Math.max(1, Math.min(8, v));
    }

    readonly property var shown: Notes.latest(root.maxNotes)
    readonly property real innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property real headSize: Math.max(9, Math.min(14, Math.round(root.innerH * 0.11)))
    readonly property real rowSize: Math.max(9, Math.min(13, Math.round(root.innerH * 0.095)))
    readonly property real headH: Math.round(root.innerH * 0.13)
    readonly property real addH: Math.max(26, Math.round(root.innerH * 0.20))

    function commitAdd() {
        var t = ("" + addInput.text).trim();
        if (t.length === 0)
            return;
        addInput.text = "";
        Notes.add(t);
    }

    Column {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(3, Math.round(root.innerH * 0.035))

        Item {
            id: head
            width: parent.width
            height: root.headH

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Mes notes"
                color: root.ink
                font.pixelSize: root.headSize
                font.weight: Font.Medium
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Notes.polls === 0 ? "Chargement…"
                      : (Notes.ok ? (Notes.count + (Notes.count > 1 ? " notes" : " note"))
                                  : "Notes indisponibles")
                color: (Notes.ok || Notes.polls === 0) ? root.inkDim : Theme.warn
                font.pixelSize: root.headSize
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }

        // Liste : la hauteur restante est partagée equitablement par les
        // rangées, donc jamais de débordement sur le champ d'ajout.
        Item {
            id: listBox
            width: parent.width
            height: Math.max(0, parent.height - head.height - addField.height
                             - 2 * parent.spacing)
            clip: true

            Text {
                anchors.fill: parent
                visible: root.shown.length === 0
                text: Notes.polls === 0 ? "Chargement…"
                                        : (Notes.ok ? "Aucune note" : "Notes indisponibles")
                color: Notes.ok || Notes.polls === 0 ? root.inkDim : Theme.warn
                font.pixelSize: root.rowSize
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Column {
                anchors.fill: parent
                spacing: 0

                Repeater {
                    model: root.shown

                    delegate: Item {
                        id: row
                        width: parent.width
                        height: Math.min(Math.max(20, Math.round(root.innerH * 0.14)),
                                         Math.max(16, listBox.height
                                                  / Math.max(1, root.shown.length)))

                        property var item: modelData

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusBtn * 0.5
                            color: rowHover.containsMouse ? Theme.a(root.ink, 0.06) : "transparent"
                        }

                        // Puce accent : repère visuel discret à gauche.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 3
                            width: 3
                            height: 3
                            radius: 2
                            color: Theme.vizA
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: del.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: (row.item && row.item.text) ? row.item.text : ""
                            color: root.ink
                            font.pixelSize: root.rowSize
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            verticalAlignment: Text.AlignVCenter
                        }

                        Rectangle {
                            id: del
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(20, Math.round(row.height * 0.72))
                            height: width
                            radius: Theme.radiusBtn * 0.5
                            color: delArea.containsMouse ? Theme.a(Theme.hot, 0.20) : "transparent"
                            visible: rowHover.containsMouse || delArea.containsMouse

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: delArea.containsMouse ? Theme.hot : root.inkDim
                                font.pixelSize: Math.round(del.height * 0.5)
                            }

                            MouseArea {
                                id: delArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.interactive && row.item && row.item.id !== undefined
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (row.item)
                                        Notes.rm(row.item.id);
                                }
                            }
                        }

                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.interactive
                            cursorShape: Qt.ArrowCursor
                        }
                    }
                }
            }
        }

        // Ajout : champ explicite (placeholder + bouton « + »), Entrée valide
        // aussi. POST /api/notes {op:"add"}.
        Row {
            id: addField
            width: parent.width
            height: root.addH
            spacing: 6

            Rectangle {
                id: addBox
                width: Math.max(0, addField.width - addField.height - addField.spacing)
                height: addField.height
                radius: Theme.radiusBtn
                color: Theme.a(Theme.glassBtn, 0.45)
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
                        text: "Ajouter une note…"
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
