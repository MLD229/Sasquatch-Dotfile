// WidgetBase.qml — base commune des 16 widgets (contrat brief §2).
//
// Racine = MouseArea (drag + curseur, comme demandé). Elle porte :
//   - les 6 propriétés du contrat (instanceId, host, variant, editing, style, options) ;
//   - la taille naturelle PAR VARIANTE (lue dans le registre, jamais en dur) ;
//   - la carte de verre (alpha/rayon depuis Theme — aucun hex, AUCUN flou) ;
//   - le drag du wrapper fourni par l'hôte et la poignée de resize 10 px.
// Un widget dérive de ce fichier et n'ajoute QUE son contenu.
//
// `interactive` (brief §2) : faux en édition, et faux sur le fond d'écran sauf
// widget `live` (media, clock) — là, un clic ouvre le CC au lieu d'être avalé.
import QtQuick
import Quickshell
import Sasquatch.Widgets 1.0

MouseArea {
    id: base

    // ── Contrat §2 ────────────────────────────────────────────────────────
    property string instanceId: ""
    // Type de registre du widget (posé par le widget concret, ex. "clock") :
    // sert uniquement à lire variantes/bornes dans le registre.
    property string widgetType: ""
    property string host: "cc"
    property string variant: "normal"
    property bool editing: false
    property var style: ({})
    property var options: ({})

    // ── Taille naturelle par variante ─────────────────────────────────────
    readonly property var vsize: WidgetRegistry.variantSize(base.widgetType, base.variant)
    implicitWidth: base.vsize.w
    implicitHeight: base.vsize.h

    // ── État dérivé ───────────────────────────────────────────────────────
    readonly property bool live: WidgetRegistry.isLive(base.widgetType)
    readonly property bool backgroundHost: base.host === "background"
    // Tous les hôtes sont interactifs hors édition : un widget posé sur le fond
    // d'écran doit répondre au clic comme dans le CC (brief momo).
    readonly property bool interactive: !base.editing
    readonly property bool compact: base.variant === "compact"
    readonly property bool hero: base.variant === "hero"

    readonly property real cardAlpha: Theme.cardAlpha(base.style, base.variant)
    readonly property int radius: Theme.radiusFor(base.style)
    readonly property color ink: Theme.ink
    readonly property color inkDim: Theme.inkDim
    // Padding intérieur ≥ 10 px (brief §3), proportionnel à la carte.
    readonly property int pad: Math.max(10, Math.round(Math.min(base.width, base.height) * 0.09))

    // Cible du drag = le wrapper de l'hôte (WidgetCanvas). Sans wrapper, pas
    // de drag : la base ne se déplace jamais elle-même (l'hôte positionne).
    property Item dragTarget: null
    readonly property bool dragEnabled: base.editing && base.dragTarget !== null

    signal dragFinished()
    signal resizeFinished()
    signal activated()
    // Studio (v1c-2) : en édition, un clic SÉLECTIONNE et un double-clic
    // DEMANDE le retrait. L'hôte décide (WidgetCanvas relaie, StudioPage
    // poste). Hors édition, rien ne change : c'est toujours `activated()`.
    signal editClicked()
    signal removeRequested()

    // Facteur d'échelle du conteneur. L'aperçu du Studio dessine l'écran
    // entier (1920x1080) réduit : la poignée de resize mesure des
    // déplacements en coordonnées de scène, donc sans ce facteur elle
    // ferait grossir le widget 1/échelle fois moins vite que la souris.
    property real uiScale: 1
    readonly property real dragScale: Math.max(0.01, base.uiScale)

    // Sélection (Studio) : contour accent 2 px, au-dessus du contenu.
    property bool selected: false
    // Survol souris (jamais de contour au repos, seulement au survol).
    readonly property bool hovered: base.containsMouse

    // ── Interaction ───────────────────────────────────────────────────────
    enabled: base.interactive || base.editing
    // Hover actif : sans survol (donc sans `enabled`) il est simplement ignoré ;
    // c'est lui qui autorise le trait discret au survol d'une carte.
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: base.dragEnabled ? Qt.DragMoveCursor
                                  : (base.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor)

    property real _pressX: 0
    property real _pressY: 0
    property bool _moved: false

    drag.target: base.dragEnabled ? base.dragTarget : null
    drag.axis: Drag.XAndYAxis
    drag.threshold: 4
    drag.smoothed: false

    onPressed: function (mouse) {
        base._pressX = mouse.x;
        base._pressY = mouse.y;
        base._moved = false;
    }

    onPositionChanged: function (mouse) {
        if (!base.dragEnabled)
            return;
        if (Math.abs(mouse.x - base._pressX) > 3 || Math.abs(mouse.y - base._pressY) > 3)
            base._moved = true;
    }

    onReleased: {
        if (!base._moved)
            return;
        base._moved = false;
        // Un SEUL POST au relâchement (brief §5), jamais pendant le drag.
        base.dragFinished();
    }

    onClicked: {
        if (base.editing) {
            base.editClicked();
            return;
        }
        if (!base.interactive)
            return;
        base.activated();
        // Fond d'écran : cliquer la carte (hors un contrôle interne, qui a
        // déjà consommé le clic) ouvre le CC — le widget reste utilisable
        // depuis le bureau.
        if (base.backgroundHost)
            Quickshell.execDetached([Qt.resolvedUrl("../../../cc.sh").toString().replace("file://", "")]);
    }

    // Double-clic en édition = retrait (Studio, brief §7 v1c-2).
    onDoubleClicked: {
        if (base.editing)
            base.removeRequested();
    }

    // Carte de verre (brief §3). `showCard: false` = widget sans fond
    // (variante `visualizer` du média : cava seul, brief §6).
    property bool showCard: true

    // ── Carte de verre (brief transparence) ───────────────────────────────
    // Décision nette : AUCUN flou (ni halo MultiEffect, ni bordure au repos).
    // La carte n'est qu'un remplissage très léger : ce sont les contenus
    // (textes, jauges, icônes) qui portent l'information, à 100 % d'opacité.
    // Le contour n'apparaît qu'en édition (drag/sélection) ou au survol.
    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: base.radius
        color: Theme.fill(base.cardAlpha)
        visible: base.showCard
    }

    // Survol : trait accent discret (jamais blanc) — sinon aucun contour.
    Rectangle {
        anchors.fill: parent
        radius: base.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.a(Theme.accent, 0.55)
        visible: base.showCard && base.hovered && !base.editing
    }

    // Contour d'édition : 1 px accent (brief §5).
    Rectangle {
        visible: base.editing
        anchors.fill: parent
        radius: base.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.accent
    }

    // Sélection (Studio) : 2 px accent, au-dessus du contenu du widget —
    // sans quoi le contenu du widget recouvrait le contour (les enfants
    // d'un composant dérivé sont posés après ceux de la base).
    Rectangle {
        z: 98
        visible: base.selected
        anchors.fill: parent
        anchors.margins: -1
        radius: base.radius + 1
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
    }

    // Poignée de resize 10 px, coin bas-droit, uniquement en édition.
    Rectangle {
        id: grip
        z: 100
        visible: base.editing && base.dragTarget !== null
        width: 10
        height: 10
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 3
        radius: 3
        color: gripArea.pressed ? Theme.accent : Theme.halo

        property real _sx: 0
        property real _sy: 0
        property real _w0: 0
        property real _h0: 0

        MouseArea {
            id: gripArea
            anchors.fill: parent
            cursorShape: Qt.SizeFDiagCursor
            onPressed: function (mouse) {
                var p = grip.mapToItem(null, mouse.x, mouse.y);
                grip._sx = p.x;
                grip._sy = p.y;
                grip._w0 = base.dragTarget.width;
                grip._h0 = base.dragTarget.height;
            }
            onPositionChanged: function (mouse) {
                if (!pressed || base.dragTarget === null)
                    return;
                var p = grip.mapToItem(null, mouse.x, mouse.y);
                // /dragScale : l'aperçu du Studio est mis à l'échelle, la
                // poignée mesure des pixels de scène ; sans ça le widget
                // grossissait 1/échelle fois moins vite que la souris.
                base.dragTarget.width = Math.max(120, grip._w0 + (p.x - grip._sx) / base.dragScale);
                base.dragTarget.height = Math.max(64, grip._h0 + (p.y - grip._sy) / base.dragScale);
            }
            onReleased: base.resizeFinished()
        }
    }
}
