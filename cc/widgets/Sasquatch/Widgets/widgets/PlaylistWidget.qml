// PlaylistWidget.qml — widget `playlist` : file d'attente MPD (catalogue §6).
//
// Variantes :
//   normal  360x180  en-tête (compteur + shuffle + lecture) + liste
//   hero    560x260  même chose, plus grande, avec l'artiste de la piste
//
// Source : Playlist (singleton) → GET /api/playlist/status + /api/playlist/list.
// Actions : clic sur une ligne = POST /api/playlist/play {pos} ; ✕ = remove ;
// bouton shuffle = POST /api/playlist/shuffle ; ▶/❚❚ = playtoggle.
// Aucun XMLHttpRequest ici (contrat §2), aucune couleur en dur : tout vient de
// Theme (alpha carte/hero via Theme.cardAlpha, y compris la variante).
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "playlist"

    readonly property var tracks: Playlist.tracks
    readonly property int innerH: Math.max(8, root.height - 2 * root.pad)

    readonly property int maxRows: {
        var v = (root.options && typeof root.options.maxTracks === "number")
                ? Math.round(root.options.maxTracks) : (root.hero ? 9 : 5);
        return Math.max(2, Math.min(20, v));
    }
    readonly property bool showArtist: !(root.options && root.options.showArtist === false)

    // Rangées visibles : la file entière peut faire des centaines de pistes,
    // la carte n'en montre qu'un écran (pas de ScrollView dans ce contrat).
    readonly property real rowH: {
        var avail = Math.max(1, root.innerH - root.headH - root.footH - 2 * root.spacing);
        return Math.max(16, Math.min(root.hero ? 30 : 24,
                                     avail / Math.max(1, Math.min(root.maxRows, root.tracks.length))));
    }
    readonly property int visibleRows: {
        var avail = Math.max(1, root.innerH - root.headH - root.footH - 2 * root.spacing);
        return Math.max(1, Math.min(root.maxRows, Math.floor(avail / root.rowH)));
    }
    readonly property var rows: {
        var out = [];
        for (var i = 0; i < root.tracks.length && i < root.visibleRows; ++i)
            out.push(root.tracks[i]);
        return out;
    }

    readonly property int spacing: Math.max(4, Math.round(root.innerH * 0.04))
    readonly property real headH: Math.round(root.innerH * (root.hero ? 0.15 : 0.17))
    readonly property real footH: Math.round(root.innerH * 0.11)
    readonly property real headSize: Math.max(10, Math.min(root.hero ? 18 : 14,
                                                          Math.round(root.innerH * 0.10)))
    readonly property real rowSize: Math.max(9, Math.min(root.hero ? 15 : 13,
                                                         Math.round(root.innerH * 0.085)))
    readonly property real subSize: Math.max(8, Math.round(root.rowSize * 0.82))
    readonly property real btnW: Math.max(30, Math.round(root.headH * 1.15))
    readonly property real btnH: Math.max(24, Math.round(root.headH * 0.82))

    // Spec copy : « 3 morceaux » (accord), et l'état d'indisponibilité nommé.
    readonly property string counter: {
        if (!Playlist.mpdOk)
            return Playlist.polls === 0 ? "Chargement…" : "Liste indisponible";
        // Liste vide : le message centré s'en charge (une info = un endroit).
        if (Playlist.declaredCount === 0)
            return "";
        var n = Playlist.declaredCount;
        return n + (n > 1 ? " morceaux" : " morceau");
    }

    // ── En-tête ───────────────────────────────────────────────────────────
    Item {
        id: head
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.pad
        height: root.headH

        Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Ma musique"
            color: root.ink
            font.pixelSize: root.headSize
            font.weight: Font.Medium
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        // Pilule shuffle : allumée = random actif côté MPD (relu, pas supposé).
        Rectangle {
            id: shuffleBtn
            anchors.right: playBtn.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: root.btnW
            height: root.btnH
            radius: Theme.radiusBtn
            color: Playlist.shuffleOn ? Theme.a(Theme.vizA, 0.30) : Theme.a(Theme.glassBtn, 0.45)
            border.width: 1
            border.color: Playlist.shuffleOn ? Theme.halo : Theme.border

            Text {
                anchors.centerIn: parent
                text: "⤨"
                color: Playlist.shuffleOn ? root.ink : root.inkDim
                font.pixelSize: Math.round(root.btnH * 0.55)
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.interactive && Playlist.mpdOk
                cursorShape: Qt.PointingHandCursor
                onClicked: Playlist.shuffle()
            }
        }

        // Pilule lecture/pause.
        Rectangle {
            id: playBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.btnW
            height: root.btnH
            radius: Theme.radiusBtn
            color: Playlist.playing ? Theme.a(Theme.vizA, 0.30) : Theme.a(Theme.glassBtn, 0.45)
            border.width: 1
            border.color: Playlist.playing ? Theme.halo : Theme.border

            Text {
                anchors.centerIn: parent
                text: Playlist.playing ? "❚❚" : "▶"
                color: Playlist.playing ? root.ink : root.inkDim
                font.pixelSize: Math.round(root.btnH * 0.46)
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.interactive && Playlist.mpdOk
                cursorShape: Qt.PointingHandCursor
                onClicked: Playlist.toggle()
            }
        }

        // Compteur entre le titre et les boutons (jamais superposé).
        Text {
            anchors.left: title.right
            anchors.leftMargin: 8
            anchors.right: shuffleBtn.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.counter
            color: Playlist.mpdOk ? root.inkDim : Theme.hot
            font.pixelSize: root.subSize
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    // ── Liste ─────────────────────────────────────────────────────────────
    Item {
        id: listBox
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: head.bottom
        anchors.bottom: foot.top
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.topMargin: root.spacing
        anchors.bottomMargin: root.spacing
        clip: true

        Text {
            anchors.fill: parent
            visible: root.rows.length === 0
            text: !Playlist.mpdOk
                  ? (Playlist.polls === 0 ? "Chargement…" : "Liste indisponible")
                  : (Playlist.declaredCount === 0 ? "Liste vide" : "—")
            color: Playlist.mpdOk ? root.inkDim : Theme.warn
            font.pixelSize: root.rowSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        // Column : le Repeater n'empile pas ses délégués, sans positionneur
        // toutes les lignes tombaient à (0,0) — d'où le texte superposé.
        Column {
            width: listBox.width
            spacing: 0

            Repeater {
                model: root.rows

                delegate: Item {
                    id: row
                    width: listBox.width
                    height: root.rowH

                    readonly property var track: modelData
                    readonly property int pos: (row.track && typeof row.track.pos === "number")
                                               ? row.track.pos : -1
                    readonly property bool current: !!(row.track && row.track.current === true)

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusBtn * 0.55
                        color: rowHover.containsMouse ? Theme.a(root.ink, 0.06)
                             : (row.current ? Theme.a(Theme.vizA, 0.10) : "transparent")
                    }

                    // Repère de la piste en cours : trait plein à gauche.
                    Rectangle {
                        visible: row.current
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 3
                        anchors.bottomMargin: 3
                        width: 2
                        radius: 1
                        color: Theme.vizA
                    }

                    Text {
                        id: idx
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(root.rowSize * 1.8)
                        text: (row.pos >= 0) ? (row.pos + 1) : "·"
                        color: row.current ? root.ink : root.inkDim
                        font.pixelSize: root.subSize
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        verticalAlignment: Text.AlignVCenter
                    }

                    Column {
                        anchors.left: idx.right
                        anchors.right: dur.left
                        anchors.leftMargin: 4
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            width: parent.width
                            text: (row.track && row.track.title) ? row.track.title : "—"
                            color: row.current ? Theme.vizA : root.ink
                            font.pixelSize: root.rowSize
                            font.weight: row.current ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }

                        Text {
                            width: parent.width
                            visible: root.showArtist && root.hero && row.track
                                     && row.track.artist && ("" + row.track.artist).length > 0
                            text: row.track ? (row.track.artist || "") : ""
                            color: root.inkDim
                            font.pixelSize: root.subSize
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                    }

                    Text {
                        id: dur
                        anchors.right: removeBtn.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(root.rowSize * 2.2)
                        text: row.track ? Playlist.fmt(row.track.duration) : ""
                        color: root.inkDim
                        font.pixelSize: root.subSize
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        id: removeBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(22, Math.round(root.rowH * 0.78))
                        height: width
                        radius: Theme.radiusBtn * 0.5
                        color: removeArea.containsMouse ? Theme.a(Theme.hot, 0.22) : "transparent"
                        visible: rowHover.containsMouse || removeArea.containsMouse

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: removeArea.containsMouse ? Theme.hot : root.inkDim
                            font.pixelSize: Math.round(removeBtn.height * 0.52)
                        }

                        MouseArea {
                            id: removeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.interactive && row.pos >= 0
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Playlist.remove(row.pos)
                        }
                    }

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.interactive && row.pos >= 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Playlist.play(row.pos)
                    }
                }
        }
        }
    }

    // ── Pied : total de la file (durée cumulée en hero) ───────────────────
    Item {
        id: foot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.pad
        height: root.footH

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: {
                // L'état est dit une seule fois, au centre de la liste.
                if (!Playlist.mpdOk || Playlist.declaredCount === 0)
                    return "";
                var total = 0;
                for (var i = 0; i < Playlist.tracks.length; ++i)
                    total += (Playlist.tracks[i] && typeof Playlist.tracks[i].duration === "number")
                             ? Playlist.tracks[i].duration : 0;
                var parts = [];
                if (root.hero && total > 0)
                    parts.push(Playlist.fmt(total) + " au total");
                if (Playlist.playing)
                    parts.push("en lecture · " + Playlist.fmt(Playlist.status.elapsed));
                return parts.join(" · ");
            }
            color: Playlist.mpdOk ? root.inkDim : Theme.hot
            font.pixelSize: root.subSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignVCenter
        }
    }
}
