// StudioPage.qml — « l'espace widget » du CC (brief widgets v1 §7 « v1c-2 »).
//
// Trois colonnes :
//   gauche  catalogue du registre (WidgetRegistry.entries) filtré par hôte,
//           une entrée = vignette dessinée + nom + variantes + bouton « + »
//   centre  aperçu 16:9 du papier peint COURANT (chemin réel via
//           /api/wallpapers → champ `current`) avec les instances
//           host: background posées dessus : clic = sélection (contour
//           accent 2 px), drag = déplacement (fractions, clamp x+w<=1),
//           poignée = resize, double-clic = retrait
//   droite  panneau de style de la sélection : variante, alpha, blur (conservé
//           dans le schéma, SANS EFFET : aucun flou), radius, accent et options
//           typées du registre + « Réinitialiser »
//
// Règle tenue (brief §4) : cette page n'écrit JAMAIS widgets.json. Tout passe
// par POST /api/widgets ; la valeur affichée vient toujours de l'`instance`
// relue que le serveur renvoie (widgets_json.apply relit le fichier avant de
// répondre). La ligne de pied « révision relue N » le montre à l'écran.
//
// Aperçu : le canvas n'est pas mis à l'échelle en dur — il fait la taille
// RÉELLE de l'écran (1920x1080) et on applique `scale` au conteneur. Les
// fractions x/y et les tailles px des widgets du fond restent donc vraies.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Sasquatch.Widgets 1.0

Item {
    id: studio

    // ── État ──────────────────────────────────────────────────────────────
    // Hôte du catalogue : "background" (aperçu) ou "cc" (board d'accueil).
    property string hostFilter: "background"
    property var instances: []          // toutes les instances du fichier
    property int revision: -1           // révision RELUE
    property string selId: ""
    property var sel: null              // copie de l'instance sélectionnée
    property string lastError: ""
    property int rawCount: 0            // instances LUES (fantômes compris)
    property var ignored: []            // instances ignorées : { id, type, reason }
    property string wpPath: ""
    property string wpFolder: ""
    property bool wpFailed: false
    property int postCount: 0           // nombre de POST acceptés (preuve)

    // Placement intelligent (brief autoplace) : le calcul est chez le serveur
    // (cc/autoplace.py), la page n'envoie qu'une opération et affiche le
    // résultat RÉEL (placés / non placés + raison). Message dans le panneau,
    // jamais un toast fugace.
    property string apStrategy: "auto"
    property int apMargin: 24
    property int apGap: 12
    property string apCorner: "tr"
    property bool apBusy: false
    property int apPlaced: -1           // -1 = aucun placement tenté
    property var apUnplaced: []
    property string apReason: ""
    // « Suivre le fond d'écran » : le placement mémorisé côté serveur
    // (doc.placement) est rejoué à chaque changement de papier peint via
    // l'op `reapply` qu'appelle apply-wallpaper.sh.
    property bool apAuto: true
    property var placement: null
    property bool placementLoaded: false
    readonly property bool apOk: apPlaced > 0 && apUnplaced.length === 0
    readonly property var apStrategies: [
        { k: "theme", t: "Thème" }, { k: "auto", t: "Auto" },
        { k: "grid", t: "Grille" }, { k: "stack", t: "Empilé" },
        { k: "center", t: "Centré" }, { k: "spread", t: "Réparti" },
        { k: "fit", t: "Remplir" }
    ]
    readonly property var apCorners: [
        { k: "tr", t: "haut d." }, { k: "tl", t: "haut g." },
        { k: "br", t: "bas d." }, { k: "bl", t: "bas g." }
    ]
    readonly property string apHostLabel: (studio.hostFilter === "cc") ? "CC" : "Fond d'écran"

    function apResultText() {
        if (studio.apPlaced < 0)
            return "";
        var n = studio.apUnplaced.length;
        if (studio.apPlaced > 0 && n === 0)
            return studio.apPlaced + " placé" + (studio.apPlaced > 1 ? "s" : "")
                   + " · " + studio.apHostLabel;
        if (n === 0)
            return "échec · " + studio.apReason;
        return studio.apPlaced + " placé" + (studio.apPlaced > 1 ? "s" : "")
               + " · " + n + " non placé" + (n > 1 ? "s" : "")
               + " · " + studio.apReason;
    }

    // POST autoplace sur l'hôte AFFICHÉ, puis relecture du fichier : l'aperçu
    // se rafraîchit par le même chemin que d'habitude (FileView → instances).
    function autoplace() {
        if (studio.apBusy)
            return;
        var ids = [];
        var list = studio.byHost(studio.hostFilter);
        for (var i = 0; i < list.length; ++i)
            ids.push(list[i].id);
        studio.apBusy = true;
        var op = {
            op: "autoplace",
            host: studio.hostFilter,
            strategy: studio.apStrategy,
            margin: studio.apMargin,
            gap: studio.apGap,
            corner: studio.apCorner,
            // Mémorisé côté serveur : c'est `auto` qui fait rejouer ce
            // placement à chaque changement de papier peint (op `reapply`).
            auto: studio.apAuto,
            ids: ids,
            screen: { w: studio.screenW, h: studio.screenH }
        };
        Api.post("/api/widgets", op, function (d) {
            studio.apBusy = false;
            if (!d) {
                studio.apPlaced = 0;
                studio.apUnplaced = [];
                studio.apReason = "aucune réponse du serveur (8765)";
                studio.lastError = "autoplace : pas de réponse";
                return;
            }
            // `ok:false` est un RÉSULTAT (« pas de place »), pas un plantage :
            // on garde les ids non placés et la raison pour le panneau.
            studio.apPlaced = (d.placed && d.placed.length) ? d.placed.length : 0;
            studio.apUnplaced = d.unplaced ? d.unplaced : [];
            studio.apReason = d.reason ? d.reason : (d.error ? d.error : "");
            if (d.ok === true) {
                studio.lastError = "";
                studio.postCount += 1;
                if (typeof d.revision === "number")
                    studio.revision = d.revision;
                studio.file.reload();
            }
        }, 15000);
    }

    readonly property url widgetsPath: Qt.resolvedUrl("../widgets.json")

    // Écran réel : c'est le repère des fractions x/y des widgets du fond.
    readonly property real screenW: (Screen.width > 0) ? Screen.width : 1920
    readonly property real screenH: (Screen.height > 0) ? Screen.height : 1080

    readonly property var bgInstances: studio.byHost("background")
    readonly property var ccInstances: studio.byHost("cc")

    // État de rendu de l'APERÇU, exposé par le canvas lui-même : c'est la
    // preuve « instance posée = instance dessinée » (aucune lecture d'arbre
    // d'objets), et le pied de page l'affiche.
    readonly property int previewReady: bgCanvas.readyCount
    readonly property int previewPending: bgCanvas.pendingCount

    function byHost(h) {
        var out = [];
        for (var i = 0; i < studio.instances.length; ++i) {
            var it = studio.instances[i];
            if (it && it.host === h)
                out.push(it);
        }
        return out;
    }

    // ── Catalogue du registre, filtré par hôte, AVEC l'état de livraison ───
    // Chaque ligne : { entry, ok, reason }. `ok` ne vient pas du champ
    // `component` du registre mais du DISQUE (`WidgetRegistry.resolveState`,
    // seule source de vérité) : une entrée non résolue reste visible, grisée,
    // non plaçable, avec sa raison — elle ne devient jamais une tuile vide sur
    // le canevas, et elle ne disparaît pas en silence non plus.
    // Calcul HORS liaison (`resolveState` lit un singleton : une binding ne
    // suivrait pas ses dépendances) → rafraîchi sur les événements utiles.
    property var catalog: []

    function refreshCatalog() {
        var out = [];
        var es = WidgetRegistry.entries || [];
        for (var i = 0; i < es.length; ++i) {
            var e = es[i];
            if (!e || typeof e.id !== "string")
                continue;
            if (!WidgetRegistry.hostAllowed(e.id, studio.hostFilter))
                continue;
            var st = WidgetRegistry.resolveState(e.id);
            out.push({ entry: e, ok: st.ok, reason: st.reason });
        }
        studio.catalog = out;
    }

    onHostFilterChanged: studio.refreshCatalog()

    Connections {
        target: WidgetRegistry
        function onRevisionChanged() { studio.refreshCatalog() }
        function onAvailabilityChanged() { studio.refreshCatalog() }
    }

    // ── Accès sûrs pour les bindings du panneau (sel peut être null) ───────
    function sType() {
        return studio.sel ? studio.sel.type : "";
    }
    function sVariant() {
        return studio.sel ? studio.sel.variant : "";
    }
    function sStyleNum(key, fallback) {
        var st = studio.sel ? studio.sel.style : null;
        var v = st ? st[key] : undefined;
        return (typeof v === "number" && isFinite(v)) ? v : fallback;
    }
    function sAccent() {
        var st = studio.sel ? studio.sel.style : null;
        return (st && typeof st.accent === "string") ? st.accent : "auto";
    }
    function sOpt(key, fallback) {
        var o = studio.sel ? studio.sel.options : null;
        var v = o ? o[key] : undefined;
        return (v === undefined || v === null) ? fallback : v;
    }

    readonly property var styleBounds: WidgetRegistry.styleBounds(studio.sType())
    readonly property var optSpecs: {
        var out = [];
        var t = studio.sType();
        var e = (t.length > 0) ? WidgetRegistry.entry(t) : null;
        if (!e || !e.options)
            return out;
        var keys = Object.keys(e.options);
        for (var i = 0; i < keys.length; ++i)
            out.push({ key: keys[i], spec: e.options[keys[i]] });
        return out;
    }

    // ── Lecture de widgets.json (jamais d'écriture ici) ────────────────────
    function applyText(txt) {
        if (!txt || txt.trim().length === 0) {
            studio.lastError = "widgets.json vide — instances précédentes conservées";
            return;
        }
        var parsed = null;
        try {
            parsed = JSON.parse(txt);
        } catch (e) {
            studio.lastError = "widgets.json invalide (" + e.message + ")";
            return;
        }
        if (!parsed || !Array.isArray(parsed.instances)) {
            studio.lastError = "widgets.json sans tableau `instances`";
            return;
        }
        var rev = (typeof parsed.revision === "number") ? parsed.revision : 0;
        // Même révision ET même nombre d'instances = rien de neuf à relire.
        // Sinon on relit : sans ça, un fichier modifié par un AUTRE hôte (le
        // fond d'écran, un drag sur le board) restait ignoré par l'aperçu.
        if (rev === studio.revision && studio.rawCount > 0
                && studio.rawCount === parsed.instances.length)
            return;
        var kept = [];
        var ignored = [];
        for (var i = 0; i < parsed.instances.length; ++i) {
            var it = parsed.instances[i];
            if (!it || typeof it.id !== "string" || typeof it.type !== "string")
                continue;
            // Instance sans composant résolvable : jamais affichée (ni ici, ni
            // sur le canevas), mais DITE — une ligne de journal + le compteur
            // en pied de page. Le fichier n'est pas réécrit pour autant : la
            // seule écriture passe par POST /api/widgets.
            var st = WidgetRegistry.resolveState(it.type);
            if (!st.ok) {
                ignored.push({ id: it.id, type: it.type, reason: st.reason });
                console.warn("widgets: instance ignorée " + it.id + " (type "
                             + it.type + ") : " + st.reason);
                continue;
            }
            kept.push(it);
        }
        studio.rawCount = parsed.instances.length;
        studio.ignored = ignored;
        studio.revision = rev;
        studio.instances = kept;
        // Placement mémorisé par le serveur : le panneau s'initialise dessus
        // UNE fois (ensuite c'est l'utilisateur qui commande).
        if (parsed.placement && typeof parsed.placement === "object") {
            studio.placement = parsed.placement;
            if (!studio.placementLoaded) {
                studio.placementLoaded = true;
                if (typeof parsed.placement.strategy === "string")
                    studio.apStrategy = parsed.placement.strategy;
                if (typeof parsed.placement.margin === "number")
                    studio.apMargin = Math.round(parsed.placement.margin);
                if (typeof parsed.placement.gap === "number")
                    studio.apGap = Math.round(parsed.placement.gap);
                if (typeof parsed.placement.corner === "string")
                    studio.apCorner = parsed.placement.corner;
                studio.apAuto = parsed.placement.auto !== false;
            }
        }
        if (studio.selId.length > 0 && studio.byId(studio.selId) === null) {
            studio.selId = "";
            studio.sel = null;
        }
    }

    function byId(id) {
        for (var i = 0; i < studio.instances.length; ++i) {
            if (studio.instances[i].id === id)
                return studio.instances[i];
        }
        return null;
    }

    // Remplace (ou insère) une instance avec la version RELUE du serveur.
    function applyInstance(inst) {
        var next = [];
        var found = false;
        for (var i = 0; i < studio.instances.length; ++i) {
            var it = studio.instances[i];
            if (it.id === inst.id) {
                next.push(inst);
                found = true;
            } else {
                next.push(it);
            }
        }
        // `rm` et `reorder` répondent {id} / {id,to} sans hôte : on n'insère pas.
        if (!found && typeof inst.host === "string")
            next.push(inst);
        studio.instances = next;
        if (studio.selId === inst.id && typeof inst.host === "string")
            studio.sel = inst;
    }

    // ── Écriture : POST, puis relecture depuis la réponse ──────────────────
    function post(op, cb) {
        Api.post("/api/widgets", op, function (d) {
            if (!d || d.ok !== true) {
                studio.lastError = (d && d.error) ? (op.op + " : " + d.error)
                                                  : (op.op + " : pas de réponse");
                if (cb)
                    cb(null);
                return;
            }
            studio.lastError = "";
            studio.postCount += 1;
            if (typeof d.revision === "number")
                studio.revision = d.revision;
            if (d.instance && typeof d.instance.id === "string")
                studio.applyInstance(d.instance);
            studio.file.reload();
            if (cb)
                cb(d.instance);
        }, 8000);
    }

    // Enchaînement séquentiel : le serveur écrit un fichier, deux POST
    // simultanés se marcheraient dessus (aucun verrou côté serveur).
    function postSeq(ops, i) {
        if (i >= ops.length)
            return;
        studio.post(ops[i], function () { studio.postSeq(ops, i + 1); });
    }

    function select(id) {
        if (!id || id.length === 0) {
            studio.selId = "";
            studio.sel = null;
            return;
        }
        studio.selId = id;
        studio.sel = studio.byId(id);
    }

    function setStyle(key, value) {
        if (!studio.sel)
            return;
        var patch = {};
        patch[key] = value;
        studio.post({ op: "style", id: studio.sel.id, style: patch });
    }

    function setAccent(name) {
        if (!studio.sel)
            return;
        studio.post({ op: "style", id: studio.sel.id, style: { accent: name } });
    }

    function setVariant(v) {
        var s = studio.sel;
        if (!s)
            return;
        var id = s.id;
        var bg = (s.host === "background");
        // La variante définit la taille naturelle : on recale la géométrie
        // du fond dessus, sinon « compact » garderait la taille du « hero ».
        var nat = WidgetRegistry.variantSize(s.type, v);
        studio.post({ op: "variant", id: id, variant: v }, function (inst) {
            if (!bg || !inst)
                return;
            studio.post({ op: "resize", id: id, geo: { w: nat.w, h: nat.h } });
        });
    }

    function setOption(key, value) {
        if (!studio.sel)
            return;
        studio.post({ op: "option", id: studio.sel.id, key: key, value: value });
    }

    // ── Taille de la sélection ─────────────────────────────────────────────
    // Fond d'écran = pixels, board CC = cellules de la grille 12 colonnes. Les
    // hôtes bar/subpage n'ont pas de resize (l'ordre fait la place) : les
    // réglages sont alors masqués, jamais un slider qui n'envoie rien.
    readonly property string sHostName: (studio.sel && typeof studio.sel.host === "string")
                                        ? studio.sel.host : ""
    readonly property bool sIsBg: studio.sHostName !== "cc"
    readonly property bool sResizable: studio.sel !== null
        && (studio.sHostName === "background" || studio.sHostName === "cc")
    readonly property int sMaxW: studio.sIsBg ? Math.max(240, Math.round(studio.screenW)) : 12
    readonly property int sMaxH: studio.sIsBg ? Math.max(160, Math.round(studio.screenH)) : 8

    function sGeoNum(key, fallback) {
        var g = studio.sel ? studio.sel.geo : null;
        var v = g ? g[key] : undefined;
        return (typeof v === "number") ? v : fallback;
    }

    // Un seul axe par envoi : le serveur garde l'autre valeur de la géométrie
    // courante (`ref`), donc pas de saut de taille en changeant la largeur.
    function setSize(key, value) {
        if (!studio.sel)
            return;
        var geo = {};
        geo[key] = Math.round(value);
        studio.post({ op: "resize", id: studio.sel.id, geo: geo });
    }

    function removeWidget(id) {
        if (!id || id.length === 0)
            return;
        if (studio.selId === id) {
            studio.selId = "";
            studio.sel = null;
        }
        studio.post({ op: "rm", id: id });
    }

    function resetSelected() {
        var s = studio.sel;
        if (!s)
            return;
        var ops = [];
        ops.push({ op: "style", id: s.id,
                   style: WidgetRegistry.defaultStyle(s.type, s.variant) });
        ops.push({ op: "variant", id: s.id,
                   variant: WidgetRegistry.variantOrDefault(s.type) });
        var opts = WidgetRegistry.defaultOptions(s.type);
        var keys = Object.keys(opts);
        for (var i = 0; i < keys.length; ++i)
            ops.push({ op: "option", id: s.id, key: keys[i], value: opts[keys[i]] });
        studio.postSeq(ops, 0);
    }

    // ── Ajout : géométrie par défaut SANS chevauchement ────────────────────
    function r4(v) {
        return Math.round(v * 10000) / 10000;
    }

    // Position libre dans le repère du fond : on balaye la grille de haut en
    // bas, de gauche à droite, tant que le rectangle recouvre un widget posé.
    function freeGeo(wPx, hPx) {
        var cw = studio.screenW;
        var ch = studio.screenH;
        var fw = Math.min(1, wPx / cw);
        var fh = Math.min(1, hPx / ch);
        var stepX = Math.max(0.01, Math.min(0.06, fw / 2));
        var stepY = Math.max(0.01, Math.min(0.08, fh / 2));
        var maxX = Math.max(0, 1 - fw);
        var maxY = Math.max(0, 1 - fh);
        var list = studio.bgInstances;
        var y = 0;
        while (y <= maxY + 0.0001) {
            var x = 0;
            while (x <= maxX + 0.0001) {
                if (!studio.overlaps(x, y, fw, fh, list, cw, ch))
                    return { x: studio.r4(x), y: studio.r4(y),
                             w: Math.round(wPx), h: Math.round(hPx) };
                x += stepX;
            }
            y += stepY;
        }
        // Aucune place : cascade en bas à droite (le canvas reclampe au rendu).
        var n = list.length;
        return { x: studio.r4(Math.min(maxX, 0.04 + 0.03 * n)),
                 y: studio.r4(Math.min(maxY, 0.04 + 0.03 * n)),
                 w: Math.round(wPx), h: Math.round(hPx) };
    }

    function overlaps(x, y, fw, fh, list, cw, ch) {
        var m = 0.004;
        for (var i = 0; i < list.length; ++i) {
            var g = list[i].geo || {};
            var ix = (typeof g.x === "number") ? g.x : 0;
            var iy = (typeof g.y === "number") ? g.y : 0;
            var iw = ((typeof g.w === "number") ? g.w : 360) / Math.max(1, cw);
            var ih = ((typeof g.h === "number") ? g.h : 180) / Math.max(1, ch);
            if (x < ix + iw + m && x + fw + m > ix && y < iy + ih + m && y + fh + m > iy)
                return true;
        }
        return false;
    }

    // Même chose pour l'hôte `cc` (cellules d'une grille 12 x n).
    function freeCell(w, h) {
        var list = studio.ccInstances;
        var cols = 12;
        for (var row = 0; row < 40; ++row) {
            for (var col = 0; col + w <= cols; ++col) {
                if (!studio.cellTaken(col, row, w, h, list))
                    return { col: col, row: row, w: w, h: h };
            }
        }
        return { col: 0, row: 0, w: w, h: h };
    }

    function cellTaken(col, row, w, h, list) {
        for (var i = 0; i < list.length; ++i) {
            var g = list[i].geo || {};
            var c = Math.round(g.col || 0);
            var r = Math.round(g.row || 0);
            var cw = Math.max(1, Math.round(g.w || 4));
            var chh = Math.max(1, Math.round(g.h || 2));
            if (col < c + cw && col + w > c && row < r + chh && row + h > r)
                return true;
        }
        return false;
    }

    function addWidget(type) {
        var e = WidgetRegistry.entry(type);
        if (!e)
            return;
        // Composant absent du disque : on refuse AVANT le POST — le serveur
        // refuserait aussi (`_require_component`), mais un clic qui ne fait
        // rien sans explication est exactement le défaut qu'on corrige.
        var st = WidgetRegistry.resolveState(type);
        if (!st.ok) {
            studio.lastError = "ajout refusé · " + type + " : " + st.reason;
            return;
        }
        var variant = WidgetRegistry.variantOrDefault(type);
        var nat = WidgetRegistry.variantSize(type, variant);
        var host = studio.hostFilter;
        var geo = (host === "background")
                ? studio.freeGeo(nat.w, nat.h)
                : studio.freeCell(nat.cell[0], nat.cell[1]);
        studio.post({ op: "add", type: type, host: host, variant: variant, geo: geo },
                    function (inst) {
                        if (inst && typeof inst.id === "string")
                            studio.select(inst.id);
                    });
    }

    // ── Papier peint (chemin réel, image réelle) ───────────────────────────
    readonly property string wpLabel: {
        var p = studio.wpPath;
        if (p.length === 0)
            return "aucun fond";
        var i = p.lastIndexOf("/");
        return (i >= 0) ? p.substring(i + 1) : p;
    }

    // Source : le fichier lui-même (pleine résolution). Si Qt n'arrive pas à
    // l'ouvrir, repli sur la miniature servie par /api/wallpaper/thumb.
    readonly property string wallpaperSource: {
        if (studio.wpPath.length === 0)
            return "";
        if (studio.wpFailed)
            return Api.base + "/api/wallpaper/thumb?file=" + encodeURIComponent(studio.wpPath);
        return encodeURI("file://" + studio.wpPath).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    function loadWallpaper() {
        Api.get("/api/wallpapers", function (d) {
            if (!d)
                return;
            studio.wpFolder = (typeof d.folder === "string") ? d.folder : "";
            studio.wpPath = (typeof d.current === "string") ? d.current : "";
        }, 6000);
    }

    Component.onCompleted: {
        studio.refreshCatalog()
        studio.loadWallpaper()
    }

    property FileView file: FileView {
        path: studio.widgetsPath
        watchChanges: true
        blockLoading: true
        printErrors: true
        onFileChanged: studio.file.reload()
        onTextChanged: studio.applyText(studio.file.text())
        onLoaded: studio.applyText(studio.file.text())
    }

    // ── Petits composants ─────────────────────────────────────────────────
    // Slider maison (aucune dépendance à QtQuick.Controls : le style par
    // défaut de QQC2 n'est pas garanti sur ce système et casserait la teinte).
    // `modelValue` = valeur relue ; `value` suit la souris pendant le drag et
    // la Binding la remet sur `modelValue` au relâchement (quand: !pressed).
    component SliderRow: Item {
        id: sr

        property string label: ""
        property real from: 0
        property real to: 1
        property real modelValue: 0
        property int decimals: 2
        property bool pressed: false
        property real value: modelValue
        // `locked` : réglage conservé dans le schéma mais sans effet (ex.
        // style.blur) — la ligne reste visible, grisée, et n'envoie rien.
        property bool locked: false
        // `note` : texte affiché à la place de la valeur (ex. « sans effet »).
        property string note: ""
        signal committed(real v)

        implicitHeight: 28
        height: 28
        opacity: sr.locked ? 0.45 : 1

        Binding {
            target: sr
            property: "value"
            value: sr.modelValue
            when: !sr.pressed
        }

        function ratioToValue(r) {
            var v = sr.from + Math.max(0, Math.min(1, r)) * (sr.to - sr.from);
            var p = Math.pow(10, Math.max(0, sr.decimals));
            v = Math.round(v * p) / p;
            return Math.max(sr.from, Math.min(sr.to, v));
        }

        Text {
            id: srLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 62
            text: sr.label
            font.pixelSize: 10
            color: Theme.textDim
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        Text {
            id: srVal
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(38, implicitWidth)
            horizontalAlignment: Text.AlignRight
            text: (sr.note.length > 0)
                  ? sr.note
                  : ((sr.decimals > 0) ? sr.value.toFixed(sr.decimals) : ("" + Math.round(sr.value)))
            font.pixelSize: 10
            color: Theme.text
        }

        Item {
            id: track
            anchors.left: srLabel.right
            anchors.leftMargin: 8
            anchors.right: srVal.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 22

            readonly property real ratio: (sr.to > sr.from)
                                          ? Math.max(0, Math.min(1, (sr.value - sr.from) / (sr.to - sr.from)))
                                          : 0

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 3
                radius: 1.5
                color: Theme.a(Theme.text, 0.16)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: track.width * track.ratio
                height: 3
                radius: 1.5
                color: Theme.accent
            }
            Rectangle {
                id: knob
                width: 9
                height: 9
                radius: 4.5
                color: Theme.text
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(track.width - knob.width,
                                        track.width * track.ratio - knob.width / 2))
            }
        }

        MouseArea {
            id: srMouse
            anchors.fill: parent
            enabled: !sr.locked
            cursorShape: sr.locked ? Qt.ArrowCursor : Qt.PointingHandCursor

            function apply(mx) {
                var p = srMouse.mapToItem(track, mx, 0);
                sr.value = sr.ratioToValue(track.width > 1 ? p.x / track.width : 0);
            }

            onPressed: function (mouse) {
                sr.pressed = true;
                apply(mouse.x);
            }
            onPositionChanged: function (mouse) {
                if (sr.pressed)
                    apply(mouse.x);
            }
            onReleased: {
                sr.pressed = false;
                sr.committed(sr.value);
            }
        }
    }

    // Vignette dessinée du catalogue : aucune instance de widget n'est créée
    // (une vignette vivante lancerait les timers de Music pour rien).
    component Thumb: Canvas {
        id: th

        property string kind: ""
        property color tint: Theme.textDim

        onKindChanged: requestPaint()
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var S = Math.min(width, height);
            if (S < 4)
                return;
            var cx = width / 2;
            var cy = height / 2;
            ctx.strokeStyle = th.tint;
            ctx.fillStyle = th.tint;
            ctx.lineWidth = Math.max(1, S * 0.075);
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            if (th.kind === "media") {
                var bw = Math.max(2, S * 0.13);
                for (var i = 0; i < 3; ++i) {
                    var bh = S * (i === 1 ? 0.46 : 0.28);
                    ctx.fillRect(cx - bw * 1.9 + i * bw * 1.85, cy + S * 0.24 - bh, bw, bh);
                }
            } else if (th.kind === "clock") {
                ctx.beginPath();
                ctx.arc(cx, cy, S * 0.32, 0, Math.PI * 2);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx, cy - S * 0.19);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx + S * 0.15, cy + S * 0.09);
                ctx.stroke();
            } else if (th.kind === "resources") {
                for (var r = 0; r < 3; ++r) {
                    ctx.beginPath();
                    ctx.moveTo(cx - S * 0.3, cy - S * 0.2 + r * S * 0.2);
                    ctx.lineTo(cx + S * (0.3 - r * 0.13), cy - S * 0.2 + r * S * 0.2);
                    ctx.stroke();
                }
            } else if (th.kind === "tasks") {
                for (var t = 0; t < 3; ++t) {
                    ctx.strokeRect(cx - S * 0.3, cy - S * 0.26 + t * S * 0.23, S * 0.1, S * 0.1);
                    ctx.beginPath();
                    ctx.moveTo(cx - S * 0.11, cy - S * 0.21 + t * S * 0.23);
                    ctx.lineTo(cx + S * 0.3, cy - S * 0.21 + t * S * 0.23);
                    ctx.stroke();
                }
            } else if (th.kind === "volume") {
                ctx.beginPath();
                ctx.moveTo(cx - S * 0.32, cy - S * 0.09);
                ctx.lineTo(cx - S * 0.2, cy - S * 0.09);
                ctx.lineTo(cx - S * 0.03, cy - S * 0.25);
                ctx.lineTo(cx - S * 0.03, cy + S * 0.25);
                ctx.lineTo(cx - S * 0.2, cy + S * 0.09);
                ctx.lineTo(cx - S * 0.32, cy + S * 0.09);
                ctx.closePath();
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(cx + S * 0.01, cy, S * 0.16, -0.9, 0.9);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(cx + S * 0.01, cy, S * 0.28, -0.9, 0.9);
                ctx.stroke();
            } else if (th.kind === "battery") {
                ctx.strokeRect(cx - S * 0.33, cy - S * 0.17, S * 0.56, S * 0.34);
                ctx.fillRect(cx + S * 0.23, cy - S * 0.07, S * 0.08, S * 0.14);
                ctx.fillRect(cx - S * 0.29, cy - S * 0.13, S * 0.3, S * 0.26);
            } else if (th.kind === "weather") {
                ctx.beginPath();
                ctx.arc(cx - S * 0.1, cy, S * 0.14, Math.PI * 0.5, Math.PI * 1.5);
                ctx.arc(cx, cy - S * 0.1, S * 0.17, Math.PI * 1.05, Math.PI * 1.85);
                ctx.arc(cx + S * 0.16, cy - S * 0.02, S * 0.13, Math.PI * 1.4, Math.PI * 2.05);
                ctx.closePath();
                ctx.stroke();
            } else {
                var s4 = S * 0.19;
                ctx.strokeRect(cx - s4 - S * 0.05, cy - s4 - S * 0.05, s4, s4);
                ctx.strokeRect(cx + S * 0.05, cy - s4 - S * 0.05, s4, s4);
                ctx.strokeRect(cx - s4 - S * 0.05, cy + S * 0.05, s4, s4);
                ctx.strokeRect(cx + S * 0.05, cy + S * 0.05, s4, s4);
            }
        }
    }

    // ── Mise en page : 3 colonnes ──────────────────────────────────────────
    Item {
        id: leftCol
        width: 232
        height: parent.height

        Text {
            id: catTitle
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            text: "CATALOGUE"
            font.pixelSize: 10
            font.bold: true
            color: Theme.textDim
        }

        Row {
            id: hostRow
            anchors.left: parent.left
            anchors.top: catTitle.bottom
            anchors.topMargin: 8
            spacing: 6

            Repeater {
                model: [{ k: "background", t: "Fond d'écran" }, { k: "cc", t: "CC" }]

                delegate: Rectangle {
                    id: hostBtn
                    required property var modelData
                    width: 96
                    height: 26
                    radius: Theme.radiusBtn
                    color: (studio.hostFilter === modelData.k)
                           ? Theme.a(Theme.accent, 0.85)
                           : Theme.a(Theme.text, 0.06)
                    Behavior on color { ColorAnimation { duration: 90 } }

                    Text {
                        anchors.centerIn: parent
                        text: hostBtn.modelData.t
                        font.pixelSize: 10
                        color: (studio.hostFilter === hostBtn.modelData.k) ? Theme.ink : Theme.textDim
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: studio.hostFilter = hostBtn.modelData.k
                    }
                }
            }
        }

        // ── Placement intelligent (brief autoplace §4) ─────────────────────
        // Panneau complet : stratégie, marges, espacement, coin (Empilé), et
        // le résultat réel renvoyé par le serveur. Il agit sur l'hôte affiché.
        Column {
            id: apPanel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: hostRow.bottom
            anchors.topMargin: 10
            spacing: 6

            Text {
                width: parent.width
                text: "PLACEMENT INTELLIGENT"
                font.pixelSize: 10
                font.bold: true
                color: Theme.textDim
            }

            Flow {
                width: parent.width
                spacing: 4

                Repeater {
                    model: studio.apStrategies

                    delegate: Rectangle {
                        id: apChip
                        required property var modelData
                        readonly property bool active: studio.apStrategy === modelData.k
                        width: apStratLabel.implicitWidth + 16
                        height: 22
                        radius: Theme.radiusBtn
                        color: active ? Theme.a(Theme.accent, 0.85) : Theme.a(Theme.text, 0.06)
                        Behavior on color { ColorAnimation { duration: 90 } }

                        Text {
                            id: apStratLabel
                            anchors.centerIn: parent
                            text: apChip.modelData.t
                            font.pixelSize: 9
                            color: (studio.apStrategy === apChip.modelData.k) ? Theme.ink : Theme.textDim
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: studio.apStrategy = apChip.modelData.k
                        }
                    }
                }
            }

            // Le coin ne concerne QUE la stratégie Empilé (brief §1).
            Flow {
                width: parent.width
                spacing: 4
                visible: studio.apStrategy === "stack"

                Repeater {
                    model: studio.apCorners

                    delegate: Rectangle {
                        id: apCornerChip
                        required property var modelData
                        readonly property bool active: studio.apCorner === modelData.k
                        width: apCornerLabel.implicitWidth + 16
                        height: 22
                        radius: Theme.radiusBtn
                        color: active ? Theme.a(Theme.accent, 0.85) : Theme.a(Theme.text, 0.06)

                        Text {
                            id: apCornerLabel
                            anchors.centerIn: parent
                            text: apCornerChip.modelData.t
                            font.pixelSize: 9
                            color: (studio.apCorner === apCornerChip.modelData.k) ? Theme.ink : Theme.textDim
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: studio.apCorner = apCornerChip.modelData.k
                        }
                    }
                }
            }

            SliderRow {
                width: apPanel.width
                label: "Marges"
                from: 8
                to: 96
                decimals: 0
                modelValue: studio.apMargin
                onCommitted: function (v) { studio.apMargin = Math.round(v); }
            }

            SliderRow {
                width: apPanel.width
                label: "Espacement"
                from: 0
                to: 48
                decimals: 0
                modelValue: studio.apGap
                onCommitted: function (v) { studio.apGap = Math.round(v); }
            }

            // « Suivre le fond d'écran » : coché → le placement mémorisé est
            // rejoué à chaque changement de papier peint. Décocher n'écrit QUE
            // le drapeau (`setplacement`) : ça ne déplace aucun widget.
            Rectangle {
                width: apPanel.width
                height: 24
                radius: Theme.radiusBtn
                color: studio.apAuto ? Theme.a(Theme.accent, 0.60) : Theme.a(Theme.text, 0.06)

                Text {
                    anchors.centerIn: parent
                    text: studio.apAuto ? "Suivre le fond ✓" : "Suivre le fond"
                    font.pixelSize: 9
                    color: studio.apAuto ? Theme.ink : Theme.textDim
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        studio.apAuto = !studio.apAuto;
                        if (studio.placement !== null)
                            studio.post({ op: "setplacement", auto: studio.apAuto });
                    }
                }
            }

            Rectangle {
                width: apPanel.width
                height: 28
                radius: Theme.radiusBtn
                color: studio.apBusy ? Theme.a(Theme.accent, 0.45)
                                     : (apGoHover.containsMouse ? Theme.a(Theme.accent, 0.85)
                                                                : Theme.a(Theme.text, 0.10))

                Text {
                    anchors.centerIn: parent
                    text: studio.apBusy ? "Placement…" : "Placer les widgets"
                    font.pixelSize: 10
                    color: apGoHover.containsMouse ? Theme.ink : Theme.text
                }

                MouseArea {
                    id: apGoHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: studio.autoplace()
                }
            }

            Text {
                width: parent.width
                visible: studio.apPlaced >= 0
                text: studio.apResultText()
                font.pixelSize: 9
                color: studio.apOk ? Theme.textDim : Theme.hot
                wrapMode: Text.WordWrap
            }
        }

        ListView {
            id: catList
            anchors.top: apPanel.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: studio.catalog

            delegate: Rectangle {
                id: catRow
                // { entry, ok, reason } — calculé par studio.refreshCatalog().
                required property var modelData
                readonly property var entry: modelData.entry
                readonly property bool available: modelData.ok === true
                width: ListView.view.width
                height: 48
                radius: Theme.radiusBtn
                // Non livré = grisé : la tuile reste lisible (on voit QUEL
                // widget manque) mais elle n'appelle ni le survol ni le clic.
                opacity: catRow.available ? 1 : 0.55
                color: (catRow.available && catHover.hovered)
                       ? Theme.a(Theme.text, 0.09) : Theme.a(Theme.text, 0.05)
                Behavior on color { ColorAnimation { duration: 90 } }

                HoverHandler {
                    id: catHover
                }

                Thumb {
                    id: catThumb
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    kind: catRow.entry.id
                    tint: Theme.textDim
                }

                Text {
                    id: catName
                    anchors.left: catThumb.right
                    anchors.leftMargin: 8
                    anchors.right: catAdd.left
                    anchors.rightMargin: 6
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    text: catRow.entry.name || catRow.entry.id
                    font.pixelSize: 11
                    color: Theme.text
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Text {
                    anchors.left: catName.left
                    anchors.right: catName.right
                    anchors.top: catName.bottom
                    anchors.topMargin: 2
                    // Composant absent : la RAISON est affichée telle quelle
                    // (« fichier manquant : widgets/X.qml »), pas un silence.
                    text: catRow.available
                          ? WidgetRegistry.variantNames(catRow.entry.id).join(" · ")
                          : "indisponible · " + catRow.modelData.reason
                    font.pixelSize: 9
                    color: catRow.available ? Theme.textDim : Theme.warn
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Rectangle {
                    id: catAdd
                    width: 28
                    height: 28
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.radiusBtn
                    // Non plaçable : teinte neutre, pas de « + » trompeur.
                    color: !catRow.available ? Theme.a(Theme.text, 0.04)
                           : (catAddHover.containsMouse ? Theme.a(Theme.accent, 0.8)
                                                        : Theme.a(Theme.text, 0.08))

                    Text {
                        anchors.centerIn: parent
                        text: catRow.available ? "+" : "—"
                        font.pixelSize: 16
                        color: !catRow.available ? Theme.textDim
                               : (catAddHover.containsMouse ? Theme.ink : Theme.text)
                    }

                    MouseArea {
                        id: catAddHover
                        anchors.fill: parent
                        enabled: catRow.available
                        hoverEnabled: true
                        cursorShape: catRow.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: studio.addWidget(catRow.entry.id)
                    }
                }
            }
        }
    }

    // ── Colonne centrale : aperçu 16:9 ─────────────────────────────────────
    Item {
        id: centerCol
        anchors.left: leftCol.right
        anchors.leftMargin: Theme.spacing
        anchors.right: rightCol.left
        anchors.rightMargin: Theme.spacing
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Item {
            id: headRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 22

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "APERÇU · FOND D'ÉCRAN"
                font.pixelSize: 10
                font.bold: true
                color: Theme.textDim
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: studio.wpLabel + " · " + studio.screenW + "×" + studio.screenH
                      + " · " + studio.bgInstances.length + " widget(s)"
                font.pixelSize: 10
                color: Theme.textDim
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }

        Text {
            id: footerLine
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26
            // « rendu N/M » = instances RÉELLEMENT dessinées par l'aperçu :
            // preuve à l'écran qu'un ajout est pris en compte sans redémarrage.
            text: "révision relue " + studio.revision + " · POST " + studio.postCount
                  + " · rendu " + studio.previewReady + "/" + studio.bgInstances.length
                  + (studio.previewPending > 0 ? " (" + studio.previewPending + " en attente)" : "")
                  + (studio.ignored.length > 0 ? " · " + studio.ignored.length + " ignorée(s)" : "")
                  + (studio.lastError.length > 0 ? " · ⚠ " + studio.lastError : "")
            font.pixelSize: 10
            color: studio.lastError.length > 0 ? Theme.hot : Theme.textDim
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            id: stage
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headRow.bottom
            anchors.topMargin: 8
            anchors.bottom: footerLine.top
            anchors.bottomMargin: 8

            Item {
                id: previewBox
                readonly property real availW: Math.max(200, stage.width)
                readonly property real availH: Math.max(140, stage.height)
                readonly property real pw: Math.min(availW, availH * 16 / 9)
                width: Math.round(pw)
                height: Math.round(pw * 9 / 16)
                anchors.centerIn: parent
                clip: true

                // Fond de secours (image absente ou en cours de chargement).
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusCard
                    color: Theme.a(Theme.bgSolid, 0.85)
                }

                // L'image : fichier réel, découpé par un simple `clip` (plus de
                // masque MultiEffect : aucun effet dans l'aperçu, rendu
                // déterministe ; les widgets posés dessus restent au-dessus).
                Rectangle {
                    id: wpFrame
                    anchors.fill: parent
                    radius: Theme.radiusCard
                    clip: true
                    color: "transparent"

                    Image {
                        id: wpImg
                        anchors.fill: parent
                        source: studio.wallpaperSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        onStatusChanged: {
                            if (status === Image.Error && studio.wallpaperSource.indexOf("file://") === 0)
                                studio.wpFailed = true;
                        }
                    }
                }

                // Les widgets du fond : canvas à la taille RÉELLE de l'écran,
                // réduit par `scale` — fractions et px restent vrais.
                Item {
                    id: stageClip
                    anchors.fill: parent
                    anchors.margins: 1
                    clip: true

                    WidgetCanvas {
                        id: bgCanvas
                        width: studio.screenW
                        height: studio.screenH
                        scale: Math.min(stageClip.width / studio.screenW,
                                        stageClip.height / studio.screenH)
                        transformOrigin: Item.TopLeft
                        x: Math.round((stageClip.width - width * scale) / 2)
                        y: Math.round((stageClip.height - height * scale) / 2)
                        host: "background"
                        layout: "free"
                        editing: true
                        instances: studio.bgInstances
                        selectedId: studio.selId
                        onInstanceClicked: function (id) { studio.select(id); }
                        onInstanceRemoveRequested: function (id) { studio.removeWidget(id); }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: Math.max(1, parent.width - 40)
                    visible: studio.bgInstances.length === 0
                    text: "aucun widget sur le fond — ajoutez-en depuis le catalogue, à gauche"
                    font.pixelSize: 11
                    color: Theme.inkDim
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                // Cadre par-dessus l'image (coins arrondis + teinte accent).
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusCard
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.border
                }
            }
        }
    }

    // ── Colonne droite : style de la sélection ─────────────────────────────
    Item {
        id: rightCol
        anchors.right: parent.right
        width: 268
        height: parent.height

        Text {
            id: stTitle
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            text: studio.sel ? ("STYLE · " + studio.sel.id) : "STYLE"
            font.pixelSize: 10
            font.bold: true
            color: Theme.textDim
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        Text {
            id: stEmpty
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: stTitle.bottom
            anchors.topMargin: 12
            visible: studio.sel === null
            text: "aucun widget sélectionné\ncliquez un widget de l'aperçu pour régler son style"
            font.pixelSize: 11
            color: Theme.textDim
            wrapMode: Text.WordWrap
        }

        Flickable {
            id: styleFlick
            anchors.top: stTitle.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: styleCol.height

            Column {
                id: styleCol
                width: styleFlick.width
                spacing: 10

                // — variante —
                Text {
                    width: styleCol.width
                    visible: studio.sel !== null
                    text: "VARIANTE"
                    font.pixelSize: 9
                    color: Theme.textDim
                }

                Row {
                    width: styleCol.width
                    visible: studio.sel !== null
                    spacing: 6

                    Repeater {
                        model: WidgetRegistry.variantNames(studio.sType())

                        delegate: Rectangle {
                            id: varChip
                            required property var modelData
                            readonly property bool active: studio.sVariant() === modelData
                            width: varLabel.implicitWidth + 20
                            height: 24
                            radius: Theme.radiusBtn
                            color: active ? Theme.a(Theme.accent, 0.85) : Theme.a(Theme.text, 0.06)

                            Text {
                                id: varLabel
                                anchors.centerIn: parent
                                text: varChip.modelData
                                font.pixelSize: 10
                                color: (studio.sVariant() === varChip.modelData) ? Theme.ink : Theme.textDim
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: studio.setVariant(varChip.modelData)
                            }
                        }
                    }
                }

                // — taille (px sur le fond, cellules dans le CC) —
                Text {
                    width: styleCol.width
                    visible: studio.sResizable
                    text: studio.sIsBg ? "TAILLE · PX" : "TAILLE · CELLULES"
                    font.pixelSize: 9
                    color: Theme.textDim
                }

                SliderRow {
                    width: styleCol.width
                    visible: studio.sResizable
                    label: "Largeur"
                    from: studio.sIsBg ? 120 : 1
                    to: studio.sMaxW
                    decimals: 0
                    modelValue: studio.sGeoNum("w", studio.sIsBg ? 360 : 4)
                    onCommitted: function (v) { studio.setSize("w", v); }
                }

                SliderRow {
                    width: styleCol.width
                    visible: studio.sResizable
                    label: "Hauteur"
                    from: studio.sIsBg ? 80 : 1
                    to: studio.sMaxH
                    decimals: 0
                    modelValue: studio.sGeoNum("h", studio.sIsBg ? 180 : 2)
                    onCommitted: function (v) { studio.setSize("h", v); }
                }

                // — alpha / blur / radius (bornes du registre) —
                SliderRow {
                    width: styleCol.width
                    visible: studio.sel !== null
                    label: "Alpha"
                    from: studio.styleBounds.alpha[0]
                    to: studio.styleBounds.alpha[1]
                    decimals: 2
                    modelValue: studio.sStyleNum("alpha", 0.08)
                    onCommitted: function (v) { studio.setStyle("alpha", v); }
                }

                // `style.blur` est CONSERVÉ dans le schéma (compatibilité du
                // fichier) mais n'est plus appliqué : aucun flou dans
                // l'interface. La ligne reste affichée, grisée, sans effet.
                SliderRow {
                    width: styleCol.width
                    visible: studio.sel !== null
                    label: "Blur"
                    from: studio.styleBounds.blur[0]
                    to: studio.styleBounds.blur[1]
                    decimals: 0
                    locked: true
                    note: "sans effet"
                    modelValue: studio.sStyleNum("blur", 9)
                    onCommitted: function (v) { studio.setStyle("blur", Math.round(v)); }
                }

                SliderRow {
                    width: styleCol.width
                    visible: studio.sel !== null
                    label: "Rayon"
                    from: studio.styleBounds.radius[0]
                    to: studio.styleBounds.radius[1]
                    decimals: 0
                    modelValue: studio.sStyleNum("radius", 16)
                    onCommitted: function (v) { studio.setStyle("radius", Math.round(v)); }
                }

                // — accent —
                Text {
                    width: styleCol.width
                    visible: studio.sel !== null
                    text: "ACCENT"
                    font.pixelSize: 9
                    color: Theme.textDim
                }

                Flow {
                    width: styleCol.width
                    visible: studio.sel !== null
                    spacing: 6

                    Repeater {
                        model: studio.styleBounds.accent

                        delegate: Rectangle {
                            id: accChip
                            required property var modelData
                            readonly property bool active: studio.sAccent() === modelData
                            width: accLabel.implicitWidth + 18
                            height: 22
                            radius: Theme.radiusBtn
                            color: active ? Theme.a(Theme.accent, 0.85) : Theme.a(Theme.text, 0.06)

                            Text {
                                id: accLabel
                                anchors.centerIn: parent
                                text: accChip.modelData
                                font.pixelSize: 9
                                color: (studio.sAccent() === accChip.modelData) ? Theme.ink : Theme.textDim
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: studio.setAccent(accChip.modelData)
                            }
                        }
                    }
                }

                // — options typées du registre —
                Repeater {
                    model: studio.optSpecs

                    delegate: Column {
                        id: optRow
                        required property var modelData
                        readonly property string optKey: modelData.key
                        readonly property var optSpec: modelData.spec
                        width: styleCol.width
                        spacing: 4

                        SliderRow {
                            width: optRow.width
                            visible: studio.sel !== null && optRow.optSpec.type === "int"
                            label: optRow.optKey
                            from: optRow.optSpec.min !== undefined ? optRow.optSpec.min : 0
                            to: optRow.optSpec.max !== undefined ? optRow.optSpec.max : 100
                            decimals: 0
                            modelValue: studio.sOpt(optRow.optKey,
                                                    optRow.optSpec["default"] !== undefined
                                                    ? optRow.optSpec["default"] : 0)
                            onCommitted: function (v) {
                                studio.setOption(optRow.optKey, Math.round(v));
                            }
                        }

                        // Item (et non Row) : le libellé est ancré à gauche et
                        // la pilule à droite, ce qu'un Row interdit.
                        Item {
                            width: optRow.width
                            visible: studio.sel !== null && optRow.optSpec.type === "bool"
                            height: 26

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 150
                                text: optRow.optKey
                                font.pixelSize: 10
                                color: Theme.textDim
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }

                            Rectangle {
                                id: boolPill
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 46
                                height: 22
                                radius: 11
                                readonly property bool isOn: studio.sOpt(optRow.optKey, false) === true
                                color: isOn ? Theme.a(Theme.accent, 0.85) : Theme.a(Theme.text, 0.10)

                                Text {
                                    anchors.centerIn: parent
                                    text: boolPill.isOn ? "on" : "off"
                                    font.pixelSize: 9
                                    color: boolPill.isOn ? Theme.ink : Theme.textDim
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: studio.setOption(optRow.optKey, !boolPill.isOn)
                                }
                            }
                        }

                        Flow {
                            width: optRow.width
                            visible: studio.sel !== null && optRow.optSpec.type === "enum"
                            spacing: 6

                            Text {
                                width: parent.width
                                text: optRow.optKey
                                font.pixelSize: 9
                                color: Theme.textDim
                            }

                            Repeater {
                                model: optRow.optSpec.values !== undefined ? optRow.optSpec.values : []

                                delegate: Rectangle {
                                    id: enumChip
                                    required property var modelData
                                    readonly property bool active: studio.sOpt(optRow.optKey, "") === modelData
                                    width: enumLabel.implicitWidth + 18
                                    height: 22
                                    radius: Theme.radiusBtn
                                    color: active ? Theme.a(Theme.accent, 0.85) : Theme.a(Theme.text, 0.06)

                                    Text {
                                        id: enumLabel
                                        anchors.centerIn: parent
                                        text: enumChip.modelData
                                        font.pixelSize: 9
                                        color: (studio.sOpt(optRow.optKey, "") === enumChip.modelData)
                                               ? Theme.ink : Theme.textDim
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: studio.setOption(optRow.optKey, enumChip.modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // — actions —
                Row {
                    width: styleCol.width
                    visible: studio.sel !== null
                    spacing: 8

                    Rectangle {
                        width: Math.round((styleCol.width - 8) / 2)
                        height: 28
                        radius: Theme.radiusBtn
                        color: resetHover.containsMouse ? Theme.a(Theme.accent, 0.75) : Theme.a(Theme.text, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: "Réinitialiser"
                            font.pixelSize: 10
                            color: resetHover.containsMouse ? Theme.ink : Theme.text
                        }

                        MouseArea {
                            id: resetHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: studio.resetSelected()
                        }
                    }

                    Rectangle {
                        width: Math.round((styleCol.width - 8) / 2)
                        height: 28
                        radius: Theme.radiusBtn
                        color: removeHover.containsMouse ? Theme.a(Theme.hot, 0.55) : Theme.a(Theme.text, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: "Retirer"
                            font.pixelSize: 10
                            color: removeHover.containsMouse ? Theme.ink : Theme.text
                        }

                        MouseArea {
                            id: removeHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: studio.removeWidget(studio.selId)
                        }
                    }
                }
            }
        }
    }
}
