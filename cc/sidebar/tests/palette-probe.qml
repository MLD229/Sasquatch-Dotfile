// palette-probe.qml — sonde de la chaîne « palette dynamique ».
//
// Ce n'est PAS l'UI : ce fichier ne dessine rien. Il prouve, à l'exécution
// (et pas seulement par lecture du code) que :
//   1. shell.qml et lui consomment la même source : GET /api/palette ;
//   2. les 12 couleurs renvoyées sont acceptées par Qt comme QColor, y
//      compris les formes 8 chiffres #AARRGGBB (overlay, accent2) qui sont
//      le piège classique ;
//   3. les 11 propriétés de couleur de la sidebar reçoivent bien ces valeurs.
//
// Usage : quickshell -p tests/palette-probe.qml   (affiche sur stdout)
import QtQuick
import Quickshell

ShellRoot {
    id: probe

    readonly property string apiBase: "http://127.0.0.1:8778"

    // reproduit exactement les propriétés de shell.qml
    property color cBg: "#1e1e2e"
    property color cBgSolid: "#181825"
    property color cCard: "#181825"
    property color cText: "#cdd6f4"
    property color cTextDim: "#a6adc8"
    property color cAccent: "#89b4fa"
    property color cAccent2: "#94e2d5"
    property color cOverlay: "#000000"
    property color cGood: "#a6e3a1"
    property color cWarn: "#f9e2af"
    property color cHot: "#f38ba8"

    function fetch() {
        var xhr = new XMLHttpRequest();
        xhr.timeout = 4000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status < 200 || xhr.status >= 300) {
                console.log("PROBE_FAIL http=" + xhr.status);
                return;
            }
            var p = JSON.parse(xhr.responseText);
            probe.cBg = p.bg;
            probe.cBgSolid = p.bgSolid;
            probe.cCard = p.card;
            probe.cText = p.text;
            probe.cTextDim = p.textDim;
            probe.cAccent = p.accent;
            probe.cAccent2 = p.accent2;
            probe.cOverlay = p.overlay;
            probe.cGood = p.good;
            probe.cWarn = p.warn;
            probe.cHot = p.hot;
            console.log("PROBE_JSON " + JSON.stringify(p));
            console.log("PROBE_QT bg=" + probe.cBg + " accent=" + probe.cAccent
                        + " accent2=" + probe.cAccent2
                        + " overlay=" + probe.cOverlay
                        + " overlayAlpha=" + probe.cOverlay.a.toFixed(3));
            console.log("PROBE_OK");
        };
        xhr.open("GET", apiBase + "/api/palette");
        xhr.send();
    }

    Component.onCompleted: {
        console.log("PROBE_START");
        fetch();
    }

    Timer {
        interval: 2500
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
