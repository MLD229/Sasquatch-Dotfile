// ClockWidget.qml — horloge (widget `clock`, brief §7 v1a).
//
// Variantes : compact = HH:mm seul · normal = + date · hero = + secondes,
// modes : `digital` (défaut), `analog` (Canvas, aucune dépendance externe),
// `kana` (heure en hiragana, ex-horloge du fond d'écran).
// Aucun timer ici : le temps vient de Env (une seule horloge pour tout le
// shell) — un widget LIT, il ne sonde pas.
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "clock"

    readonly property bool analog: !!(root.options && root.options.mode === "analog")
    // Catalogue brief §6 : compact = HH:mm · normal = + date · hero = + secondes.
    // L'option `showSeconds` ne pilote donc que la variante hero.
    readonly property bool showSecondsOption: !!(root.options && root.options.showSeconds)
    readonly property bool showSeconds: root.hero && root.showSecondsOption
    readonly property bool hour24: !(root.options && root.options.hour24 === false)

    // ── Mode `kana` : heure en hiragana ──────────────────────────────────
    // Tables portées de l'ex-horloge du fond d'écran (waybar/scripts/
    // wallclock-ja.py) — même découpage que là-bas : le suffixe じ / ぷん /
    // ふん est teinté accent, le nombre reste en couleur de texte.
    readonly property bool kanaMode: !!(root.options && root.options.mode === "kana")

    readonly property var kanaHours: [
        "れい", "いち", "に", "さん", "よ", "ご", "ろく", "しち", "はち", "く",
        "じゅう", "じゅういち", "じゅうに", "じゅうさん", "じゅうよ", "じゅうご",
        "じゅうろく", "じゅうしち", "じゅうはち", "じゅうく", "にじゅう",
        "にじゅういち", "にじゅうに", "にじゅうさん"
    ]
    readonly property var kanaTens: ["", "じゅう", "にじゅう", "さんじゅう", "よんじゅう", "ごじゅう"]
    readonly property var kanaUnits: ["", "いっ", "に", "さん", "よん", "ご", "ろっ", "なな", "はっ", "きゅう"]
    // Suffixe par chiffre des unités : 1 いっぷん · 3 さんぷん · 6 ろっぷん …
    readonly property var kanaSuffix: ["ぷん", "ふん", "ぷん", "ぷん", "ふん", "ぷん", "ふん", "ぷん", "ふん"]
    readonly property var kanaMonths: [
        "いちがつ", "にがつ", "さんがつ", "しがつ", "ごがつ", "ろくがつ",
        "しちがつ", "はちがつ", "くがつ", "じゅうがつ", "じゅういちがつ", "じゅうにがつ"
    ]
    readonly property var kanaDays: [
        "ついたち", "ふつか", "みっか", "よっか", "いつか", "むいか", "なのか",
        "ようか", "ここのか", "とおか", "じゅういちにち", "じゅうににち",
        "じゅうさんにち", "じゅうよっか", "じゅうごにち", "じゅうろくにち",
        "じゅうしちにち", "じゅうはちにち", "じゅうくにち", "はつか",
        "にじゅういちにち", "にじゅうににち", "にじゅうさんにち", "にじゅうよっか",
        "にじゅうごにち", "にじゅうろくにち", "にじゅうしちにち", "にじゅうはちにち",
        "にじゅうくにち", "さんじゅうにち", "さんじゅういちにち"
    ]
    readonly property var kanaWeekdays: ["日", "月", "火", "水", "木", "金", "土"]

    // Minutes : 0 → rien (on dit juste ろくじ), dizaine exacte → じゅっぷん.
    function kanaMinuteOf(m) {
        if (!m)
            return { num: "", suffix: "" };
        var t = Math.floor(m / 10);
        var u = m % 10;
        if (u === 0)
            return { num: root.kanaTens[t].replace("じゅう", "じゅっ"), suffix: "ぷん" };
        return { num: root.kanaTens[t] + root.kanaUnits[u], suffix: root.kanaSuffix[u - 1] };
    }

    readonly property string kanaHour: root.kanaHours[Env.now.getHours()]
    readonly property var kanaMinute: root.kanaMinuteOf(Env.now.getMinutes())
    readonly property string kanaDate: root.kanaMonths[Env.now.getMonth()] + " " + root.kanaDays[Env.now.getDate() - 1]
    readonly property string kanaDay: root.kanaWeekdays[Env.now.getDay()]

    // Les hiragana sont pleine chasse, mais l'avance réelle dépend de la
    // police : on la MESURE (TextMetrics à 100 px) au lieu de la supposer.
    // La taille est alors celle qui fait tenir la ligne entière, espace entre
    // groupes compris (0.42 em) — aucune découpe, aucun Fit par morceau.
    readonly property string kanaFull: root.kanaHour + "じ"
        + (root.kanaMinute.num.length > 0
           ? " " + root.kanaMinute.num + root.kanaMinute.suffix : "")

    TextMetrics {
        id: kanaMetrics
        font.pixelSize: 100
        font.family: "Noto Sans CJK JP"
        font.weight: Font.Black
        text: root.kanaFull
    }

    readonly property real kanaAdvEm: kanaMetrics.advanceWidth / 100
    readonly property real kanaSize: Math.max(10, Math.min(root.height * 0.30,
        (root.width - 2 * root.pad) / (root.kanaAdvEm + 0.42)))
    readonly property real kanaDateSize: Math.max(8, Math.min(root.height * 0.10,
        (root.width - 2 * root.pad) / (kanaDateMetrics.advanceWidth / 100)))

    TextMetrics {
        id: kanaDateMetrics
        font.pixelSize: 100
        font.family: "Noto Sans CJK JP"
        text: root.kanaDate + "  " + root.kanaDay
    }

    readonly property string timeFormat: root.hour24
        ? (root.showSeconds ? "HH:mm:ss" : "HH:mm")
        : (root.showSeconds ? "h:mm:ss AP" : "h:mm AP")

    // Taille issue de la carte (jamais un littéral) : « HH:mm » ≈ 2,9 fois
    // la taille de police en largeur, plafonnée par la hauteur utile.
    readonly property real timeSize: Math.max(12, Math.min(root.height * 0.34,
                                                           (root.width - 2 * root.pad) / 2.9))
    readonly property real dateSize: Math.max(9, Math.min(root.height * 0.11, root.timeSize * 0.32))

    readonly property string timeText: Qt.formatDateTime(Env.now, root.timeFormat)
    // Date en français, sans dépendre de la locale du processus (voir Env).
    readonly property string dateText: Env.dayShort[Env.now.getDay()] + " "
                                        + Env.now.getDate() + " "
                                        + Env.monthShort[Env.now.getMonth()]

    // ── Digital ───────────────────────────────────────────────────────────
    Column {
        id: digital
        visible: !root.analog && !root.kanaMode
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.compact ? 0 : Math.round(root.height * 0.02)

        Text {
            width: parent.width
            height: parent.height - (date.visible ? date.height + parent.spacing : 0)
            text: root.timeText
            color: root.ink
            font.pixelSize: root.timeSize
            font.weight: Font.Light
            // La police du rice n'est pas monospace : on borne la taille mais
            // c'est le Fit qui garantit que « 23:49:57 » reste entier.
            fontSizeMode: Text.Fit
            minimumPixelSize: 9
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        Text {
            id: date
            width: parent.width
            visible: !root.compact
            text: root.dateText
            color: root.inkDim
            font.pixelSize: root.dateSize
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    // ── Kana (mode `kana`) ────────────────────────────────────────────────
    // Deux groupes collés (« ろく » + じ, « ごじゅう » + ご + ふん) séparés par
    // un espace : les suffixes portent l'accent, comme sur l'ancienne horloge.
    Column {
        id: kana
        visible: root.kanaMode
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.round(root.height * 0.02)

        Item {
            id: kanaTimeBox
            width: parent.width
            height: parent.height - (kanaDate.visible ? kanaDate.height + kana.spacing : 0)

            Row {
                anchors.centerIn: parent
                spacing: 0

                Text {
                    text: root.kanaHour
                    color: root.ink
                    font.pixelSize: root.kanaSize
                    font.weight: Font.Black
                    font.family: "Noto Sans CJK JP"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "じ"
                    color: root.accentInk
                    font.pixelSize: root.kanaSize
                    font.weight: Font.Black
                    font.family: "Noto Sans CJK JP"
                    anchors.verticalCenter: parent.verticalCenter
                }
                // Espace entre les deux groupes (même avance qu'un hiragana).
                Item {
                    width: Math.round(root.kanaSize * 0.42)
                    height: 1
                }
                Text {
                    text: root.kanaMinute.num
                    visible: text.length > 0
                    color: root.ink
                    font.pixelSize: root.kanaSize
                    font.weight: Font.Black
                    font.family: "Noto Sans CJK JP"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.kanaMinute.suffix
                    visible: text.length > 0
                    color: root.accentInk
                    font.pixelSize: root.kanaSize
                    font.weight: Font.Black
                    font.family: "Noto Sans CJK JP"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Text {
            id: kanaDate
            width: parent.width
            visible: !root.compact
            text: root.kanaDate + "  " + root.kanaDay
            color: root.inkDim
            font.pixelSize: root.kanaDateSize
            font.family: "Noto Sans CJK JP"
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    // ── Analogique (hero, mode `analog`) ──────────────────────────────────
    Canvas {
        id: face
        anchors.fill: parent
        anchors.margins: root.pad + 4
        visible: root.analog

        readonly property real side: Math.min(width, height)
        readonly property color tickColor: Theme.a(root.ink, 0.35)
        readonly property color hourColor: root.ink
        readonly property color minuteColor: root.ink
        readonly property color secondColor: Theme.accent

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var w = width;
            var h = height;
            var cx = w / 2;
            var cy = h / 2;
            var r = face.side / 2 - 2;
            if (r <= 4)
                return;

            ctx.lineWidth = Math.max(1, r * 0.012);
            ctx.strokeStyle = face.tickColor;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.stroke();

            // 12 repères
            var i, ang, r1, r2;
            for (i = 0; i < 12; ++i) {
                ang = i * Math.PI / 6;
                r1 = r * (i % 3 === 0 ? 0.82 : 0.90);
                r2 = r * 0.97;
                ctx.beginPath();
                ctx.moveTo(cx + Math.sin(ang) * r1, cy - Math.cos(ang) * r1);
                ctx.lineTo(cx + Math.sin(ang) * r2, cy - Math.cos(ang) * r2);
                ctx.stroke();
            }

            var now = Env.now;
            var sec = now.getSeconds();
            var min = now.getMinutes() + sec / 60;
            var hr = (now.getHours() % 12) + min / 60;

            function hand(angle, length, widthPx, color) {
                ctx.beginPath();
                ctx.lineWidth = widthPx;
                ctx.strokeStyle = color;
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx + Math.sin(angle) * length, cy - Math.cos(angle) * length);
                ctx.stroke();
            }

            hand(hr * Math.PI / 6, r * 0.52, Math.max(2, r * 0.05), face.hourColor);
            hand(min * Math.PI / 30, r * 0.74, Math.max(1.5, r * 0.032), face.minuteColor);
            if (root.showSeconds)
                hand(sec * Math.PI / 30, r * 0.84, Math.max(1, r * 0.014), face.secondColor);

            ctx.beginPath();
            ctx.fillStyle = face.secondColor;
            ctx.arc(cx, cy, Math.max(1.5, r * 0.03), 0, Math.PI * 2);
            ctx.fill();
        }

        onWidthChanged: if (visible) requestPaint()
        onHeightChanged: if (visible) requestPaint()
        onVisibleChanged: if (visible) requestPaint()
    }

    Connections {
        target: Env
        function onTickChanged() {
            if (face.visible)
                face.requestPaint();
        }
    }
}
