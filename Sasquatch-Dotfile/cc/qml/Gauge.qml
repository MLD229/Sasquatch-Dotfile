// Gauge.qml — jauge circulaire (CPU / RAM / GPU) : anneau + % au centre + label.
// Composant purement visuel : les données viennent de properties (pct).
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: gauge
    spacing: 4
    Layout.alignment: Qt.AlignHCenter

    property real pct: 0
    property color strokeColor: "#89b4fa"    // défaut = cAccent
    property color textColor: "#cdd6f4"      // cText
    property color labelColor: "#a6adc8"     // cTextDim
    property string label: ""
    property bool showPct: true              // false → affiche "N/A" (ex: GPU absent)

    onPctChanged: cvs.requestPaint()

    Canvas {
        id: cvs
        width: 90; height: 90
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var cx = width/2, cy = height/2, r = width/2 - 8;
            ctx.lineWidth = 8;
            ctx.strokeStyle = Qt.rgba(1,1,1,0.1);
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI*2); ctx.stroke();
            ctx.strokeStyle = gauge.strokeColor;
            ctx.beginPath();
            var start = -Math.PI/2;
            ctx.arc(cx, cy, r, start, start + (gauge.pct/100)*Math.PI*2);
            ctx.stroke();
            ctx.fillStyle = gauge.textColor;
            ctx.font = "bold 15px sans-serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(gauge.showPct ? Math.round(gauge.pct) + "%" : "N/A", cx, cy);
        }
    }

    Text {
        text: gauge.label
        font.pixelSize: 10
        color: gauge.labelColor
        Layout.alignment: Qt.AlignHCenter
    }
}
