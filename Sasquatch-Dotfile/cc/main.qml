// Sasquatch Control Center - main UI (single-file Quickshell QML)
// Everything (palette, helpers, all blocks) lives inline in this file by design.

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

FloatingWindow {
    id: root
    title: "Sasquatch CC"
    implicitWidth: Screen.width
    implicitHeight: Screen.height
    visible: true
    color: "transparent"

    // ---------- Palette (Catppuccin Mocha glassmorphism) ----------
    readonly property color cBg: "#1e1e2e"
    readonly property color cBgSolid: "#181825"
    readonly property color cOverlay: "#000000"
    readonly property color cText: "#cdd6f4"
    readonly property color cTextDim: "#a6adc8"
    readonly property color cAccent: "#89b4fa"
    readonly property color cAccent2: "#94e2d5"
    readonly property color cGood: "#a6e3a1"
    readonly property color cWarn: "#f9e2af"
    readonly property color cHot: "#f38ba8"

    // ---------- state ----------
    property bool serverOk: true
    property bool everShown: false
    // true while the panel is hidden for a screenshot; prevents quit() during the hide.
    property bool screenshotHide: false
    // true while a screenshot request is in flight; blocks double-click.
    property bool shotBusy: false
    property var stats: ({})
    property var music: ({playing: false, paused: false, title: null, artist: null, volume: 0, elapsed: 0, duration: 0})
    property var vizVals: []

    // ---------- API helper (XHR, inline) ----------
    function api(method, path, body, cb, timeoutMs) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = timeoutMs || 3000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    var parsed = null;
                    try { parsed = JSON.parse(xhr.responseText); } catch (e) { parsed = null; }
                    if (cb) cb(parsed);
                } else {
                    if (cb) cb(null);
                }
            }
        };
        xhr.ontimeout = function() { if (cb) cb(null); };
        xhr.onerror = function() { if (cb) cb(null); };
        try {
            xhr.open(method, "http://127.0.0.1:8765" + path);
            if (body !== null && body !== undefined) {
                xhr.setRequestHeader("Content-Type", "application/json");
                xhr.send(JSON.stringify(body));
            } else {
                xhr.send();
            }
        } catch (e) {
            if (cb) cb(null);
        }
    }

    function quit() {
        api("POST", "/api/close", null, function() {});
        Qt.quit();
    }

    // Hide the panel, take a screenshot, then restore. The panel must not
    // appear in the capture, so we unmap (visible=false) BEFORE asking the
    // server, and only restore once the capture completed (server responds
    // after grim/slurp finishes, with a long timeout for interactive area/window).
    function takeScreenshot(mode) {
        if (shotBusy) return;  // block double-click while a capture is in flight
        shotBusy = true;
        screenshotHide = true;
        visible = false;
        root.api("POST", "/api/screenshot?mode=" + mode, null, function(res) {
            shotBusy = false;
            screenshotHide = false;
            visible = true;
        }, 120000);
    }

    onVisibleChanged: {
        if (visible) everShown = true;
        // Quit only after the window was actually shown once (avoids the
        // initial invisible->visible transition killing the server at startup).
        if (everShown && !visible && !screenshotHide) quit();
    }

    Shortcut {
        sequence: "Escape"
        // Don't steal Escape while typing in the image-search field.
        enabled: !imgQuery.activeFocus
        onActivated: root.quit()
    }

    // ---------- pollers ----------
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.api("GET", "/api/stats", null, function(res) {
                if (res) { root.stats = res; root.serverOk = true; }
                else { root.serverOk = false; }
            });
        }
    }
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.api("GET", "/api/music/status", null, function(res) {
                if (res) root.music = res;
            });
        }
    }
    Timer {
        interval: 120; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.api("GET", "/api/viz", null, function(res) {
                if (res && res.vals) root.vizVals = res.vals;
            });
        }
    }
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: clockLabel.text = Qt.formatDateTime(new Date(), "hh:mm")
    }

    // ---------- veil ----------
    Rectangle {
        id: veil
        anchors.fill: parent
        color: root.cOverlay
        opacity: 0.55
        MouseArea {
            anchors.fill: parent
            onClicked: root.quit()
        }
    }

    // ---------- panel ----------
    Rectangle {
        id: panel
        width: Math.min(1000, parent.width - 40)
        height: Math.min(780, parent.height - 40)
        anchors.centerIn: parent
        radius: 22
        color: Qt.rgba(30/255, 30/255, 46/255, 0.92)
        border.width: 1
        border.color: Qt.rgba(137/255, 180/255, 250/255, 0.25)

        opacity: 0
        scale: 0.98
        Component.onCompleted: { opacity = 1; scale = 1; }
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // swallow clicks landing on empty panel space so they don't reach the veil
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14

            // ---------- HEADER ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "⚡ Sasquatch Control Center"
                    font.pixelSize: 20
                    font.bold: true
                    color: root.cText
                }
                Text {
                    text: {
                        var s = root.stats;
                        if (!root.serverOk) return "serveur injoignable…";
                        if (!s || !s.hostname) return "…";
                        var ram = s.ram ? s.ram.pct : 0;
                        var rf = s.refresh || 0;
                        return s.hostname + " · " + rf + " Hz · " + Math.round(ram) + "% RAM";
                    }
                    font.pixelSize: 12
                    color: root.serverOk ? root.cTextDim : root.cHot
                    Layout.leftMargin: 4
                }
                Item { Layout.fillWidth: true }
                Text {
                    id: clockLabel
                    text: "--:--"
                    font.pixelSize: 18
                    font.bold: true
                    color: root.cText
                }
                Rectangle {
                    width: 30; height: 30; radius: 15
                    color: closeMa.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "✕"; color: root.cText; font.pixelSize: 14 }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.quit()
                    }
                }
            }

            // ---------- RANGÉE 1: PERFORMANCE ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                radius: 16
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.06)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    Text { text: "PERFORMANCE"; font.pixelSize: 11; font.bold: true; color: root.cTextDim }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 18

                        ColumnLayout {
                            spacing: 4
                            Layout.alignment: Qt.AlignHCenter
                            Canvas {
                                id: cpuGauge
                                width: 90; height: 90
                                property real pct: root.stats && root.stats.cpu ? root.stats.cpu : 0
                                onPctChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    var cx = width/2, cy = height/2, r = width/2 - 8;
                                    ctx.lineWidth = 8;
                                    ctx.strokeStyle = Qt.rgba(1,1,1,0.1);
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI*2); ctx.stroke();
                                    ctx.strokeStyle = root.cAccent;
                                    ctx.beginPath();
                                    var start = -Math.PI/2;
                                    ctx.arc(cx, cy, r, start, start + (pct/100)*Math.PI*2);
                                    ctx.stroke();
                                    ctx.fillStyle = root.cText;
                                    ctx.font = "bold 15px sans-serif";
                                    ctx.textAlign = "center";
                                    ctx.textBaseline = "middle";
                                    ctx.fillText(Math.round(pct) + "%", cx, cy);
                                }
                            }
                            Text { text: "CPU"; font.pixelSize: 10; color: root.cTextDim; Layout.alignment: Qt.AlignHCenter }
                        }

                        ColumnLayout {
                            spacing: 4
                            Layout.alignment: Qt.AlignHCenter
                            Canvas {
                                id: ramGauge
                                width: 90; height: 90
                                property real pct: root.stats && root.stats.ram ? root.stats.ram.pct : 0
                                onPctChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    var cx = width/2, cy = height/2, r = width/2 - 8;
                                    ctx.lineWidth = 8;
                                    ctx.strokeStyle = Qt.rgba(1,1,1,0.1);
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI*2); ctx.stroke();
                                    ctx.strokeStyle = root.cAccent2;
                                    ctx.beginPath();
                                    var start = -Math.PI/2;
                                    ctx.arc(cx, cy, r, start, start + (pct/100)*Math.PI*2);
                                    ctx.stroke();
                                    ctx.fillStyle = root.cText;
                                    ctx.font = "bold 15px sans-serif";
                                    ctx.textAlign = "center";
                                    ctx.textBaseline = "middle";
                                    ctx.fillText(Math.round(pct) + "%", cx, cy);
                                }
                            }
                            Text { text: "RAM"; font.pixelSize: 10; color: root.cTextDim; Layout.alignment: Qt.AlignHCenter }
                        }

                        ColumnLayout {
                            spacing: 4
                            Layout.alignment: Qt.AlignHCenter
                            Canvas {
                                id: gpuGauge
                                width: 90; height: 90
                                property real pct: root.stats && root.stats.gpu ? root.stats.gpu.util : 0
                                onPctChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    var cx = width/2, cy = height/2, r = width/2 - 8;
                                    ctx.lineWidth = 8;
                                    ctx.strokeStyle = Qt.rgba(1,1,1,0.1);
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI*2); ctx.stroke();
                                    ctx.strokeStyle = root.cWarn;
                                    ctx.beginPath();
                                    var start = -Math.PI/2;
                                    ctx.arc(cx, cy, r, start, start + (pct/100)*Math.PI*2);
                                    ctx.stroke();
                                    ctx.fillStyle = root.cText;
                                    ctx.font = "bold 15px sans-serif";
                                    ctx.textAlign = "center";
                                    ctx.textBaseline = "middle";
                                    ctx.fillText((root.stats && root.stats.gpu) ? Math.round(pct) + "%" : "N/A", cx, cy);
                                }
                            }
                            Text { text: "GPU"; font.pixelSize: 10; color: root.cTextDim; Layout.alignment: Qt.AlignHCenter }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6

                            Repeater {
                                model: [
                                    {label: "VRAM", key: "vram", color: root.cAccent2},
                                    {label: "Temp CPU", key: "cpu_temp", color: root.cHot},
                                    {label: "Temp GPU", key: "gpu_temp", color: root.cWarn},
                                    {label: "Réseau", key: "down", color: root.cAccent}
                                ]
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        text: modelData.label
                                        font.pixelSize: 10
                                        color: root.cTextDim
                                        Layout.preferredWidth: 70
                                    }
                                    Canvas {
                                        id: spark
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        property var hist: (root.stats && root.stats.history && root.stats.history[modelData.key]) ? root.stats.history[modelData.key] : []
                                        onHistChanged: requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.reset();
                                            var h = hist;
                                            if (!h || h.length < 2) return;
                                            var maxV = Math.max.apply(null, h.concat([1]));
                                            ctx.strokeStyle = modelData.color;
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
                                }
                            }
                        }
                    }
                }
            }

            // ---------- RANGÉE 2: MUSIQUE ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                radius: 16
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.06)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 14

                    Rectangle {
                        width: 90; height: 90
                        radius: 12
                        color: Qt.rgba(1,1,1,0.08)
                        clip: true
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            // Stable cache-buster keyed on the track itself, NOT
                            // Date.now(): music is re-polled every second, so a
                            // time-based URL would re-download the full artwork
                            // once per second.
                            source: (root.music && root.music.title) ? "http://127.0.0.1:8765/albumart?t=" + (root.music.file || root.music.title) : ""
                            cache: false
                            asynchronous: true
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "🎵"
                            font.pixelSize: 28
                            visible: !root.music || !root.music.title
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6

                        Text {
                            text: (root.music && root.music.title) ? root.music.title : "Aucune musique en cours"
                            font.pixelSize: 14
                            font.bold: true
                            color: root.cText
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: (root.music && root.music.artist) ? root.music.artist : ""
                            font.pixelSize: 11
                            color: root.cTextDim
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            id: timeline
                            Layout.fillWidth: true
                            height: 8
                            radius: 4
                            color: Qt.rgba(1,1,1,0.1)
                            Rectangle {
                                radius: 4
                                color: root.cAccent
                                height: parent.height
                                width: {
                                    var d = (root.music && root.music.duration) ? root.music.duration : 0;
                                    var e = (root.music && root.music.elapsed) ? root.music.elapsed : 0;
                                    return d > 0 ? parent.width * Math.min(1, e / d) : 0;
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: function(mouse) {
                                    var d = (root.music && root.music.duration) ? root.music.duration : 0;
                                    if (d <= 0) return;
                                    var pos = Math.round((mouse.x / width) * d);
                                    root.api("POST", "/api/music/seek", {pos: pos}, function() {});
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: prevMa.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text { anchors.centerIn: parent; text: "⏮"; color: root.cText }
                                MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.api("POST", "/api/music/prev", null, function() {}) }
                            }
                            Rectangle {
                                width: 36; height: 36; radius: 18
                                color: playMa.containsMouse ? Qt.rgba(1,1,1,0.16) : Qt.rgba(1,1,1,0.09)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: (root.music && root.music.playing) ? "⏸" : "▶"
                                    color: root.cText
                                }
                                MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.api("POST", "/api/music/toggle", null, function() {}) }
                            }
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: nextMa.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text { anchors.centerIn: parent; text: "⏭"; color: root.cText }
                                MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.api("POST", "/api/music/next", null, function() {}) }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 100
                                height: 8
                                radius: 4
                                color: Qt.rgba(1,1,1,0.1)
                                Rectangle {
                                    radius: 4
                                    color: root.cAccent2
                                    height: parent.height
                                    width: parent.width * ((root.music && root.music.volume) ? root.music.volume/100 : 0)
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: function(mouse) {
                                        var ratio = Math.max(0, Math.min(1, mouse.x / width));
                                        root.api("POST", "/api/music/volume", {v: Math.round(ratio*100)}, function() {});
                                    }
                                }
                            }

                            RowLayout {
                                spacing: 2
                                Layout.preferredWidth: 100
                                Repeater {
                                    model: 20
                                    delegate: Rectangle {
                                        width: 3
                                        height: {
                                            var v = (root.vizVals && root.vizVals.length > index) ? root.vizVals[index] : 0;
                                            return Math.max(2, v * 30);
                                        }
                                        radius: 1
                                        color: root.cAccent
                                        Behavior on height { NumberAnimation { duration: 80 } }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- RANGÉE 3: 3 tuiles ----------
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                spacing: 14

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: Qt.rgba(1,1,1,0.06)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        Text { text: "📷 CAPTURE"; font.pixelSize: 11; font.bold: true; color: root.cTextDim }
                        RowLayout {
                            spacing: 8
                            Layout.fillWidth: true
                            Repeater {
                                model: [
                                    {label: "Zone", mode: "area"},
                                    {label: "Plein écran", mode: "full"},
                                    {label: "Fenêtre", mode: "window"}
                                ]
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: 30
                                    radius: 8
                                    color: shotMa.containsMouse ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.07)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Text { anchors.centerIn: parent; text: modelData.label; font.pixelSize: 10; color: root.cText }
                                    MouseArea {
                                        id: shotMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.takeScreenshot(modelData.mode)
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: Qt.rgba(1,1,1,0.06)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        Text { text: "🎤 RECONNAÎTRE"; font.pixelSize: 11; font.bold: true; color: root.cTextDim }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 28
                            radius: 8
                            color: findMa.containsMouse ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.07)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: findLabel.busy ? "Écoute…" : "Identifier"
                                font.pixelSize: 11
                                color: root.cText
                            }
                            MouseArea {
                                id: findMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (findLabel.busy) return;  // block re-click while recording
                                    findLabel.busy = true;
                                    findLabel.resultText = "";
                                    // Finder takes >=6s (arecord) + up to 15s (songrec):
                                    // the default 3s XHR timeout would kill it — use 25s.
                                    root.api("POST", "/api/music/finder", null, function(res) {
                                        findLabel.busy = false;
                                        if (res && res.recognized) {
                                            findLabel.resultText = res.title + (res.artist ? " — " + res.artist : "");
                                        } else {
                                            findLabel.resultText = (res && res.error) ? res.error : "non reconnu";
                                        }
                                    }, 25000);
                                }
                            }
                        }
                        Text {
                            id: findLabel
                            property bool busy: false
                            property string resultText: ""
                            text: resultText
                            font.pixelSize: 10
                            color: root.cTextDim
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: Qt.rgba(1,1,1,0.06)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        Text { text: "🌐 RECHERCHE IMAGE"; font.pixelSize: 11; font.bold: true; color: root.cTextDim }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            TextField {
                                id: imgQuery
                                Layout.fillWidth: true
                                placeholderText: "mot-clé…"
                                color: root.cText
                                font.pixelSize: 11
                                background: Rectangle { radius: 8; color: Qt.rgba(1,1,1,0.08) }
                                // Enter triggers the search (mirrors the 🔍 button)
                                Keys.onReturnPressed: root.api("POST", "/api/imgsearch", {q: imgQuery.text}, function() {})
                            }
                            Rectangle {
                                width: 30; height: 26; radius: 8
                                color: imgMa.containsMouse ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.07)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text { anchors.centerIn: parent; text: "🔍"; font.pixelSize: 12; color: root.cText }
                                MouseArea {
                                    id: imgMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.api("POST", "/api/imgsearch", {q: imgQuery.text}, function() {})
                                }
                            }
                        }
                    }
                }
            }

            // ---------- RANGÉE 4: TRADUCTION ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                radius: 16
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.06)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    Text { text: "🖼️ TRADUCTION"; font.pixelSize: 11; font.bold: true; color: root.cTextDim }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 200; height: 32; radius: 8
                        color: transMa.containsMouse ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.07)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { anchors.centerIn: parent; text: "Traduire depuis l'écran"; font.pixelSize: 11; color: root.cText }
                        MouseArea {
                            id: transMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.api("POST", "/api/translate", null, function() {})
                        }
                    }
                }
            }

            // ---------- FOOTER ----------
            RowLayout {
                Layout.fillWidth: true
                Text { text: root.serverOk ? "Serveur prêt ✓" : "Serveur injoignable ✗"; font.pixelSize: 10; color: root.serverOk ? root.cGood : root.cHot }
                Item { Layout.fillWidth: true }
                Text { text: "Échap / ✕ / clic dehors pour fermer"; font.pixelSize: 10; color: root.cTextDim }
            }
        }
    }
}
