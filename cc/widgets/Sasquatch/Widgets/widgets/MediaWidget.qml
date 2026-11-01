// MediaWidget.qml — widget `media` (brief v1b).
//
// Variantes :
//   compact    220x64   barre de son (titre + piste) + bouton lecture
//   normal     360x180  pochette 96², titre/artiste, cava, transport + pilule source
//   hero       560x260  idem, pochette 128², album, cava extensible, temps sur la
//                       même ligne que le transport et la pilule source
//   visualizer —        cava SEUL, aucune carte
//
// Mise en page : la colonne de droite est ANCRÉE (titre/artiste/album en haut,
// transport en bas, barre de progression juste AU-DESSUS du transport, cava
// entre les deux). Le cava ne peut donc jamais recouvrir le titre ni la barre
// de progression : sa géométrie est le résultat des ancres, pas d'un calcul de
// hauteur qui peut se désynchroniser (§ correctif média b).
//
// Aucune couleur en dur, aucune taille littérale : tout dérive de Theme, de la
// variante (registre) et de la carte. Aucun XMLHttpRequest : tout passe par
// Music (brief §2) — le widget LIT, Music sonde.
import QtQuick
import QtQuick.Effects
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "media"
    // « visualizer » = cava seul, pas de carte (brief §6).
    showCard: !root.vizOnly

    readonly property bool vizOnly: root.variant === "visualizer"
    readonly property bool showSource: !(root.options && root.options.showSource === false)
    readonly property int barCount: {
        var b = (root.options && typeof root.options.bars === "number") ? root.options.bars : 28;
        return Math.max(8, Math.min(48, Math.round(b)));
    }

    // ── Métriques dérivées de la carte (jamais de littéral de taille) ──────
    readonly property real innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property real titleSize: Math.max(12, Math.min(19, Math.round(root.innerH * 0.115)))
    readonly property real artistSize: Math.max(9, Math.round(root.titleSize * 0.76))
    readonly property real btnSize: Math.max(30, Math.min(34, Math.round(root.innerH * 0.2)))
    readonly property int pillH: Math.max(18, Math.min(24, Math.round(root.innerH * 0.13)))
    readonly property real gap: Math.max(3, Math.round(root.innerH * 0.035))
    // Correctif média (c) : pochette 128² en hero (le brief c) l'impose).
    readonly property real coverSide: Math.max(36, Math.min(root.hero ? 128 : 96,
                                                              root.innerH, root.width * 0.42))
    readonly property real lineH: Math.round(root.innerH * (root.hero ? 0.12 : 0.15))
    readonly property real subH: Math.round(root.innerH * (root.hero ? 0.085 : 0.11))
    readonly property real albumH: root.hero ? Math.round(root.innerH * 0.065) : 0
    // Largeurs typographiques estimées : une `width` ne doit JAMAIS dépendre
    // d'un `implicitWidth` de Text (boucle de binding, vérifié au chargement).
    readonly property real timeW: Math.round(Math.max(9, root.artistSize - 1) * 5.8)
    readonly property string pillLabel: "● " + Music.sourceLabel
                                        + (Music.pinned.length > 0 ? " · épinglée" : "")
    readonly property real pillTextW: Math.round(root.pillLabel.length
                                                 * Math.max(9, Math.round(root.pillH * 0.52)) * 0.58)

    // Spec copy : le titre reste le MORCEAU (jamais « En lecture »), et les
    // trois états se distinguent — chargement / rien en lecture / indisponible.
    readonly property bool searching: Music.statusPolls === 0
    readonly property bool noReader: !root.searching
                                    && (Music.source === "none" || !Api.online)
    readonly property string titleText: {
        if (root.searching)
            return "Recherche d'un lecteur…";
        if (root.noReader)
            return Music.hasTrack ? Music.title : "Aucun lecteur disponible";
        return Music.hasTrack ? Music.title : "Rien en lecture";
    }
    // « artiste · nom du lecteur » : le lecteur est toujours nommé.
    readonly property string artistText: {
        if (root.searching)
            return "";
        var parts = [];
        if (Music.hasTrack && Music.artist.length > 0)
            parts.push(Music.artist);
        if (!root.noReader)
            parts.push(Music.sourceLabel);
        return parts.join(" · ");
    }

    onEditingChanged: if (root.editing) sourcePopup.visible = false

    // ── Bouton de verre (cible ≥ 30 px, brief §3) ─────────────────────────
    component GlassButton: Rectangle {
        id: btn

        property string glyph: ""
        property bool active: false
        property real size: 30
        property bool locked: false
        signal tapped()

        implicitWidth: btn.size
        implicitHeight: btn.size
        radius: Theme.radiusBtn
        color: Theme.a(Theme.glassBtn, Theme.alphaBtn)
        border.width: 1
        border.color: (btnHover.containsMouse || btn.active) ? Theme.halo : Theme.border
        opacity: btn.locked ? 0.55 : 1.0

        Behavior on color {
            ColorAnimation {
                duration: 90
                easing.type: Easing.OutCubic
            }
        }

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: Theme.ink
            font.pixelSize: Math.round(btn.height * 0.42)
        }

        MouseArea {
            id: btnHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !btn.locked
            onClicked: btn.tapped()
        }
    }

    // ── Cava (28 barres 2 px, gap 2, radius 1) ────────────────────────────
    // Correctif média (a) : la teinte vient de Theme.vizA / vizB, qui dérive
    // l'accent vers le texte quand l'accent est trop sombre (ici c'est le cas),
    // et l'opacité des barres animées monte à 0.9.
    component Cava: Canvas {
        id: cava

        property int count: 28
        property bool active: false
        property string regKey: ""
        // Clé effectivement enregistrée auprès de Music (permet de libérer
        // l'ancienne quand `regKey` change : instanceId posé par l'hôte).
        property string lastKey: ""
        readonly property var vals: Music.vizVals
        readonly property bool live: Music.playing

        // Enregistrement auprès de Music : le timer 60 ms ne tourne que si au
        // moins un cava VISIBLE existe (brief v1b). Idempotent.
        function syncReg() {
            var want = cava.active && cava.regKey.length > 0;
            if (cava.lastKey.length > 0 && cava.lastKey !== cava.regKey)
                Music.wantViz(cava.lastKey, false);
            cava.lastKey = want ? cava.regKey : "";
            if (cava.regKey.length > 0)
                Music.wantViz(cava.regKey, want);
        }
        onActiveChanged: cava.syncReg()
        onRegKeyChanged: cava.syncReg()
        Component.onCompleted: cava.syncReg()
        Component.onDestruction: Music.wantViz(cava.lastKey.length > 0 ? cava.lastKey
                                                                     : cava.regKey, false)

        function barPath(ctx, x, y, w, h, r) {
            var rr = Math.min(r, h / 2, w / 2);
            ctx.beginPath();
            ctx.moveTo(x, y + h);
            ctx.lineTo(x, y + rr);
            ctx.quadraticCurveTo(x, y, x + rr, y);
            ctx.lineTo(x + w - rr, y);
            ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
            ctx.lineTo(x + w, y + h);
            ctx.closePath();
            ctx.fill();
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var w = width;
            var h = height;
            if (w <= 4 || h <= 4)
                return;
            var n = Math.max(1, cava.count);
            var bw = 2;                     // largeur imposée (brief v1b)
            var gapPx = 2;                  // écart imposé
            var need = n * bw + (n - 1) * gapPx;
            if (need > w)                   // carte étroite : on ne rogne pas les barres
                gapPx = Math.max(0.5, (w - n * bw) / Math.max(1, n - 1));
            var total = n * bw + (n - 1) * gapPx;
            var x0 = Math.max(0, (w - total) / 2);

            var src = cava.vals;

            // Échantillon par barre (le viz renvoie 20 valeurs, le widget en
            // dessine 8..48 : plusieurs barres peuvent lire la même valeur).
            var vals = [];
            var maxV = 0;
            for (var s = 0; s < n; ++s) {
                var v = 0;
                if (src && src.length > 0)
                    v = src[Math.min(src.length - 1, Math.floor(s * src.length / n))];
                if (typeof v !== "number" || !isFinite(v))
                    v = 0;
                v = Math.max(0, Math.min(1, v));
                vals.push(v);
                if (v > maxV)
                    maxV = v;
            }

            // Correctif v1c-2 : cava au repos (toutes les valeurs ~0, donc en
            // pause) — on ne dessine plus une rangée de barres pointillées de
            // 2 px qui ressemblait à un bug d'affichage, mais UNE ligne de
            // base de 1 px à alpha 0.15.
            if (maxV < 0.02) {
                ctx.fillStyle = Theme.a(Theme.vizA, 0.15);
                ctx.fillRect(x0, h - 1, total, 1);
                return;
            }

            var rest = Theme.a(Theme.vizA, 0.25);   // alpha 0.25 au repos
            var grad = null;
            if (cava.live) {
                grad = ctx.createLinearGradient(0, h, 0, 0);
                grad.addColorStop(0, Theme.a(Theme.vizA, Theme.vizAlpha));
                grad.addColorStop(1, Theme.a(Theme.vizB, Theme.vizAlpha));
            }
            ctx.fillStyle = cava.live ? grad : rest;

            for (var i = 0; i < n; ++i) {
                // Barres visibles (2 px mini) : un cava figé (valeurs non
                // nulles, lecture en pause) reste lisible.
                var bh = Math.max(2, Math.round(vals[i] * h));
                cava.barPath(ctx, x0 + i * (bw + gapPx), h - bh, bw, bh, 1);
            }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        Connections {
            target: Music
            function onVizValsChanged() {
                if (cava.visible)
                    cava.requestPaint();
            }
            function onPlayingChanged() {
                if (cava.visible)
                    cava.requestPaint();
            }
        }
    }

    // ── Variante visualizer : cava seul, hors carte ───────────────────────
    Cava {
        anchors.fill: parent
        anchors.margins: Math.round(root.height * 0.06)
        visible: root.vizOnly && root.visible
        count: root.barCount
        regKey: root.instanceId + "/viz"
        active: visible && !root.editing
    }

    // ── Contenu avec carte ────────────────────────────────────────────────
    Item {
        id: content
        anchors.fill: parent
        anchors.margins: root.pad
        visible: !root.vizOnly

        // — compact : barre de son + lecture —
        Row {
            anchors.fill: parent
            visible: root.compact
            spacing: 10

            Column {
                width: Math.max(1, parent.width - root.btnSize - parent.spacing)
                height: parent.height
                spacing: 4

                Text {
                    width: parent.width
                    height: Math.round(parent.height * 0.40)
                    text: root.titleText
                    color: Music.hasTrack ? root.ink : root.inkDim
                    font.pixelSize: Math.max(11, Math.round(root.height * 0.19))
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    width: parent.width
                    height: Math.round(parent.height * 0.26)
                    text: root.artistText
                    color: root.inkDim
                    font.pixelSize: Math.max(9, Math.round(root.height * 0.13))
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    verticalAlignment: Text.AlignVCenter
                }

                // Piste de lecture (2 px, rayon 1).
                Rectangle {
                    width: parent.width
                    height: 2
                    radius: 1
                    color: Theme.a(root.ink, 0.12)

                    Rectangle {
                        width: parent.width * Music.progress
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
            }

            GlassButton {
                anchors.verticalCenter: parent.verticalCenter
                size: root.btnSize
                locked: root.editing
                glyph: Music.playing ? "⏸" : "▶"
                active: Music.playing
                onTapped: Music.toggle()
            }
        }

        // — normal / hero : pochette à gauche, colonne ancrée à droite —
        Row {
            anchors.fill: parent
            visible: !root.compact
            spacing: Theme.spacing

            // Pochette arrondie. MultiEffect masque l'Image avec un rectangle
            // du même rayon (le Canvas ne sait pas dessiner une Image dans cet
            // environnement : testé, rendu vide).
            Item {
                id: coverBox
                width: root.coverSide
                height: root.coverSide
                anchors.verticalCenter: parent.verticalCenter

                // Placeholder dégradé card → accent (aucune image, 404 compris).
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusBtn
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Theme.glassCard
                        }
                        GradientStop {
                            position: 1.0
                            color: Theme.a(Theme.vizA, 0.34)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: coverImg.status !== Image.Ready
                        text: "♪"
                        color: Theme.a(root.ink, 0.55)
                        font.pixelSize: Math.round(coverBox.height * 0.36)
                    }
                }

                Image {
                    id: coverImg
                    anchors.fill: parent
                    visible: false
                    source: Music.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: Math.round(root.coverSide * 2)
                    sourceSize.height: Math.round(root.coverSide * 2)
                }

                MultiEffect {
                    anchors.fill: parent
                    visible: coverImg.status === Image.Ready
                    source: coverImg
                    maskEnabled: true
                    maskSource: coverMask
                    maskThresholdMin: 0.5
                }

                // Masque : rectangle arrondi rendu en texture (layer).
                Item {
                    id: coverMask
                    anchors.fill: parent
                    layer.enabled: true
                    visible: false

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusBtn
                        color: Theme.ink
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusBtn
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.border
                }
            }

            // Colonne de droite : tout est ancré, donc aucune zone ne peut
            // en recouvrir une autre. Ordre vertical imposé :
            // titre → artiste → album → cava (extensible) → progression →
            // transport (boutons + temps + pilule source sur UNE ligne).
            Item {
                id: rightCol
                width: Math.max(1, parent.width - coverBox.width - parent.spacing)
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: trackTitle
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: root.lineH
                    text: root.titleText
                    color: Music.hasTrack ? root.ink : root.inkDim
                    font.pixelSize: root.titleSize
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    id: trackArtist
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: trackTitle.bottom
                    height: root.subH
                    text: root.artistText
                    color: root.inkDim
                    font.pixelSize: root.artistSize
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    id: trackAlbum
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: trackArtist.bottom
                    height: root.albumH
                    visible: root.hero
                    text: Music.album
                    color: Theme.a(root.inkDim, 0.8)
                    font.pixelSize: Math.max(9, root.artistSize - 1)
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    verticalAlignment: Text.AlignVCenter
                }

                // Cava : occupe TOUT l'espace libre entre le bloc texte et la
                // barre de progression (hero : la moitié basse n'est jamais
                // vide). Masqué si la place restante est trop courte.
                Cava {
                    id: inlineCava
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: trackAlbum.visible ? trackAlbum.bottom : trackArtist.bottom
                    anchors.topMargin: root.gap
                    anchors.bottom: progressBar.top
                    anchors.bottomMargin: root.gap
                    visible: height >= 10 && root.visible
                    count: root.barCount
                    regKey: root.instanceId + "/inline"
                    active: visible && !root.editing
                }

                // Barre de progression : ligne dédiée 2 px rayon 1, fond
                // rgba(text, 0.12), AU-DESSUS du transport (correctif b).
                Rectangle {
                    id: progressBar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: transportRow.top
                    anchors.bottomMargin: root.gap
                    height: 2
                    radius: 1
                    color: Theme.a(root.ink, 0.12)

                    Rectangle {
                        width: parent.width * Music.progress
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

                // Transport + temps + pilule source (une seule ligne).
                Item {
                    id: transportRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: root.btnSize

                    Row {
                        id: btns
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        GlassButton {
                            size: root.btnSize
                            locked: root.editing
                            glyph: "⏮"
                            onTapped: Music.prev()
                        }
                        GlassButton {
                            size: root.btnSize
                            locked: root.editing
                            glyph: Music.playing ? "⏸" : "▶"
                            active: Music.playing
                            onTapped: Music.toggle()
                        }
                        GlassButton {
                            size: root.btnSize
                            locked: root.editing
                            glyph: "⏭"
                            onTapped: Music.next()
                        }
                    }

                    Text {
                        id: timeText
                        anchors.right: pill.visible ? pill.left : parent.right
                        anchors.rightMargin: pill.visible ? 8 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.hero && Music.duration > 0
                        // Largeur bornée par la place à gauche de la pilule :
                        // jamais d'implicitWidth ici (boucle de binding).
                        width: visible ? Math.max(0, Math.min(root.timeW,
                                                              transportRow.width - btns.width - root.pillH * 6))
                                       : 0
                        text: Music.clock(Music.elapsed) + " / " + Music.clock(Music.duration)
                        color: root.inkDim
                        font.pixelSize: Math.max(9, root.artistSize - 1)
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        verticalAlignment: Text.AlignVCenter
                    }

                    // Pilule source (brief §6) : clic = épingler une source.
                    Rectangle {
                        id: pill
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.showSource
                        readonly property real avail: Math.max(0, transportRow.width - btns.width - 8
                                                                  - (timeText.visible ? timeText.width + 8 : 0))
                        width: visible ? Math.min(avail, root.pillTextW + 2 * Math.round(root.pillH * 0.5)) : 0
                        height: visible ? root.pillH : 0
                        radius: Theme.radiusBtn
                        color: Theme.a(Theme.glassBtn, Theme.alphaBtn)
                        border.width: 1
                        border.color: pillHover.containsMouse ? Theme.halo : Theme.border

                        Text {
                            id: pillText
                            anchors.centerIn: parent
                            width: Math.max(0, pill.width - 8)
                            text: root.pillLabel
                            color: Music.playing ? Theme.vizA : root.inkDim
                            font.pixelSize: Math.max(9, Math.round(root.pillH * 0.52))
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }

                        MouseArea {
                            id: pillHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.editing && root.showSource
                            onClicked: {
                                Music.refreshSources();
                                sourcePopup.visible = !sourcePopup.visible;
                            }
                        }
                    }
                }
            }
        }

        // — liste des sources détectées (épinglage) —
        Rectangle {
            id: sourcePopup
            visible: false
            z: 200
            width: Math.min(root.width - 2 * root.pad, 210)
            height: Math.min(root.height - 2 * root.pad, popColumn.implicitHeight + 8)
            radius: Theme.radiusCard
            color: Theme.a(Theme.glassBase, 0.92)
            border.width: 1
            border.color: Theme.border
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            Column {
                id: popColumn
                anchors.fill: parent
                anchors.margins: 4
                spacing: 2

                Repeater {
                    model: [{ name: "", label: "Automatique", detail: "la plus récente" }].concat(
                               Music.sourceChoices)

                    delegate: Rectangle {
                        width: popColumn.width
                        height: Math.max(22, Math.round(root.pillH * 1.15))
                        radius: Theme.radiusBtn
                        color: rowHover.containsMouse ? Theme.a(Theme.glassBtn, Theme.alphaBtn)
                                                      : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: (modelData.label || modelData.name)
                                  + (modelData.detail ? " · " + modelData.detail : "")
                            color: (Music.pinned === modelData.name) ? Theme.vizA : root.ink
                            font.pixelSize: Math.max(9, root.artistSize - 1)
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }

                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Music.pinSource(modelData.name);
                                sourcePopup.visible = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
