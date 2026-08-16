// Sasquatch Playlist — gestionnaire de playlist MPD (Quickshell, Super+P)
//
// Panneau séparé (comme le sélecteur de fonds d'écran wp/, Super+Y) qui pilote
// le MPD via le serveur CC (127.0.0.1:8765) : toggles random/repeat/single,
// liste de la playlist courante (clic = jouer, ✕ = retirer), recherche dans la
// bibliothèque (~/songs) + ajout, chargement du dossier en aléatoire, choix du
// dossier de musique (zenity, côté serveur).
//
// Style : même structure que wp/main.qml (veil + panneau glassmorphism centré
// à dimensions explicites — jamais de ColumnLayout en fill direct dans la
// FloatingWindow), palette dynamique pollée via /api/palette.

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQml.Models
import Quickshell
import "qml"

FloatingWindow {
    id: root
    title: "Sasquatch Playlist"
    // Fenêtre COMPACTE (pas de voile plein écran) : le panneau = la fenêtre,
    // le reste de l'écran (waybar, fenêtres…) reste visible — pattern Aiko
    // (demande momo « le reste de l'écran visible »). Position injectée par
    // pl.sh (droite, sous waybar) — `move 100%-N` ne marche pas avec
    // match:title (bug Hyprland 0.56).
    implicitWidth: 900
    implicitHeight: Screen.height - 82   // 42 waybar + 40 marges
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

    // ---------- state ----------
    property bool everShown: false
    property var st: ({})                     // /api/playlist/status
    property string curFolder: ""
    property bool inLibrary: true
    property string lastSig: ""
    property bool searchActive: false

    ListModel { id: plModel }
    ListModel { id: libModel }

    // ---------- API helper (XHR, comme le CC / wp) ----------
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
    function fmtTime(sec) {
        if (!sec || sec <= 0) return "0:00";
        var s = Math.floor(sec);
        return Math.floor(s / 60) + ":" + (s % 60).toString().padStart(2, "0");
    }
    property real progressRatio: {
        var d = root.st && root.st.duration ? root.st.duration : 0;
        if (d <= 0) return 0;
        var r = (root.st.elapsed || 0) / d;
        return Math.max(0, Math.min(1, r));
    }
    function seekTo(ratio) {
        var d = root.st && root.st.duration ? root.st.duration : 0;
        if (d <= 0) return;
        var sec = Math.max(0, Math.min(Math.round(ratio * d), Math.floor(d)));
        root.api("POST", "/api/playlist/seek", {sec: sec});
    }
    function refresh() {
        root.api("GET", "/api/playlist/status", null, function(res) {
            if (res && res.ok) root.st = res;
        });
        root.api("GET", "/api/playlist/list", null, function(res) {
            if (!res || !res.ok) return;
            var sig = JSON.stringify(res.tracks || []);
            if (sig === root.lastSig) return;   // pas de changement → pas de rebuild
            root.lastSig = sig;
            plModel.clear();
            var tracks = res.tracks || [];
            for (var i = 0; i < tracks.length; i++) {
                var t = tracks[i];
                plModel.append({
                    pos: t.pos,
                    title: t.title,
                    sub: t.artist,
                    dur: t.duration,
                    current: !!t.current
                });
            }
        });
    }

    function loadFolderInfo() {
        root.api("GET", "/api/playlist/library", null, function(res) {
            if (!res || !res.ok) return;
            root.curFolder = res.folder;
            root.inLibrary = res.inLibrary;
        });
    }

    function doSearch() {
        var q = searchField.text.trim();
        libModel.clear();
        if (!q) { root.searchActive = false; return; }
        root.searchActive = true;
        root.api("GET", "/api/playlist/library?q=" + encodeURIComponent(q), null, function(res) {
            libModel.clear();
            if (!res || !res.ok || !res.files) return;
            for (var i = 0; i < res.files.length; i++) {
                var f = res.files[i];
                libModel.append({ file: f.rel, title: f.name, sub: f.path });
            }
        }, 8000);
    }

    // ---------- actions ----------
    function toggleMode(mode) {
        root.api("POST", "/api/playlist/toggle", {mode: mode}, function() {});
    }

    function loadAllRandom() {
        root.api("POST", "/api/playlist/load", {random: true}, function() {});
    }

    function clearPlaylist() {
        root.api("POST", "/api/playlist/clear", null, function() {});
    }

    function shufflePlaylist() {
        root.api("POST", "/api/playlist/shuffle", null, function() {});
    }

    function playPos(pos) {
        root.api("POST", "/api/playlist/play", {pos: pos}, function() {});
    }

    function removePos(pos) {
        root.api("POST", "/api/playlist/remove", {pos: pos}, function() {});
    }

    function addTrack(file) {
        root.api("POST", "/api/playlist/add", {file: file, play: true}, function() {});
    }

    function pickFolder() {
        root.api("POST", "/api/playlist/pick", {kind: "folder"}, function(res) {
            if (!res || !res.ok) return;
            root.api("POST", "/api/playlist/folder", {folder: res.path}, function(r2) {
                if (r2 && r2.ok) root.loadFolderInfo();
            }, 5000);
        }, 200000);
    }

    // ---------- cycle de vie ----------
    onVisibleChanged: {
        if (visible) everShown = true;
        if (everShown && !visible) Qt.quit();
    }
    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }

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
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.loadFolderInfo()

    // ── UI (fenêtre compacte : panel = la fenêtre, coins arrondis) ──
    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(root.cCard.r, root.cCard.g, root.cCard.b, 0.97)
        border.width: 1
        border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.35)

        opacity: 0
        scale: 0.98
        Component.onCompleted: { opacity = 1; scale = 1; }
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // clic sur le vide : rend le focus à la fenêtre (Escape redevient actif)
        MouseArea { anchors.fill: parent; onClicked: panel.forceActiveFocus() }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 12

                // ── En-tête : titre + dossier + action principale ──
                RowLayout { spacing: 12; Layout.fillWidth: true; Layout.preferredHeight: 42
                    Text { text: "🎵"; font.pixelSize: 26; color: root.cAccent }
                    Rectangle { width: 1; height: 30; color: Qt.rgba(root.cTextDim.r, root.cTextDim.g, root.cTextDim.b, 0.35) }
                    ColumnLayout { spacing: 0
                        Text { text: "Playlist"; font.pixelSize: 16; font.weight: Font.DemiBold; color: root.cText }
                        Text {
                            text: root.curFolder || "…"
                            font.pixelSize: 11; color: root.cTextDim
                            elide: Text.ElideMiddle; Layout.maximumWidth: 420
                        }
                    }
                    Item { Layout.fillWidth: true }
                    PlButton {
                        label: "🎲 Tout en aléatoire"
                        accent: true
                        accentColor: root.cAccent
                        onClicked: root.loadAllRandom()
                    }
                    PlButton { label: "✕"; fg: root.cHot; bg: root.cCardSolid; onClicked: Qt.quit() }
                }

                // ⚠ Dossier hors bibliothèque MPD : le chargement est impossible.
                Text {
                    visible: !root.inLibrary
                    text: "⚠ Dossier hors bibliothèque MPD (" + (root.curFolder === "" ? "~/songs" : "") + ") — MPD ne lit que ~/songs"
                    font.pixelSize: 12; color: root.cWarn
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                // ── Rangée toggles + actions ──
                RowLayout { spacing: 8; Layout.fillWidth: true; Layout.preferredHeight: 38
                    PlButton {
                        label: "🎲 Random"
                        active: root.st.random === true
                        accentColor: root.cAccent
                        fg: root.cText; bg: root.cCardSolid
                        onClicked: root.toggleMode("random")
                    }
                    PlButton {
                        label: "🔁 Répéter"
                        active: root.st.repeat === true
                        fg: root.cText; bg: root.cCardSolid
                        onClicked: root.toggleMode("repeat")
                    }
                    PlButton {
                        label: "🔂 Une seule"
                        active: root.st.single === true
                        fg: root.cText; bg: root.cCardSolid
                        onClicked: root.toggleMode("single")
                    }
                    Item { Layout.fillWidth: true }
                    PlButton { label: "📂 Dossier…"; fg: root.cText; bg: root.cCardSolid; onClicked: root.pickFolder() }
                    PlButton { label: "🗑 Vider"; fg: root.cText; bg: root.cCardSolid; disabled: (root.st.playlistlength || 0) === 0; onClicked: root.clearPlaylist() }
                    PlButton { label: "🔀 Shuffle"; fg: root.cText; bg: root.cCardSolid; disabled: (root.st.playlistlength || 0) === 0; onClicked: root.shufflePlaylist() }
                }

                // ── Transport : contrôles de lecture + barre de progression ──
                RowLayout { spacing: 10; Layout.fillWidth: true; Layout.preferredHeight: 42
                    PlButton {
                        label: "⏮"; fg: root.cText; bg: root.cCardSolid
                        disabled: (root.st.playlistlength || 0) === 0
                        onClicked: root.api("POST", "/api/playlist/prev")
                    }
                    PlButton {
                        label: root.st.state === "play" ? "⏸" : "▶"
                        accent: true; accentColor: root.cAccent
                        Layout.preferredWidth: 72
                        disabled: (root.st.playlistlength || 0) === 0
                        onClicked: root.api("POST", "/api/playlist/playtoggle")
                    }
                    PlButton {
                        label: "⏹"; fg: root.cText; bg: root.cCardSolid
                        disabled: root.st.state === "stop"
                        onClicked: root.api("POST", "/api/playlist/stop")
                    }
                    PlButton {
                        label: "⏭"; fg: root.cText; bg: root.cCardSolid
                        disabled: (root.st.playlistlength || 0) === 0
                        onClicked: root.api("POST", "/api/playlist/next")
                    }
                    Text {
                        text: root.fmtTime(root.st.elapsed)
                        font.pixelSize: 12; color: root.cTextDim
                        Layout.preferredWidth: 42; horizontalAlignment: Text.AlignRight
                    }
                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: 8
                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: Qt.rgba(root.cTextDim.r, root.cTextDim.g, root.cTextDim.b, 0.2)
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: parent.width * root.progressRatio
                            radius: 4
                            color: root.cAccent
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: root.seekTo(mouse.x / width)
                            onPositionChanged: if (pressed) root.seekTo(mouse.x / width)
                        }
                    }
                    Text {
                        text: root.fmtTime(root.st.duration)
                        font.pixelSize: 12; color: root.cTextDim
                        Layout.preferredWidth: 42
                    }
                }

                // ── Recherche ──
                RowLayout { spacing: 8; Layout.fillWidth: true; Layout.preferredHeight: 36
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 10
                        color: Qt.rgba(root.cCardSolid.r, root.cCardSolid.g, root.cCardSolid.b, 0.9)
                        border.width: 1
                        border.color: Qt.rgba(root.cTextDim.r, root.cTextDim.g, root.cTextDim.b, 0.25)
                        TextField {
                            id: searchField
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            placeholderText: "Rechercher un morceau dans la bibliothèque…"
                            placeholderTextColor: Qt.rgba(root.cTextDim.r, root.cTextDim.g, root.cTextDim.b, 0.6)
                            color: root.cText
                            font.pixelSize: 13
                            background: null
                            onAccepted: root.doSearch()
                            onTextChanged: {
                                if (text.trim() === "" && root.searchActive) root.doSearch();
                            }
                        }
                    }
                    PlButton { label: "🔍"; fg: root.cText; bg: root.cCardSolid; onClicked: root.doSearch() }
                }

                // ── Résultats de recherche ──
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.searchActive && libModel.count > 0
                    spacing: 6
                    Text {
                        text: "Résultats (" + libModel.count + ")"
                        font.pixelSize: 11; font.bold: true; color: root.cAccent
                    }
                    ListView {
                        id: libList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(150, 34 * libModel.count)
                        clip: true
                        model: libModel
                        // Wrapper Item : le delegate custom (PlLibRow) n'a pas
                        // accès à `model` dans son propre contexte — le wrapper
                        // inline (contexte du delegate) résout model.* et passe
                        // les valeurs (ReferenceError « model is not defined »).
                        delegate: Item {
                            width: libList.width
                            height: 34
                            PlLibRow {
                                anchors.fill: parent
                                file: model.file
                                title: model.title
                                sub: model.sub
                                accent: root.cAccent
                                textColor: root.cText
                                dimColor: root.cTextDim
                                cardColor: root.cCardSolid
                                onAddClicked: function(f) { root.addTrack(f); }
                            }
                        }
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                }

                // ── Playlist courante ──
                RowLayout { Layout.fillWidth: true; Layout.preferredHeight: 18; spacing: 10
                    Text {
                        text: "Playlist (" + (root.st.playlistlength || 0) + ")"
                        font.pixelSize: 11; font.bold: true; color: root.cAccent
                    }
                    Text {
                        text: root.st.state === "play" ? "▶ en lecture" : (root.st.state === "pause" ? "⏸ en pause" : "■ arrêté")
                        font.pixelSize: 11; color: root.cTextDim
                    }
                    Item { Layout.fillWidth: true }
                }

                ListView {
                    id: plList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 120
                    clip: true
                    spacing: 4
                    model: plModel
                    delegate: Item {
                        width: plList.width
                        height: 38
                        PlRow {
                            anchors.fill: parent
                            pos: model.pos
                            title: model.title
                            sub: model.sub
                            dur: model.dur
                            current: model.current
                            accent: root.cAccent
                            textColor: root.cText
                            dimColor: root.cTextDim
                            cardColor: root.cCardSolid
                            onPlayClicked: function(p) { root.playPos(p); }
                            onRemoveClicked: function(p) { root.removePos(p); }
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Text {
                        anchors.centerIn: parent
                        visible: plList.count === 0
                        text: "Playlist vide — 🎲 charge tout en aléatoire, 🔍 cherche un morceau, ou 📂 choisis un dossier"
                        color: root.cTextDim
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
