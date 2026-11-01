// Theme.qml — singleton : palette (GET /api/palette) + tokens verre + texte adaptatif.
//
// Règle (brief §3) : AUCUN hex dans les widgets, jamais de font.family en dur.
// Toutes les teintes dérivent de la palette dynamique ; si le serveur ne
// répond pas au démarrage, le repli vient de SystemPalette (thème Qt), pas
// d'une couleur écrite en dur.
// Nombres imposés (brief §3) : rayons 18/16/10, espacement 14, bordure 0.35.
// Transparence (brief transparence) : remplissage de carte TRÈS LÉGER
// (0.06–0.10, hero 0.05), aucun flou, aucun filet clair, aucun contour au
// repos. `style.blur` reste dans le schéma mais n'est PLUS appliqué.
pragma Singleton
import QtQuick
import Sasquatch.Widgets 1.0

QtObject {
    id: theme

    // ── Palette brute ─────────────────────────────────────────────────────
    property var pal: ({})
    property var sysPal: SystemPalette { colorGroup: SystemPalette.Active }

    function pick(key, fallback) {
        var v = theme.pal ? theme.pal[key] : undefined;
        return (typeof v === "string" && v.length > 0) ? v : fallback;
    }

    readonly property color bg: theme.pick("bg", theme.sysPal.window)
    readonly property color bgSolid: theme.pick("bgSolid", theme.sysPal.window)
    readonly property color card: theme.pick("card", theme.sysPal.window)
    readonly property color cardSolid: theme.pick("cardSolid", theme.sysPal.window)
    readonly property color text: theme.pick("text", theme.sysPal.windowText)
    readonly property color textDim: theme.pick("textDim", theme.sysPal.windowText)
    readonly property color accent: theme.pick("accent", theme.sysPal.highlight)
    readonly property color accent2: theme.pick("accent2", theme.sysPal.highlight)
    readonly property color overlay: theme.pick("overlay", theme.sysPal.shadow)
    readonly property color good: theme.pick("good", theme.sysPal.highlight)
    readonly property color warn: theme.pick("warn", theme.sysPal.highlight)
    readonly property color hot: theme.pick("hot", theme.sysPal.highlight)

    // ── Tokens verre (brief §3, nombres imposés) ──────────────────────────
    readonly property color glassBase: Qt.lighter(theme.bgSolid, 1.18)
    readonly property color glassCard: Qt.darker(theme.card, 1.20)
    readonly property color glassBtn: Qt.darker(theme.card, 1.55)
    // Bordure : uniquement pour les éléments INTERNES d'un widget (pilules,
    // champs) en survol/focus. La carte elle-même n'a plus de contour.
    readonly property color border: theme.a(theme.accent, 0.30)
    readonly property color halo: theme.a(theme.accent, 0.32)
    // Rebord flou et filet clair RETIRÉS (brief transparence) : plus de
    // MultiEffect, plus de trait 1 px en haut des cartes.

    readonly property real alphaPanel: 0.36
    // Remplissage de carte : très léger, le fond ne doit pas former de plaque.
    readonly property real alphaCard: 0.08
    readonly property real alphaHero: 0.05
    readonly property real alphaBtn: 0.62
    // Bornes du réglage `style.alpha` (le Studio et widgets_json.py lisent les
    // mêmes bornes dans registry.json).
    readonly property real alphaMin: 0.03
    readonly property real alphaMax: 0.35

    readonly property int radiusPanel: 18
    readonly property int radiusCard: 16
    readonly property int radiusBtn: 10
    readonly property int spacing: 14
    // Conservé pour la compatibilité du schéma : `style.blur` n'est plus
    // appliqué nulle part (aucun flou dans l'interface).
    readonly property int blurDefault: 9

    // Color = couleur de base + alpha demandé (jamais un hex).
    function a(c, alpha) {
        return Qt.rgba(c.r, c.g, c.b, alpha);
    }

    // ── Luminance / mélange (correctif média : cava lisible) ──────────────
    // Luminance relative 0..1 (même pondération que WCAG 2.x).
    function luminance(c) {
        if (!c)
            return 0;
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }

    // Mélange linéaire de deux couleurs ; `t` = part de c2 (0..1).
    function mix(c1, c2, t) {
        var k = Math.max(0, Math.min(1, t));
        return Qt.rgba(c1.r + (c2.r - c1.r) * k,
                       c1.g + (c2.g - c1.g) * k,
                       c1.b + (c2.b - c1.b) * k,
                       1.0);
    }

    // Seuil sous lequel un accent ne porte plus une barre de cava.
    readonly property real vizMinLum: 0.30
    readonly property real vizMix: 0.55

    // Teinte du cava : accent sombre dérivé vers le texte (55 %). Sur ce rice
    // l'accent est très sombre, les barres disparaissaient sur la carte.
    readonly property color vizA: theme.luminance(theme.accent) < theme.vizMinLum
                                  ? theme.mix(theme.accent, theme.text, theme.vizMix)
                                  : theme.accent
    readonly property color vizB: theme.luminance(theme.accent2) < theme.vizMinLum
                                  ? theme.mix(theme.accent2, theme.text, theme.vizMix)
                                  : theme.accent2
    // Opacité des barres quand un morceau joue (correctif média).
    readonly property real vizAlpha: 0.9

    // Remplissage d'une carte : verre dérivé de `card`, alpha du widget.
    function fill(alpha) {
        return theme.a(theme.glassCard, alpha);
    }

    function panelFill(alpha) {
        return theme.a(theme.glassBase, alpha);
    }

    // ── Valeurs de style effectives (bornées par le registre, clampées ici) ─
    function clamp(v, lo, hi) {
        if (typeof v !== "number" || !isFinite(v))
            return lo;
        return Math.max(lo, Math.min(hi, v));
    }

    function cardAlpha(style, variant) {
        var s = (style && typeof style === "object") ? style : ({});

        if (typeof s.alpha === "number" && isFinite(s.alpha))
            return Math.max(theme.alphaMin, Math.min(theme.alphaMax, s.alpha));
        return theme.cardAlphaFor(variant);
    }

    function cardAlphaFor(variant) {
        return variant === "hero" ? theme.alphaHero : theme.alphaCard;
    }

    function radiusFor(style) {
        var s = (style && typeof style === "object") ? style : ({});
        return Math.round(theme.clamp(s.radius, theme.radiusCard, 24));
    }

    // `style.blur` n'a plus de lecture : il n'y a aucun flou dans l'interface.
    // La clé reste acceptée par le schéma (widgets_json.py) pour ne pas casser
    // un fichier existant ni le panneau du Studio ; elle est inerte.

    // ── Texte adaptatif (lumgrid, brief §4) ───────────────────────────────
    // /api/wallpaper/lumgrid renvoie 32x18 valeurs 0..1. Fond clair → encre
    // sombre. Si PIL manque ou si le service ne répond pas : values = [] →
    // on garde le texte clair (jamais de crash, brief §4).
    property bool lightWallpaper: false
    property var lumValues: []

    readonly property color ink: theme.lightWallpaper ? Qt.darker(theme.bgSolid, 1.35) : theme.text
    readonly property color inkDim: theme.lightWallpaper ? Qt.darker(theme.bgSolid, 1.10) : theme.textDim

    function readLumgrid(d) {
        if (!d || !d.values || d.values.length === 0) {
            theme.lightWallpaper = false;
            theme.lumValues = [];
            return;
        }
        var sum = 0;
        for (var i = 0; i < d.values.length; ++i)
            sum += d.values[i];
        theme.lumValues = d.values;
        theme.lightWallpaper = (sum / d.values.length) > 0.55;
    }

    // ── Sondes ────────────────────────────────────────────────────────────
    function refreshPalette() {
        Api.get("/api/palette", function (d) {
            if (d && typeof d === "object" && typeof d.accent === "string")
                theme.pal = d;
        });
    }

    function refreshLumgrid() {
        Api.get("/api/wallpaper/lumgrid", function (d) {
            theme.readLumgrid(d);
        });
    }

    property Timer paletteTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: theme.refreshPalette()
    }

    property Timer lumTimer: Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: theme.refreshLumgrid()
    }
}
