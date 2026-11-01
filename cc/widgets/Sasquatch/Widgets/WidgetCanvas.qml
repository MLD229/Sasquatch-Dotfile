// WidgetCanvas.qml — placement des widgets dans un hôte.
//
// Deux géométries (brief §4/§5) :
//   grid : hôte `cc` — 12 colonnes, ligne 96 px, écart 14 ; geo = {col,row,w,h}
//   free : hôte `background` — geo.x/geo.y en FRACTIONS 0..1 (robuste au
//          changement de résolution), geo.w/geo.h en px, bornés au canvas
//   slot : hôte `bar|subpage` — geo.slot (ordre entier)
//
// Le QML ne réécrit JAMAIS widgets.json : drag/resize postent une seule
// opération au relâchement (move / resize) sur POST /api/widgets. L'hôte
// relit ensuite le fichier (FileView) : la vérité reste le fichier du serveur.
import QtQuick
import Sasquatch.Widgets 1.0

Item {
    id: canvas

    property string host: "cc"
    property string layout: "grid"
    property bool editing: false
    property var instances: []

    // Studio (v1c-2) : id de l'instance sélectionnée (posé par la page) et
    // deux signaux remontés au parent — le canvas ne décide jamais du sort
    // d'une instance, il signale (la page poste).
    property string selectedId: ""
    signal instanceClicked(string id)
    signal instanceRemoveRequested(string id)

    // Grille CC (brief §5)
    property int columns: 12
    property real rowHeight: 96
    property real gap: Theme.spacing

    // Lignes réellement occupées (hôte grid). Sert à dimensionner le board sur
    // son contenu : une grille de 5 lignes sur un panneau plein écran laissait
    // la moitié basse vide.
    readonly property int usedRows: {
        var r = 0;
        for (var i = 0; i < canvas.instances.length; ++i) {
            var g = canvas.instances[i].geo || {};
            r = Math.max(r, Math.round(g.row || 0) + Math.round(g.h || 1));
        }
        return Math.max(1, r);
    }
    readonly property real contentHeight: canvas.usedRows * canvas.rowHeight
                                          + Math.max(0, canvas.usedRows - 1) * canvas.gap

    // Rectangles de widgets qui doivent CAPTER la souris (masque d'entrée du
    // fond d'écran). Correctif brief bugs §1.6/§3 : plus de plafond à 8, et
    // hors édition seuls les widgets `live` captent — les autres laissent
    // passer le clic au lieu de l'avaler. Aucun rectangle vide n'est émis.
    readonly property var inputRects: {
        var out = [];
        var list = canvas.instances || [];
        for (var i = 0; i < list.length; ++i) {
            var inst = list[i];
            if (!inst)
                continue;
            // TOUS les widgets captent la souris : sur le fond d'écran aussi,
            // un widget doit réagir (momo : « aucun ne réagit au clic »).
            // Le masque ne couvre que les rectangles des widgets, donc le reste
            // du bureau continue de traverser.
            var r = canvas.rectFor(inst);
            if (!(r.w > 0) || !(r.h > 0))
                continue;
            out.push({ x: r.x, y: r.y, w: r.w, h: r.h });
        }
        return out;
    }

    readonly property real cellWidth: Math.max(1, (canvas.width - canvas.gap * (canvas.columns - 1)) / canvas.columns)

    // ── Bornes de placement libre (brief §4) ──────────────────────────────
    // Un widget de largeur `wPx` ne peut pas commencer plus loin que
    // 1 - wPx/canvasW : sinon x + w/canvasW > 1 et le widget sort de l'écran.
    // C'est cette fraction-là qui est PERSISTÉE au relâchement du drag : sans
    // elle, le fichier gardait 0.9 pour un widget de 420 px sur 900 px et le
    // widget « sautait » à chaque relecture (le rendu reclampe, pas le JSON).
    function freeX(fx, wPx) {
        var lim = Math.max(0, 1 - Math.max(0, wPx) / Math.max(1, canvas.width));
        var v = (typeof fx === "number" && isFinite(fx)) ? fx : 0;
        return Math.max(0, Math.min(lim, v));
    }

    function freeY(fy, hPx) {
        var lim = Math.max(0, 1 - Math.max(0, hPx) / Math.max(1, canvas.height));
        var v = (typeof fy === "number" && isFinite(fy)) ? fy : 0;
        return Math.max(0, Math.min(lim, v));
    }

    // ── Visibilité de la surface (brief v1b) ──────────────────────────────
    // Music n'ouvre le poll 1 s et le viz 60 ms que si une surface d'accueil
    // est visible ; masquer l'hôte (CC fermé, fond d'écran caché) arrête les
    // deux timers. Enregistrement par clé pour que plusieurs hôtes du même
    // processus ne s'annulent pas.
    property string surfaceKey: canvas.host
    onVisibleChanged: Music.setSurface(canvas.surfaceKey, canvas.visible)
    Component.onCompleted: Music.setSurface(canvas.surfaceKey, canvas.visible)
    Component.onDestruction: Music.setSurface(canvas.surfaceKey, false)

    // ── Géométrie ─────────────────────────────────────────────────────────
    function cellOf(inst) {
        var g = (inst && inst.geo) ? inst.geo : ({});
        return {
            col: Math.max(0, Math.round(g.col || 0)),
            row: Math.max(0, Math.round(g.row || 0)),
            w: Math.max(1, Math.round(g.w || 4)),
            h: Math.max(1, Math.round(g.h || 2))
        };
    }

    function rectFor(inst) {
        if (canvas.layout === "grid") {
            var c = canvas.cellOf(inst);
            var cw = canvas.cellWidth;
            return {
                x: c.col * (cw + canvas.gap),
                y: c.row * (canvas.rowHeight + canvas.gap),
                w: c.w * cw + (c.w - 1) * canvas.gap,
                h: c.h * canvas.rowHeight + (c.h - 1) * canvas.gap
            };
        }
        var g = (inst && inst.geo) ? inst.geo : ({});
        var fx = (typeof g.x === "number") ? g.x : 0;
        var fy = (typeof g.y === "number") ? g.y : 0;
        var w = (typeof g.w === "number") ? g.w : 360;
        var h = (typeof g.h === "number") ? g.h : 180;
        w = Math.min(w, canvas.width);
        h = Math.min(h, canvas.height);
        // Clamp en FRACTION : x + w/canvasW <= 1 (et idem en y).
        fx = canvas.freeX(fx, w);
        fy = canvas.freeY(fy, h);
        return {
            x: fx * canvas.width,
            y: fy * canvas.height,
            w: Math.max(1, w),
            h: Math.max(1, h)
        };
    }

    // Taille réelle de la surface : le serveur en a besoin pour borner
    // `x + w/écran <= 1` sur l'hôte libre (il ne connaît pas l'écran).
    function screenOp() {
        return { w: Math.round(canvas.width), h: Math.round(canvas.height) };
    }

    // ── État de rendu par instance (vignette d'attente) ───────────────────
    // Chaque Loader déclare son statut ici : la page (Studio) et les sondes
    // savent combien d'instances sont RÉELLEMENT dessinées, sans lire l'arbre.
    //   status : 0 Null (source vide) · 1 Ready · 2 Loading · 3 Error
    property var loadStates: ({})

    function setLoadState(id, status) {
        if (typeof id !== "string" || id.length === 0)
            return;
        var m = Object.assign({}, canvas.loadStates);
        m[id] = status;
        canvas.loadStates = m;
    }

    function statusOf(id) {
        var v = canvas.loadStates[id];
        return (typeof v === "number") ? v : 0;
    }

    readonly property int readyCount: canvas.countStatus(1)
    readonly property int pendingCount: {
        // Dépend de loadStates ET de la liste : un ajout non encore chargé
        // compte, et un retrait disparaît.
        var n = 0;
        var list = canvas.instances || [];
        var seen = canvas.loadStates || {};
        for (var i = 0; i < list.length; ++i) {
            var it = list[i];
            if (!it)
                continue;
            var s = seen[it.id];
            if (typeof s !== "number" || s !== 1)
                n += 1;
        }
        return n;
    }

    function countStatus(status) {
        var n = 0;
        var list = canvas.instances || [];
        var seen = canvas.loadStates || {};
        for (var i = 0; i < list.length; ++i) {
            var it = list[i];
            if (it && seen[it.id] === status)
                n += 1;
        }
        return n;
    }

    // Libellé de la vignette : dit POURQUOI il n'y a rien de dessiné.
    function pendingLabel(loader, type) {
        var t = (typeof type === "string" && type.length > 0) ? type : "widget";
        if (loader.status === Loader.Error)
            return "échec de chargement · " + t;
        var src = (loader.source === undefined || loader.source === null) ? "" : ("" + loader.source);
        if (src.length === 0)
            return "composant non livré · " + t;
        return "chargement… · " + t;
    }

    function commitMove(wrapper) {
        var inst = wrapper.inst;
        if (!inst)
            return;
        var geo;
        if (canvas.layout === "grid") {
            var col = Math.round(wrapper.x / (canvas.cellWidth + canvas.gap));
            var row = Math.round(wrapper.y / (canvas.rowHeight + canvas.gap));
            geo = { col: col, row: row };
        } else {
            // Les fractions persistées respectent x + w/canvasW <= 1 : ce que
            // l'écran affiche est ce que le fichier contient (aucun saut à la
            // relecture).
            var wPx = Math.max(1, wrapper.width);
            var hPx = Math.max(1, wrapper.height);
            var fx = canvas.freeX(wrapper.x / Math.max(1, canvas.width), wPx);
            var fy = canvas.freeY(wrapper.y / Math.max(1, canvas.height), hPx);
            geo = {
                x: Math.round(fx * 10000) / 10000,
                y: Math.round(fy * 10000) / 10000
            };
        }
        var op = { op: "move", id: inst.id, geo: geo };
        if (canvas.layout !== "grid")
            op.screen = canvas.screenOp();
        canvas.post(op);
    }

    function commitResize(wrapper) {
        var inst = wrapper.inst;
        if (!inst)
            return;
        var geo;
        if (canvas.layout === "grid") {
            var gw = Math.max(1, Math.round(wrapper.width / (canvas.cellWidth + canvas.gap)));
            var gh = Math.max(1, Math.round(wrapper.height / (canvas.rowHeight + canvas.gap)));
            geo = { w: gw, h: gh };
        } else {
            geo = { w: Math.round(wrapper.width), h: Math.round(wrapper.height) };
        }
        var op = { op: "resize", id: inst.id, geo: geo };
        if (canvas.layout !== "grid")
            op.screen = canvas.screenOp();
        canvas.post(op);
    }

    function post(op) {
        Api.post("/api/widgets", op, function (d) {
            if (!d || d.ok !== true)
                console.warn("widgets: opération refusée —", d ? d.error : "pas de réponse");
        });
    }

    // ── Instances ─────────────────────────────────────────────────────────
    Repeater {
        model: canvas.instances

        delegate: Item {
            id: wrapper
            // Nom d'objet : diagnostic (studio-probe.qml compte les wrappers et
            // l'état des Loader pour prouver qu'une instance est RENDUE).
            objectName: "widget-wrapper"
            property var inst: modelData
            property var r: canvas.rectFor(wrapper.inst)
            // L'instance sélectionnée passe devant les autres (Studio).
            z: (wrapper.inst && wrapper.inst.id === canvas.selectedId) ? 5 : 1

            // Placé par l'hôte hors édition ; en édition le drag écrit x/y et la
            // poignée de resize écrit width/height. Aucune liaison directe
            // width/height ici : elle se réappliquait pendant le drag et
            // annulait le redimensionnement (l'aperçu du Studio était figé).
            Binding {
                target: wrapper
                property: "x"
                value: wrapper.r.x
                when: !canvas.editing
            }
            Binding {
                target: wrapper
                property: "y"
                value: wrapper.r.y
                when: !canvas.editing
            }
            Binding {
                target: wrapper
                property: "width"
                value: wrapper.r.w
                when: !canvas.editing
            }
            Binding {
                target: wrapper
                property: "height"
                value: wrapper.r.h
                when: !canvas.editing
            }

            // Amorçage : quand l'hôte démarre DÉJÀ en édition (Studio), les
            // Binding x/y/w/h sont inactives et le widget naissait en 0,0 à la
            // taille par défaut au lieu de sa géométrie enregistrée.
            Component.onCompleted: {
                if (canvas.editing) {
                    wrapper.x = wrapper.r.x;
                    wrapper.y = wrapper.r.y;
                    wrapper.width = wrapper.r.w;
                    wrapper.height = wrapper.r.h;
                }
            }

            Loader {
                id: loader
                objectName: "widget-loader"
                anchors.fill: parent
                // Chemin du composant : registre UNIQUEMENT (brief §4).
                source: WidgetRegistry.component(wrapper.inst ? wrapper.inst.type : "")
                // Statut publié au canvas (compteur « prêt / en attente »).
                onStatusChanged: canvas.setLoadState(wrapper.inst ? wrapper.inst.id : "", loader.status)
                Component.onCompleted: canvas.setLoadState(wrapper.inst ? wrapper.inst.id : "", loader.status)
            }

            // Vignette d'attente EXPLICITE (brief transparence §3) : un widget
            // dont le composant n'est pas livré, ou dont le chargement échoue,
            // doit se VOIR — jamais un trou invisible. Posée SOUS le Loader :
            // dès que celui-ci est Ready, elle disparaît.
            Rectangle {
                objectName: "widget-pending"
                anchors.fill: parent
                radius: Theme.radiusCard
                visible: loader.status !== Loader.Ready
                color: Theme.fill(0.10)
                border.width: 1
                border.color: Theme.a(Theme.warn, 0.35)

                Column {
                    anchors.centerIn: parent
                    width: Math.max(1, parent.width - 20)
                    spacing: 2

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: canvas.pendingLabel(loader, wrapper.inst ? wrapper.inst.type : "")
                        color: Theme.ink
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: wrapper.inst !== undefined && wrapper.inst !== null
                        text: (wrapper.inst && wrapper.inst.variant) ? wrapper.inst.variant : ""
                        color: Theme.inkDim
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                }
            }

            Binding {
                target: loader.item
                property: "instanceId"
                value: wrapper.inst ? wrapper.inst.id : ""
                when: loader.status === Loader.Ready
            }
            Binding {
                target: loader.item
                property: "host"
                value: canvas.host
                when: loader.status === Loader.Ready
            }
            Binding {
                target: loader.item
                property: "variant"
                value: wrapper.inst ? wrapper.inst.variant : "normal"
                when: loader.status === Loader.Ready
            }
            Binding {
                target: loader.item
                property: "editing"
                value: canvas.editing
                when: loader.status === Loader.Ready
            }
            Binding {
                target: loader.item
                property: "style"
                value: wrapper.inst ? (wrapper.inst.style || ({})) : ({})
                when: loader.status === Loader.Ready
            }
            Binding {
                target: loader.item
                property: "options"
                value: wrapper.inst ? (wrapper.inst.options || ({})) : ({})
                when: loader.status === Loader.Ready
            }
            Binding {
                target: loader.item
                property: "dragTarget"
                value: wrapper
                when: loader.status === Loader.Ready
            }
            Binding {
                target: loader.item
                property: "selected"
                value: !!(wrapper.inst && wrapper.inst.id === canvas.selectedId)
                when: loader.status === Loader.Ready
            }
            // Échelle du conteneur : l'aperçu du Studio réduit un écran
            // entier, la poignée de resize en a besoin (WidgetBase.uiScale).
            Binding {
                target: loader.item
                property: "uiScale"
                value: canvas.scale
                when: loader.status === Loader.Ready
            }

            Connections {
                target: loader.item
                ignoreUnknownSignals: true
                function onDragFinished() {
                    canvas.commitMove(wrapper);
                }
                function onResizeFinished() {
                    canvas.commitResize(wrapper);
                }
                function onEditClicked() {
                    canvas.instanceClicked(wrapper.inst ? wrapper.inst.id : "");
                }
                function onRemoveRequested() {
                    canvas.instanceRemoveRequested(wrapper.inst ? wrapper.inst.id : "");
                }
            }
        }
    }
}
