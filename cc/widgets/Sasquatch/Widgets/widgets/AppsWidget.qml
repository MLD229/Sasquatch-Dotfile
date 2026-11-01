// AppsWidget.qml — widget `apps` : favoris / mini-lanceur (catalogue §6).
//
// Variantes :
//   compact  220x64   une rangée d'icônes (favoris)
//   normal   360x180  grille 3 × 2 : icône + nom
//
// L'INDEX VIENT DE cc/bar/appindex.py — le même script que la barre, lu par le
// singleton Apps (aucune copie de la logique .desktop ici) : icônes résolues
// côté Python, lancement par `appindex.py --launch <id>`.
// Favoris = bar.json → apps[] (écrit par le « + » de la barre).
// Une app épinglée mais absente de l'index n'est jamais une case vide :
// pastille avec l'initiale + le nom, clic sans effet (état « absente »).
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "apps"

    readonly property int maxItems: {
        var v = (root.options && typeof root.options.maxItems === "number")
                ? Math.round(root.options.maxItems) : 6;
        return Math.max(1, Math.min(12, v));
    }
    readonly property bool showNames: !(root.options && root.options.showNames === false)

    readonly property var favs: Apps.favorites.slice(0, root.maxItems)
    readonly property real innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property real headSize: Math.max(9, Math.min(14, Math.round(root.innerH * 0.11)))
    readonly property real nameSize: Math.max(8, Math.min(11, Math.round(root.innerH * 0.085)))
    readonly property real headH: root.compact ? 0 : Math.round(root.innerH * 0.15)
    readonly property real gap: Math.max(4, Math.round(root.innerH * 0.05))

    // Tuile : icône (ou initiale) et, si demandé, le nom dessous. Positionnement
    // explicite (pas de Column) : une icône + un texte tronqué à hauteur fixe,
    // donc jamais de case vide ni de nom hors du cadre.
    component AppTile: Item {
        id: tile

        property var app: null
        property real iconSize: 24
        property bool withName: false

        readonly property string appId: tile.app ? ("" + tile.app.id) : ""
        readonly property string appName: tile.app ? ("" + tile.app.name) : ""
        readonly property string iconPath: tile.app ? ("" + (tile.app.icon || "")) : ""
        readonly property bool known: !!(tile.app && tile.app.known === true)
        // App introuvable : jamais une case vide ni une suppression muette —
        // pastille initiale + nom + action « Retirer » (spec copy).
        readonly property bool missing: tile.app !== null && !tile.known
        readonly property real nameH: Math.max(9, Math.round(root.nameSize * 1.45))
        readonly property real retireH: (tile.missing && tile.withName)
                                        ? Math.max(10, Math.round(root.nameSize * 1.4)) : 0
        readonly property real iconY: tile.withName
                                      ? Math.max(0, (tile.height - tile.iconSize - tile.nameH
                                                     - tile.retireH - 4) / 2)
                                      : Math.max(0, (tile.height - tile.iconSize) / 2)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusBtn * 0.6
            color: hoverArea.containsMouse ? Theme.a(root.ink, 0.07) : "transparent"
        }

        Item {
            id: iconBox
            x: Math.round((tile.width - tile.iconSize) / 2)
            y: Math.round(tile.iconY)
            width: tile.iconSize
            height: tile.iconSize

            // Pastille de repli : initiale du nom (jamais une case vide).
            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusBtn * 0.7
                color: Theme.a(Theme.glassBtn, 0.55)
                border.width: 1
                border.color: hoverArea.containsMouse ? Theme.halo : Theme.border

                Text {
                    anchors.centerIn: parent
                    text: Apps.initial(tile.appName)
                    color: tile.known ? root.ink : root.inkDim
                    font.pixelSize: Math.max(8, Math.round(iconBox.height * 0.46))
                    font.weight: Font.DemiBold
                }
            }

            Image {
                id: icon
                anchors.fill: parent
                source: tile.iconPath.length > 0 ? ("file://" + tile.iconPath) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: icon.status === Image.Ready
                sourceSize.width: Math.round(tile.iconSize * 2)
                sourceSize.height: Math.round(tile.iconSize * 2)
            }
        }

        Text {
            id: nameLabel
            x: 0
            y: Math.round(tile.iconY + tile.iconSize + 2)
            width: tile.width
            height: tile.nameH
            visible: tile.withName
            text: tile.appName
            color: tile.known ? root.inkDim : Theme.warn
            font.pixelSize: root.nameSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        // Action explicite pour une app introuvable (jamais de retrait muet).
        Text {
            id: retireLabel
            x: 0
            y: Math.round(tile.iconY + tile.iconSize + 2 + tile.nameH)
            width: tile.width
            height: tile.retireH
            visible: tile.retireH > 0
            text: "Retirer"
            color: retireArea.containsMouse ? Theme.hot : Theme.warn
            font.pixelSize: Math.max(8, Math.round(root.nameSize * 0.92))
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap

            MouseArea {
                id: retireArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.interactive
                onClicked: {
                    if (tile.appId.length > 0)
                        Apps.removeFavorite(tile.appId);
                }
            }
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.interactive && tile.known
            cursorShape: tile.known ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (tile.appId.length > 0)
                    Apps.launch(tile.appId);
            }
        }

        opacity: tile.known ? 1.0 : 0.55
    }

    // ── compact : rangée d'icônes ─────────────────────────────────────────
    Item {
        visible: root.compact
        anchors.fill: parent
        anchors.margins: root.pad

        Text {
            anchors.fill: parent
            visible: root.favs.length === 0
            text: !Apps.ready ? "Chargement…"
                               : (Apps.lastError.length > 0 ? "Applications indisponibles"
                                                            : "Aucun favori")
            color: root.inkDim
            font.pixelSize: root.nameSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        Row {
            id: favRow
            anchors.fill: parent
            visible: root.favs.length > 0
            spacing: root.gap

            readonly property real tileW: Math.min(parent.height,
                                                  (parent.width - Math.max(0, root.favs.length - 1) * spacing)
                                                  / Math.max(1, root.favs.length))

            Repeater {
                model: root.favs

                delegate: AppTile {
                    width: Math.round(favRow.tileW)
                    height: favRow.height
                    app: modelData
                    iconSize: Math.round(Math.min(favRow.height * 0.72, width * 0.9))
                    withName: false
                }
            }
        }
    }

    // ── normal : grille 3 × 2 ─────────────────────────────────────────────
    Column {
        visible: !root.compact
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(3, Math.round(root.innerH * 0.03))

        Item {
            id: head
            width: parent.width
            height: root.headH

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Favoris"
                color: root.ink
                font.pixelSize: root.headSize
                font.weight: Font.Medium
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: !Apps.ready ? "Chargement…"
                      : (Apps.lastError.length > 0 ? "Applications indisponibles"
                                                   : (root.favs.length + (root.favs.length > 1 ? " apps" : " app")))
                color: (!Apps.ready || Apps.lastError.length > 0) ? Theme.warn : root.inkDim
                font.pixelSize: root.headSize
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }

        Item {
            id: bodyBox
            width: parent.width
            height: Math.max(0, parent.height - head.height - parent.spacing)

            Text {
                anchors.fill: parent
                visible: root.favs.length === 0
                text: !Apps.ready ? "Chargement…"
                      : (Apps.lastError.length > 0 ? "Applications indisponibles"
                                                   : "Aucun favori")
                color: Apps.ready ? root.inkDim : Theme.warn
                font.pixelSize: root.nameSize
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Grid {
                id: appGrid
                anchors.fill: parent
                visible: root.favs.length > 0
                columns: 3
                spacing: root.gap

                readonly property real cellW: (width - (columns - 1) * spacing) / columns
                readonly property int rows: Math.max(1, Math.ceil(root.favs.length / columns))
                readonly property real cellH: (height - Math.max(0, rows - 1) * spacing)
                                              / Math.max(1, rows)

                Repeater {
                    model: root.favs

                    delegate: AppTile {
                        width: appGrid.cellW
                        height: appGrid.cellH
                        app: modelData
                        iconSize: Math.round(Math.min(appGrid.cellH * 0.5, appGrid.cellW * 0.42))
                        withName: root.showNames
                    }
                }
            }
        }
    }
}
