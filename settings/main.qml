// Sasquatch Settings - main UI
// Panneau de configuration du dotfile (Super+I). Backend : settings.py (8770).
// Style calqué sur le CC (cc/main.qml) : FloatingWindow plein écran, palette
// dynamique pollée toutes les 2 s, verre dépoli, voile cliquable, api() XHR
// inline, piège everShown pour quit().
//
// PIÈGES RESPECTÉS :
//  - jamais d'anchors.fill sur les enfants directs d'un Layout
//    (Layout.fillWidth/fillHeight à la place)
//  - contenu scrollable (Flickable) : 7 sections dépassent ~900 px
//  - les signaux d'interaction (onClicked/onMoved/onAccepted) n'émettent
//    JAMAIS de POST pendant le chargement initial (state chargé une fois)

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "qml"

FloatingWindow {
    id: root
    title: "Sasquatch Settings"
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
    property bool fieldFocus: false
    property bool stateLoaded: false
    property bool hypridle: false
    property var keybindsModel: ListModel {}
    property var accentColors: ["#89b4fa", "#a6e3a1", "#f9e2af", "#f38ba8", "#f5c2e7",
                                "#cba6f7", "#94e2d5", "#fab387", "#94e2d5", "#cdd6f4",
                                "#a6adc8", "#b4befe"]

    // valeurs éditables (chargées depuis /api/state puis pilotées par l'UI)
    property bool pEnabled: true
    property int pDim: 3
    property int pLock: 5
    property int pOff: 7
    property int pSuspend: 15
    property string pMode: "auto"
    property string pAccent: "#88aaee"
    property string pAccent2: "#aa88ff"
    property string clockFormat: "\uf5d4  {:%H:%M   %d %b}"
    property bool lock24h: true
    property bool lockDate: true
    property bool ccCava: true
    property string ccOcr: "fra"
    property bool ccCover: true
    property int pGapsIn: 5
    property int pGapsOut: 10
    property int pRounding: 12
    property bool pAnim: true
    property bool sysLoaded: false
    property string langMode: "ja"

    // ---------- API helper (XHR, inline — identique au CC) ----------
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
            xhr.open(method, "http://127.0.0.1:8770" + path);
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

    onVisibleChanged: {
        if (visible) everShown = true;
        // Quit only after the window was actually shown once (avoids the
        // initial invisible->visible transition killing the server at startup).
        if (everShown && !visible) quit();
    }

    // Touche Escape : ferme, sauf quand un champ texte a le focus.
    Shortcut {
        sequence: "Escape"
        enabled: !root.fieldFocus
        onActivated: root.quit()
    }

    // ---------- actions ----------
    function saveVeille() {
        root.api("POST", "/api/veille", {
            enabled: root.pEnabled,
            dim_min: root.pDim,
            lock_min: root.pLock,
            off_min: root.pOff,
            suspend_min: root.pSuspend
        }, function(res) { if (res) root.hypridle = res.hypridle; });
    }
    function savePalette() {
        root.api("POST", "/api/palette", {
            mode: root.pMode,
            accent: root.pAccent,
            accent2: root.pAccent2
        }, function() {});
    }
    function saveClock() {
        root.api("POST", "/api/clock", {
            waybar_format: root.clockFormat,
            lock_24h: root.lock24h,
            lock_date: root.lockDate
        }, function() {});
    }
    function saveCc() {
        root.api("POST", "/api/cc", {
            cava: root.ccCava,
            ocr_lang: root.ccOcr,
            cover_art: root.ccCover
        }, function() {});
    }
    function saveSystem() {
        root.api("POST", "/api/system", {
            gaps_in: root.pGapsIn,
            gaps_out: root.pGapsOut,
            rounding: root.pRounding,
            animations: root.pAnim
        }, function() {});
    }
    function saveLang() {
        root.api("POST", "/api/lang", {mode: root.langMode}, function() {});
    }
    function openWallpaper() {
        root.api("POST", "/api/wallpaper", null, function() {});
    }
    function saveKeybind(id, command) {
        root.api("POST", "/api/keybinds", {id: id, command: command},
                 function(res) { if (res && res.ok) root.loadKeybinds(); });
    }
    function loadKeybinds() {
        root.api("GET", "/api/keybinds", null, function(res) {
            if (!res || !res.keybinds) return;
            root.keybindsModel.clear();
            for (var i = 0; i < res.keybinds.length; i++)
                root.keybindsModel.append(res.keybinds[i]);
        });
    }

    // ---------- pollers ----------
    // State : chargé UNE fois (widgets bindés sur p*), hypridle re-pollé.
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.api("GET", "/api/state", null, function(res) {
                if (!res) { root.serverOk = false; return; }
                root.serverOk = true;
                root.hypridle = !!res.hypridle;
                if (res.settings && !root.stateLoaded) {
                    root.stateLoaded = true;
                    var s = res.settings;
                    if (s.idle) {
                        root.pEnabled = s.idle.enabled !== false;
                        root.pDim = s.idle.dim_min || 3;
                        root.pLock = s.idle.lock_min || 5;
                        root.pOff = s.idle.off_min || 7;
                        root.pSuspend = s.idle.suspend_min || 15;
                    }
                    if (s.palette) {
                        root.pMode = s.palette.mode || "auto";
                        root.pAccent = s.palette.accent || "#88aaee";
                        root.pAccent2 = s.palette.accent2 || "#aa88ff";
                    }
                    if (s.clock) {
                        root.clockFormat = s.clock.waybar_format || root.clockFormat;
                        root.lock24h = s.clock.lock_24h !== false;
                        root.lockDate = s.clock.lock_date !== false;
                    }
                    if (s.cc) {
                        root.ccCava = s.cc.cava !== false;
                        root.ccOcr = s.cc.ocr_lang || "fra";
                        root.ccCover = s.cc.cover_art !== false;
                    }
                    if (s.lang) {
                        root.langMode = s.lang.mode || "ja";
                    }
                }
            });
            // Système (gaps/rounding/animations) : chargé une fois.
            root.api("GET", "/api/system", null, function(res) {
                if (res && !root.sysLoaded) {
                    root.sysLoaded = true;
                    root.pGapsIn = res.gaps_in;
                    root.pGapsOut = res.gaps_out;
                    root.pRounding = res.rounding;
                    root.pAnim = !!res.animations;
                }
            });
        }
    }
    // Palette dynamique : suit theme-apply (relue toutes les 2 s).
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
        onTriggered: clockLabel.text = Qt.formatDateTime(new Date(), "hh:mm")
    }
    // Keybinds chargés peu après l'ouverture.
    Timer {
        interval: 400; running: true; repeat: false; triggeredOnStart: true
        onTriggered: root.loadKeybinds()
    }
    // Debounce veille (300 ms après le dernier mouvement de slider).
    Timer {
        id: veilleTimer
        interval: 300
        onTriggered: root.saveVeille()
    }
    // Debounce système (gaps/rounding/animations).
    Timer {
        id: systemTimer
        interval: 300
        onTriggered: root.saveSystem()
    }

    // ---------- voile (léger : le verre doit laisser voir le desktop flouté) ----------
    Rectangle {
        anchors.fill: parent
        color: root.cOverlay
        opacity: 0.3
        MouseArea {
            anchors.fill: parent
            onClicked: root.quit()
        }
    }

    // ---------- panneau (verre dépoli) ----------
    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(1000, root.width - 40)
        height: Math.min(720, root.height - 40)
        radius: 22
        color: Qt.rgba(root.cCard.r, root.cCard.g, root.cCard.b, 0.42)
        border.width: 1
        border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.4)

        opacity: 0
        scale: 0.98
        Component.onCompleted: { opacity = 1; scale = 1; }
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // swallow clicks on empty panel space (so they don't reach the veil)
        // et retire le focus des champs → Escape redevient actif.
        MouseArea {
            anchors.fill: parent
            onClicked: panel.forceActiveFocus()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 10

            // ---------- header ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "⚙ Sasquatch Settings"
                    color: root.cText
                    font.pixelSize: 17
                    font.bold: true
                }
                Rectangle {
                    implicitHeight: 22
                    Layout.preferredWidth: badgeText.implicitWidth + 16
                    radius: 11
                    color: root.serverOk
                           ? Qt.rgba(root.cGood.r, root.cGood.g, root.cGood.b, 0.15)
                           : Qt.rgba(root.cHot.r, root.cHot.g, root.cHot.b, 0.15)
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: root.serverOk ? "● connecté" : "○ serveur hors ligne"
                        color: root.serverOk ? root.cGood : root.cHot
                        font.pixelSize: 10
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    id: clockLabel
                    color: root.cTextDim
                    font.pixelSize: 12
                }
                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 14
                    color: closeMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: root.cTextDim
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.quit()
                    }
                }
            }

            // ---------- contenu scrollable (5 sections : ça déborde) ----------
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: contentCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 6
                    background: Rectangle { color: "transparent" }
                    contentItem: Rectangle { radius: 3; color: Qt.rgba(1, 1, 1, 0.15) }
                }

                ColumnLayout {
                    id: contentCol
                    width: parent.width
                    spacing: 12

                    // ═══════════ 1. LANGUE 言語 ═══════════
                    Section {
                        title: "LANGUE 言語"
                        Layout.fillWidth: true

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Langue"
                                color: root.cTextDim
                                font.pixelSize: 11
                            }
                            Rectangle {
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: langJaText.implicitWidth + 24
                                radius: 8
                                color: root.langMode === "ja"
                                       ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.25)
                                       : Qt.rgba(1, 1, 1, 0.08)
                                border.width: root.langMode === "ja" ? 1 : 0
                                border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.6)
                                Text {
                                    id: langJaText
                                    anchors.centerIn: parent
                                    text: "日本語"
                                    color: root.langMode === "ja" ? root.cAccent : root.cTextDim
                                    font.pixelSize: 11
                                    font.bold: root.langMode === "ja"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.langMode = "ja"; root.saveLang(); }
                                }
                            }
                            Rectangle {
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: langFrText.implicitWidth + 24
                                radius: 8
                                color: root.langMode === "fr"
                                       ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.25)
                                       : Qt.rgba(1, 1, 1, 0.08)
                                border.width: root.langMode === "fr" ? 1 : 0
                                border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.6)
                                Text {
                                    id: langFrText
                                    anchors.centerIn: parent
                                    text: "Français"
                                    color: root.langMode === "fr" ? root.cAccent : root.cTextDim
                                    font.pixelSize: 11
                                    font.bold: root.langMode === "fr"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.langMode = "fr"; root.saveLang(); }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Text {
                            text: "Toute l'UI bascule : waybar (labels + heure), horloge murale, hyprlock, noms des workspaces."
                            color: root.cTextDim
                            font.pixelSize: 10
                        }
                    }

                    // ═══════════ 2. VEILLE ═══════════
                    Section {
                        title: "VEILLE"
                        Layout.fillWidth: true

                        Toggle {
                            label: "Veille automatique (hypridle)"
                            checked: root.pEnabled
                            Layout.fillWidth: true
                            onToggled: { root.pEnabled = value; root.veilleTimer.restart(); }
                        }
                        SliderRow {
                            label: "Diminution"
                            from: 1; to: 10
                            value: root.pDim
                            Layout.fillWidth: true
                            onChanged: { root.pDim = value; root.veilleTimer.restart(); }
                        }
                        SliderRow {
                            label: "Verrouillage"
                            from: 1; to: 30
                            value: root.pLock
                            Layout.fillWidth: true
                            onChanged: { root.pLock = value; root.veilleTimer.restart(); }
                        }
                        SliderRow {
                            label: "Écran off"
                            from: 1; to: 30
                            value: root.pOff
                            Layout.fillWidth: true
                            onChanged: { root.pOff = value; root.veilleTimer.restart(); }
                        }
                        SliderRow {
                            label: "Suspension"
                            from: 1; to: 60
                            value: root.pSuspend
                            Layout.fillWidth: true
                            onChanged: { root.pSuspend = value; root.veilleTimer.restart(); }
                        }
                    }

                    // ═══════════ 3. APPARENCE ═══════════
                    Section {
                        title: "APPARENCE"
                        Layout.fillWidth: true

                        Toggle {
                            label: "Palette auto (wallpaper)"
                            checked: root.pMode === "auto"
                            Layout.fillWidth: true
                            onToggled: {
                                root.pMode = value ? "auto" : "manual";
                                root.savePalette();
                            }
                        }

                        // mode manuel : swatches + hex (visible seulement en manuel)
                        ColumnLayout {
                            visible: root.pMode === "manual"
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "Accent"
                                color: root.cTextDim
                                font.pixelSize: 11
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: root.accentColors
                                    delegate: ColorSwatch {
                                        colorHex: modelData
                                        selected: root.pAccent === modelData
                                        accentColor: root.cAccent
                                        onPicked: { root.pAccent = modelData; root.savePalette(); }
                                    }
                                }
                            }
                            Text {
                                text: "Accent 2"
                                color: root.cTextDim
                                font.pixelSize: 11
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: root.accentColors
                                    delegate: ColorSwatch {
                                        colorHex: modelData
                                        selected: root.pAccent2 === modelData
                                        accentColor: root.cAccent
                                        onPicked: { root.pAccent2 = modelData; root.savePalette(); }
                                    }
                                }
                            }
                            FieldRow {
                                label: "Accent hex"
                                text: root.pAccent
                                accentColor: root.cAccent
                                Layout.fillWidth: true
                                onFocusActiveChanged: root.fieldFocus = focusActive
                                onSubmitted: { root.pAccent = text.trim(); root.savePalette(); }
                            }
                            FieldRow {
                                label: "Accent 2 hex"
                                text: root.pAccent2
                                accentColor: root.cAccent
                                Layout.fillWidth: true
                                onFocusActiveChanged: root.fieldFocus = focusActive
                                onSubmitted: { root.pAccent2 = text.trim(); root.savePalette(); }
                            }
                        }
                    }

                    // ═══════════ 4. HORLOGE ═══════════
                    Section {
                        title: "HORLOGE"
                        Layout.fillWidth: true

                        FieldRow {
                            label: "Format waybar"
                            text: root.clockFormat
                            accentColor: root.cAccent
                            Layout.fillWidth: true
                            onFocusActiveChanged: root.fieldFocus = focusActive
                            onSubmitted: { root.clockFormat = text; root.saveClock(); }
                        }
                        Toggle {
                            label: "24h (hyprlock)"
                            checked: root.lock24h
                            Layout.fillWidth: true
                            onToggled: { root.lock24h = value; root.saveClock(); }
                        }
                        Toggle {
                            label: "Afficher la date (hyprlock)"
                            checked: root.lockDate
                            Layout.fillWidth: true
                            onToggled: { root.lockDate = value; root.saveClock(); }
                        }
                    }

                    // ═══════════ 5. RACCOURCIS ═══════════
                    Section {
                        title: "RACCOURCIS"
                        Layout.fillWidth: true

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: resetText.implicitWidth + 24
                                radius: 8
                                color: resetMa.containsMouse
                                       ? Qt.rgba(root.cHot.r, root.cHot.g, root.cHot.b, 0.22)
                                       : Qt.rgba(root.cHot.r, root.cHot.g, root.cHot.b, 0.12)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    id: resetText
                                    anchors.centerIn: parent
                                    text: "Réinitialiser les overrides"
                                    color: root.cHot
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: resetMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.api("POST", "/api/keybinds/reset", null,
                                                 function(res) { if (res && res.ok) root.loadKeybinds(); });
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 14
                                color: refMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "↻"
                                    color: root.cTextDim
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    id: refMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.loadKeybinds()
                                }
                            }
                        }
                        Text {
                            text: root.keybindsModel.count + " raccourcis"
                            color: root.cTextDim
                            font.pixelSize: 10
                        }

                        Repeater {
                            model: root.keybindsModel
                            delegate: KeybindRow {
                                Layout.fillWidth: true
                                bindId: model.id
                                mods: model.mods
                                key: model.key
                                section: model.section
                                command: model.arg
                                         ? (model.dispatcher + ", " + model.arg)
                                         : model.dispatcher
                                originalCommand: command
                                accentColor: root.cAccent
                                onFocusActiveChanged: root.fieldFocus = focusActive
                                onSave: { root.saveKeybind(id, command); }
                                onRevert: { /* le champ a déjà été restauré localement */ }
                            }
                        }
                    }

                    // ═══════════ 6. CONTROL PANEL ═══════════
                    Section {
                        title: "CONTROL PANEL"
                        Layout.fillWidth: true

                        Toggle {
                            label: "Cava (visualiseur CC)"
                            checked: root.ccCava
                            Layout.fillWidth: true
                            onToggled: { root.ccCava = value; root.saveCc(); }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Langue OCR"
                                color: root.cTextDim
                                font.pixelSize: 11
                            }
                            Rectangle {
                                Layout.preferredHeight: 26
                                Layout.preferredWidth: 46
                                radius: 8
                                color: root.ccOcr === "fra"
                                       ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.25)
                                       : Qt.rgba(1, 1, 1, 0.08)
                                border.width: root.ccOcr === "fra" ? 1 : 0
                                border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.6)
                                Text {
                                    anchors.centerIn: parent
                                    text: "Fra"
                                    color: root.ccOcr === "fra" ? root.cAccent : root.cTextDim
                                    font.pixelSize: 11
                                    font.bold: root.ccOcr === "fra"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.ccOcr = "fra"; root.saveCc(); }
                                }
                            }
                            Rectangle {
                                Layout.preferredHeight: 26
                                Layout.preferredWidth: 46
                                radius: 8
                                color: root.ccOcr === "eng"
                                       ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.25)
                                       : Qt.rgba(1, 1, 1, 0.08)
                                border.width: root.ccOcr === "eng" ? 1 : 0
                                border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.6)
                                Text {
                                    anchors.centerIn: parent
                                    text: "Eng"
                                    color: root.ccOcr === "eng" ? root.cAccent : root.cTextDim
                                    font.pixelSize: 11
                                    font.bold: root.ccOcr === "eng"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.ccOcr = "eng"; root.saveCc(); }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Toggle {
                            label: "Cover art (MPD)"
                            checked: root.ccCover
                            Layout.fillWidth: true
                            onToggled: { root.ccCover = value; root.saveCc(); }
                        }
                    }

                    // ═══════════ 7. SYSTÈME ═══════════
                    Section {
                        title: "SYSTÈME"
                        Layout.fillWidth: true

                        SliderRow {
                            label: "Gaps intérieur"
                            from: 0; to: 30
                            value: root.pGapsIn
                            Layout.fillWidth: true
                            onChanged: { root.pGapsIn = value; root.systemTimer.restart(); }
                        }
                        SliderRow {
                            label: "Gaps extérieur"
                            from: 0; to: 50
                            value: root.pGapsOut
                            Layout.fillWidth: true
                            onChanged: { root.pGapsOut = value; root.systemTimer.restart(); }
                        }
                        SliderRow {
                            label: "Coins arrondis"
                            from: 0; to: 30
                            value: root.pRounding
                            Layout.fillWidth: true
                            onChanged: { root.pRounding = value; root.systemTimer.restart(); }
                        }
                        Toggle {
                            label: "Animations"
                            checked: root.pAnim
                            Layout.fillWidth: true
                            onToggled: { root.pAnim = value; root.saveSystem(); }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: wallText.implicitWidth + 24
                                radius: 8
                                color: wallMa.containsMouse
                                       ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.25)
                                       : Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.12)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    id: wallText
                                    anchors.centerIn: parent
                                    text: "🖼 Choisir un wallpaper"
                                    color: root.cAccent
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: wallMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openWallpaper()
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }

            // ---------- footer ----------
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Modifications sauvegardées automatiquement"
                color: root.cTextDim
                font.pixelSize: 10
            }
        }
    }
}
