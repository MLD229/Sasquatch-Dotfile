// WidgetRegistry.qml — singleton : catalogue des widgets (registry.json).
//
// Règle (brief §4) : le chemin d'un composant ne vient JAMAIS du fichier
// d'instances (widgets.json), seulement de ce registre embarqué. Les bornes de
// style/options viennent d'ici aussi : le QML et widgets_json.py lisent le
// MÊME fichier, donc les deux clamps sont identiques.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: reg

    property var entries: []
    property string lastError: ""
    property bool ready: false
    property int revision: 0

    readonly property url registryPath: Qt.resolvedUrl("registry.json")

    // ── Chargement ────────────────────────────────────────────────────────
    function applyText(txt) {
        if (!txt || txt.trim().length === 0) {
            reg.lastError = "registry.json vide — catalogue précédent conservé";
            return;
        }
        var parsed = null;
        try {
            parsed = JSON.parse(txt);
        } catch (e) {
            reg.lastError = "registry.json invalide (" + e.message + ") — catalogue précédent conservé";
            return;
        }
        if (!parsed || !Array.isArray(parsed.widgets)) {
            reg.lastError = "registry.json sans tableau `widgets` — catalogue précédent conservé";
            return;
        }
        reg.entries = parsed.widgets.filter(function (w) {
            return w && typeof w === "object" && typeof w.id === "string" && w.id.length > 0;
        });
        reg.ready = true;
        reg.lastError = "";
        reg.revision += 1;
    }

    // ── Résolution id → entrée / composant / variantes ────────────────────
    function entry(id) {
        for (var i = 0; i < reg.entries.length; ++i) {
            if (reg.entries[i].id === id)
                return reg.entries[i];
        }
        return null;
    }

    function exists(id) {
        return reg.entry(id) !== null;
    }

    // Un widget déclaré mais non livré (media en v1a) a `component: ""`.
    // NB : champ du registre SEULEMENT — la preuve « fichier sur disque » est
    // `resolveState()` plus bas, seule source de vérité pour l'UI.
    function isAvailable(id) {
        var e = reg.entry(id);
        return e !== null && typeof e.component === "string" && e.component.length > 0;
    }

    // URL du composant — SEULE source du chemin (brief §4).
    function component(id) {
        var e = reg.entry(id);
        if (!e || typeof e.component !== "string" || e.component.length === 0)
            return "";
        return Qt.resolvedUrl("widgets/" + e.component);
    }

    // ── Composant RÉELLEMENT livré (anti « widget fantôme ») ──────────────
    // `isAvailable()` ne lit qu'un champ du registre : une entrée qui nomme un
    // fichier ABSENT passait pour livrée → le Studio proposait la tuile et
    // l'hôte dessinait un rectangle vide (« des widgets inexistants sont
    // montrés »). La vérité est le disque : UNE lecture du dossier `widgets/`
    // au démarrage, puis comparaison du nom de fichier — exactement la règle
    // de `component()` (chemin = `<module>/widgets/<component>`).
    //   delivered      : table { "ClockWidget.qml": true, … }, null = sonde
    //                    pas encore revenue (on ne cache rien entre-temps)
    //   deliveredError : dit pourquoi la sonde n'a pas conclu
    property var delivered: null
    property string deliveredError: ""
    property int deliveredCount: -1
    property bool probeStarted: false
    signal availabilityChanged()

    // Sonde PARESSEUSE : la barre importe le même module mais ne dessine
    // aucun widget — elle ne doit pas payer un processus. Le premier appel à
    // `resolveState()` (Studio, canevas) démarre la lecture, une seule fois.
    function ensureDelivered() {
        if (!reg.probeStarted && reg.widgetsDirPath.length > 0)
            reg.probeStarted = true;
        return reg.delivered;
    }

    readonly property string widgetsDirPath: reg.filePath(Qt.resolvedUrl("widgets/"))

    // file://… → chemin absolu (le shell ne reçoit pas de QUrl).
    function filePath(u) {
        var s = "" + u;
        if (s.indexOf("file://") !== 0)
            return "";
        s = s.substring(7);
        try {
            s = decodeURIComponent(s);
        } catch (e) {
            // chemin déjà littéral : on garde tel quel
        }
        return s;
    }

    function applyDelivered(text) {
        var lines = ("" + text).split("\n");
        var base = reg.widgetsDirPath;
        if (base.length > 0 && base.charAt(base.length - 1) !== "/")
            base += "/";
        var map = {};
        var n = 0;
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i].trim();
            if (line.length === 0)
                continue;
            var rel = line;
            if (base.length > 0 && rel.indexOf(base) === 0)
                rel = rel.substring(base.length);
            if (rel.length === 0 || rel.charAt(0) === "/")
                continue;
            map[rel] = true;
            n += 1;
        }
        reg.delivered = map;
        reg.deliveredCount = n;
        reg.deliveredError = "";
        reg.availabilityChanged();
    }

    // État de résolution d'un type : { ok, url, reason }.
    // `reason` est affichée TELLE QUELLE dans la tuile « indisponible ».
    function resolveState(id) {
        reg.ensureDelivered();
        var e = reg.entry(id);
        if (!e)
            return { ok: false, url: "", reason: "type absent du registre" };
        var comp = (typeof e.component === "string") ? e.component.trim() : "";
        if (comp.length === 0)
            return { ok: false, url: "", reason: "composant non livré (registre)" };
        var key = comp;
        if (key.indexOf("./") === 0)
            key = key.substring(2);
        var url = reg.component(id);
        if (reg.delivered === null)
            return { ok: true, url: url, reason: "" };       // sonde en cours
        if (!reg.delivered[key])
            return { ok: false, url: url, reason: "fichier manquant : widgets/" + key };
        return { ok: true, url: url, reason: "" };
    }

    function isResolved(id) {
        return reg.resolveState(id).ok;
    }

    // Sonde : une seule commande, chemin passé en $1 (aucune interpolation de
    // shell). Les deux marqueurs distinguent « dossier absent » de « dossier
    // vide » ; sans marqueur, `delivered` reste null (état « inconnu », on ne
    // grise rien et on ne promet rien).
    property Process deliveredProbe: Process {
        command: ["/bin/sh", "-c",
                  "d=$1; [ -d \"$d\" ] || { printf '%s\\n' __NO_DIR__; exit 3; }; " +
                  "find \"$d\" -name '*.qml' -type f -print; printf '%s\\n' __END__",
                  "sh", reg.widgetsDirPath]
        running: reg.probeStarted
        stdout: StdioCollector {
            onStreamFinished: reg.readProbe(this.text || "")
        }
    }

    function readProbe(text) {
        var t = "" + text;
        if (t.indexOf("__NO_DIR__") >= 0) {
            reg.deliveredError = "dossier widgets introuvable : " + reg.widgetsDirPath;
            return;
        }
        if (t.indexOf("__END__") < 0) {
            reg.deliveredError = "sonde incomplète (find indisponible ?)";
            return;
        }
        reg.applyDelivered(t.substring(0, t.indexOf("__END__")));
    }

    function variantNames(id) {
        var e = reg.entry(id);
        return (e && e.variants) ? Object.keys(e.variants) : [];
    }

    function variantOrDefault(id) {
        var e = reg.entry(id);
        if (!e)
            return "normal";
        return (typeof e.defaultVariant === "string" && e.variants && e.variants[e.defaultVariant])
                ? e.defaultVariant : reg.variantNames(id)[0] || "normal";
    }

    // Taille naturelle par variante (défauts brief §2 : 220x64 / 360x180 / 560x260).
    function variantSize(id, variant) {
        var e = reg.entry(id);
        var def = (variant === "compact") ? ({ w: 220, h: 64, cell: [4, 1] })
                : (variant === "hero") ? ({ w: 560, h: 260, cell: [8, 2] })
                : ({ w: 360, h: 180, cell: [4, 2] });
        if (!e || !e.variants)
            return def;
        var v = e.variants[variant] || e.variants[reg.variantOrDefault(id)] || def;
        return {
            w: (typeof v.w === "number") ? v.w : def.w,
            h: (typeof v.h === "number") ? v.h : def.h,
            cell: Array.isArray(v.cell) ? v.cell : def.cell
        };
    }

    function hosts(id) {
        var e = reg.entry(id);
        return (e && Array.isArray(e.hosts)) ? e.hosts : ["cc"];
    }

    function hostAllowed(id, host) {
        return reg.hosts(id).indexOf(host) >= 0;
    }

    // Un widget `live` reste cliquable sur le fond d'écran (clic = ouvrir le CC).
    function isLive(id) {
        var e = reg.entry(id);
        return !!(e && e.live === true);
    }

    // ── Bornes de style ───────────────────────────────────────────────────
    // `blur` reste déclaré (schéma + panneau du Studio) mais n'est plus
    // appliqué : aucun flou dans l'interface (brief transparence).
    function styleBounds(id) {
        var e = reg.entry(id);
        var s = (e && e.style) ? e.style : ({});
        return {
            alpha: Array.isArray(s.alpha) ? s.alpha : [0.03, 0.35],
            blur: Array.isArray(s.blur) ? s.blur : [0, 20],
            radius: Array.isArray(s.radius) ? s.radius : [0, 24],
            accent: Array.isArray(s.accent) ? s.accent : ["auto"]
        };
    }

    function defaultStyle(id, variant) {
        var e = reg.entry(id);
        if (e && e.defaultStyle && typeof e.defaultStyle === "object")
            return Object.assign({}, e.defaultStyle);
        var v = variant || reg.variantOrDefault(id);
        return {
            alpha: (v === "hero") ? 0.05 : 0.08,
            accent: "auto",
            blur: 9,
            radius: 16
        };
    }

    function clampNum(v, lo, hi) {
        if (typeof v !== "number" || !isFinite(v))
            return lo;
        return Math.max(lo, Math.min(hi, v));
    }

    function sanitizeStyle(id, style) {
        var b = reg.styleBounds(id);
        var s = (style && typeof style === "object") ? style : ({});
        var out = reg.defaultStyle(id);
        if (typeof s.alpha === "number")
            out.alpha = reg.clampNum(s.alpha, b.alpha[0], b.alpha[1]);
        if (typeof s.blur === "number")
            out.blur = Math.round(reg.clampNum(s.blur, b.blur[0], b.blur[1]));
        if (typeof s.radius === "number")
            out.radius = Math.round(reg.clampNum(s.radius, b.radius[0], b.radius[1]));
        if (typeof s.accent === "string" && b.accent.indexOf(s.accent) >= 0)
            out.accent = s.accent;
        return out;
    }

    // ── Bornes d'options (mêmes règles que widgets_json.py) ───────────────
    function optionSpec(id, key) {
        var e = reg.entry(id);
        if (!e || !e.options || !e.options[key])
            return null;
        return e.options[key];
    }

    function defaultOptions(id) {
        var e = reg.entry(id);
        var out = {};
        if (!e || !e.options)
            return out;
        var keys = Object.keys(e.options);
        for (var i = 0; i < keys.length; ++i) {
            var spec = e.options[keys[i]];
            if (spec && spec["default"] !== undefined)
                out[keys[i]] = spec["default"];
        }
        return out;
    }

    function sanitizeOptions(id, options) {
        var e = reg.entry(id);
        var out = reg.defaultOptions(id);
        if (!e || !e.options || !options || typeof options !== "object")
            return out;
        var keys = Object.keys(options);
        for (var i = 0; i < keys.length; ++i) {
            var spec = e.options[keys[i]];
            if (!spec)
                continue;
            var v = options[keys[i]];
            if (spec.type === "int") {
                if (typeof v === "number" && isFinite(v))
                    out[keys[i]] = Math.round(reg.clampNum(v, spec.min, spec.max));
            } else if (spec.type === "bool") {
                if (typeof v === "boolean")
                    out[keys[i]] = v;
            } else if (spec.type === "enum") {
                if (typeof v === "string" && Array.isArray(spec.values) && spec.values.indexOf(v) >= 0)
                    out[keys[i]] = v;
            } else if (spec.type === "string") {
                if (typeof v === "string")
                    out[keys[i]] = v;
            } else {
                out[keys[i]] = v;
            }
        }
        return out;
    }

    property FileView file: FileView {
        path: reg.registryPath
        watchChanges: true
        blockLoading: true
        printErrors: true
        onFileChanged: reg.file.reload()
        onTextChanged: reg.applyText(reg.file.text())
        onLoaded: reg.applyText(reg.file.text())
    }
}
