// NotificationsWidget.qml — widget `notifications` (catalogue §6).
//
// Variantes :
//   compact  220x64   badge de compte + dernière notification (app · titre)
//   normal   360x180  en-tête (badge + « tout effacer ») + 3 dernières
//
// Source : Notifs (singleton) → GET /api/notifications, qui lit réellement
// `makoctl list -j` + `makoctl history -j` (format vérifié : le drapeau JSON
// est `-j`). Actions : POST /api/notifications {op:"dismiss-all"} (makoctl
// dismiss -a) et {op:"dismiss", id} (makoctl dismiss -n id) ; l'état affiché
// est celui RELU après l'action, jamais une supposition.
// mako absent → état « indisponible » + commande d'installation (jamais une
// carte vide, brief §7).
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "notifications"

    readonly property int maxItems: {
        var v = (root.options && typeof root.options.maxItems === "number")
                ? Math.round(root.options.maxItems) : 3;
        return Math.max(1, Math.min(5, v));
    }
    readonly property bool showBadge: !(root.options && root.options.showBadge === false)

    readonly property var shown: Notifs.latest(root.maxItems)
    readonly property bool offline: !Notifs.available || !Notifs.ok
    // Premier appel pas encore revenu : on n'affiche pas la commande d'install
    // (elle clignoterait à chaque démarrage).
    readonly property bool loading: Notifs.polls === 0 && !Notifs.ok

    readonly property real innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property real headSize: Math.max(9, Math.min(14, Math.round(root.innerH * 0.11)))
    readonly property real rowSize: Math.max(9, Math.min(13, Math.round(root.innerH * 0.095)))
    readonly property real subSize: Math.max(8, Math.round(root.rowSize * 0.82))
    readonly property real headH: Math.round(root.innerH * 0.15)

    // ── Copy (spec §3) ────────────────────────────────────────────────────
    // Un titre qui est un nom de fichier devient un titre humain :
    // « Capture d'écran 20:28 ». Les helpers vivent dans le singleton Notifs
    // (une seule implémentation, testable par tests/copy-tests.qml).
    function humanTitle(note) {
        return Notifs.humanTitle(note);
    }

    function humanBody(note) {
        return Notifs.humanBody(note);
    }

    readonly property string offlineText: {
        if (root.loading)
            return "Chargement…";
        if (!Notifs.available)
            return "Notifications indisponibles · " + Notifs.install;
        return "Notifications indisponibles";
    }

    // Sous-titre du titre : « 3 nouvelles » (jamais un badge doublé d'un texte).
    readonly property string countText: {
        if (root.loading)
            return "";
        if (!Notifs.ok)
            return "";
        if (Notifs.count === 0)
            return "";
        return Notifs.count + (Notifs.count > 1 ? " nouvelles" : " nouvelle");
    }

    // Badge de compte : nombre de notifications (visibles + historique).
    component CountBadge: Rectangle {
        id: badge
        property int value: 0
        implicitWidth: Math.max(16, Math.round(badge.height * (0.55 + 0.30 * ("" + badge.value).length)))
        implicitHeight: Math.max(14, Math.round(root.headSize * 1.25))
        radius: height / 2
        color: root.showBadge && badge.value > 0 ? Theme.a(Theme.vizA, Theme.alphaBtn)
                                                 : Theme.a(Theme.glassBtn, 0.35)
        border.width: 1
        border.color: badge.value > 0 ? Theme.halo : Theme.border
        visible: root.showBadge

        Text {
            anchors.centerIn: parent
            text: "" + badge.value
            color: badge.value > 0 ? root.ink : root.inkDim
            font.pixelSize: Math.max(8, Math.round(badge.height * 0.66))
            font.weight: Font.DemiBold
        }
    }

    // ── compact : badge + la plus récente ─────────────────────────────────
    Item {
        visible: root.compact
        anchors.fill: parent
        anchors.margins: root.pad

        CountBadge {
            id: cBadge
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            value: Notifs.count
        }

        Column {
            anchors.left: cBadge.right
            anchors.right: clearAll.left
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: root.offline ? (root.loading ? "Chargement…" : "Notifications indisponibles")
                                   : (root.shown.length > 0
                                      ? root.humanTitle(root.shown[0]) : "Aucune notification")
                color: root.offline ? (root.loading ? root.inkDim : Theme.warn) : root.ink
                font.pixelSize: root.rowSize
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            // Deuxième ligne : l'app de la notification, ou — mako absent — la
            // COMMANDE D'INSTALLATION entière, en petit (jamais un mot coupé).
            Text {
                width: parent.width
                visible: root.offline ? !root.loading : (root.shown.length > 0)
                text: root.offline
                      ? (Notifs.available ? "" : Notifs.install)
                      : (root.shown.length > 0 ? (root.shown[0].app || "") : "")
                color: root.inkDim
                font.pixelSize: Math.max(7, root.subSize - 1)
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }

        // Tout effacer (makoctl dismiss -a), même en compact.
        Rectangle {
            id: clearAll
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(22, Math.round(root.innerH * 0.42))
            height: width
            radius: Theme.radiusBtn * 0.5
            color: clearArea.containsMouse ? Theme.a(Theme.hot, 0.20) : Theme.a(Theme.glassBtn, 0.40)
            opacity: Notifs.count > 0 ? 1.0 : 0.4

            Text {
                anchors.centerIn: parent
                text: "⌫"
                color: clearArea.containsMouse ? Theme.hot : root.inkDim
                font.pixelSize: Math.round(clearAll.height * 0.52)
            }

            MouseArea {
                id: clearArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.interactive && Notifs.available && Notifs.count > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: Notifs.dismissAll()
            }
        }
    }

    // ── normal : en-tête + 3 dernières ────────────────────────────────────
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
                id: title
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: root.ink
                font.pixelSize: root.headSize
                font.weight: Font.Medium
            }

            // Sous-titre « 3 nouvelles » : le compte est ici, pas en badge
            // doublé d'un texte (une information = un emplacement).
            Text {
                anchors.left: title.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.countText
                color: root.inkDim
                font.pixelSize: root.subSize
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            // « tout effacer » : makoctl dismiss -a, puis relecture serveur.
            Rectangle {
                id: clearBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width * 0.42, Math.max(64, Math.round(root.innerH * 0.62)))
                height: Math.max(20, Math.round(root.headH * 0.86))
                radius: Theme.radiusBtn * 0.7
                color: clearBtnArea.containsMouse ? Theme.a(Theme.hot, 0.18)
                                                  : Theme.a(Theme.glassBtn, 0.45)
                border.width: 1
                border.color: clearBtnArea.containsMouse ? Theme.a(Theme.hot, 0.45) : Theme.border
                opacity: Notifs.count > 0 && Notifs.available ? 1.0 : 0.4

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    text: "tout effacer"
                    color: clearBtnArea.containsMouse ? Theme.hot : root.inkDim
                    font.pixelSize: Math.max(8, Math.round(root.subSize * 0.95))
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                MouseArea {
                    id: clearBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.interactive && Notifs.available && Notifs.count > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.dismissAll()
                }
            }
        }

        // État indisponible : une seule ligne lisible, avec la commande.
        Text {
            width: parent.width
            height: Math.max(20, parent.height - head.height - parent.spacing)
            visible: root.offline
            text: root.offlineText
            color: Notifs.available ? root.inkDim : Theme.warn
            font.pixelSize: root.rowSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignTop
            topPadding: 6
        }

        // Liste : état vide explicite, puis les n plus récentes.
        Item {
            width: parent.width
            height: Math.max(0, parent.height - head.height - parent.spacing)
            visible: !root.offline

            Text {
                anchors.fill: parent
                visible: root.shown.length === 0
                text: root.loading ? "Chargement…" : "Aucune notification"
                color: root.inkDim
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
                        height: Math.max(24, Math.round(parent.height
                                        / Math.max(1, root.maxItems)))

                        readonly property var note: modelData
                        readonly property bool live: !!(row.note && row.note.active === true)

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusBtn * 0.5
                            color: rowHover.containsMouse ? Theme.a(root.ink, 0.06) : "transparent"
                        }

                        // Repère « visible à l'écran » : trait accent à gauche.
                        Rectangle {
                            visible: row.live
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.topMargin: 3
                            anchors.bottomMargin: 3
                            width: 2
                            radius: 1
                            color: Theme.vizA
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: kill.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            Text {
                                width: parent.width
                                text: row.note ? root.humanTitle(row.note) : ""
                                color: root.ink
                                font.pixelSize: root.rowSize
                                font.weight: row.live ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }

                            // Corps sur DEUX lignes maximum, ellipse propre : un
                            // nom de fichier en tête est retiré (spec copy).
                            Text {
                                width: parent.width
                                height: Math.min(parent.height, root.subSize * 2.4)
                                visible: text.length > 0
                                text: row.note ? root.humanBody(row.note) : ""
                                color: root.inkDim
                                font.pixelSize: root.subSize
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                wrapMode: Text.WordWrap
                                lineHeight: 1.05
                            }
                        }

                        // ✕ par ligne : dismiss -n id (la notification reste
                        // dans l'historique, c'est mako qui décide).
                        Rectangle {
                            id: kill
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(20, Math.round(row.height * 0.62))
                            height: width
                            radius: Theme.radiusBtn * 0.5
                            color: killArea.containsMouse ? Theme.a(Theme.hot, 0.20) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: killArea.containsMouse ? Theme.hot : root.inkDim
                                font.pixelSize: Math.round(kill.height * 0.5)
                            }

                            MouseArea {
                                id: killArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.interactive
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Notifs.dismiss(row.note ? row.note.id : null)
                            }
                        }

                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.interactive
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.dismiss(row.note ? row.note.id : null)
                        }
                    }
                }
            }
        }
    }
}
