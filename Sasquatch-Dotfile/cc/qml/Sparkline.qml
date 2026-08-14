// Sparkline.qml — mini graphe de tendance (historique métrique).
// Reçoit un tableau de valeurs (hist) et une couleur de ligne.
import QtQuick

Canvas {
    id: spark
    property var hist: []
    property color lineColor: "#89b4fa"     // défaut = cAccent

    onHistChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var h = hist;
        if (!h || h.length < 2) return;
        var maxV = Math.max.apply(null, h.concat([1]));
        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 2;
        ctx.beginPath();
        for (var i = 0; i < h.length; i++) {
            var x = (i / (h.length - 1)) * width;
            var y = height - (h[i] / maxV) * height;
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.stroke();
    }
}
