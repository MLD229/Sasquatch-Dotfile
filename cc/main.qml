// Sasquatch Control Center — shell (refonte v1c-1, brief §7 « v1c »).
//
// Ce fichier ne contient plus de contenu de page : il garde la fenêtre
// (FloatingWindow, toggle cc.sh, close(), suppressQuit, capture/OCR), la
// palette dynamique (/api/palette) et le helper api(), puis dessine le cadre :
// board centré (max 1340 × h-80, rayon 18), rail gauche 64 px
// (Accueil / Widgets / Système / Outils + point d'état serveur) et header
// (salutation, heure, météo compacte).
//
// Les pages vivent dans cc/pages/ : HomePage (hôte de widgets `cc`),
// StudioPage (l'espace widget : catalogue + aperçu du fond + panneau de
// style), SystemPage (perf) et ToolsPage (outils).
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "qml"
import "pages"
import Sasquatch.Widgets 1.0

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

    // Encre sur fond accentué (bouton de rail actif) : noir ou blanc selon la
    // luminance de l'accent — lisible même avec un accent sombre.
    function lum(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b; }
    readonly property color cInk: {
        var la = lum(cAccent);
        return Math.abs(la - lum(cText)) > Math.abs(la - lum(cBgSolid)) ? cText : cBgSolid;
    }

    // ---------- state ----------
    property bool serverOk: true
    property bool everShown: false
    // true while the panel is hidden for a screenshot / OCR selection;
    // prevents quit() during the hide.
    property bool suppressQuit: false
    // true while a screenshot request is in flight; blocks double-click.
    property bool shotBusy: false
    property var stats: ({})
    // Page affichée : "home" (board de widgets) | "widgets" (Studio, l'espace
    // widget) | "sys" (perf) | "tools" (outils)
    property string page: "home"
    property string shotStatus: ""

    // ---------- helpers ----------
    // Helper historique : même transport XHR que le reste du CC (timeout
    // explicite pour les routes longues).
    function api(method, path, body, cb, timeoutMs) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = timeoutMs || 3000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    let parsed = null;
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
        // Le serveur backend est un service systemd user (sasquatch-cc) :
        // il vit en permanence, le CC ne fait que se fermer. NE PAS appeler
        // /api/close (ça tuerait le serveur → restart inutile à chaque
        // ouverture + perte de la synchro musique).
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
            // Retour visible : un échec (sélection annulée, outil manquant)
            // ne doit pas laisser le bouton muet.
            shotStatus = (res && res.ok) ? "capturé ✓"
                                         : ("⚠ " + ((res && res.error) || "capture impossible"));
        }, 120000);
    }

    // ---------- header : heure + salutation ----------
    property string clockText: Qt.formatDateTime(new Date(), "hh:mm")
    property int clockHour: new Date().getHours()
    readonly property string greeting: root.clockHour < 6 ? "Bonne nuit"
                                      : root.clockHour < 12 ? "Bonjour"
                                      : root.clockHour < 18 ? "Bon après-midi"
                                      : "Bonsoir"

    onVisibleChanged: {
        if (visible) everShown = true;
        // Quit only after the window was actually shown once (avoids the
        // initial invisible->visible transition killing the server at startup).
        if (everShown && !visible && !suppressQuit) quit();
    }

    Shortcut {
        sequence: "Escape"
        // Don't steal Escape while typing in the image-search / translate field.
        enabled: !(pageLoader.item && pageLoader.item.searchFocused === true)
        onActivated: root.quit()
    }

    // ---------- pollers ----------
    // Battement du serveur : sert au point d'état du rail et à la ligne du
    // header (hôte · RAM · Hz).
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
            var d = new Date();
            root.clockText = Qt.formatDateTime(d, "hh:mm");
            root.clockHour = d.getHours();
        }
    }

    // ---------- veil (léger : le verre doit laisser voir le desktop flouté) ----------
    Rectangle {
        anchors.fill: parent
        color: root.cOverlay
        opacity: 0.3
        MouseArea {
            anchors.fill: parent
            onClicked: root.quit()
        }
    }

    // ---------- board ----------
    readonly property real boardW: Math.min(1340, Math.max(640, root.width - 80))
    // Pleine hauteur pour les pages à listes ; sur l'Accueil, le board prend la
    // hauteur de ses widgets (grille 12 colonnes) et ne laisse plus de vide.
    readonly property real boardH: {
        if (root.page !== "home")
            return Math.max(420, root.height - 80);
        var content = boardColumn.implicitHeight;
        if (!(content > 0))
            return Math.max(420, root.height - 80);
        return Math.min(root.height - 80, content + Theme.spacing * 2);
    }

    // Icônes du rail, dessinées : aucun émoji (la police couleur casse la
    // teinte, et les glyphes symboliques manquent selon la police).
    // 0 accueil · 1 widgets · 2 système · 3 outils
    component RailIcon: Canvas {
        id: ri
        property int kind: 0
        property color tint: root.cText

        function repaint() { requestPaint(); }
        onKindChanged: repaint()
        onTintChanged: repaint()
        onWidthChanged: repaint()
        onHeightChanged: repaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var S = Math.min(width, height);
            if (S < 6)
                return;
            ctx.strokeStyle = ri.tint;
            ctx.fillStyle = ri.tint;
            ctx.lineWidth = Math.max(1.2, S * 0.09);
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            function P(v) { return v / 24 * S; }

            if (ri.kind === 0) {
                ctx.beginPath();
                ctx.moveTo(P(12), P(3));
                ctx.lineTo(P(21), P(10));
                ctx.lineTo(P(18), P(10));
                ctx.lineTo(P(18), P(21));
                ctx.lineTo(P(14), P(21));
                ctx.lineTo(P(14), P(15));
                ctx.lineTo(P(10), P(15));
                ctx.lineTo(P(10), P(21));
                ctx.lineTo(P(6), P(21));
                ctx.lineTo(P(6), P(10));
                ctx.lineTo(P(3), P(10));
                ctx.closePath();
                ctx.stroke();
            } else if (ri.kind === 1) {
                ctx.strokeRect(P(3), P(3), P(8), P(8));
                ctx.strokeRect(P(13), P(3), P(8), P(8));
                ctx.strokeRect(P(3), P(13), P(8), P(8));
                ctx.strokeRect(P(13), P(13), P(8), P(8));
            } else if (ri.kind === 2) {
                ctx.beginPath();
                ctx.arc(P(12), P(12), P(8), Math.PI * 0.75, Math.PI * 2.25);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(P(12), P(12));
                ctx.lineTo(P(16), P(8));
                ctx.stroke();
            } else {
                ctx.beginPath();
                ctx.moveTo(P(4), P(20));
                ctx.lineTo(P(13), P(11));
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(P(16), P(8), P(4.5), 0, Math.PI * 2);
                ctx.stroke();
            }
        }
    }

    Rectangle {
        id: board
        anchors.centerIn: parent
        width: root.boardW
        height: root.boardH
        radius: Theme.radiusPanel
        // Opacité du panneau calculée sur la luminance du papier peint DERRIÈRE
        // lui (0.36 → 0.80 selon la zone) : à 0.36 sur un fond clair le panneau
        // se laisse traverser et le texte perd son support. Les widgets du
        // board, eux, gardent leur verre à 0.05–0.10 — c'est le panneau qui
        // s'adapte, pas les cartes.
        color: Theme.panelFill(Theme.panelAlphaOn(Theme.lumAt(
                   (Math.max(0, root.width - root.boardW) / 2) / root.width,
                   (Math.max(0, root.height - root.boardH) / 2) / root.height,
                   (Math.max(0, root.width - root.boardW) / 2 + root.boardW) / root.width,
                   (Math.max(0, root.height - root.boardH) / 2 + root.boardH) / root.height)))
        border.width: 1
        border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.4)

        // Brief encre §B.1 : le remplissage du panneau glisse vers sa nouvelle
        // opacité quand le papier peint change (220 ms), au lieu de sauter.
        Behavior on color { ColorAnimation { duration: 220 } }

        opacity: 0
        scale: 0.98
        Component.onCompleted: { opacity = 1; scale = 1; }
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // swallow clicks landing on empty board space so they don't reach the veil
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacing
            spacing: Theme.spacing

            // ---------- rail (64 px) ----------
            Rectangle {
                Layout.preferredWidth: 64
                Layout.fillHeight: true
                radius: Theme.radiusCard
                color: Theme.a(root.cText, 0.04)
                border.width: 1
                border.color: Theme.a(root.cText, 0.06)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6

                    Repeater {
                        model: [
                            { k: "home",    t: "Accueil" },
                            { k: "widgets", t: "Widgets" },
                            { k: "sys",     t: "Système" },
                            { k: "tools",   t: "Outils" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 52
                            radius: Theme.radiusBtn
                            color: root.page === modelData.k
                                   ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.85)
                                   : (railHover.containsMouse
                                      ? Theme.a(root.cText, 0.10)
                                      : Theme.a(root.cText, 0.05))
                            Behavior on color { ColorAnimation { duration: 90 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 3

                                RailIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 18
                                    height: 18
                                    kind: index
                                    tint: root.page === modelData.k ? root.cInk : root.cText
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.t
                                    font.pixelSize: 8
                                    color: root.page === modelData.k ? root.cInk : root.cTextDim
                                }
                            }

                            MouseArea {
                                id: railHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.page = modelData.k
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Point d'état serveur (sasquatch-cc sur 8765).
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: root.serverOk ? root.cGood : root.cHot
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                }
            }

            // ---------- colonne : header + page ----------
            ColumnLayout {
                id: boardColumn
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.spacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        spacing: 2

                        Text {
                            text: root.greeting
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
                            font.pixelSize: 11
                            color: root.serverOk ? root.cTextDim : root.cHot
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        id: clockLabel
                        text: root.clockText
                        font.pixelSize: 22
                        font.bold: true
                        color: root.cText
                    }

                    // Météo compacte : c'est le widget `weather` du registre
                    // (variante compact), pas un texte recopié.
                    WeatherWidget {
                        variant: "compact"
                        Layout.preferredWidth: 172
                        Layout.preferredHeight: 54
                    }

                    IconButton {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        glyph: "✕"
                        fontSize: 14
                        glyphColor: root.cText
                        onClicked: root.quit()
                    }
                }

                // ---------- contenu ----------
                Loader {
                    id: pageLoader
                    Layout.fillWidth: true
                    // Accueil : la page donne sa hauteur naturelle (widgets) ;
                    // les autres pages remplissent le board.
                    Layout.fillHeight: root.page !== "home"
                    // « widgets » = StudioPage (l'espace widget, v1c-2).
                    sourceComponent: root.page === "home" ? homePage
                                     : root.page === "widgets" ? studioPage
                                     : root.page === "tools" ? toolsPage
                                     : sysPage
                }
            }
        }
    }

    Component {
        id: homePage
        HomePage {}
    }

    Component {
        id: studioPage
        StudioPage {}
    }

    Component {
        id: sysPage
        SystemPage {
            stats: root.stats
        }
    }

    Component {
        id: toolsPage
        ToolsPage {
            shotStatus: root.shotStatus
            onScreenshotRequested: function(mode) { root.takeScreenshot(mode); }
            onHidePanel: { root.suppressQuit = true; root.visible = false; }
            onShowPanel: { root.suppressQuit = false; root.visible = true; }
        }
    }
}
