// shell.qml — Slide bar Sasquatch (Quickshell 0.3.2)
// Point d'entrée NEUF : `quickshell -p ~/.config/cc/sidebar/shell.qml`
// lancé par `~/.config/cc/sidebar/sidebar.sh` (Super+U).
//
// ARCHITECTURE (voir README.md du dossier)
//   shell.qml        → cette fenêtre + le rendu
//   server.py        → backend HTTP 8778 (todo persistante, chrono/timer/
//                      alarme, modes) : service systemd user PERMANENT, donc
//                      le temps continue de tourner panneau fermé.
//   clock.py         → moteur chrono/timer/alarme (horloge absolue)
//   modes.py         → modes système avec sauvegarde/restauration de l'état
//
// PALETTE : aucune couleur en dur. Les valeurs ci-dessous sont des SECOURS
// (identiques aux défauts de cc/palette.py, donc jamais un thème inventé) et
// sont remplacées dès la première réponse de GET /api/palette, relu toutes
// les 2 s. /api/palette lit ~/.config/cc/qml/Palette.qml, régénéré par
// theme-apply.py à chaque changement de wallpaper → le panneau suit le fond.
//
// ANIMATION : on n'anime NI la largeur NI l'exclusiveZone de la fenêtre
// (quickshell#866 : désynchronisation des deux). exclusiveZone reste 0 et on
// anime l'offset interne du contenu (x + opacité).
//
// VERRE : la fenêtre reste `color: "transparent"`. Le flou derrière est
// demandé via Quickshell.Wayland BackgroundEffect (ext-background-effect-v1) ;
// si le compositeur ne l'implémente pas, le fallback est le blur de layer
// surface côté Hyprland (layerrule = blur, quickshell). L'effet « plus ou
// moins glacé selon la partie » vient des tokens glass* ci-dessous : chaque
// surface porte son propre alpha, calculé depuis /api/palette.

// Delegates (ListView/Repeater) accèdent aux ids du parent (root, …) :
// légal et explicite grâce à ce pragma (sinon qmllint : « unqualified access »).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "qml"


PanelWindow {
    id: root

    // ── Palette : VALEURS DE SECOURS uniquement (identiques aux défauts de
    // cc/palette.py). Chaque ligne est écrasée par GET /api/palette, qui lit
    // ~/.config/cc/qml/Palette.qml régénéré par theme-apply.py à chaque
    // changement de wallpaper. Aucune couleur n'est utilisée « telle quelle »
    // hors de ces 11 lignes de secours.
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
    property bool paletteLive: false

    readonly property string apiBase: "http://127.0.0.1:8778"

    // ── Tokens « verre » (glassmorphism) ─────────────────────────────────
    // AUCUN hex ici : tout dérive de /api/palette à l'exécution.
    //   shade(c, k) : k>1 éclaircit (Qt.lighter), k<1 fonce (Qt.darker)
    //   glass(c, k, a) : même teinte avec l'alpha du niveau de verre
    // Échelle d'opacité (brief A, resserrée 2026-10-30 pour plus de verre) :
    //   panneau 0.27-0.34 (le plus opaque, c'est le fond)
    //   cartes  0.18      (plus transparentes : on voit le fond à travers)
    //   héro    0.11      (bloc TEMPS, la pièce qui respire)
    //   boutons 0.46      (verre FUMÉ plus foncé)
    // Baissés de ~25 % relatifs (0.36/0.46/0.24/0.15/0.62/0.50 avant) : les
    // bordures (glassBorder) et les reflets (glassHighlight) restent inchangés,
    // c'est ce qui garde les formes lisibles quand les surfaces s'effacent.
    function shade(c, k) {
        return k >= 1 ? Qt.lighter(c, k) : Qt.darker(c, 1 / k);
    }
    function glass(c, k, a) {
        var s = root.shade(c, k);
        return Qt.rgba(s.r, s.g, s.b, a);
    }
    function rgba(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
    // mixN : mélange deux teintes de la palette (t = part de b)
    function mixN(a, b, t) {
        return Qt.rgba(a.r * (1 - t) + b.r * t,
                       a.g * (1 - t) + b.g * t,
                       a.b * (1 - t) + b.b * t, 1.0);
    }
    // glassTint : teinte de verre = couleur palette + un peu de la couleur de
    // texte (le « lait » du verre), puis l'alpha du niveau.
    function glassTint(c, t, a) {
        var m = root.mixN(c, root.cText, t);
        return Qt.rgba(m.r, m.g, m.b, a);
    }

    readonly property color glassBg: root.glassTint(root.cBgSolid, 0.10, 0.27)
    readonly property color glassBgDeep: root.glassTint(Qt.darker(root.cBgSolid, 1.25), 0.05, 0.34)
    readonly property color glassCard: root.glassTint(root.cCard, 0.17, 0.18)
    readonly property color glassHero: root.glassTint(root.cCard, 0.24, 0.11)
    readonly property color glassBtn: root.glassTint(Qt.darker(root.cCard, 1.75), 0.07, 0.46)
    readonly property color glassInset: root.glassTint(Qt.darker(root.cBg, 1.4), 0.04, 0.37)
    // Accent utilisable en APLAT : mélangé au texte pour rester visible même
    // quand la palette renvoie un accent très sombre (wallpaper N&B → #0c0c0c).
    readonly property color accentLift: root.mixN(root.cAccent, root.cText, 0.30)
    readonly property color accent2Lift: root.mixN(root.accent2Solid, root.cText, 0.30)

    readonly property color glassBorder: root.rgba(root.accentLift, 0.30)
    readonly property color glassHighlight: root.rgba(root.cText, 0.12)
    readonly property color glassShadow: root.rgba(root.cOverlay, 0.35)
    readonly property color glassActive: root.rgba(root.accentLift, 0.30)
    // cAccent2 arrive parfois déjà alphaïque (#AARRGGBB) : on garde le RGB
    readonly property color accent2Solid: root.rgba(root.cAccent2, 1.0)


    // ── État UI ───────────────────────────────────────────────────────────
    property bool opened: false
    property bool serverOk: false
    property string lastError: ""
    property var st: ({})
    property var todo: []
    property var counts: ({ total: 0, remaining: 0, done: 0 })
    property var alarms: []
    property var modes: ({})
    property int kelvin: 4000
    property var envTools: ({})
    property int lastEventId: 0
    property string flashMsg: ""
    property bool flash: false
    property bool showDone: false
    property string timeTab: "chrono"
    property string newTodoText: ""
    property string newTimerMin: ""
    property string newAlarmHH: ""
    property string newAlarmMM: ""
    property var player: ({})
    property var clips: []
    property int volume: 0
    property int brightness: 0
    // true = la saisie to-do prend le focus à l'ouverture (comportement prod)
    property bool shellFocus: true

    // ── Fenêtre (overlay : ne pousse aucune fenêtre) ──────────────────────
    anchors {
        top: true
        bottom: true
        right: true
    }
    margins {
        top: 10
        right: 10
        bottom: 10
    }
    implicitWidth: 392
    exclusiveZone: 0
    aboveWindows: true
    focusable: true
    color: "transparent"
    visible: true

    // Flou derrière la fenêtre (ext-background-effect-v1). Si le compositeur
    // ne l'implémente pas, quickshell ignore simplement la requête : le
    // fallback est alors le blur de layer surface côté Hyprland.
    // La région suit la feuille (donc l'animation d'ouverture).
    BackgroundEffect.blurRegion: Region {
        item: sheet
        radius: 9          // flou TRÈS léger (momo) : 18 était trop marqué
    }

    // ── HTTP helper (XHR inline, même pattern que cc/main.qml) ────────────
    function api(method, path, body, cb) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = 4000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var data = null;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    data = JSON.parse(xhr.responseText);
                } catch (e) {
                    data = null;
                }
            }
            if (cb)
                cb(data);
        };
        xhr.open(method, root.apiBase + path);
        if (body !== null)
            xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body !== null ? JSON.stringify(body) : null);
    }

    function post(path, body) {
        root.api("POST", path, body || {}, function (res) {
            if (res && res.ok === false && res.error)
                root.lastError = res.error;
            else if (res && res.ok)
                root.lastError = "";
            root.refreshState();
        });
    }

    // ── Palette : relue à chaque changement de wallpaper ──────────────────
    function refreshPalette() {
        root.api("GET", "/api/palette", null, function (p) {
            if (!p || !p.bg)
                return;
            root.cBg = p.bg || root.cBg;
            root.cBgSolid = p.bgSolid || root.cBgSolid;
            root.cCard = p.card || root.cCard;
            root.cText = p.text || root.cText;
            root.cTextDim = p.textDim || root.cTextDim;
            root.cAccent = p.accent || root.cAccent;
            root.cAccent2 = p.accent2 || root.cAccent2;
            root.cOverlay = p.overlay || root.cOverlay;
            root.cGood = p.good || root.cGood;
            root.cWarn = p.warn || root.cWarn;
            root.cHot = p.hot || root.cHot;
            root.paletteLive = true;
        });
    }

    // ── État (todo / temps / modes) ───────────────────────────────────────
    function applyState(s) {
        root.serverOk = true;
        root.st = s;
        root.todo = s.todo || [];
        root.counts = s.counts || { total: 0, remaining: 0, done: 0 };
        root.alarms = s.alarms || [];
        root.modes = s.modes || {};
        // La température affichée doit refléter l'état réel (sinon le curseur
        // reste à 4000 K alors que hyprsunset tourne à 3600 K).
        if (s.modes && s.modes.kelvin)
            root.kelvin = s.modes.kelvin;
        // Volume / luminosité : /api/state renvoie des OBJETS
        // ({ok, volume, muted} / {ok, brightness, error}), pas des nombres.
        // L'ancien test `typeof s.volume === "number"` ne matchait jamais →
        // les deux curseurs restaient bloqués à 0 %.
        if (s.volume && typeof s.volume.volume === "number")
            root.volume = s.volume.volume;
        if (s.brightness && typeof s.brightness.brightness === "number")
            root.brightness = s.brightness.brightness;
        // Événements (timer/alarme sonnés côté backend) → flash dans le panneau
        var evs = s.events || [];
        for (var i = 0; i < evs.length; i++) {
            if (evs[i].id > root.lastEventId) {
                root.lastEventId = evs[i].id;
                root.flashMsg = (evs[i].kind === "alarm" ? "⏰ " : "⏱ ")
                    + (evs[i].label || "temps écoulé");
                root.flash = true;
                flashTimer.restart();
            }
        }
    }

    function refreshState() {
        root.api("GET", "/api/state?since=" + root.lastEventId, null, function (s) {
            if (!s) {
                root.serverOk = false;
                return;
            }
            root.applyState(s);
        });
    }

    function refreshEnv() {
        root.api("GET", "/api/env", null, function (e) {
            if (!e)
                return;
            root.envTools = e;
            root.kelvin = root.kelvin || 4000;
        });
    }

    function refreshExtras() {
        root.api("GET", "/api/player", null, function (p) {
            root.player = p || ({});
        });
        root.api("GET", "/api/clipboard", null, function (c) {
            root.clips = (c && c.items) ? c.items : [];
        });
    }

    // ── Actions ───────────────────────────────────────────────────────────
    function addTodo() {
        var t = root.newTodoText.trim();
        if (t === "")
            return;
        root.newTodoText = "";
        root.post("/api/todo", { action: "add", text: t });
    }
    function todoToggle(id) {
        root.post("/api/todo", { action: "toggle", id: id });
    }
    function todoDel(id) {
        root.post("/api/todo", { action: "del", id: id });
    }
    function todoPrio(id) {
        root.post("/api/todo", { action: "set_prio", id: id });
    }
    function clearDone() {
        root.post("/api/todo", { action: "clear_done" });
    }

    function modeAvailable(m) {
        var t = root.envTools;
        if (m === "bluesun")
            return !!t.hyprsunset;
        if (m === "dnd")
            return !!t.makoctl;
        if (m === "lite" || m === "gaming")
            return !!t.hyprland;
        return true;
    }
    function modeHint(m) {
        if (m === "bluesun" && !root.envTools.hyprsunset)
            return "hyprsunset non installé — sudo pacman -S hyprsunset";
        if (m === "dnd" && !root.envTools.makoctl)
            return "mako absent";
        if ((m === "lite" || m === "gaming") && !root.envTools.hyprland)
            return "session Hyprland absente (hyprctl injoignable)";
        return "";
    }
    function toggleMode(m) {
        if (!root.modeAvailable(m))
            return;
        // État EFFECTIF : pour la lumière bleue, hyprsunset peut déjà tourner
        // sans que la sidebar l'ait lancé → un clic doit alors l'ÉTEINDRE,
        // pas le relancer.
        var actif = !!root.modes[m];
        if (m === "bluesun")
            actif = actif || !!root.envTools.hyprsunset_running;
        root.post("/api/modes", { mode: m, on: !actif, kelvin: root.kelvin });
    }

    function startTimer(sec) {
        root.post("/api/timer", { action: "start", seconds: sec });
    }

    // ── Fermeture animée puis sortie du process ──────────────────────────
    function close() {
        console.log("[sidebar] close() appelé — grabArmed=" + root.grabArmed
                    + " grabFailed=" + root.grabFailed + " opened=" + root.opened);
        if (!root.opened)
            return;
        root.opened = false;
        quitTimer.restart();
    }

    // ── Timers ────────────────────────────────────────────────────────────
    Timer {
        id: openTimer

        interval: 30
        running: false
        repeat: false
        onTriggered: root.opened = true
    }
    Timer {
        id: quitTimer

        interval: 240          // durée de l'animation de sortie
        running: false
        repeat: false
        onTriggered: Qt.quit()
    }
    Timer {
        id: pollTimer

        interval: 500
        running: true
        repeat: true
        onTriggered: root.refreshState()
    }
    Timer {
        id: paletteTimer

        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refreshPalette()
    }
    // Détection des outils (hyprsunset, mako…) : rafraîchie régulièrement,
    // sinon un paquet installé APRÈS l'ouverture du panneau restait vu comme
    // « non installé » jusqu'au prochain lancement.
    Timer {
        id: envTimer

        interval: 10000
        running: true
        repeat: true
        onTriggered: root.refreshEnv()
    }

    Timer {
        id: extrasTimer

        interval: 3000
        running: true
        repeat: true
        onTriggered: root.refreshExtras()
    }
    Timer {
        id: kelvinDebounce

        interval: 300
        running: false
        repeat: false
        onTriggered: {
            if (root.modes.bluesun)
                root.post("/api/modes", { mode: "bluesun", on: true,
                                          kelvin: root.kelvin });
        }
    }
    Timer {
        id: flashTimer

        interval: 6000
        running: false
        repeat: false
        onTriggered: root.flash = false
    }

    // Focus clavier rendu au compositeur à la fermeture : la fenêtre est
    // détruite (Qt.quit) donc le focus repart tout seul côté Hyprland.
    // Escape ferme, où que soit le curseur dans le panneau.
    Shortcut {
        sequence: "Escape"
        onActivated: root.close()
    }

    // Grab clavier (hyprland_focus_grab_v1) : permet au panneau de capter le
    // clavier (saisie to-do, Échap) tant que le compositeur l'accorde.
    // Il N'EST PLUS utilisé pour fermer au clic extérieur : sur Hyprland 0.56.2
    // le grab est perdu au bout de ~1 s même sans clic (une autre app prend le
    // focus), et l'ancien `onCleared: root.close()` fermait donc le panneau
    // tout seul. Fermeture = Échap ou SUPER+U.
    // SASQUATCH_SIDEBAR_NOGRAB=1 : ne demande aucun grab (captures, CI).
    property bool grabArmed: false
    property bool grabFailed: false

    Timer {
        id: grabArmTimer

        interval: 1500
        running: false
        repeat: false
        onTriggered: root.grabArmed = true
    }

    HyprlandFocusGrab {
        windows: [root]
        active: Quickshell.env("SASQUATCH_SIDEBAR_NOGRAB") !== "1" && !root.grabFailed
        onActiveChanged: {
            if (active) {
                grabArmTimer.restart();
            } else {
                grabArmTimer.stop();
                root.grabArmed = false;
            }
        }
        // ⚠️ NE PAS fermer sur `cleared`. Mesuré sur ce Hyprland 0.56.2 :
        // le grab est perdu au bout de ~1 s même sans clic (changement de focus
        // par une autre app), ce qui fermait le panneau tout seul — symptôme
        // « SUPER+U ouvre puis ça disparaît ». Fermeture = Échap ou SUPER+U.
        // (Le grab reste demandé : il sert au clavier tant qu'il tient.)
        onCleared: {
            root.grabArmed = false;
        }
    }

    Component.onCompleted: {
        root.refreshPalette();
        root.refreshEnv();
        root.refreshState();
        root.refreshExtras();
        openTimer.start();
        // Focus clavier : le panneau prend le focus (focusable: true) et le
        // champ de saisie de la to-do le reçoit → on tape une tâche dès
        // l'ouverture, sans clic. Échap ferme dans tous les cas. À la
        // fermeture le process Quickshell se termine, donc le focus retourne
        // à la fenêtre précédente côté Hyprland (rien à rendre à la main).
        if (root.shellFocus)
            inputTodo.forceActiveFocus();
    }

    // ── Feuille (glissement + fondu) ──────────────────────────────────────
    // Ombre portée : déclarée AVANT la feuille pour passer dessous (en QML un
    // enfant, même avec z négatif, se dessine au-dessus de son parent).
    Rectangle {
        id: sheetShadow

        x: sheet.x + 2
        y: sheet.y + 10
        width: sheet.width - 4
        height: sheet.height - 12
        radius: 22
        color: root.glassShadow
        opacity: sheet.opacity * 0.9
    }

    Rectangle {
        id: sheet

        width: root.width
        height: root.height
        x: root.opened ? 0 : root.width + 6
        opacity: root.opened ? 1 : 0
        radius: 18
        // Panneau = verre le plus clair et le plus opaque (le fond)
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.glassBg }
            GradientStop { position: 1.0; color: root.glassBgDeep }
        }
        border.width: 1
        border.color: root.glassBorder

        Behavior on x {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        // Liseré clair : 1 px qui « accroche la lumière » sur le verre
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            height: 1
            color: root.rgba(root.cText, 0.16)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ── En-tête ───────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "SASQUATCH"
                    color: root.cText
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 2
                }
                Text {
                    text: root.serverOk ? (root.paletteLive ? "· thème live" : "· démarrage")
                                        : "· backend HS"
                    color: root.serverOk ? root.cTextDim : root.cHot
                    font.pixelSize: 9
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: Qt.formatDateTime(new Date(), "HH:mm")
                    color: root.cTextDim
                    font.pixelSize: 11
                }
                // croix de fermeture
                GlassButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    radiusPx: 13
                    glyph: "✕"
                    baseColor: root.glassBtn
                    accentColor: root.cHot
                    fgText: root.cText
                    highlightColor: root.cText
                    onClicked: root.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(root.cTextDim.r, root.cTextDim.g, root.cTextDim.b, 0.2)
            }

            // ── Corps défilant ────────────────────────────────────────────
            Flickable {
                id: body

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: bodyCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: body.contentHeight > body.height ? ScrollBar.AsNeeded
                                                             : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: bodyCol

                    width: body.width
                    spacing: 10

                    // ═══ MODES ════════════════════════════════════════════
                    Section {
                        title: "MODES"
                        order: 0
                        fgText: root.cText
                        fgDim: root.cTextDim
                        glassColor: root.glassCard
                        borderColor: root.accentLift
                        shadowColor: root.cOverlay

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 8
                            rowSpacing: 8

                            Pill {
                                glyph: "🪶"
                                label: "Allégé"
                                on: !!root.modes.lite
                                unavailable: !root.modeAvailable("lite")
                                hint: root.modeHint("lite")
                                accentColor: root.accentLift
                                baseColor: root.glassBtn
                                fgText: root.cText
                                fgDim: root.cTextDim
                                warnColor: root.cWarn
                                highlightColor: root.cText
                                onToggled: root.toggleMode("lite")
                            }
                            Pill {
                                glyph: "🎮"
                                label: "Gaming"
                                on: !!root.modes.gaming
                                unavailable: !root.modeAvailable("gaming")
                                hint: root.modeHint("gaming")
                                accentColor: root.accent2Lift
                                baseColor: root.glassBtn
                                fgText: root.cText
                                fgDim: root.cTextDim
                                warnColor: root.cWarn
                                highlightColor: root.cText
                                onToggled: root.toggleMode("gaming")
                            }
                            Pill {
                                glyph: "🌙"
                                label: "Lumière bleue"
                                // ON si la sidebar l'a activé OU si hyprsunset
                                // tourne déjà (lancé à la main, service…).
                                on: !!root.modes.bluesun || !!root.envTools.hyprsunset_running
                                unavailable: !root.modeAvailable("bluesun")
                                hint: root.modeHint("bluesun")
                                accentColor: root.accentLift
                                baseColor: root.glassBtn
                                fgText: root.cText
                                fgDim: root.cTextDim
                                warnColor: root.cWarn
                                highlightColor: root.cText
                                onToggled: root.toggleMode("bluesun")
                            }
                            Pill {
                                glyph: "🔕"
                                label: "Ne pas déranger"
                                on: !!root.modes.dnd
                                unavailable: !root.modeAvailable("dnd")
                                hint: root.modeHint("dnd")
                                accentColor: root.cHot
                                baseColor: root.glassBtn
                                fgText: root.cText
                                fgDim: root.cTextDim
                                warnColor: root.cWarn
                                highlightColor: root.cText
                                onToggled: root.toggleMode("dnd")
                            }
                            Pill {
                                glyph: "☕"
                                label: "Anti-veille"
                                on: !!root.modes.nosleep
                                accentColor: root.cGood
                                baseColor: root.glassBtn
                                fgText: root.cText
                                fgDim: root.cTextDim
                                warnColor: root.cWarn
                                highlightColor: root.cText
                                onToggled: root.toggleMode("nosleep")
                            }
                            Pill {
                                glyph: "🖼"
                                label: "Fond suivant"
                                unavailable: !root.envTools.hyprland
                                hint: "session Hyprland absente"
                                accentColor: root.accent2Lift
                                baseColor: root.glassBtn
                                fgText: root.cText
                                fgDim: root.cTextDim
                                warnColor: root.cWarn
                                highlightColor: root.cText
                                onToggled: root.post("/api/action", { name: "wallpaper_next" })
                            }
                        }

                        // Température de la lumière bleue (hyprsunset)
                        SliderRow {
                            label: "Température couleur"
                            suffix: " K"
                            from: 2500
                            to: 6500
                            value: root.kelvin
                            enabledControl: !!root.envTools.hyprsunset
                            fgText: root.cText
                            fgDim: root.cTextDim
                            accentColor: root.accentLift
                            accentColor2: root.accent2Lift
                            onMoved: function (v) {
                                // Anti-rebond : hyprsunset ne prend la température
                                // qu'au lancement, donc chaque envoi relance le
                                // process. On regroupe les mouvements (300 ms).
                                root.kelvin = Math.round(v / 50) * 50;
                                kelvinDebounce.restart();
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.lastError !== ""
                            text: "⚠ " + root.lastError
                            color: root.cWarn
                            font.pixelSize: 9
                            wrapMode: Text.Wrap
                        }
                    }

                    // ═══ TO-DO ════════════════════════════════════════════
                    Section {
                        order: 1
                        title: "À FAIRE · " + root.counts.remaining
                               + (root.counts.remaining > 1 ? " restantes" : " restante")
                               + " / " + root.counts.total
                        fgText: root.cText
                        fgDim: root.cTextDim
                        glassColor: root.glassCard
                        borderColor: root.accentLift
                        shadowColor: root.cOverlay

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                height: 30
                                radius: 8
                                color: root.glassInset
                                border.width: 1
                                border.color: root.glassBorder

                                TextField {
                                    id: inputTodo

                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    placeholderText: "Nouvelle tâche…"
                                    placeholderTextColor: root.cTextDim
                                    color: root.cText
                                    font.pixelSize: 11
                                    background: null
                                    leftPadding: 0
                                    text: root.newTodoText
                                    onTextChanged: root.newTodoText = text
                                    onAccepted: root.addTodo()
                                    Keys.onEscapePressed: root.close()
                                }
                            }
                            GlassButton {
                                implicitWidth: 30
                                implicitHeight: 30
                                radiusPx: 10
                                glyph: "+"
                                baseColor: root.glassBtn
                                accentColor: root.accentLift
                                fgText: root.cText
                                highlightColor: root.cText
                                onClicked: root.addTodo()
                            }
                        }

                        ListView {
                            id: todoList

                            Layout.fillWidth: true
                            height: Math.min(contentHeight, 190)
                            visible: height > 0
                            clip: true
                            spacing: 2
                            model: {
                                var out = [];
                                for (var i = 0; i < root.todo.length; i++) {
                                    if (root.todo[i].done === root.showDone)
                                        out.push(root.todo[i]);
                                }
                                return out;
                            }
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            delegate: RowLayout {
                                required property var modelData
                                id: todoRow
                                width: todoList.width
                                height: 26
                                spacing: 7

                                // case à cocher
                                Rectangle {
                                    width: 14
                                    height: 14
                                    radius: 4
                                    color: todoRow.modelData.done ? Qt.rgba(root.cGood.r, root.cGood.g,
                                                                    root.cGood.b, 0.9)
                                                         : "transparent"
                                    border.width: 1
                                    border.color: todoRow.modelData.done ? root.cGood : root.cTextDim
                                    Text {
                                        anchors.centerIn: parent
                                        visible: todoRow.modelData.done
                                        text: "✓"
                                        color: root.cBgSolid
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.todoToggle(todoRow.modelData.id)
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: todoRow.modelData.text
                                    elide: Text.ElideRight
                                    color: todoRow.modelData.done ? root.cTextDim : root.cText
                                    font.pixelSize: 11
                                    font.strikeout: todoRow.modelData.done
                                }
                                Text {
                                    visible: todoRow.modelData.prio === "high" && !todoRow.modelData.done
                                    text: "!"
                                    color: root.cHot
                                    font.pixelSize: 11
                                    font.bold: true
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.todoPrio(todoRow.modelData.id)
                                    }
                                }
                                Text {
                                    text: "🗑"
                                    font.pixelSize: 10
                                    opacity: delMa.containsMouse ? 1.0 : 0.45
                                    MouseArea {
                                        id: delMa

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.todoDel(todoRow.modelData.id)
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: root.showDone ? "▲ actives"
                                                      : "▼ faites (" + root.counts.done + ")"
                                color: root.cTextDim
                                font.pixelSize: 9
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.showDone = !root.showDone
                                }
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: root.counts.done > 0
                                text: "effacer faites"
                                color: root.cHot
                                font.pixelSize: 9
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.clearDone()
                                }
                            }
                        }
                    }

                    // ═══ TEMPS ════════════════════════════════════════════
                    Section {
                        title: "TEMPS"
                        order: 2
                        hero: true
                        glassColor: root.glassHero
                        fgText: root.cText
                        fgDim: root.cTextDim
                        borderColor: root.accentLift
                        shadowColor: root.cOverlay

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [{ k: "chrono", l: "Chrono" },
                                        { k: "timer", l: "Timer" },
                                        { k: "alarme", l: "Alarme" }]
                                delegate: GlassButton {
                                    required property var modelData
                                    id: tabRow
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    radiusPx: 9
                                    label: tabRow.modelData.l
                                    on: root.timeTab === tabRow.modelData.k
                                    baseColor: root.glassBtn
                                    accentColor: root.accentLift
                                    fgText: root.cText
                                    highlightColor: root.cText
                                    onClicked: root.timeTab = tabRow.modelData.k
                                }
                            }
                        }

                        // ── Chrono ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.timeTab === "chrono"
                            spacing: 6

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: (root.st.stopwatch && root.st.stopwatch.text)
                                      ? root.st.stopwatch.text : "00:00"
                                color: root.cText
                                font.pixelSize: 30
                                font.bold: true
                                font.family: "monospace"
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: [{ a: "start", l: "▶" },
                                            { a: "pause", l: "⏸" },
                                            { a: "reset", l: "⟲" }]
                                    delegate: GlassButton {
                                        required property var modelData
                                        id: chronoBtn
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        radiusPx: 10
                                        glyph: chronoBtn.modelData.l
                                        baseColor: root.glassBtn
                                        accentColor: root.accentLift
                                        fgText: root.cText
                                        highlightColor: root.cText
                                        onClicked: root.post("/api/stopwatch",
                                                             { action: chronoBtn.modelData.a })
                                    }
                                }
                            }
                        }

                        // ── Timer ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.timeTab === "timer"
                            spacing: 6

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: (root.st.timer && root.st.timer.text)
                                      ? root.st.timer.text : "00:00"
                                color: (root.st.timer && root.st.timer.running)
                                       ? root.cAccent2 : root.cText
                                font.pixelSize: 30
                                font.bold: true
                                font.family: "monospace"
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: [5, 10, 25, 45]
                                    delegate: GlassButton {
                                        required property var modelData
                                        id: presetBtn
                                        Layout.fillWidth: true
                                        implicitHeight: 26
                                        radiusPx: 9
                                        label: presetBtn.modelData + "m"
                                        baseColor: root.glassBtn
                                        accentColor: root.accent2Lift
                                        fgText: root.cText
                                        highlightColor: root.cText
                                        onClicked: root.startTimer(presetBtn.modelData * 60)
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 8
                                    color: root.glassInset
                                    border.width: 1
                                    border.color: root.glassBorder
                                    TextField {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        placeholderText: "minutes libres…"
                                        placeholderTextColor: root.cTextDim
                                        color: root.cText
                                        font.pixelSize: 10
                                        background: null
                                        leftPadding: 0
                                        text: root.newTimerMin
                                        validator: IntValidator { bottom: 1; top: 1440 }
                                        onTextChanged: root.newTimerMin = text
                                        onAccepted: {
                                            var m = parseInt(text);
                                            if (m > 0)
                                                root.startTimer(m * 60);
                                        }
                                    }
                                }
                                Repeater {
                                    model: [{ a: "start", l: "▶" },
                                            { a: "pause", l: "⏸" },
                                            { a: "reset", l: "⟲" }]
                                    delegate: GlassButton {
                                        required property var modelData
                                        id: timerBtn
                                        implicitWidth: 30
                                        implicitHeight: 30
                                        radiusPx: 10
                                        glyph: timerBtn.modelData.l
                                        baseColor: root.glassBtn
                                        accentColor: root.accentLift
                                        fgText: root.cText
                                        highlightColor: root.cText
                                        onClicked: {
                                            var b = { action: timerBtn.modelData.a };
                                            if (timerBtn.modelData.a === "start"
                                                    && root.newTimerMin !== "")
                                                b.seconds = parseInt(root.newTimerMin) * 60;
                                            root.post("/api/timer", b);
                                        }
                                    }
                                }
                            }
                        }

                        // ── Alarme ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.timeTab === "alarme"
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 8
                                    color: root.glassInset
                                    border.width: 1
                                    border.color: root.glassBorder
                                    TextField {
                                        id: hhField

                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        placeholderText: "HH"
                                        placeholderTextColor: root.cTextDim
                                        color: root.cText
                                        font.pixelSize: 12
                                        horizontalAlignment: TextInput.AlignHCenter
                                        background: null
                                        leftPadding: 0
                                        validator: IntValidator { bottom: 0; top: 23 }
                                        onTextChanged: root.newAlarmHH = text
                                    }
                                }
                                Text {
                                    text: ":"
                                    color: root.cTextDim
                                    font.pixelSize: 13
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 8
                                    color: root.glassInset
                                    border.width: 1
                                    border.color: root.glassBorder
                                    TextField {
                                        id: mmField

                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        placeholderText: "MM"
                                        placeholderTextColor: root.cTextDim
                                        color: root.cText
                                        font.pixelSize: 12
                                        horizontalAlignment: TextInput.AlignHCenter
                                        background: null
                                        leftPadding: 0
                                        validator: IntValidator { bottom: 0; top: 59 }
                                        onTextChanged: root.newAlarmMM = text
                                    }
                                }
                                GlassButton {
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    radiusPx: 10
                                    glyph: "＋"
                                    baseColor: root.glassBtn
                                    accentColor: root.accentLift
                                    fgText: root.cText
                                    highlightColor: root.cText
                                    onClicked: {
                                        var h = parseInt(hhField.text);
                                        var m = parseInt(mmField.text);
                                        if (isNaN(h) || isNaN(m))
                                            return;
                                        root.post("/api/alarm", {
                                            action: "add",
                                            hhmm: (h < 10 ? "0" : "") + h + ":"
                                                  + (m < 10 ? "0" : "") + m
                                        });
                                        hhField.text = "";
                                        mmField.text = "";
                                    }
                                }
                            }

                            Repeater {
                                model: root.alarms
                                delegate: RowLayout {
                                    required property var modelData
                                    id: alarmRow
                                    Layout.fillWidth: true
                                    height: 22
                                    Text {
                                        text: "⏰"
                                        font.pixelSize: 10
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: alarmRow.modelData.hhmm
                                        color: root.cText
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                    Text {
                                        text: "✕"
                                        color: root.cHot
                                        font.pixelSize: 10
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.post("/api/alarm",
                                                                 { action: "del",
                                                                   id: alarmRow.modelData.id })
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: root.alarms.length === 0
                                text: "aucune alarme"
                                color: root.cTextDim
                                font.pixelSize: 9
                            }
                        }
                    }

                    // ═══ SYSTÈME ══════════════════════════════════════════
                    Section {
                        title: "SYSTÈME"
                        order: 3
                        fgText: root.cText
                        fgDim: root.cTextDim
                        glassColor: root.glassCard
                        borderColor: root.accentLift
                        shadowColor: root.cOverlay

                        SliderRow {
                            label: "Volume"
                            suffix: " %"
                            value: root.volume
                            enabledControl: !!root.envTools.wpctl
                            fgText: root.cText
                            fgDim: root.cTextDim
                            accentColor: root.accent2Lift
                            accentColor2: root.accent2Lift
                            onMoved: function (v) {
                                root.volume = Math.round(v);
                                root.post("/api/system", { target: "volume", value: root.volume });
                            }
                        }
                        SliderRow {
                            label: "Luminosité"
                            suffix: " %"
                            value: root.brightness
                            enabledControl: !!root.envTools.brightnessctl
                            fgText: root.cText
                            fgDim: root.cTextDim
                            accentColor: root.accentLift
                            accentColor2: root.accent2Lift
                            onMoved: function (v) {
                                root.brightness = Math.round(v);
                                root.post("/api/system", { target: "brightness",
                                                          value: root.brightness });
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            GlassButton {
                                implicitWidth: 30
                                implicitHeight: 26
                                radiusPx: 9
                                glyph: "⏮"
                                unavailable: !root.envTools.playerctl
                                baseColor: root.glassBtn
                                accentColor: root.accentLift
                                fgText: root.cText
                                highlightColor: root.cText
                                onClicked: root.post("/api/media", { action: "prev" })
                            }
                            GlassButton {
                                implicitWidth: 30
                                implicitHeight: 26
                                radiusPx: 9
                                glyph: "⏯"
                                unavailable: !root.envTools.playerctl
                                baseColor: root.glassBtn
                                accentColor: root.accentLift
                                fgText: root.cText
                                highlightColor: root.cText
                                onClicked: root.post("/api/media", { action: "playpause" })
                            }
                            GlassButton {
                                implicitWidth: 30
                                implicitHeight: 26
                                radiusPx: 9
                                glyph: "⏭"
                                unavailable: !root.envTools.playerctl
                                baseColor: root.glassBtn
                                accentColor: root.accentLift
                                fgText: root.cText
                                highlightColor: root.cText
                                onClicked: root.post("/api/media", { action: "next" })
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.player.title
                                      ? (root.player.title + " — " + (root.player.artist || ""))
                                      : (root.envTools.playerctl ? "rien en lecture"
                                                                 : "playerctl absent")
                                color: root.cTextDim
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                        }

                        // Séparateur + titre : les entrées presse-papier
                        // arrivaient sans étiquette, collées au lecteur média.
                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: root.rgba(root.cTextDim, 0.18)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.clips.length > 0 ? "PRESSE-PAPIER" : "PRESSE-PAPIER · vide"
                            color: root.cTextDim
                            font.pixelSize: 8
                            font.letterSpacing: 0.8
                            opacity: 0.75
                        }

                        Repeater {
                            model: root.clips
                            delegate: Rectangle {
                                required property var modelData
                                id: clipRow
                                Layout.fillWidth: true
                                implicitHeight: 22
                                radius: 8
                                color: clipMa.containsMouse
                                       ? root.rgba(root.cText, 0.07) : "transparent"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 90
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    spacing: 6

                                    Text {
                                        text: "📋"
                                        font.pixelSize: 9
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: clipRow.modelData.preview
                                        color: root.cTextDim
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: clipMa

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.post("/api/action",
                                                         { name: "clipboard_copy",
                                                           id: clipRow.modelData.id })
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            GlassButton {
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radiusPx: 10
                                label: "🔒 verrouiller"
                                baseColor: root.glassBtn
                                accentColor: root.accentLift
                                fgText: root.cText
                                highlightColor: root.cText
                                onClicked: root.post("/api/action", { name: "lock" })
                            }
                            GlassButton {
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radiusPx: 10
                                label: "📷 capture"
                                baseColor: root.glassBtn
                                accentColor: root.accentLift
                                fgText: root.cText
                                highlightColor: root.cText
                                onClicked: root.post("/api/action", { name: "screenshot" })
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        height: 4
                    }
                }
            }

            // ── Flash de fin de timer / alarme ────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: root.flash ? 34 : 0
                visible: height > 0
                radius: 11
                // verre coloré : la teinte good, jamais en aplat opaque
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.rgba(root.cGood, 0.88) }
                    GradientStop { position: 1.0; color: root.rgba(Qt.darker(root.cGood, 1.12), 0.78) }
                }
                border.width: 1
                border.color: root.rgba(root.cGood, 0.9)

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: 1
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    height: 1
                    color: root.rgba(root.cText, 0.22)
                }

                Text {
                    anchors.centerIn: parent
                    text: root.flashMsg
                    color: root.cBgSolid
                    font.pixelSize: 11
                    font.bold: true
                }
                Behavior on height {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
