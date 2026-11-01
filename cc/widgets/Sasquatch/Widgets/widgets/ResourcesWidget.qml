// ResourcesWidget.qml — widget `resources` (catalogue §6 / tranche v1d).
//
// Variantes :
//   compact  220x64   3 anneaux (CPU / RAM / GPU), pourcentage seul
//   normal   360x180   3 anneaux légendés + sparkline CPU + température
//   hero     560x260   anneaux plus grands, sparkline haute, RAM et réseau
//
// Source : Env.stats (poll 2 s), qui reflète /api/stats
// {cpu, ram:{used,total,pct}, gpu:{util,temp}, cpu_temp, net:{up,down},
//  history:{cpu:[...]}}.
// Aucun XMLHttpRequest : le widget LIT Env. Aucune couleur en dur : les
// anneaux utilisent la teinte cava dérivée (Theme.vizA), donc lisibles même
// quand l'accent du thème est très sombre.
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "resources"

    readonly property var s: (Env.stats && typeof Env.stats === "object") ? Env.stats : ({})

    function num(v, dflt) {
        return (typeof v === "number" && isFinite(v)) ? v : dflt;
    }

    readonly property real cpu: Math.max(0, Math.min(100, root.num(root.s.cpu, 0)))
    readonly property real ramPct: Math.max(0, Math.min(100,
                                         root.num(root.s.ram ? root.s.ram.pct : undefined, 0)))
    readonly property real gpu: Math.max(0, Math.min(100,
                                     root.num(root.s.gpu ? root.s.gpu.util : undefined, 0)))
    readonly property real cpuTemp: root.num(root.s.cpu_temp, -1)
    readonly property real gpuTemp: root.num(root.s.gpu ? root.s.gpu.temp : undefined, -1)
    readonly property real ramUsed: root.num(root.s.ram ? root.s.ram.used : undefined, 0)
    readonly property real ramTotal: root.num(root.s.ram ? root.s.ram.total : undefined, 0)
    readonly property var history: (root.s.history && Array.isArray(root.s.history.cpu))
                                   ? root.s.history.cpu : []

    readonly property bool showSpark: !(root.options && root.options.showSparkline === false)
    readonly property bool showTemp: !(root.options && root.options.showTemp === false)

    // Trois états distincts (spec copy) : zéro est une MESURE, l'absence de
    // champ n'en est pas une. « GPU 0 % » ne doit jamais remplacer « non mesuré ».
    readonly property bool loading: Env.statsPolls === 0
    readonly property bool cpuMeasured: typeof root.s.cpu === "number"
    readonly property bool ramMeasured: !!(root.s.ram && typeof root.s.ram.pct === "number")
    readonly property bool gpuMeasured: !!(root.s.gpu && typeof root.s.gpu.util === "number")
    readonly property bool anyMeasured: root.cpuMeasured || root.ramMeasured || root.gpuMeasured
    readonly property bool unavailable: !root.loading && !root.anyMeasured

    readonly property real innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property real gap: Math.max(3, Math.round(root.innerH * 0.05))
    readonly property real headSize: Math.max(9, Math.min(14, Math.round(root.innerH * 0.11)))
    // Anneaux : hauteur bornée pour ne jamais écraser la sparkline.
    readonly property real ringH: Math.round(root.innerH * (root.hero ? 0.42
                                                    : (root.compact ? 1.0 : 0.40)))
    readonly property bool ringCaption: !root.compact

    readonly property string tempText: (root.cpuTemp < 0) ? "—" : (Math.round(root.cpuTemp) + "°")
    readonly property string ramText: (root.ramTotal > 0)
        ? ("Mémoire " + (root.ramUsed / 1024).toFixed(1) + "/" + (root.ramTotal / 1024).toFixed(0) + " Go")
        : "Mémoire"

    // ── Anneau (Canvas : aucune dépendance) ───────────────────────────────
    component Ring: Item {
        id: ring

        property real value: 0
        property bool measured: true
        property color strokeColor: Theme.vizA
        property string caption: ""
        property bool withCaption: true

        readonly property real captionH: ring.withCaption
            ? Math.max(9, Math.round(ring.height * 0.18)) : 0
        readonly property real side: Math.max(8, Math.min(ring.width, ring.height - ring.captionH))

        Canvas {
            id: arc
            width: ring.side
            height: ring.side
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter

            readonly property real lw: Math.max(2, Math.round(arc.width * 0.10))
            readonly property real v: Math.max(0, Math.min(100, ring.value))

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var r = width / 2 - arc.lw / 2 - 1;
                if (r <= 2)
                    return;
                var cx = width / 2;
                var cy = height / 2;
                ctx.lineCap = "round";
                ctx.lineWidth = arc.lw;

                // Piste (fond) puis valeur.
                ctx.beginPath();
                ctx.strokeStyle = Theme.a(Theme.ink, 0.12);
                ctx.arc(cx, cy, r, 0, Math.PI * 2);
                ctx.stroke();

                // Anneau vide quand la donnée n'est pas mesurée : la piste
                // seule suffit, on n'invente pas un 0 %.
                if (!ring.measured)
                    return;

                ctx.beginPath();
                ctx.strokeStyle = ring.strokeColor;
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (arc.v / 100));
                ctx.stroke();
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: ring
                function onValueChanged() {
                    arc.requestPaint();
                }
                function onStrokeColorChanged() {
                    arc.requestPaint();
                }
            }

            Text {
                anchors.centerIn: parent
                text: ring.measured ? (Math.round(arc.v) + "") : "—"
                color: ring.measured ? root.ink : root.inkDim
                font.pixelSize: Math.max(9, Math.round(arc.width * 0.30))
                font.weight: Font.Medium
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: ring.captionH
            visible: ring.withCaption
            text: ring.caption
            color: root.inkDim
            // Police ajustée à la colonne : « Carte graphique » ne doit jamais
            // être tronqué sur une carte étroite.
            font.pixelSize: Math.max(7, Math.min(Math.round(root.headSize * 0.82),
                                                 Math.floor(ring.width
                                                            / Math.max(1, ring.caption.length * 0.56))))
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    // ── Sparkline CPU (historique /api/stats) ─────────────────────────────
    component Spark: Canvas {
        id: spark

        property var values: []

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var n = spark.values ? spark.values.length : 0;
            if (n < 2 || width <= 4 || height <= 4)
                return;
            function px(i) {
                return (i / (n - 1)) * width;
            }
            function py(v) {
                var k = Math.max(0, Math.min(100, v));
                return height - (k / 100) * height;
            }

            // Courbe seule (constat brief §2 : « sparkline sans fioritures ») :
            // l'aire dégradée sous la courbe est supprimée.
            ctx.strokeStyle = Theme.a(Theme.vizA, 0.9);
            ctx.lineWidth = Math.max(1, Math.round(height * 0.035));
            ctx.lineJoin = "round";
            ctx.beginPath();
            for (var j = 0; j < n; ++j) {
                if (j === 0)
                    ctx.moveTo(px(j), py(spark.values[j]));
                else
                    ctx.lineTo(px(j), py(spark.values[j]));
            }
            ctx.stroke();
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: Env
            function onStatsChanged() {
                if (spark.visible)
                    spark.requestPaint();
            }
        }
    }

    // ── compact : 3 anneaux nus ───────────────────────────────────────────
    Row {
        visible: root.compact
        anchors.fill: parent
        spacing: Math.round(root.pad * 0.5)

        Ring {
            width: (parent.width - 2 * parent.spacing) / 3
            height: parent.height
            value: root.cpu
            measured: root.cpuMeasured
            strokeColor: Theme.vizA
            withCaption: false
        }
        Ring {
            width: (parent.width - 2 * parent.spacing) / 3
            height: parent.height
            value: root.ramPct
            measured: root.ramMeasured
            strokeColor: Theme.mix(Theme.vizA, Theme.ink, 0.35)
            withCaption: false
        }
        Ring {
            width: (parent.width - 2 * parent.spacing) / 3
            height: parent.height
            value: root.gpu
            measured: root.gpuMeasured
            strokeColor: Theme.mix(Theme.vizA, Theme.ink, 0.62)
            withCaption: false
        }
    }

    // ── normal / hero ─────────────────────────────────────────────────────
    Column {
        id: full
        visible: !root.compact
        anchors.fill: parent
        // Marge intérieure : « CPU 60° » était collé/coupé au bord arrondi
        // de la carte sur une carte de 4 colonnes (v1c-1).
        anchors.margins: root.pad
        spacing: root.gap

        Item {
            id: head
            width: parent.width
            height: Math.round(root.innerH * 0.12)

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Utilisation"
                color: root.ink
                font.pixelSize: root.headSize
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                id: tempLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.showTemp && root.cpuTemp >= 0
                width: visible ? Math.round(head.width * 0.40) : 0
                text: "Temp. " + root.tempText
                color: root.inkDim
                font.pixelSize: root.headSize
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                id: netLabel
                anchors.right: tempLabel.visible ? tempLabel.left : parent.right
                anchors.rightMargin: tempLabel.visible ? 10 : 0
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hero && root.ramTotal > 0
                width: visible ? Math.round(head.width * 0.34) : 0
                text: root.ramText
                color: root.inkDim
                font.pixelSize: root.headSize
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Légende = spec copy (« Processeur · Mémoire · Carte graphique ») :
        // un seul mot par anneau, jamais CPU/RAM/GPU.
        Row {
            id: ringsRow
            width: parent.width
            height: root.ringH
            spacing: Theme.spacing
            visible: !root.loading && !root.unavailable

            Ring {
                width: (parent.width - 2 * parent.spacing) / 3
                height: parent.height
                value: root.cpu
                measured: root.cpuMeasured
                strokeColor: Theme.vizA
                caption: "Processeur"
                withCaption: root.ringCaption
            }
            Ring {
                width: (parent.width - 2 * parent.spacing) / 3
                height: parent.height
                value: root.ramPct
                measured: root.ramMeasured
                strokeColor: Theme.mix(Theme.vizA, Theme.ink, 0.35)
                caption: "Mémoire"
                withCaption: root.ringCaption
            }
            Ring {
                width: (parent.width - 2 * parent.spacing) / 3
                height: parent.height
                value: root.gpu
                measured: root.gpuMeasured
                strokeColor: Theme.mix(Theme.vizA, Theme.ink, 0.62)
                caption: "Carte graphique"
                withCaption: root.ringCaption
            }
        }

        // État explicite quand il n'y a rien à mesurer (brief §1).
        Text {
            width: parent.width
            visible: root.loading || root.unavailable
            text: root.loading ? "Mesure…" : "Mesure indisponible"
            color: root.loading ? root.inkDim : Theme.warn
            font.pixelSize: root.headSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        // Sparkline : prend toute la place restante (jamais de vide en bas).
        Spark {
            width: parent.width
            height: Math.max(0, parent.height - Math.round(root.innerH * 0.12) - root.ringH
                             - 2 * parent.spacing)
            visible: root.showSpark && height > 6 && root.anyMeasured
            values: root.history
        }
    }
}
