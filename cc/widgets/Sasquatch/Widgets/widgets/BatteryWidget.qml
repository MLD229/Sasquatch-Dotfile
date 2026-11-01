// BatteryWidget.qml — widget `battery` (catalogue §6 / tranche v1d).
//
// Variantes :
//   compact  220x64   glyphe + pourcentage + état
//   normal   360x180  glyphe + grand pourcentage + état + jauge + conso/autonomie
//
// Lecture DIRECTE de /sys/class/power_supply/BAT0/ (capacity, status,
// power_now, energy_now, energy_full) : aucune route API n'existe pour la
// batterie, et le brief impose la lecture sysfs. Elle est faite une seule fois
// pour tout le shell par Env (Process, poll 30 s) ; le widget LIT Env.
// Machine sans BAT0 : batteryPct reste à -1 et le widget affiche « — » sans
// jamais planter (aucun chemin d'erreur, aucun index hors bornes).
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "battery"

    readonly property bool showWatts: !(root.options && root.options.showWatts === false)
    readonly property bool showTime: !(root.options && root.options.showTime === false)

    readonly property int pct: Env.batteryPct
    readonly property bool known: Env.batteryKnown
    readonly property bool full: Env.batteryState === "Full"
    readonly property bool charging: Env.batteryState === "Charging"
    readonly property bool low: root.known && root.pct <= 20

    // Métriques de l'icône dessinée (aucun glyphe unicode : la police des
    // emojis le rendait en couleur).
    readonly property real iconW: Math.max(22, Math.round(root.glyphSize * 1.7))
    readonly property real iconH: Math.round(root.iconW * 0.52)

    // Spec copy : à 100 % le pourcentage suffit — jamais « pleine » en plus.
    readonly property string stateText: {
        switch (Env.batteryState) {
        case "Charging":
            return "En charge";
        case "Discharging":
            return "Sur batterie";
        case "Full":
            return "";
        case "Not charging":
            return "Branchée";
        }
        return root.known ? "" : "Batterie non détectée";
    }

    readonly property string pctText: root.known ? (root.pct + " %") : "—"

    function duration(mins) {
        if (mins < 0 || !isFinite(mins))
            return "";
        var h = Math.floor(mins / 60);
        var m = Math.round(mins % 60);
        if (h <= 0)
            return m + " min";
        return h + " h " + (m < 10 ? "0" : "") + m;
    }

    // Autonomie (décharge) ou temps de charge restant : seulement si le noyau
    // expose power_now (sinon on n'affiche rien plutôt qu'un chiffre inventé).
    readonly property string timeText: {
        if (!root.known || Env.batteryMinutes < 0)
            return "";
        return (root.charging ? "reste " : "autonomie ") + root.duration(Env.batteryMinutes);
    }

    readonly property string wattsText: (root.showWatts && Env.batteryPower > 0)
        ? (Env.batteryWatts.toFixed(1) + " W") : ""

    readonly property real innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property real glyphSize: Math.max(14, Math.min(root.innerH * (root.compact ? 0.62 : 0.34),
                                                            root.width * 0.28))
    readonly property real bigSize: Math.max(14, Math.min(root.innerH * (root.compact ? 0.55 : 0.30),
                                                          root.width * 0.34))
    readonly property real smallSize: Math.max(9, Math.min(12, Math.round(root.innerH * 0.09)))
    readonly property real barH: Math.max(4, Math.round(root.innerH * 0.035))

    // Icône batterie dessinée au Canvas : un glyphe unicode (▮, ⚡) est rendu
    // par la police de l'emoji en couleur et casse la teinte du widget.
    // Ici : contour + borne + niveau + éclair quand ça charge, tout en Theme.
    component BatIcon: Canvas {
        id: bi

        property real level: 0        // 0..1 (0 si inconnu)
        property bool plugged: false
        property bool unknown: false
        property color tint: Theme.inkDim

        onLevelChanged: requestPaint()
        onPluggedChanged: requestPaint()
        onUnknownChanged: requestPaint()
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var w = width;
            var h = height;
            if (w < 8 || h < 6)
                return;
            var lw = Math.max(1, h * 0.11);
            var bw = w * 0.80;
            var bh = h * 0.66;
            var x0 = w * 0.04;
            var y0 = (h - bh) / 2;
            var inset = lw * 0.9;

            ctx.lineWidth = lw;
            ctx.lineJoin = "round";
            ctx.strokeStyle = Theme.a(bi.tint, 0.75);
            ctx.fillStyle = Theme.a(bi.tint, 0.9);

            ctx.beginPath();
            ctx.rect(x0, y0, bw, bh);
            ctx.stroke();

            // Borne (petit rectangle à droite).
            ctx.beginPath();
            ctx.moveTo(x0 + bw, y0 + bh * 0.30);
            ctx.lineTo(w * 0.99, y0 + bh * 0.30);
            ctx.lineTo(w * 0.99, y0 + bh * 0.70);
            ctx.lineTo(x0 + bw, y0 + bh * 0.70);
            ctx.stroke();

            if (!bi.unknown) {
                var inW = Math.max(0, (bw - 2 * inset) * bi.level);
                if (inW > 0.5)
                    ctx.fillRect(x0 + inset, y0 + inset, inW, bh - 2 * inset);
            }

            if (bi.plugged) {
                // Éclair au centre, à la couleur du texte : lisible sur le
                // niveau comme sur le fond.
                ctx.strokeStyle = Theme.ink;
                ctx.lineWidth = Math.max(1, h * 0.09);
                var bx = x0 + bw * 0.52;
                var by = y0 + bh * 0.18;
                ctx.beginPath();
                ctx.moveTo(bx, by);
                ctx.lineTo(bx - bw * 0.18, by + bh * 0.36);
                ctx.lineTo(bx + bw * 0.04, by + bh * 0.36);
                ctx.lineTo(bx - bw * 0.14, by + bh * 0.68);
                ctx.stroke();
            }
        }
    }

    readonly property color tint: !root.known ? Theme.inkDim
                                  : root.low ? Theme.hot
                                  : root.charging ? Theme.vizA : Theme.ink

    // ── compact : glyphe + pourcentage + état ─────────────────────────────
    Row {
        visible: root.compact
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.round(root.pad * 0.55)

        BatIcon {
            id: cbGlyph
            width: root.iconW
            height: root.iconH
            anchors.verticalCenter: parent.verticalCenter
            level: root.known ? root.pct / 100 : 0
            plugged: root.charging
            unknown: !root.known
            tint: root.tint
        }

        Text {
            id: cbPct
            anchors.verticalCenter: parent.verticalCenter
            text: root.pctText
            color: root.tint
            font.pixelSize: root.bigSize
            font.weight: Font.Light
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - cbGlyph.width - cbPct.width - 2 * parent.spacing)
            visible: text.length > 0
            text: root.stateText
            color: root.inkDim
            font.pixelSize: root.smallSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignVCenter
        }
    }

    // ── normal : glyphe + grand pourcentage, jauge, conso ─────────────────
    // Disposition ANCRÉE, pas un Column qui pousse ses enfants : la jauge
    // reste TOUJOURS dans la carte, juste sous le pourcentage, même sur une
    // carte d'une seule rangée (4x1 = 96 px). Correctif v1c-1 (la barre
    // débordait sous la carte et sous le texte).
    Item {
        id: nArea
        visible: !root.compact
        anchors.fill: parent
        anchors.margins: root.pad

        // Hauteurs qui se partagent EXACTEMENT la carte (aucun débordement).
        readonly property real spacing: Math.max(3, Math.min(8, Math.round(nArea.height * 0.05)))
        readonly property real barH: Math.max(4, Math.min(8, Math.round(nArea.height * 0.06)))
        readonly property real footH: nFoot.visible ? Math.round(root.smallSize * 1.45) : 0
        // Sur une carte d'une ligne (96 px) le calcul « tout l'espace restant »
        // poussait la jauge sur l'arête basse : elle se lisait comme un trait.
        // On plafonne le bloc d'en-tête pour les cartes basses.
        readonly property real natHeaderH: Math.max(0, nArea.height - nArea.barH - nArea.footH - 2 * nArea.spacing)
        readonly property real headerH: (nArea.height < 140)
                                         ? Math.min(natHeaderH, Math.round(nArea.height * 0.55))
                                         : natHeaderH

        Row {
            id: nHead
            width: parent.width
            height: nArea.headerH
            spacing: Math.round(root.pad * 0.55)
            clip: true

            BatIcon {
                id: nbIcon
                width: root.iconW * 1.15
                height: root.iconH * 1.15
                anchors.verticalCenter: parent.verticalCenter
                level: root.known ? root.pct / 100 : 0
                plugged: root.charging
                unknown: !root.known
                tint: root.tint
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - nbIcon.width - parent.spacing)
                spacing: 1

                Text {
                    text: root.pctText
                    color: root.tint
                    font.pixelSize: root.bigSize
                    font.weight: Font.Light
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: root.stateText
                    color: root.inkDim
                    font.pixelSize: root.smallSize
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
            }
        }

        // Jauge : piste rgba(text, 0.12) + remplissage à la teinte d'état.
        Rectangle {
            id: nBar
            // Jauge courte : pleine largeur elle se lisait comme un filet /
            // séparateur, surtout à 100 % où le remplissage couvre la piste.
            anchors.left: parent.left
            width: Math.max(48, Math.round(parent.width * 0.62))
            // Jauge réellement DANS la carte : à 96 px de haut la piste
            // tombait sur l'arête et se lisait comme un séparateur.
            y: Math.min(nArea.headerH + nArea.spacing,
                        parent.height - nArea.barH - Math.max(2, Math.round(nArea.spacing * 0.6)))
            height: nArea.barH
            radius: Math.round(height / 2)
            // Pas de piste : sur fond transparent une piste à 10 % se lit comme
            // un filet blanc. Seul le remplissage porte l'information.
            color: "transparent"
            clip: true

            Rectangle {
                width: parent.width * (root.known ? Math.max(0, Math.min(1, root.pct / 100)) : 0)
                height: parent.height
                radius: parent.radius
                // Même règle que le cava : un accent sombre ne se voit pas sur
                // la carte, on le dérive vers l'encre (sinon jauge invisible).
                color: {
                    if (Theme.luminance(root.tint) < 0.25)
                        return Theme.mix(root.tint, root.ink, 0.65);
                    return root.tint;
                }
                Behavior on width {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Text {
            id: nFoot
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: nArea.footH
            text: {
                var parts = [];
                if (root.timeText.length > 0)
                    parts.push(root.timeText);
                if (root.wattsText.length > 0)
                    parts.push(root.wattsText);
                return parts.join(" · ");
            }
            color: root.inkDim
            font.pixelSize: root.smallSize
            visible: text.length > 0
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignBottom
        }
    }
}
