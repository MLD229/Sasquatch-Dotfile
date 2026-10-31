// BarPalette.qml — singleton : palette générée depuis le wallpaper (CC 8765).
//
// Source : GET http://127.0.0.1:8765/api/palette toutes les 2 s (brief §5).
// Aucune couleur en dur hors les valeurs de SECOURS ci-dessous (commentées).
// Les valeurs de secours sont les défauts de cc/palette.py : si le backend est
// absent au démarrage, la barre reste lisible au lieu d'être noire sur noire.
pragma Singleton
import QtQuick

QtObject {
    id: pal

    // ── Secours (remplacés dès la 1re réponse de l'API) ───────────────────
    property color bg: "#151515"        // secours = cc/palette.py
    property color bgSolid: "#151515"
    property color card: "#2d2d2d"
    property color cardSolid: "#2d2d2d"
    property color text: "#d1d1d1"
    property color textDim: "#7c7c7c"
    property color accentRaw: "#dddddd"
    property color accent2Raw: "#44dddddd"
    property color overlay: "#99021933"
    property color good: "#a6e3a1"
    property color warn: "#f9e2af"
    property color hot: "#f38ba8"

    property bool live: false
    property string lastError: ""
    property int revision: 0

    readonly property string apiBase: "http://127.0.0.1:8765"

    // ── Luminance relative (sRGB simplifié, suffisant pour un seuil) ──────
    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }

    // Brief §9 : si luminance(accent) est à moins de 15 % de celle de bg,
    // tirer l'accent vers la couleur de texte. Cas réel : wallpaper monochrome
    // → accent #dddddd sur fond #151515 (écart correct) mais wallpaper clair
    // → accent quasi identique au fond, états actifs invisibles.
    readonly property color accent: {
        var l = Math.abs(pal.luminance(pal.accentRaw) - pal.luminance(pal.bg));
        if (l >= 0.15)
            return pal.accentRaw;
        var t = 0.55;
        return Qt.rgba(pal.accentRaw.r * (1 - t) + pal.text.r * t,
                       pal.accentRaw.g * (1 - t) + pal.text.g * t,
                       pal.accentRaw.b * (1 - t) + pal.text.b * t,
                       1.0);
    }
    // accent2 arrive avec son alpha (#44dddddd) : on expose le RGB seul.
    readonly property color accent2: Qt.rgba(pal.accent2Raw.r, pal.accent2Raw.g,
                                             pal.accent2Raw.b, 1.0)

    // ── Surfaces dérivées (aucun hex : tout vient des tokens ci-dessus) ───
    // Brief §3 : c'est le FOND qui devient quasi invisible, jamais le texte.
    // Les alphas viennent toutes de bar.json (appearance.*), rien en dur ici.
    function a(c, alpha) {
        return Qt.rgba(c.r, c.g, c.b, Math.max(0, Math.min(1, alpha)));
    }
    readonly property color barBg: pal.a(pal.bg, Config.panelAlpha)
    // Bloc AU REPOS : blockAlpha (0 = invisible). C'est cette ligne qui enlève
    // les pilules opaques : au repos on ne voit que le glyphe/le texte.
    readonly property color block: pal.a(pal.card, Config.blockAlpha)
    // Survol / actif : la pilule apparaît (alphas légers, bar.json).
    readonly property color blockHover: pal.a(pal.card, Config.hoverAlpha)
    readonly property color blockActive: pal.a(pal.accent, Config.activeAlpha)
    // Survol d'une LIGNE dans un popup : surface déjà opaque (cardAlpha), donc
    // un fond de carte à alpha faible serait invisible. Dérivé du texte, pas
    // une couleur en dur, et indépendant de hoverAlpha (qui est celui de la
    // barre, désormais très léger).
    readonly property color rowHover: pal.a(pal.text, 0.10)
    // Bordure du panneau : quasi invisible au repos (0-0.15).
    readonly property color border: pal.a(pal.card, Config.borderAlpha)
    // Bordure de pilule : seulement au survol / actif (brief §3).
    readonly property color borderHover: pal.a(pal.text, Config.borderHoverAlpha)
    readonly property color accentBar: pal.accent
    // Fond des pastilles de secours (icône d'app non résolue) : accent très dilué.
    readonly property color accentSoft: pal.a(pal.accent, 0.22)

    function refresh() {
        var xhr = new XMLHttpRequest();
        xhr.timeout = 2500;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status < 200 || xhr.status >= 300) {
                pal.lastError = "palette: HTTP " + xhr.status;
                console.warn("bar: /api/palette HTTP " + xhr.status);
                return;
            }
            var p = null;
            try {
                p = JSON.parse(xhr.responseText);
            } catch (e) {
                pal.lastError = "palette: JSON invalide";
                return;
            }
            if (!p || !p.bg)
                return;
            if (p.bg) pal.bg = p.bg;
            if (p.bgSolid) pal.bgSolid = p.bgSolid;
            if (p.card) pal.card = p.card;
            if (p.cardSolid) pal.cardSolid = p.cardSolid;
            if (p.text) pal.text = p.text;
            if (p.textDim) pal.textDim = p.textDim;
            if (p.accent) pal.accentRaw = p.accent;
            if (p.accent2) pal.accent2Raw = p.accent2;
            if (p.overlay) pal.overlay = p.overlay;
            if (p.good) pal.good = p.good;
            if (p.warn) pal.warn = p.warn;
            if (p.hot) pal.hot = p.hot;
            if (!pal.live)
                console.info("bar: palette reçue (accent " + p.accent + ", bg " + p.bg + ")");
            pal.live = true;
            pal.lastError = "";
            pal.revision += 1;
        };
        xhr.open("GET", pal.apiBase + "/api/palette");
        xhr.send(null);
    }

    property Timer poll: Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: pal.refresh()
    }
}
