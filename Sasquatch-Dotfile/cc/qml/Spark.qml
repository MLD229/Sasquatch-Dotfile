// Sasquatch Control Center — Spark.qml
// Graphique historique (sparkline) en canvas.
import QtQuick

Canvas {
    id: root
    property var values: []
    property color color: Palette.accent
    property real maxValue: 100
    implicitHeight: 34
    antialiasing: true

    onValuesChanged: requestPaint()
    onColorChanged: requestPaint()
    onMaxValueChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        var w = width, h = height;
        ctx.clearRect(0, 0, w, h);
        var vals = root.values;
        if (!vals || vals.length < 2) return;
        var maxV = root.maxValue > 0 ? root.maxValue : 100;
        ctx.strokeStyle = root.color;
        ctx.lineWidth = 1.6;
        ctx.beginPath();
        for (var i = 0; i < vals.length; i++) {
            var x = (i / (vals.length - 1)) * w;
            var raw = vals[i] || 0;
            var y = h - 2 - (Math.min(maxV, Math.max(0, raw)) / maxV) * (h - 6);
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.stroke();
    }
}
