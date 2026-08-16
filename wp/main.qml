// Sasquatch Wallpaper Picker — sélecteur de fonds d'écran (Quickshell, Super+Y)
//
// Remplace waypaper comme outil de changement de wallpaper. Backend = serveur
// CC (127.0.0.1:8765) : liste, miniatures, choix de dossier (zenity côté
// serveur), application → waypaper --restore → theme-apply.sh → toute la
// palette du dotfile suit (waybar, kitty, fastfetch, CC, overlays japonais).
//
// Le « souvenir » du dossier = la config waypaper (clé folder=) : le sélecteur
// retombe dessus au lancement ; sur un fresh install où le dossier n'existe
// pas, l'UI affiche un bandeau et invite à parcourir (Dossier…).
//
// Style : même structure que le CC (veil + panneau glassmorphism centré avec
// dimensions explicites — jamais de ColumnLayout en fill direct dans la
// FloatingWindow), palette dynamique pollée via /api/palette, crossfade entre
// images, molette, filmstrip de miniatures (cache serveur).

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "qml"

FloatingWindow {
    id: root
    title: "Sasquatch Wallpaper"
    implicitWidth: Screen.width
    implicitHeight: Screen.height
    visible: true
    color: "transparent"

    // Palette (fallback Catppuccin Mocha, pollée /api/palette toutes les 2 s)
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

    // État du sélecteur
    property var wp: ({folder: "", folderExists: false, current: "", files: []})
    property int idx: 0
    property bool applyBusy: false
    property bool everShown: false
    property string curPath: ""
    property string oldPath: ""
    property string curName: ""

    // ---------- API helper (XHR, comme le CC) ----------
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

    // ---------- données ----------
    function loadWallpapers() {
        root.api("GET", "/api/wallpapers", null, function(res) {
            if (!res) return;
            root.wp = res;
            root.idx = 0;
            for (var i = 0; i < res.files.length; i++) {
                if (res.files[i].path === res.current) { root.idx = i; break; }
            }
            if (res.files.length > 0 && res.files[root.idx]) {
                root.curPath = res.files[root.idx].path;
                root.curName = res.files[root.idx].name;
            } else {
                root.curPath = "";
                root.curName = "";
            }
        });
    }

    function goTo(n) {
        var files = root.wp.files;
        if (!files || files.length === 0) return;
        if (n < 0) n = files.length - 1;
        if (n >= files.length) n = 0;
        if (n === root.idx) return;
        root.oldPath = root.curPath;
        root.idx = n;
        root.curPath = files[n].path;
        root.curName = files[n].name;
        fadeTimer.start();
    }

    // ---------- actions ----------
    function pickFolder() {
        root.api("POST", "/api/wallpaper/pick", {kind: "folder"}, function(res) {
            if (!res || !res.ok) return;
            root.api("POST", "/api/wallpaper/folder", {folder: res.path}, function(r2) {
                if (r2 && r2.ok) root.loadWallpapers();
            }, 5000);
        }, 200000);
    }

    function pickFile() {
        root.api("POST", "/api/wallpaper/pick", {kind: "file"}, function(res) {
            if (!res || !res.ok) return;
            root.api("POST", "/api/wallpaper/apply", {file: res.path}, function(r2) {
                if (r2 && r2.ok) root.loadWallpapers();
            }, 30000);
        }, 200000);
    }

    function applyCurrent() {
        var files = root.wp.files;
        if (root.applyBusy || !files || files.length === 0) return;
        root.applyBusy = true;
        root.api("POST", "/api/wallpaper/apply", {file: files[root.idx].path}, function(res) {
            root.applyBusy = false;
            if (res && res.ok) root.loadWallpapers();
        }, 30000);
    }

    function randomPick() {
        // 🎲 : le serveur pioche dans le dossier courant → preview (crossfade),
        // l'utilisateur valide avec Appliquer (cohérent avec le reste du picker).
        root.api("GET", "/api/wallpaper/random", null, function(res) {
            if (!res || !res.ok) return;
            var files = root.wp.files;
            if (!files) return;
            for (var i = 0; i < files.length; i++) {
                if (files[i].path === res.path) { root.goTo(i); return; }
            }
            root.loadWallpapers();
        });
    }

    // ---------- cycle de vie ----------
    onCurPathChanged: {
        imgOld.opacity = 1.0;
        fadeTimer.start();
    }
    Timer { id: fadeTimer; interval: 40; repeat: false; onTriggered: imgOld.opacity = 0.0 }

    onVisibleChanged: {
        if (visible) everShown = true;
        if (everShown && !visible) Qt.quit();
    }
    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
    Shortcut { sequence: "Left";  onActivated: root.goTo(root.idx - 1) }
    Shortcut { sequence: "Right"; onActivated: root.goTo(root.idx + 1) }

    // ---------- pollers ----------
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.api("GET", "/api/palette", null, function(p) {
            if (!p) return;
            root.cBg = p.bg; root.cBgSolid = p.bgSolid; root.cCard = p.card;
            root.cCardSolid = p.cardSolid; root.cText = p.text; root.cTextDim = p.textDim;
            root.cAccent = p.accent; root.cAccent2 = p.accent2; root.cOverlay = p.overlay;
            root.cGood = p.good; root.cWarn = p.warn; root.cHot = p.hot;
        });
    }

    Component.onCompleted: root.loadWallpapers()

    // ── UI (structure CC : veil + panel centré à dimensions explicites) ──
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.cBg.r, root.cBg.g, root.cBg.b, 0.74)
        // clic sur la voile = fermer (comme le CC)
        MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: 0

        Rectangle {
            id: panel
            Layout.preferredWidth: Math.min(1500, root.width - 90)
            Layout.preferredHeight: Math.min(920, root.height - 90)
            radius: 22
            color: Qt.rgba(root.cCard.r, root.cCard.g, root.cCard.b, 0.94)
            border.width: 1
            border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.35)

            opacity: 0
            scale: 0.98
            Component.onCompleted: { opacity = 1; scale = 1; }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            // clics sur le panneau (hors boutons) : ne pas fermer
            MouseArea { anchors.fill: parent; onClicked: {} }

            // Molette N'IMPORTE OÙ sur le panneau = changer de wallpaper
            // (les WheelHandler plus profonds — preview, filmstrip — gagnent).
            WheelHandler {
                onWheel: (event) => {
                    if (event.angleDelta.y !== 0)
                        root.goTo(root.idx - (event.angleDelta.y > 0 ? 1 : -1));
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 26
                spacing: 14

                // ── En-tête : titre + dossier + actions ──
                RowLayout { spacing: 12; Layout.fillWidth: true; Layout.preferredHeight: 42
                    Text { text: "壁紙"; font.pixelSize: 27; font.weight: Font.Bold; color: root.cAccent }
                    Rectangle { width: 1; height: 30; color: Qt.rgba(root.cTextDim.r, root.cTextDim.g, root.cTextDim.b, 0.35) }
                    ColumnLayout { spacing: 0
                        Text { text: "Sélecteur de fonds d'écran"; font.pixelSize: 15; font.weight: Font.DemiBold; color: root.cText }
                        Text {
                            text: root.wp.folder || "aucun dossier"
                            font.pixelSize: 12; color: root.cTextDim
                            elide: Text.ElideMiddle; Layout.maximumWidth: 480
                        }
                    }
                    Item { Layout.fillWidth: true }
                    WpButton { label: "Dossier…"; fg: root.cText; bg: root.cCardSolid; onClicked: root.pickFolder() }
                    WpButton { label: "Fichier…"; fg: root.cText; bg: root.cCardSolid; onClicked: root.pickFile() }
                    WpButton { label: "✕"; fg: root.cHot; bg: root.cCardSolid; onClicked: Qt.quit() }
                }

                // ── Preview : image + crossfade + molette ──
                Item {
                    id: previewArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 200
                    clip: true

                    Image {
                        id: imgOld
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        source: root.oldPath ? "file://" + root.oldPath : ""
                        opacity: 0
                        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                    Image {
                        id: imgNew
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        source: root.curPath ? "file://" + root.curPath : ""
                        smooth: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.wp.folderExists && root.wp.files.length === 0
                        text: "⚠ Dossier introuvable — clique « Dossier… » pour en choisir un"
                        color: root.cWarn; font.pixelSize: 17
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: root.wp.folderExists && root.wp.files.length === 0
                        text: "Aucune image dans ce dossier"
                        color: root.cTextDim; font.pixelSize: 17
                    }

                    // Molette = défilement stylé
                    WheelHandler {
                        onWheel: (event) => {
                            if (event.angleDelta.y !== 0)
                                root.goTo(root.idx - (event.angleDelta.y > 0 ? 1 : -1));
                        }
                    }
                }

                // ── Filmstrip : miniatures du dossier (cache serveur) ──
                ListView {
                    id: strip
                    Layout.fillWidth: true
                    Layout.preferredHeight: 66
                    orientation: ListView.Horizontal
                    spacing: 7
                    clip: true
                    model: root.wp.files

                    // Molette sur la liste = la faire défiler horizontalement
                    // (le drag natif marche aussi) — PAS changer de wallpaper.
                    WheelHandler {
                        onWheel: (event) => {
                            if (event.angleDelta.y !== 0)
                                strip.contentX -= event.angleDelta.y > 0 ? 70 : -70;
                        }
                    }
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: 104; height: 66
                        Rectangle {
                            anchors.fill: parent
                            radius: 9
                            color: root.idx === index ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.16)
                                                      : Qt.rgba(root.cCardSolid.r, root.cCardSolid.g, root.cCardSolid.b, 0.9)
                            border.width: root.idx === index ? 2 : 1
                            border.color: root.idx === index ? root.cAccent
                                                              : Qt.rgba(root.cTextDim.r, root.cTextDim.g, root.cTextDim.b, 0.2)
                            Image {
                                anchors.fill: parent
                                anchors.margins: 3
                                fillMode: Image.PreserveAspectCrop
                                source: "http://127.0.0.1:8765/api/wallpaper/thumb?file=" + encodeURIComponent(modelData.path)
                                sourceSize: Qt.size(200, 120)
                                smooth: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.goTo(index)
                            }
                        }
                    }
                }

                // ── Pied : navigation + compteur + nom + appliquer ──
                RowLayout { spacing: 14; Layout.fillWidth: true; Layout.preferredHeight: 42
                    WpButton { label: "‹"; fg: root.cText; bg: root.cCardSolid; onClicked: root.goTo(root.idx - 1) }
                    WpButton { label: "›"; fg: root.cText; bg: root.cCardSolid; onClicked: root.goTo(root.idx + 1) }
                    WpButton { label: "🎲 Aléatoire"; fg: root.cText; bg: root.cCardSolid; onClicked: root.randomPick() }
                    ColumnLayout { spacing: 0
                        Text {
                            text: root.wp.files.length > 0 ? (root.idx + 1) + " / " + root.wp.files.length : "—"
                            font.pixelSize: 13; color: root.cAccent; font.weight: Font.DemiBold
                        }
                        Text {
                            text: root.curName || "—"
                            font.pixelSize: 12; color: root.cTextDim
                            elide: Text.ElideMiddle; Layout.maximumWidth: 420
                        }
                    }
                    Item { Layout.fillWidth: true }
                    WpButton {
                        label: root.applyBusy ? "Application…" : "Appliquer"
                        accent: true
                        accentColor: root.cAccent
                        disabled: root.applyBusy || root.wp.files.length === 0
                        onClicked: root.applyCurrent()
                    }
                }
            }
        }
    }
}
