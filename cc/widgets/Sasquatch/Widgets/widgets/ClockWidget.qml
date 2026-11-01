// ClockWidget.qml — horloge (widget `clock`, brief §7 v1a).
//
// Variantes : compact = HH:mm seul · normal = + date · hero = + secondes,
// et mode analogique (Canvas, aucune dépendance externe).
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
        visible: !root.analog
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
