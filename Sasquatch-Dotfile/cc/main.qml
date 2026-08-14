// Sasquatch Control Center - main UI
// Point d'entrée : fenêtre, palette, état, API, voile et panneau.
// Les composants visuels réutilisables vivent dans qml/ (Gauge, IconButton,
// Tile, Sparkline) — le backend HTTP est server.py (modules Python dans cc/).
//
// NOTE thème dynamique : la palette est pollée via /api/palette (relue depuis
// qml/Palette.qml, régénéré par theme-apply.py à chaque changement de
// wallpaper) — le CC suit donc le thème au lieu de rester figé.

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "qml"

FloatingWindow {
    id: root
    title: "Sasquatch CC"
    implicitWidth: Screen.width
    implicitHeight: Screen.height
    visible: true
    color: "transparent"

    // ---------- Palette (dynamique : /api/palette ← qml/Palette.qml) ----------
    // Valeurs de secours Catppuccin Mocha tant que /api/palette n'a pas répondu.
    property color cBg: "#1e1e2e"
    property color cBgSolid: "#181825"
    property color cCard: "#181825"
    property color cCardSolid: "#181825"
    property color cOverlay: "#000000"
    property color cText: "#cdd6f4"
    property color cTextDim: "#a6adc8"
    property color cAccent: "#89b4fa"
    property color cAccent2: "#94e2d5"
    property color cGood: "#a6e3a1"
    property color cWarn: "#f9e2af"
    property color cHot: "#f38ba8"

    // ---------- state ----------
    property bool serverOk: true
    property bool everShown: false
    // true while the panel is hidden for a screenshot / OCR selection;
    // prevents quit() during the hide.
    property bool suppressQuit: false
    // true while a screenshot request is in flight; blocks double-click.
    property bool shotBusy: false
    property var stats: ({})
    property var music: ({playing: false, paused: false, title: null, artist: null, volume: 0, elapsed: 0, duration: 0})
    property var sysVol: ({volume: 0, muted: false})
    property var sysBright: ({brightness: 0})
    property var vizVals: []
    // Sidebar volume/luminosité (colonne à côté du panel)
    property int sidebarW: 110
    property int ccH: Math.min(780, root.height - 40)

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
        suppressQuit = true;
        visible = false;
        root.api("POST", "/api/screenshot?mode=" + mode, null, function(res) {
            shotBusy = false;
            suppressQuit = false;
            visible = true;
        }, 120000);
    }

    onVisibleChanged: {
        if (visible) everShown = true;
        // Quit only after the window was actually shown once (avoids the
        // initial invisible->visible transition killing the server at startup).
        if (everShown && !visible && !suppressQuit) quit();
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
    // Palette dynamique : suit theme-apply (relue toutes les 2 s). Le CC se
    // retinte en direct quand momo change de wallpaper.
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.api("GET", "/api/palette", null, function(p) {
                if (!p) return;
                root.cBg = p.bg;
                root.cBgSolid = p.bgSolid;
                root.cCard = p.card;
                root.cCardSolid = p.cardSolid;
                root.cText = p.text;
                root.cTextDim = p.textDim;
                root.cAccent = p.accent;
                root.cAccent2 = p.accent2;
                root.cOverlay = p.overlay;
                root.cGood = p.good;
                root.cWarn = p.warn;
                root.cHot = p.hot;
            });
        }
    }
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.api("GET", "/api/music/status", null, function(res) {
                if (res) root.music = res;
            });
            // Volume système (wpctl) : la barre reflète le vrai volume audible,
            // pas le volume MPD (indépendant, souvent figé à 0).
            root.api("GET", "/api/system/volume", null, function(res) {
                if (res) root.sysVol = res;
            });
            // Luminosité (brightnessctl) : sidebar du CC.
            root.api("GET", "/api/system/brightness", null, function(res) {
                if (res) root.sysBright = res;
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

    // ---------- veil (léger : le verre doit laisser voir le desktop flouté) ----------
    Rectangle {
        id: veil
        anchors.fill: parent
        color: root.cOverlay
        opacity: 0.3
        MouseArea {
            anchors.fill: parent
            onClicked: root.quit()
        }
    }

    // ---------- CC : panel + sidebar (volume/luminosité) ----------
    RowLayout {
        id: ccRow
        anchors.centerIn: parent
        spacing: 14

        // ---------- panel (verre dépoli : translucide + blur Hyprland derrière) ----------
        Rectangle {
            id: panel
            Layout.preferredWidth: Math.min(1000, root.width - 40 - root.sidebarW - 14)
            Layout.preferredHeight: root.ccH
            radius: 22
            color: Qt.rgba(root.cCard.r, root.cCard.g, root.cCard.b, 0.42)
            border.width: 1
            border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.4)

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
                IconButton {
                    width: 30; height: 30
                    glyph: "✕"
                    fontSize: 14
                    glyphColor: root.cText
                    onClicked: root.quit()
                }
            }

            // ---------- RANGÉE 1: PERFORMANCE ----------
            Tile {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                Layout.minimumHeight: 150
                Layout.fillHeight: true
                title: "PERFORMANCE"
                contentMargins: 14

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 18

                    Gauge {
                        pct: root.stats && root.stats.cpu ? root.stats.cpu : 0
                        strokeColor: root.cAccent
                        label: "CPU"
                    }
                    Gauge {
                        pct: root.stats && root.stats.ram ? root.stats.ram.pct : 0
                        strokeColor: root.cAccent2
                        label: "RAM"
                    }
                    Gauge {
                        pct: root.stats && root.stats.gpu ? root.stats.gpu.util : 0
                        strokeColor: root.cWarn
                        label: "GPU"
                        showPct: !!(root.stats && root.stats.gpu)
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
                                Sparkline {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 24
                                    hist: (root.stats && root.stats.history && root.stats.history[modelData.key]) ? root.stats.history[modelData.key] : []
                                    lineColor: modelData.color
                                }
                            }
                        }
                    }
                }
            }

            // ---------- RANGÉE 2: MUSIQUE ----------
            Tile {
                Layout.fillWidth: true
                Layout.preferredHeight: 165
                Layout.minimumHeight: 130
                Layout.fillHeight: true
                contentMargins: 14

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                            // once per second. `art` est fourni par le serveur :
                            // MPRIS (thumbnail navigateur/YouTube) ou MPD.
                            source: (root.music && root.music.art) ? "http://127.0.0.1:8765" + root.music.art : ""
                            cache: false
                            asynchronous: true
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "🎵"
                            font.pixelSize: 28
                            visible: !root.music || !root.music.art
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
                        Text {
                            text: (root.music && root.music.album) ? root.music.album : ""
                            font.pixelSize: 10
                            color: root.cTextDim
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        // Badge source : montre d'où vient la musique (navigateur
                        // YouTube, MPD…).
                        Text {
                            text: (root.music && root.music.source === "mpris") ? ("via " + ((root.music.player) ? root.music.player : "navigateur")) : ""
                            font.pixelSize: 10
                            font.bold: true
                            color: root.cAccent
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

                            IconButton {
                                width: 32; height: 32
                                glyph: "⏮"
                                glyphColor: root.cText
                                onClicked: root.api("POST", "/api/music/prev", null, function() {})
                            }
                            IconButton {
                                width: 36; height: 36
                                glyph: (root.music && root.music.playing) ? "⏸" : "▶"
                                baseColor: Qt.rgba(1,1,1,0.09)
                                hoverColor: Qt.rgba(1,1,1,0.16)
                                glyphColor: root.cText
                                onClicked: root.api("POST", "/api/music/toggle", null, function() {})
                            }
                            IconButton {
                                width: 32; height: 32
                                glyph: "⏹"
                                glyphColor: root.cText
                                onClicked: root.api("POST", "/api/music/stop", null, function() {})
                            }
                            IconButton {
                                width: 32; height: 32
                                glyph: "⏭"
                                glyphColor: root.cText
                                onClicked: root.api("POST", "/api/music/next", null, function() {})
                            }

                            IconButton {
                                width: 26; height: 26
                                glyph: (root.sysVol && root.sysVol.muted) ? "🔇" : "🔊"
                                fontSize: 11
                                glyphColor: root.cText
                                onClicked: root.api("POST", "/api/system/volume", {mute: !(root.sysVol && root.sysVol.muted)}, function() {})
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 90
                                height: 8
                                radius: 4
                                color: Qt.rgba(1,1,1,0.1)
                                Rectangle {
                                    radius: 4
                                    color: root.cAccent2
                                    height: parent.height
                                    width: parent.width * ((root.sysVol && root.sysVol.volume) ? root.sysVol.volume/100 : 0)
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: function(mouse) {
                                        var ratio = Math.max(0, Math.min(1, mouse.x / width));
                                        root.api("POST", "/api/system/volume", {v: Math.round(ratio*100)}, function() {});
                                    }
                                }
                            }

                            RowLayout {
                                spacing: 2
                                Layout.preferredWidth: 100
                                Layout.preferredHeight: 30
                                Layout.minimumHeight: 30
                                Layout.maximumHeight: 30
                                // Collé en bas de la rangée : les barres
                                // poussent vers le haut comme un égaliseur.
                                Layout.alignment: Qt.AlignBottom
                                Repeater {
                                    model: 20
                                    delegate: Rectangle {
                                        Layout.preferredWidth: 3
                                        Layout.preferredHeight: {
                                            var v = (root.vizVals && root.vizVals.length > index) ? root.vizVals[index] : 0;
                                            return Math.max(2, v * 30);
                                        }
                                        radius: 1
                                        color: root.cAccent
                                        Layout.alignment: Qt.AlignBottom
                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 80 } }
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
                Layout.minimumHeight: 85
                Layout.fillHeight: true
                spacing: 14

                Tile {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: "📷 CAPTURE"
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

                Tile {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: "🎤 RECONNAÎTRE"
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
                                // Finder : ~8s (enregistrement) + retry 15s si échec + songrec :
                                // le timeout XHR par défaut (3s) le tuerait — 60s couvre le pire cas.
                                root.api("POST", "/api/music/finder", null, function(res) {
                                    findLabel.busy = false;
                                    if (res && res.recognized) {
                                        findLabel.resultText = res.title + (res.artist ? " — " + res.artist : "");
                                    } else {
                                        findLabel.resultText = (res && res.error) ? res.error : "non reconnu";
                                    }
                                }, 60000);
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

                Tile {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: "🌐 RECHERCHE IMAGE"
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

            // ---------- RANGÉE 4: TRADUCTION ----------
            Tile {
                Layout.fillWidth: true
                Layout.preferredHeight: 170
                Layout.minimumHeight: 120
                Layout.fillHeight: true
                title: "🖼️ TRADUCTION"
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        height: 32
                        radius: 8
                        color: transMa.containsMouse ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.07)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: transOrig.busy ? "OCR + traduction…" : "Traduire depuis l'écran"
                            font.pixelSize: 12
                            color: root.cText
                        }
                        MouseArea {
                            id: transMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (transOrig.busy) return;
                                transOrig.busy = true;
                                transOrig.detected = "";
                                transOrig.translation = "";
                                // Masque le CC pendant la sélection OCR (même
                                // mécanisme que le screenshot) : le serveur ne
                                // répond qu'une fois texte + traduction prêts
                                // (max 120 s), puis le panneau remonte.
                                root.suppressQuit = true;
                                root.visible = false;
                                root.api("POST", "/api/translate", null, function(res) {
                                    transOrig.busy = false;
                                    root.suppressQuit = false;
                                    root.visible = true;
                                    if (res && res.ok && res.translation) {
                                        transOrig.detected = res.text || "";
                                        transOrig.translation = res.translation;
                                    } else {
                                        transOrig.detected = "";
                                        transOrig.translation = (res && res.error) ? "⚠ " + res.error : "⚠ échec";
                                    }
                                }, 120000);
                            }
                        }
                    }

                    // Texte détecté (original OCR)
                    Text {
                        id: transOrig
                        property bool busy: false
                        property string detected: ""
                        property string translation: ""
                        visible: detected !== ""
                        text: "Détecté : " + detected
                        font.pixelSize: 12
                        color: root.cTextDim
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    // Traduction : zone COULISSABLE (scroll) + texte plus grand
                    // — les longues traductions se font défiler au lieu de
                    // déborder/être coupées.
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        TextArea {
                            id: transResult
                            text: transOrig.translation
                            readOnly: true
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            font.pixelSize: 14
                            color: root.cText
                            selectByMouse: true
                            background: Rectangle {
                                color: Qt.rgba(1,1,1,0.05)
                                radius: 8
                            }
                            padding: 8
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

        // ---------- SIDEBAR : volume + luminosité (barres épaisses arrondies) ----------
        Rectangle {
            id: sidebar
            Layout.preferredWidth: root.sidebarW
            Layout.preferredHeight: root.ccH
            radius: 22
            color: Qt.rgba(root.cCard.r, root.cCard.g, root.cCard.b, 0.42)
            border.width: 1
            border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.4)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                // ── Volume ──
                Text {
                    text: "🔊"
                    font.pixelSize: 14
                    color: root.cText
                    Layout.alignment: Qt.AlignHCenter
                }
                // Barre épaisse verticale, arrondie, remplie depuis le bas.
                Rectangle {
                    id: volBar
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 60
                    radius: 12
                    color: Qt.rgba(1,1,1,0.10)
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 3
                        radius: 10
                        height: parent.height * ((root.sysVol && root.sysVol.volume) ? root.sysVol.volume/100 : 0)
                        color: root.cAccent
                        Behavior on height { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: volBar.setFromY(mouse.y)
                        onPositionChanged: if (pressed) volBar.setFromY(mouse.y)
                    }
                    function setFromY(y) {
                        var ratio = 1 - Math.max(0, Math.min(1, y / height));
                        root.api("POST", "/api/system/volume", {v: Math.round(ratio*100)}, function() {});
                    }
                }
                Text {
                    text: (root.sysVol && root.sysVol.volume ? Math.round(root.sysVol.volume) : 0) + "%"
                    font.pixelSize: 11
                    color: root.cTextDim
                    Layout.alignment: Qt.AlignHCenter
                }

                Item { Layout.preferredHeight: 6 }  // espace entre les deux

                // ── Luminosité ──
                Text {
                    text: "☀"
                    font.pixelSize: 14
                    color: root.cText
                    Layout.alignment: Qt.AlignHCenter
                }
                Rectangle {
                    id: brightBar
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 60
                    radius: 12
                    color: Qt.rgba(1,1,1,0.10)
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 3
                        radius: 10
                        height: parent.height * ((root.sysBright && root.sysBright.brightness) ? root.sysBright.brightness/100 : 0)
                        color: root.cWarn
                        Behavior on height { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: brightBar.setFromY(mouse.y)
                        onPositionChanged: if (pressed) brightBar.setFromY(mouse.y)
                    }
                    function setFromY(y) {
                        var ratio = 1 - Math.max(0, Math.min(1, y / height));
                        root.api("POST", "/api/system/brightness", {v: Math.round(ratio*100)}, function() {});
                    }
                }
                Text {
                    text: (root.sysBright && root.sysBright.brightness ? Math.round(root.sysBright.brightness) : 0) + "%"
                    font.pixelSize: 11
                    color: root.cTextDim
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
