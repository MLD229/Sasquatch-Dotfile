// WeatherWidget.qml — widget `weather` (catalogue §6 / tranche v1d).
//
// Variantes :
//   compact  220x64   température + icône (glyphe météo)
//   normal   360x180  + ville + libellé
//   hero     560x260  + ligne 3 jours SI la donnée existe
//
// Règle tenue : aucun widget ne sonde. Tout vient de Env.weather (poll 10 min
// dans Env), qui reflète /api/weather {ok, city, temp, code, label, age_s}.
// Le serveur NE fournit PAS de prévision quotidienne : la ligne 3 jours ne
// s'affiche donc que si un jour `daily` (ou `forecast`) apparaît un jour dans
// le payload. Rien n'est inventé, rien n'est simulé.
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "weather"

    readonly property var w: (Env.weather && typeof Env.weather === "object") ? Env.weather : ({})
    readonly property bool ok: root.w.ok === true
    readonly property bool hasTemp: (typeof root.w.temp === "number")
    readonly property int code: (typeof root.w.code === "number") ? root.w.code : -1
    readonly property string city: (typeof root.w.city === "string" && root.w.city.length > 0)
                                   ? root.w.city : "—"
    readonly property string label: (typeof root.w.label === "string") ? root.w.label : ""
    readonly property string tempText: root.hasTemp ? (Math.round(root.w.temp) + "°") : "—"

    // Trois états distincts (spec copy) : chargement / valeur / indisponible.
    readonly property bool loading: Env.weatherPolls === 0
    readonly property bool unavailable: !root.loading && (!root.ok || !root.hasTemp)
    // Sous-titre : « Lyon · plutôt dégagé » (une seule ligne, jamais vide).
    readonly property string subtitle: {
        var parts = [];
        if (root.ok && root.city !== "—")
            parts.push(root.city);
        if (root.ok && root.label.length > 0)
            parts.push(root.label);
        return parts.join(" · ");
    }
    // Fraîcheur en français : « actualisé il y a 5 min », jamais « open-meteo ».
    readonly property string ageText: {
        if (typeof root.w.age_s !== "number")
            return "";
        var s = Math.max(0, Math.round(root.w.age_s));
        if (s < 60)
            return "actualisé à l'instant";
        var m = Math.round(s / 60);
        if (m < 60)
            return "actualisé il y a " + m + " min";
        return "actualisé il y a " + Math.round(m / 60) + " h";
    }

    // Icône dessinée au Canvas (aucune dépendance, aucune couleur en dur,
    // jamais d'émoji couleur : la police du rice substituait les émojis et
    // cassait la teinte). `kind` : 0 inconnu, 1 soleil, 2 éclaircies,
    // 3 couvert, 4 brouillard, 5 pluie, 6 neige, 7 averses, 8 orage.
    component WxIcon: Canvas {
        id: wx

        property int kind: 0
        property color tint: Theme.vizA

        onKindChanged: requestPaint()
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var w = width;
            var h = height;
            var S = Math.min(w, h);
            if (S < 6)
                return;
            ctx.strokeStyle = wx.tint;
            ctx.fillStyle = wx.tint;
            ctx.lineWidth = Math.max(1.2, S * 0.065);
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            var cx = w / 2;
            var cy = h / 2;

            function sun(x, y, r) {
                ctx.beginPath();
                ctx.arc(x, y, r, 0, Math.PI * 2);
                ctx.stroke();
                for (var i = 0; i < 8; ++i) {
                    var a = i * Math.PI / 4;
                    ctx.beginPath();
                    ctx.moveTo(x + Math.cos(a) * r * 1.42, y + Math.sin(a) * r * 1.42);
                    ctx.lineTo(x + Math.cos(a) * r * 1.9, y + Math.sin(a) * r * 1.9);
                    ctx.stroke();
                }
            }

            function cloud(x, y, r) {
                ctx.beginPath();
                ctx.arc(x - r * 0.9, y, r * 0.62, Math.PI * 0.5, Math.PI * 1.5);
                ctx.arc(x - r * 0.2, y - r * 0.45, r * 0.72, Math.PI * 1.05, Math.PI * 1.85);
                ctx.arc(x + r * 0.75, y - r * 0.15, r * 0.6, Math.PI * 1.4, Math.PI * 2.05);
                ctx.closePath();
                ctx.stroke();
            }

            switch (wx.kind) {
            case 1:
                sun(cx, cy, S * 0.20);
                break;
            case 2:
                sun(cx + S * 0.17, cy - S * 0.17, S * 0.12);
                cloud(cx - S * 0.06, cy + S * 0.12, S * 0.28);
                break;
            case 3:
                cloud(cx, cy, S * 0.34);
                break;
            case 4:
                for (var f = 0; f < 3; ++f) {
                    ctx.beginPath();
                    ctx.moveTo(S * 0.16, cy - S * 0.14 + f * S * 0.14);
                    ctx.lineTo(S * 0.84 - (f === 1 ? S * 0.12 : 0), cy - S * 0.14 + f * S * 0.14);
                    ctx.stroke();
                }
                break;
            case 5:
                cloud(cx, cy - S * 0.12, S * 0.28);
                for (var r5 = 0; r5 < 3; ++r5) {
                    ctx.beginPath();
                    ctx.moveTo(cx - S * 0.20 + r5 * S * 0.17, cy + S * 0.20);
                    ctx.lineTo(cx - S * 0.25 + r5 * S * 0.17, cy + S * 0.34);
                    ctx.stroke();
                }
                break;
            case 6:
                cloud(cx, cy - S * 0.12, S * 0.28);
                for (var d6 = 0; d6 < 3; ++d6) {
                    ctx.beginPath();
                    ctx.arc(cx - S * 0.18 + d6 * S * 0.17, cy + S * 0.28, Math.max(1, S * 0.035), 0, Math.PI * 2);
                    ctx.fill();
                }
                break;
            case 7:
                cloud(cx, cy - S * 0.12, S * 0.28);
                for (var r7 = 0; r7 < 2; ++r7) {
                    ctx.beginPath();
                    ctx.moveTo(cx - S * 0.12 + r7 * S * 0.24, cy + S * 0.20);
                    ctx.lineTo(cx - S * 0.20 + r7 * S * 0.24, cy + S * 0.36);
                    ctx.stroke();
                }
                break;
            case 8:
                cloud(cx, cy - S * 0.14, S * 0.28);
                ctx.beginPath();
                ctx.moveTo(cx + S * 0.02, cy + S * 0.13);
                ctx.lineTo(cx - S * 0.10, cy + S * 0.28);
                ctx.lineTo(cx + S * 0.02, cy + S * 0.28);
                ctx.lineTo(cx - S * 0.06, cy + S * 0.44);
                ctx.stroke();
                break;
            default:
                ctx.beginPath();
                ctx.arc(cx, cy, Math.max(1.5, S * 0.06), 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }

    function kindFor(c) {
        if (c < 0)
            return 0;
        if (c <= 1)
            return 1;
        if (c === 2)
            return 2;
        if (c === 3)
            return 3;
        if (c === 45 || c === 48)
            return 4;
        if (c >= 51 && c <= 67)
            return 5;
        if (c >= 71 && c <= 77)
            return 6;
        if (c >= 80 && c <= 82)
            return 7;
        if (c >= 95)
            return 8;
        return 3;
    }

    readonly property int kind: root.kindFor(root.code)

    readonly property color tint: root.ok ? Theme.vizA : Theme.inkDim

    // Prévision : tolérant sur les noms de champs, vide = pas de ligne.
    readonly property var days: {
        if (Array.isArray(root.w.daily))
            return root.w.daily;
        if (Array.isArray(root.w.forecast))
            return root.w.forecast;
        return [];
    }
    readonly property int dayCount: Math.min(3, root.days.length)
    readonly property bool hasDays: root.dayCount > 0

    function dayName(d, i) {
        if (!d)
            return "";
        var v = d.day || d.label || d.name || d.date || "";
        if (typeof v !== "string" || v.length === 0)
            return "";
        return v.length > 6 ? v.substring(0, 6) : v;
    }

    function dayCode(d) {
        if (!d)
            return -1;
        return (typeof d.code === "number") ? d.code : -1;
    }

    function dayRange(d) {
        if (!d)
            return "";
        var mx = (typeof d.max === "number") ? d.max
               : (typeof d.tmax === "number") ? d.tmax
               : (typeof d.temp_max === "number") ? d.temp_max : null;
        var mn = (typeof d.min === "number") ? d.min
               : (typeof d.tmin === "number") ? d.tmin
               : (typeof d.temp_min === "number") ? d.temp_min : null;
        if (mx === null && mn === null)
            return "";
        if (mn === null)
            return Math.round(mx) + "°";
        if (mx === null)
            return Math.round(mn) + "°";
        return Math.round(mx) + "° / " + Math.round(mn) + "°";
    }

    // ── Tailles dérivées de la carte ──────────────────────────────────────
    readonly property real innerH: Math.max(8, root.height - 2 * root.pad)
    // Carte courte (4x1 = 96 px dans le board du CC) : le bloc normal doit
    // tenir SANS sortir de la carte (correctif v1c-1 — le libellé et l'icône
    // étaient coupés par le bord arrondi).
    readonly property bool shortCard: root.innerH < 110
    readonly property real tempSize: Math.max(16, Math.min(root.innerH * (root.compact ? 0.58
                                                          : (root.shortCard ? 0.36 : 0.44)),
                                                           (root.width - 2 * root.pad) * 0.42))
    // Icône : carrée, un peu plus grande que la ligne de température.
    readonly property real iconSide: Math.max(16, Math.round(root.tempSize * 0.92))
    readonly property real dayIconSide: Math.max(10, Math.round(root.labelSize * 1.3))
    readonly property real citySize: Math.max(10, Math.min(16, Math.round(root.innerH * 0.10)))
    readonly property real labelSize: Math.max(9, Math.round(root.citySize * 0.86))
    // Correctif v1c-2 : pied du hero (« données open-meteo · il y a N s »).
    // Sa hauteur est RÉSERVÉE, sinon le bloc du milieu pouvait passer dessous.
    readonly property bool showAge: root.hero && typeof root.w.age_s === "number"
    readonly property real ageH: root.showAge ? Math.round(root.labelSize * 1.6) : 0

    // Température : le chiffre et le degré ont des tailles DIFFÉRENTES.
    // Correctif v1c-1 : à la taille du chiffre, le glyphe « ° » de la police
    // du rice sort presque aussi gros qu'un chiffre (cercle disproportionné).
    // Ici le degré est un exposant à 42 % et remonté de 6 %.
    component Temp: Item {
        id: tp

        property string digits: root.loading ? "…" : (root.hasTemp ? (Math.round(root.w.temp) + "") : "—")
        property real size: root.tempSize
        // Le degré suit la taille du chiffre (constat brief §2 : l'exposant à
        // 42 % se lisait comme un point parasite).
        readonly property real degSize: Math.round(tp.size * 0.95)

        implicitWidth: Math.round(tpDigit.implicitWidth + tpDeg.implicitWidth)
        implicitHeight: Math.round(tpDigit.implicitHeight)

        Text {
            id: tpDigit
            text: tp.digits
            color: root.ink
            font.pixelSize: tp.size
            font.weight: Font.Light
        }

        Text {
            id: tpDeg
            x: tpDigit.implicitWidth
            y: 0
            visible: root.hasTemp
            text: "°"
            color: root.ink
            font.pixelSize: tp.degSize
            font.weight: Font.Light
        }
    }

    // ── compact : icône + température ─────────────────────────────────────
    Row {
        visible: root.compact
        anchors.centerIn: parent
        spacing: Math.round(root.pad * 0.6)

        WxIcon {
            width: root.iconSide
            height: root.iconSide
            anchors.verticalCenter: parent.verticalCenter
            kind: root.kind
            tint: root.tint
        }

        Temp {
            size: root.tempSize
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ── normal : titre, température au centre, sous-titre en pied ─────────
    // Répartition verticale (constat brief §2 : le bas de la carte était vide).
    // Titre `Météo`, sous-titre `Lyon · plutôt dégagé` (spec copy).
    Item {
        id: block
        visible: !root.compact && !root.hero
        anchors.fill: parent
        anchors.margins: root.pad

        Text {
            id: nTitle
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.round(root.labelSize * 1.4)
            text: "Météo"
            color: root.inkDim
            font.pixelSize: root.labelSize
            font.weight: Font.Medium
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignTop
        }

        Text {
            id: nSub
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.round(root.citySize * 1.4)
            visible: root.subtitle.length > 0 && !root.loading && !root.unavailable
            text: root.subtitle
            color: root.ink
            font.pixelSize: root.citySize
            font.weight: Font.Medium
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignBottom
        }

        // Ligne 3 jours : uniquement si la donnée existe réellement.
        Days {
            id: nDays
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: nSub.top
        }

        Item {
            id: nMidArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: nTitle.bottom
            anchors.bottom: root.hasDays ? nDays.top : (nSub.visible ? nSub.top : parent.bottom)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: Math.round(root.pad * 0.6)

                WxIcon {
                    width: root.iconSide
                    height: root.iconSide
                    anchors.verticalCenter: parent.verticalCenter
                    kind: root.kind
                    tint: root.tint
                }

                Temp {
                    size: root.tempSize
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // État explicite, jamais une carte muette (§1 du brief).
        Text {
            anchors.fill: parent
            anchors.topMargin: nTitle.height
            visible: root.loading || root.unavailable
            text: root.loading ? "Récupération…" : "Météo indisponible"
            color: root.loading ? root.inkDim : Theme.warn
            font.pixelSize: root.citySize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignVCenter
        }
    }

    // ── hero : hauteur RÉPARTIE (correctif v1c-2) ─────────────────────────
    // Icône + température en haut, ville + libellé au milieu de la place
    // restante, date des données en pied. Le serveur ne fournit pas de
    // prévision : sans cette répartition la carte hero avait une moitié
    // basse entièrement vide.
    Item {
        id: heroBlock
        visible: root.hero
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.topMargin: root.pad
        anchors.bottomMargin: root.pad + root.ageH

        Text {
            id: heroTitle
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.round(root.labelSize * 1.4)
            text: "Météo"
            color: root.inkDim
            font.pixelSize: root.labelSize
            font.weight: Font.Medium
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        Row {
            id: heroHead
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: heroTitle.bottom
            height: root.iconSide
            spacing: Math.round(root.pad * 0.6)

            WxIcon {
                width: root.iconSide
                height: root.iconSide
                anchors.verticalCenter: parent.verticalCenter
                kind: root.kind
                tint: root.tint
            }

            Temp {
                size: root.tempSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Zone restante sous l'entête : le bloc ville/libellé y est centré,
        // donc l'écart au-dessus et en dessous est le même (pas de vide
        // collé au pied).
        Item {
            id: heroMidArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: heroHead.bottom
            anchors.bottom: parent.bottom

            Column {
                id: heroMid
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(root.innerH * 0.02)

                Text {
                    width: parent.width
                    text: root.subtitle
                    color: root.ink
                    font.pixelSize: root.citySize + 3
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    visible: !root.loading && !root.unavailable && text.length > 0
                }

                Text {
                    width: parent.width
                    visible: root.loading || root.unavailable
                    text: root.loading ? "Récupération…" : "Météo indisponible"
                    color: root.loading ? root.inkDim : Theme.warn
                    font.pixelSize: root.labelSize + 1
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Days {}
            }
        }
    }

    // Ligne « 3 jours » partagée par normal et hero : un seul endroit.
    component Days: Row {
        id: days
        width: parent.width
        visible: root.hasDays
        height: visible ? Math.round(root.innerH * (root.hero ? 0.24 : 0.18)) : 0
        spacing: Theme.spacing

        Repeater {
            model: root.dayCount

            delegate: Column {
                width: Math.max(1, (days.width - (root.dayCount - 1) * days.spacing)
                                   / Math.max(1, root.dayCount))
                height: days.height
                spacing: 1

                Text {
                    width: parent.width
                    text: root.dayName(modelData, index)
                    color: root.inkDim
                    font.pixelSize: root.labelSize
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Row {
                    width: parent.width
                    height: root.dayIconSide + 2
                    spacing: 4

                    WxIcon {
                        width: root.dayIconSide
                        height: root.dayIconSide
                        anchors.verticalCenter: parent.verticalCenter
                        kind: root.kindFor(root.dayCode(modelData))
                        tint: root.tint
                    }

                    Text {
                        width: Math.max(0, parent.width - root.dayIconSide - 4)
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.dayRange(modelData)
                        color: root.ink
                        font.pixelSize: root.labelSize
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                }
            }
        }
    }

    // Hero : la fraîcheur de la donnée est RÉELLE (champ age_s du payload) —
    // jamais de valeur inventée. Alignée en pied, hauteur réservée (`ageH`).
    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.pad
        visible: root.showAge
        height: root.ageH
        text: root.ageText
        color: Theme.a(root.inkDim, 0.75)
        font.pixelSize: root.labelSize
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        verticalAlignment: Text.AlignBottom
    }
}
