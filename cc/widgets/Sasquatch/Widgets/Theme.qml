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
// Quickshell.Io = FileView (lumgrid surveillé, plus aucun timer de luminance).
import Quickshell
import Quickshell.Io
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

    readonly property color ink: theme.text
    readonly property color inkDim: theme.textDim

    // ── Contraste LOCAL (lumgrid) ─────────────────────────────────────────
    // `lightWallpaper` est une moyenne GLOBALE : sur un fond mixte (zone sombre
    // + zone claire) elle impose une encre qui disparaît sur l'autre moitié —
    // mesuré sur le fond « cavalier » : texte sombre lisible sur la brume,
    // illisible sur le bleu nuit. On expose donc la luminance d'une ZONE et une
    // encre calculée par contraste dessus, ce qui rend lisible un widget posé
    // sur un fond clair ET un widget posé sur la zone sombre du MÊME papier
    // peint, sans ajouter le moindre fond.
    readonly property int lumGridW: 32
    readonly property int lumGridH: 18

    function lumAt(fx0, fy0, fx1, fy1) {
        var v = theme.lumValues;
        var gw = theme.lumGridW;
        var gh = theme.lumGridH;
        if (!v || v.length < gw * gh)
            return -1;
        var c0 = Math.max(0, Math.min(gw - 1, Math.floor(fx0 * gw)));
        var c1 = Math.max(0, Math.min(gw - 1, Math.floor(fx1 * gw)));
        var r0 = Math.max(0, Math.min(gh - 1, Math.floor(fy0 * gh)));
        var r1 = Math.max(0, Math.min(gh - 1, Math.floor(fy1 * gh)));
        if (c1 < c0)
            c1 = c0;
        if (r1 < r0)
            r1 = r0;
        var sum = 0;
        var n = 0;
        for (var y = r0; y <= r1; ++y) {
            for (var x = c0; x <= c1; ++x) {
                sum += v[y * gw + x];
                n += 1;
            }
        }
        return (n > 0) ? sum / n : -1;
    }

    function luma(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }

    // ── Encre TEINTÉE (brief encre §A) ────────────────────────────────────
    // Mélange MINIMAL de `base` vers blanc (`light = true`) ou vers noir
    // jusqu'à obtenir `target` d'écart de luminance avec `bgLum`. « Minimal »
    // = on s'arrête DÈS que l'écart est atteint : c'est ce qui garde le
    // maximum de saturation possible, donc l'encre reste colorée au lieu de
    // finir en blanc pur (Qt.lighter poussait jusqu'au neutre).
    // Sonde binaire bornée (8 itérations → pas de boucle non bornée, précision
    // 1/256). Retourne `base` intacte si l'écart est déjà suffisant, ou si la
    // direction demandée ne peut pas atteindre la cible (fond au bout du blanc
    // ou du noir) — l'appelant décide alors du repli.
    function tint(base, bgLum, target, light) {
        if (!base || !(bgLum >= 0))
            return base;
        var tgt = theme.clamp(target, 0, 1);
        if (Math.abs(theme.luma(base) - bgLum) >= tgt)
            return base;
        var goal = light ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(0, 0, 0, 1);
        if (Math.abs(theme.luma(goal) - bgLum) < tgt)
            return base;
        var lo = 0.0;
        var hi = 1.0;
        for (var i = 0; i < 8; ++i) {
            var k = (lo + hi) / 2;
            var probe = Math.abs(theme.luma(theme.mix(base, goal, k)) - bgLum);
            if (probe >= tgt)
                hi = k;
            else
                lo = k;
        }
        var out = theme.mix(base, goal, hi);
        return Qt.rgba(out.r, out.g, out.b, 1.0);
    }

    // Encre lisible sur une luminance donnée : on GARDE la teinte de la palette
    // et on l'éclaircit / l'assombrit jusqu'à l'écart de luminance voulu
    // (0.42 ≈ contraste franc pour du texte, 0.30 pour du texte secondaire).
    function contrastOn(base, bgLum, target, light) {
        if (bgLum === undefined || bgLum === null || bgLum < 0 || !base)
            return base;
        var c = base;
        var guard = 0;
        while (Math.abs(theme.luma(c) - bgLum) < target && guard < 14) {
            c = light ? Qt.lighter(c, 1.28) : Qt.darker(c, 1.28);
            guard += 1;
        }
        return c;
    }

    // Direction de l'encre : on écrit CLAIR sur un fond sombre ou moyen (le
    // texte clair tient mieux sur une illustration colorée), sombre seulement
    // quand le fond est franchement clair. Le seuil à 0.62 évite le cas
    // mesuré « fond à 0.55 » où assombrir donnait un texte noir sur des rochers
    // déjà sombres.
    function wantLight(bgLum) {
        return bgLum < 0.62;
    }

    // ── Teinte conservée : on ne mélange PAS vers blanc/noir ──────────────
    // Mesure sur la palette du moment (#8f707b, chroma 31) : mélanger 25 %
    // d'accent dans le gris de la palette ne donne que 7/255 de chroma — donc
    // encore gris à l'œil, exactement ce que momo refuse. Un mélange vers
    // blanc/noir détruit la chroma par construction. On garde donc TEINTE et
    // SATURATION de l'accent et on ne bouge que la LUMINOSITÉ (HSL) jusqu'à
    // l'écart de luminance voulu.
    function chroma(c) {
        var mx = Math.max(c.r, c.g, c.b);
        var mn = Math.min(c.r, c.g, c.b);
        return (mx - mn) * 255.0;
    }

    // Luminosité HSL qui produit la luminance relative demandée (monotone →
    // dichotomie bornée à 10 itérations).
    function lightnessFor(h, s, targetLuma) {
        var lo = 0.0;
        var hi = 1.0;
        for (var i = 0; i < 10; ++i) {
            var mid = (lo + hi) / 2.0;
            if (theme.luma(Qt.hsla(h, s, mid, 1.0)) < targetLuma)
                lo = mid;
            else
                hi = mid;
        }
        return (lo + hi) / 2.0;
    }

    // Encre COLORÉE : teinte de l'accent, saturation bornée (du texte, pas un
    // néon), luminosité calculée. `minSat` garantit que la couleur se voit même
    // quand l'accent de la palette est presque gris.
    function coloured(base, bgLum, target, minSat, maxSat) {
        if (!(bgLum >= 0) || !base)
            return base;
        if (theme.chroma(base) < 6.0)
            return theme.contrastOn(base, bgLum, target, theme.wantLight(bgLum));
        // Direction : on prend le côté qui a le PLUS de marge (avec une petite
        // préférence pour le clair, qui est le parti pris du thème). Sinon,
        // autour de 0.5–0.6, le clair tombait sur du blanc pur — la teinte
        // disparaissait précisément là où momo la veut.
        var up = 1.0 - bgLum;
        var down = bgLum;
        var light = (up - 0.02) >= down;
        if (light && up < target && down >= target)
            light = false;
        else if (!light && down < target && up >= target)
            light = true;
        var goal = light ? Math.min(1.0, bgLum + target) : Math.max(0.0, bgLum - target);
        // Jamais un extrême pur (0 ou 1) : à ces luminosités toute teinte
        // disparaît par construction.
        goal = Math.max(0.06, Math.min(0.94, goal));
        var h = (base.hslHue >= 0) ? base.hslHue : 0.0;
        var s = Math.max(minSat, Math.min(maxSat, base.hslSaturation));
        var l = theme.lightnessFor(h, s, goal);
        var out = Qt.hsla(h, s, l, 1.0);
        // Près des extrêmes, la chroma s'écrase : on remonte la saturation
        // jusqu'à ce que la couleur se voie encore (borné, 8 pas).
        var guard = 0;
        while (theme.chroma(out) < 15.0 && s < 0.88 && guard < 8) {
            s = Math.min(0.88, s + 0.08);
            l = theme.lightnessFor(h, s, goal);
            out = Qt.hsla(h, s, l, 1.0);
            guard += 1;
        }
        return out;
    }

    // Encre principale : la couleur du fond, en plus clair (zone sombre) ou plus
    // foncé (zone claire). Plus jamais du blanc pur.
    function inkOn(bgLum) {
        if (!(bgLum >= 0))
            return theme.text;
        return theme.coloured(theme.accent, bgLum, 0.50, 0.22, 0.42);
    }

    // Texte secondaire (date en kana) : même recette, plus discret.
    function inkDimOn(bgLum) {
        if (!(bgLum >= 0))
            return theme.textDim;
        return theme.coloured(theme.accent, bgLum, 0.34, 0.18, 0.34);
    }

    // Accent (suffixes じ / ふん, jauges) : teinte la plus franche — c'est lui
    // qui doit rester reconnaissable comme la couleur du papier peint.
    function accentOn(bgLum) {
        if (!(bgLum >= 0))
            return theme.accent;
        return theme.coloured(theme.accent, bgLum, 0.42, 0.35, 0.75);
    }

    // Opacité du PANNEAU (CC) selon la luminance derrière lui : à 0.36 sur un
    // fond clair, le panneau se laisse traverser et le texte perd son support.
    // On ne monte pas « au feeling » : on calcule l'opacité MINIMALE qui garde
    // le panneau plus sombre que l'encre (composite ≤ 0.36), donc on perd le
    // moins de transparence possible. Les widgets, eux, ne changent pas — leur
    // verre reste à 0.05–0.10.
    function panelAlphaOn(bgLum) {
        if (!(bgLum >= 0))
            return theme.alphaPanel;
        var panelLum = theme.luma(theme.glassBase);
        var denom = bgLum - panelLum;
        if (denom <= 0.02)
            return theme.alphaPanel;
        var need = (bgLum - 0.36) / denom;
        return Math.max(theme.alphaPanel, Math.min(0.88, need));
    }

    function readLumgrid(d) {
        if (!d || !d.values || d.values.length === 0) {
            theme.lightWallpaper = false;
            theme.lumValues = [];
            return;
        }
        var sum = 0;
        for (var i = 0; i < d.values.length; ++i)
            sum += d.values[i];
        // Grille inattendue (dimensions changées côté serveur) : on ne devine
        // pas les indexes, on retombe sur l'encre de palette.
        if (d.values.length !== theme.lumGridW * theme.lumGridH) {
            theme.lumValues = [];
            theme.lightWallpaper = false;
            return;
        }
        theme.lumValues = d.values;
        theme.lightWallpaper = (sum / d.values.length) > 0.55;
    }

    // ── Lumgrid SURVEILLÉ (brief §D : zéro polling, zéro requête) ─────────
    // theme-apply.py écrit la grille 32x18 à côté du lock de palette, dans
    // $XDG_RUNTIME_DIR. Quickshell la LIT et la surveille (inotify) : aucun
    // timer, aucune requête — l'encre des cartes et l'opacité du panneau
    // suivent le changement de papier peint à la frame suivante.
    readonly property string lumgridPath: {
        var d = Quickshell.env("XDG_RUNTIME_DIR");
        var base = (typeof d === "string" && d.length > 0) ? d : "/tmp";
        return base + "/sasquatch-lumgrid.json";
    }
    // Repli consommé UNE seule fois (jamais de boucle).
    property bool lumFetchedOnce: false

    property FileView lumFile: FileView {
        path: theme.lumgridPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: theme.lumFile.reload()
        onTextChanged: theme.readLumgridText(theme.lumFile.text())
        onLoaded: theme.readLumgridText(theme.lumFile.text())
        onLoadFailed: theme.fetchLumgridOnce()
    }

    // Parse défensif : fichier absent / tronqué / JSON invalide → on garde
    // l'état courant (jamais de crash, jamais de valeurs devinées).
    function readLumgridText(txt) {
        if (typeof txt !== "string" || txt.length === 0)
            return;
        var d = null;
        try {
            d = JSON.parse(txt);
        } catch (e) {
            return;
        }
        theme.readLumgrid(d);
    }

    // Repli UNIQUE au démarrage : au premier boot XDG_RUNTIME_DIR est vide,
    // le fichier n'existe pas encore → UN appel HTTP, puis le FileView prend
    // le relais dès le prochain theme-apply.
    function fetchLumgridOnce() {
        if (theme.lumFetchedOnce)
            return;
        theme.lumFetchedOnce = true;
        theme.refreshLumgrid();
    }

    // ── Sondes ────────────────────────────────────────────────────────────
    // Signature de la dernière palette : sert seulement à savoir si le papier
    // peint a réellement changé (voir refreshPalette).
    property string _palSig: ""

    function refreshPalette() {
        Api.get("/api/palette", function (d) {
            if (!d || typeof d !== "object" || typeof d.accent !== "string")
                return;
            var sig = String(d.bg) + "|" + String(d.text) + "|" + String(d.accent);
            // `_palSig` vide = premier passage : le démarrage est déjà couvert
            // par le chargement du FileView (onLoaded / fetchLumgridOnce), donc
            // on n'ajoute pas un reload concurrent ici.
            var changed = (theme._palSig !== "" && sig !== theme._palSig);
            theme._palSig = sig;
            theme.pal = d;
            // Filet de sécurité SANS timer : theme-apply écrit le lumgrid par
            // `os.replace`, donc l'inode surveillé disparaît et un FileView
            // peut rater le signal (mesuré sur widgets.json). Nouvelle palette
            // = nouveau papier peint → on force la relecture du fichier LOCAL
            // ici (aucune requête réseau, aucun process).
            if (changed)
                theme.lumFile.reload();
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
}
