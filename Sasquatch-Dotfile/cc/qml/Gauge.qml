// Sasquatch Control Center — Gauge.qml
// Jauge en arc (canvas) pour CPU / RAM / GPU.
import QtQuick

Canvas {
    id: root
    property real value: 0
    property color color: Palette.accent
    implicitWidth: 150
    implicitHeight: 84
    antialiasing: true

    onValueChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        var w = width, h = height;
        ctx.clearRect(0, 0, w, h);
        var cx = w / 2, cy = h - 10, r = Math.min(w, h * 2) * 0.32;
        ctx.lineWidth = 8;
        ctx.lineCap = "round";
        ctx.strokeStyle = "rgba(255,255,255,0.08)";
        ctx.beginPath();
        ctx.arc(cx, cy, r, Math.PI, 2 * Math.PI);
        ctx.stroke();
        var v = Math.max(0, Math.min(100, root.value));
        ctx.strokeStyle = root.color;
        ctx.beginPath();
        ctx.arc(cx, cy, r, Math.PI, Math.PI + (Math.PI * v / 100));
        ctx.stroke();
    }
}
