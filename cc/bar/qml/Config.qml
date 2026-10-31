// Config.qml — singleton : lecture, validation et rechargement à chaud de bar.json.
//
// RÈGLE (brief §5) : aucun module ne lit le JSON. Tout passe par ce singleton.
// RÈGLE (brief §7) : chaque clé absente prend son défaut ICI (pas dans le JSON).
// RÈGLE (brief §7) : un JSON invalide ne casse jamais la barre — on garde la
// dernière configuration valide et on expose l'erreur dans `lastError`.
pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: cfg

    // ── Dernière config valide (défauts codés ici, pas dans bar.json) ──────
    // v5b : les défauts suivent l'état en service (barre 40 px, îlots, AUCUN
    // fond : panelAlpha 0 + blockAlpha 0 ; seuls les glyphes se voient, et une
    // pilule légère apparaît au survol).
    readonly property var defaults: ({
        bar: {
            enabled: true,
            position: "left",
            width: 40,
            marginTop: 8,
            marginBottom: 8,
            marginLeft: 6,
            marginRight: 6,
            exclusiveZone: true,
            radius: 14,
            spacing: 8,
            blockInset: 4,
            blur: true,
            blurRadius: 10,
            persistentWorkspaces: 10
        },
        modules: ["search", "workspaces", "netRate", "clock", "volume",
                  "pinnedApps", "runningApps", "quickToggles", "settings"],
        clock: { hourFormat: "HH", minuteFormat: "mm", period: "AP", calendarIcon: true },
        apps: [],
        popups: { calendar: true, volume: true, network: true, notifications: true },
        appearance: {
            panelAlpha: 0.0, blockAlpha: 0.0, cardAlpha: 0.86,
            hoverAlpha: 0.16, activeAlpha: 0.30,
            borderAlpha: 0.0, borderHoverAlpha: 0.18,
            iconSize: 15, appIconSize: 19, clockSize: 15, netSize: 9
        },
        // Nombre d'apps en cours affichées avant défilement (panneau Settings).
        runningApps: { maxVisible: 3 }
    })

    // Racine validée. Rechargée uniquement si le JSON parse ET reste un objet.
    property var data: cfg.defaults
    property string lastError: ""
    property int revision: 0

    // ── Accès typés (les modules n'utilisent que ceux-là) ─────────────────
    readonly property var barOpts: cfg.data.bar || cfg.defaults.bar
    readonly property bool enabled: cfg.optBool(cfg.barOpts, "enabled", true)
    readonly property string position: cfg.optStr(cfg.barOpts, "position", "left")
    readonly property int width: cfg.optInt(cfg.barOpts, "width", 40, 32, 240)
    readonly property int marginTop: cfg.optInt(cfg.barOpts, "marginTop", 8, 0, 200)
    readonly property int marginBottom: cfg.optInt(cfg.barOpts, "marginBottom", 8, 0, 200)
    readonly property int marginLeft: cfg.optInt(cfg.barOpts, "marginLeft", 6, 0, 200)
    // Miroir de marginLeft pour position = "right" (v5b). Défaut = même valeur
    // que la gauche : les trois positions ont le même écart au bord.
    readonly property int marginRight: cfg.optInt(cfg.barOpts, "marginRight", 6, 0, 200)
    // ── Orientation (v5b) ─────────────────────────────────────────────────
    // position est un CHOIX FERMÉ (left | top | right) : barjson.py --set
    // refuse tout le reste, et un fichier ancien sans la clé retombe sur
    // "left" (comportement identique à la v4).
    //   vertical   : barre pleine hauteur, ancrée à gauche ou à droite
    //   horizontal : bande pleine largeur, ancrée en haut ; les QUATRE groupes
    //                passent en Row (voir shell.qml) et chaque module rend sa
    //                variante « une ligne » (voir modules/*.qml).
    readonly property bool vertical: cfg.position !== "top"
    readonly property bool horizontal: !cfg.vertical
    readonly property bool sideRight: cfg.position === "right"
    readonly property bool reserve: cfg.optBool(cfg.barOpts, "exclusiveZone", true)
    readonly property int radius: cfg.optInt(cfg.barOpts, "radius", 14, 0, 40)
    readonly property int spacing: cfg.optInt(cfg.barOpts, "spacing", 8, 0, 40)
    readonly property int inset: cfg.optInt(cfg.barOpts, "blockInset", 4, 0, 20)
    readonly property bool blur: cfg.optBool(cfg.barOpts, "blur", true)
    readonly property int blurRadius: cfg.optInt(cfg.barOpts, "blurRadius", 10, 0, 40)
    // v4 §9 : points de workspaces PERSISTANTS (défaut 10, comme l'ancienne
    // waybar). 0 = comportement v3 : on n'affiche que les workspaces existants.
    readonly property int persistentWorkspaces: cfg.optInt(cfg.barOpts, "persistentWorkspaces", 10, 0, 40)

    // Largeur d'un bloc = largeur de barre moins les marges latérales.
    // AUCUNE taille de bloc n'est écrite en dur dans les modules : ils lisent
    // `Config.block`, donc la barre reste correcte de 32 à 56 px (brief §4).
    // Plancher 30 : en dessous, les glyphes de 16 px n'ont plus d'air.
    readonly property int block: Math.max(30, cfg.width - 2 * cfg.inset)
    // Cible cliquable minimale pour les POPUPS (brief v2 §2). Elle ne vaut que
    // là : à 40 px de large, un bloc de barre fait 32 px — une cible de 38 px
    // déborderait de la colonne (v4 §4 : « rien ne colle, rien ne déborde »).
    readonly property int hitMin: 38
    // Cible cliquable d'un bloc de barre = sa taille visuelle (v2 §2), donc
    // jamais plus large que Config.block.
    readonly property int hit: cfg.block

    // Épaisseur de la barre sur son PETIT axe : largeur en vertical, hauteur
    // en horizontal — c'est la même valeur (bar.width) dans les trois
    // positions, donc la barre ne change pas d'épaisseur quand on la déplace.
    readonly property int thickness: cfg.width
    // Placement des surfaces annexes (infobulle, popups) : en haut elles
    // passent SOUS la bande réservée (6 px), ailleurs marginTop + 8 comme
    // avant. Sans réserve (exclusiveZone false) la zone utile repart de 0 : il
    // faut alors ajouter la marge + l'épaisseur à la main.
    readonly property int popupGap: 10
    readonly property int popupTop: cfg.horizontal
                                     ? (cfg.reserve ? 6
                                                    : (cfg.marginTop + cfg.thickness + 6))
                                     : (cfg.marginTop + 8)

    // ── Métriques d'îlot (v4 §1/§3) : UNE seule règle pour tous les blocs ──
    // caseH : hauteur d'une case carrée (un glyphe, une app) = Config.block.
    // pad   : padding interne d'une pilule = blockInset (4 px ≥ 3 px exigés §4).
    // pillRadius : même rayon partout (12 px pour un bloc de 32 = 0,375 × block).
    // wsStep : pas vertical d'un point de workspace (points serrés, §1).
    readonly property int caseH: cfg.block
    readonly property int pad: cfg.inset
    readonly property int pillRadius: Math.max(6, Math.min(14, Math.round(cfg.block * 0.375)))
    readonly property int wsStep: Math.max(9, Math.min(24, cfg.pad * 2 + 5))

    readonly property var modules: Array.isArray(cfg.data.modules)
                                   ? cfg.data.modules.filter(function (m) {
                                         return typeof m === "string" && m.length > 0
                                     })
                                   : cfg.defaults.modules

    readonly property var clockOpts: cfg.data.clock || cfg.defaults.clock
    readonly property string hourFormat: cfg.optStr(cfg.clockOpts, "hourFormat", "HH")
    readonly property string minuteFormat: cfg.optStr(cfg.clockOpts, "minuteFormat", "mm")
    readonly property string period: cfg.optStr(cfg.clockOpts, "period", "AP")
    readonly property bool calendarIcon: cfg.optBool(cfg.clockOpts, "calendarIcon", true)

    readonly property var apps: Array.isArray(cfg.data.apps)
                               ? cfg.data.apps.filter(function (a) {
                                     return a && typeof a === "object" && a.id
                                 })
                               : []

    readonly property var popupOpts: cfg.data.popups || cfg.defaults.popups
    // Apps en cours visibles (runningApps.maxVisible) : piloté par le panneau
    // Settings via barjson.py --set, relu à chaud comme le reste.
    readonly property var runningApps: cfg.data.runningApps || cfg.defaults.runningApps
    readonly property int maxVisible: cfg.optInt(cfg.runningApps, "maxVisible", 3, 1, 6)

    readonly property var appearance: cfg.data.appearance || cfg.defaults.appearance
    // Alphas (v5b : AUCUN fond par défaut).
    //   panelAlpha : la dalle de barre (0 = pas de dalle du tout)
    //   blockAlpha : fond d'une pilule AU REPOS (0 = seule l'icône se voit ;
    //                c'est ce qui enlève les pilules opaques)
    //   hoverAlpha : fond de la pilule AU SURVOL (léger : 0.16)
    //   activeAlpha: état actif (popup ouverte, mute, app ouverte…) sur l'accent
    //   cardAlpha  : surface des POPUPS uniquement (elles restent lisibles)
    // Aucune valeur n'est écrite ailleurs : BarPalette les lit ici.
    // ATTENTION : les bornes basses de panelAlpha, blockAlpha et borderAlpha
    // valent 0.0 — avec 0.02 elles ramenaient un « 0 » de bar.json à 0.02, donc
    // une dalle fantôme sur toute la barre (bug relevé en v4 §1).
    readonly property real panelAlpha: cfg.optNum(cfg.appearance, "panelAlpha", 0.0, 0.0, 1.0)
    // blockAlpha : clé v5b. Un bar.json antérieur n'en a pas → 0.0 par défaut
    // (aucun fond), jamais cardAlpha (qui reste la surface des popups).
    readonly property real blockAlpha: cfg.optNum(cfg.appearance, "blockAlpha", 0.0, 0.0, 1.0)
    readonly property real cardAlpha: cfg.optNum(cfg.appearance, "cardAlpha", 0.86, 0.05, 1.0)
    readonly property real hoverAlpha: cfg.optNum(cfg.appearance, "hoverAlpha", 0.16, 0.0, 1.0)
    readonly property real activeAlpha: cfg.optNum(cfg.appearance, "activeAlpha", 0.95, 0.05, 1.0)
    readonly property real borderAlpha: cfg.optNum(cfg.appearance, "borderAlpha", 0.0, 0.0, 1.0)
    readonly property real borderHoverAlpha: cfg.optNum(cfg.appearance, "borderHoverAlpha", 0.18, 0.0, 1.0)
    // Tailles : glyphes d'icônes, icônes d'app, chiffres de l'horloge, débit.
    readonly property int iconSize: cfg.optInt(cfg.appearance, "iconSize", 15, 12, 32)
    readonly property int appIconSize: cfg.optInt(cfg.appearance, "appIconSize", 19, 12, 32)
    readonly property int clockSize: cfg.optInt(cfg.appearance, "clockSize", 15, 14, 32)
    readonly property int netSize: cfg.optInt(cfg.appearance, "netSize", 9, 9, 20)

    function popupOn(name) {
        return cfg.optBool(cfg.popupOpts, name, true);
    }

    // ── Helpers de validation ─────────────────────────────────────────────
    function optInt(obj, key, def, lo, hi) {
        var v = obj ? obj[key] : undefined;
        if (typeof v !== "number" || !isFinite(v))
            return def;
        v = Math.round(v);
        if (lo !== undefined && v < lo)
            return lo;
        if (hi !== undefined && v > hi)
            return hi;
        return v;
    }
    function optNum(obj, key, def, lo, hi) {
        var v = obj ? obj[key] : undefined;
        if (typeof v !== "number" || !isFinite(v))
            return def;
        if (lo !== undefined && v < lo)
            return lo;
        if (hi !== undefined && v > hi)
            return hi;
        return v;
    }
    function optBool(obj, key, def) {
        var v = obj ? obj[key] : undefined;
        return typeof v === "boolean" ? v : def;
    }
    function optStr(obj, key, def) {
        var v = obj ? obj[key] : undefined;
        return typeof v === "string" && v.length > 0 ? v : def;
    }

    // Fusion superficielle : les clés manquantes du JSON prennent le défaut.
    function merge(root) {
        var d = cfg.defaults;
        return {
            bar: Object.assign({}, d.bar, root.bar || {}),
            modules: Array.isArray(root.modules) ? root.modules : d.modules,
            clock: Object.assign({}, d.clock, root.clock || {}),
            apps: Array.isArray(root.apps) ? root.apps : d.apps,
            popups: Object.assign({}, d.popups, root.popups || {}),
            appearance: Object.assign({}, d.appearance, root.appearance || {})
        };
    }

    function applyText(txt) {
        if (!txt || txt.trim().length === 0) {
            cfg.lastError = "bar.json vide — config précédente conservée";
            return;
        }
        var parsed = null;
        try {
            parsed = JSON.parse(txt);
        } catch (e) {
            cfg.lastError = "JSON invalide (" + e.message + ") — config précédente conservée";
            return;
        }
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
            cfg.lastError = "bar.json n'est pas un objet — config précédente conservée";
            return;
        }
        cfg.data = cfg.merge(parsed);
        cfg.lastError = "";
        cfg.revision += 1;
    }

    // ── Fichier surveillé ─────────────────────────────────────────────────
    property FileView file: FileView {
        path: Qt.resolvedUrl("../bar.json")
        watchChanges: true
        blockLoading: true
        printErrors: true
        onFileChanged: cfg.file.reload()
        onTextChanged: cfg.applyText(cfg.file.text())
        onLoaded: cfg.applyText(cfg.file.text())
    }
}
