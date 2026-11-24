// shell.qml — barre verticale gauche (Quickshell 0.3.2) : point d'entrée.
//
// Lancement : service `sasquatch-bar` (bar.sh = toggle Super+J).
//
// ARCHITECTURE (brief §5, inchangée en v2)
//   shell.qml        cette fenêtre + les surfaces (barre, infobulle, popups)
//   qml/             singletons Config / BarPalette / Backend / AppIndex /
//                    Hypr / Ui / Tip + composants (Pill, IconButton, AppIcon)
//   modules/         un fichier par module, chargé selon bar.json.modules
//   popups/          une surface par popup, ancrée au bord gauche
//   appindex.py      index .desktop (icônes + lancement)
//
// RÈGLES RESPECTÉES
//   - aucune couleur en dur : tout vient de BarPalette (GET /api/palette, 2 s) ;
//   - aucun timer par module : un seul timer de données (Backend) + palette ;
//   - on n'anime jamais la largeur ni l'exclusiveZone de la fenêtre
//     (quickshell#866) ; le masquage = arrêt du service (bar.sh) ;
//   - exclusiveZone = largeur de la barre : Hyprland ajoute marginLeft, ce qui
//     réserve largeur + marge (vérifié avec `hyprctl layers`).
//
// V2 (brief polish) : un seul axe vertical (ColumnLayout + AlignHCenter),
// largeur 46 px et blocs calculés depuis bar.json (Config.block), alphas
// quasi invisibles (Config.panelAlpha / cardAlpha / hoverAlpha).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "qml"
import "modules"
import "popups"

ShellRoot {
    id: shell

    // ── Barre : une seule surface, taille fixe, jamais animée ─────────────
    PanelWindow {
        id: barWin

        // ── Position : left | top | right (bar.json, v5b) ─────────────────
        // Une SEULE fenêtre : on la déplace, on n'en crée jamais une seconde.
        // Les ancrages booléens de la couche viennent de Config, donc le bouton
        // du panneau Settings ne peut pas mentir sur l'état réel.
        //   left  : gauche + haut + bas → verticale, pleine hauteur
        //   right : droite + haut + bas → verticale, pleine hauteur (miroir)
        //   top   : haut + gauche + droite → bande horizontale, pleine largeur
        anchors {
            // v5c : en horizontal il faut DEUX ancrages opposés, sinon la
            // surface reste à 40 px de large (bug « top » : rien de visible).
            left: Config.horizontal || !Config.sideRight
            right: Config.horizontal || Config.sideRight
            top: true
            bottom: Config.vertical
        }
        margins {
            left: Config.marginLeft
            right: Config.marginRight
            top: Config.marginTop
            bottom: Config.vertical ? Config.marginBottom : 0
        }
        // Vertical : la hauteur vient des ancrages haut+bas (plein écran) ;
        // horizontal : deux ancrages opposés (gauche+droite) forcent la largeur
        // à celle de l'écran, implicitWidth est alors ignoré. Dans les deux cas
        // l'ÉPAISSEUR est Config.width (bar.width) : la barre ne change pas
        // d'épaisseur en changeant de bord.
        implicitWidth: Config.width
        implicitHeight: Config.vertical ? 0 : Config.thickness
        // Réserve de la place : l'épaisseur demandée à la surface ; Hyprland
        // ajoute la marge de son côté. Jamais animée (quickshell#866).
        exclusiveZone: (Config.enabled && Config.reserve) ? Config.thickness : 0
        color: "transparent"
        visible: Config.enabled
        focusable: false
        aboveWindows: true

        WlrLayershell.namespace: "sasquatch-bar"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Blur demandé mais discret : radius ≤ 10, sinon voile laiteux sur un
        // fond aussi transparent (brief v2 §3). Valeur : bar.json.blurRadius.
        // v5b : bar.blur = false par défaut → rayon 0, donc AUCUNE bande
        // floutée sur la hauteur de la barre.
        // v5c : BackgroundEffect n'a QUE blurRegion (pas de `enabled` : la
        // propriété n'existe pas et fait planter le chargement). Pour couper le
        // flou on vise une région de taille nulle quand blur=false.
        // Région nulle : le flou n'a alors aucune surface à traiter.
        Item {
            id: zoneSansFlou
            width: 0
            height: 0
            visible: false
        }

        BackgroundEffect.blurRegion: Region {
            item: Config.blur ? barBg : zoneSansFlou
            radius: Config.blur ? Config.blurRadius : 0
        }

        // Fond de barre : RIEN par défaut (panelAlpha 0 et blur false). Le
        // rectangle reste DÉCLARÉ : il est la région du BackgroundEffect
        // ci-dessus et la région d'entrée de la surface — le supprimer ferait
        // tomber les clics à travers la barre.
        Rectangle {
            id: barBg
            anchors.fill: parent
            radius: Config.radius
            color: (Config.panelAlpha > 0 || Config.blur) ? BarPalette.barBg : "transparent"
            border.width: Config.borderAlpha > 0 ? 1 : 0
            border.color: BarPalette.border
        }

        // Clic sur une zone vide de la barre : referme la popup ouverte (v4 §7).
        // Ce MouseArea est SOUS les groupes : un clic sur un module ne passe
        // jamais ici, un clic dans le vide (écart entre deux pilules) si.
        MouseArea {
            id: barClick
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: Ui.close()
        }

        // ── Quatre groupes, UNE seule règle d'espace (v4 §2) ───────────────
        // haut  : recherche + workspaces
        // info  : débit + horloge + volume
        // apps  : épinglées (+ « + ») + en cours
        // bas   : son/wifi/DND + engrenage
        //
        // Chaque groupe prend sa LONGUEUR NATURELLE sur le grand axe (somme de
        // ses blocs) : aucun groupe ne s'étire, donc aucune pilule ne s'étire
        // (bug §1). L'espace libre est réparti à parts égales ENTRE les
        // groupes — une seule règle, pas deux ressorts de tailles différentes.
        //
        // v5b : la MÊME règle sert les trois positions. Le grand axe est
        // vertical (left/right) ou horizontal (top) et les groupes sont des
        // Flow dont la direction suit Config.horizontal : mêmes modules, même
        // ordre, même calcul d'écart. Un groupe est un Flow et non un Row
        // parce que le Flow accepte les deux directions avec les mêmes
        // enfants (aucun module n'est instancié deux fois).
        Item {
            id: stack
            anchors.fill: parent
            // Inset sur le PETIT axe : haut/bas en vertical, gauche/droite en
            // horizontal — les pilules gardent 4 px d'air dans les deux cas.
            anchors.topMargin: Config.vertical ? Config.inset : 0
            anchors.bottomMargin: Config.vertical ? Config.inset : 0
            anchors.leftMargin: Config.vertical ? 0 : Config.inset
            anchors.rightMargin: Config.vertical ? 0 : Config.inset

            readonly property int groupGap: Config.spacing
            readonly property real used: topGroup.main + infoGroup.main
                                         + appsGroup.main + botGroup.main
            // Place disponible sur le grand axe : hauteur (vertical) ou
            // largeur (haut).
            readonly property real mainLen: Config.horizontal ? stack.width : stack.height
            readonly property real freeSpace: stack.mainLen - stack.used
                                              - 3 * stack.groupGap
            // Part de libre ajoutée à CHAQUE écart entre groupes (0 si le
            // contenu remplit déjà la barre : les groupes ne se chevauchent
            // jamais, ils dépassent au pire à l'extrémité).
            // v5d (mode haut) : les modules PRENNENT la longueur au lieu de
            // laisser des vides entre les groupes. En horizontal, l'espace libre
            // est réparti dans la LARGEUR des modules ; en vertical (gauche /
            // droite) rien ne change : c'est l'écart entre groupes qui absorbe.
            readonly property real extra: Config.horizontal
                                           ? 0 : Math.max(0, stack.freeSpace / 3)
            readonly property real gap: stack.groupGap + stack.extra
            readonly property real natTotal: topGroup.nat + infoGroup.nat
                                             + appsGroup.nat + botGroup.nat
            readonly property int nbModules: Config.modules.length
            readonly property real gapsTotal: 3 * Config.spacing
                                              + Math.max(0, stack.nbModules - 4) * Config.spacing
            readonly property real extraModule: Config.horizontal
                ? Math.max(0, (stack.mainLen - stack.natTotal - stack.gapsTotal)
                              / Math.max(1, stack.nbModules))
                : 0
            // Centrage sur le petit axe : la bande fait Config.width, un bloc
            // fait Config.block, donc la même marge des deux côtés.
            readonly property real cross: Config.horizontal
                                          ? Math.round((stack.height - Config.caseH) / 2)
                                          : Math.round((stack.width - Config.block) / 2)

            Component.onCompleted: {
                // mainLen (= hauteur de la surface) vaut 0 tant que le
                // compositeur n'a pas configuré la fenêtre layer : le premier
                // passage sert de mesure, pas de diagnostic. Sans ce garde,
                // chaque démarrage d'une installation neuve affichait
                // « 594 px > place utile -8 px » alors que l'écran est sain
                // (mesuré deux fois : session réelle + Hyprland imbriqué).
                // On ne juge donc que sur une longueur réelle (> 0), et une
                // seule fois par configuration.
                if (stack.mainLen <= 0)
                    return
                if (stack.freeSpace < 0 && !Config.horizontal)
                    console.warn("bar: contenu " + Math.round(stack.used)
                                 + " px > place utile " + Math.round(stack.mainLen)
                                 + " px (position " + Config.position
                                 + ") — réduire persistentWorkspaces ou les apps");
            }

            // ── haut : recherche + workspaces ─────────────────────────────
            Flow {
                id: topGroup
                flow: Config.horizontal ? Flow.LeftToRight : Flow.TopToBottom
                spacing: Config.spacing
                // Somme des largeurs NATURELLES des modules de ce groupe
                // (indépendante de l'étirement, donc aucun cycle de liaison).
                readonly property real nat: {
                    var t = 0;
                    for (var k = 0; k < children.length; k++) {
                        var c = children[k];
                        if (c && c.natW !== undefined)
                            t += c.natW;
                    }
                    return t;
                }
                // Largeur = largeur NATURELLE du Flow (défaut Qt : width =
                // implicitWidth) : somme des enfants en horizontal, colonne de
                // Config.block en vertical. Aucune auto-référence width <->
                // implicitWidth, donc pas de boucle de liaison.
                // Longueur occupée sur le grand axe (lue par stack.used).
                readonly property real main: Config.horizontal ? width : height
                x: Config.horizontal ? 0 : stack.cross
                y: Config.horizontal ? stack.cross : 0

                Repeater {
                    model: shell.modulesIn("top")
                    delegate: Loader {
                        required property string modelData
                        // Largeur NATURELLE du module : sert de base au calcul
                        // d'étirement (ne dépend pas de la largeur imposée).
                        readonly property real natW: item ? Math.ceil(item.implicitWidth) : 0
                        // Horizontal : naturelle + part de l'espace libre (v5d).
                        width: Config.horizontal
                               ? (natW + stack.extraModule)
                               : Config.block
                        height: Config.horizontal
                                ? Config.caseH
                                : (item ? item.implicitHeight : 0)
                        source: shell.moduleSource(modelData)
                    }
                }
            }

            // ── info : débit + horloge + volume ───────────────────────────
            Flow {
                id: infoGroup
                flow: Config.horizontal ? Flow.LeftToRight : Flow.TopToBottom
                spacing: Config.spacing
                // Somme des largeurs NATURELLES des modules de ce groupe
                // (indépendante de l'étirement, donc aucun cycle de liaison).
                readonly property real nat: {
                    var t = 0;
                    for (var k = 0; k < children.length; k++) {
                        var c = children[k];
                        if (c && c.natW !== undefined)
                            t += c.natW;
                    }
                    return t;
                }
                readonly property real main: Config.horizontal ? width : height
                x: Config.horizontal ? topGroup.main + stack.gap : stack.cross
                y: Config.horizontal ? stack.cross : topGroup.main + stack.gap

                Repeater {
                    model: shell.modulesIn("info")
                    delegate: Loader {
                        required property string modelData
                        readonly property real natW: item ? Math.ceil(item.implicitWidth) : 0
                        width: Config.horizontal
                               ? (natW + stack.extraModule)
                               : Config.block
                        height: Config.horizontal
                                ? Config.caseH
                                : (item ? item.implicitHeight : 0)
                        source: shell.moduleSource(modelData)
                    }
                }
            }

            // ── apps : épinglées (+ « + ») + en cours ─────────────────────
            Flow {
                id: appsGroup
                flow: Config.horizontal ? Flow.LeftToRight : Flow.TopToBottom
                spacing: Config.spacing
                // Somme des largeurs NATURELLES des modules de ce groupe
                // (indépendante de l'étirement, donc aucun cycle de liaison).
                readonly property real nat: {
                    var t = 0;
                    for (var k = 0; k < children.length; k++) {
                        var c = children[k];
                        if (c && c.natW !== undefined)
                            t += c.natW;
                    }
                    return t;
                }
                readonly property real main: Config.horizontal ? width : height
                x: Config.horizontal ? infoGroup.x + infoGroup.main + stack.gap : stack.cross
                y: Config.horizontal ? stack.cross : infoGroup.y + infoGroup.main + stack.gap

                Repeater {
                    model: shell.modulesIn("apps")
                    delegate: Loader {
                        required property string modelData
                        readonly property real natW: item ? Math.ceil(item.implicitWidth) : 0
                        width: Config.horizontal
                               ? (natW + stack.extraModule)
                               : Config.block
                        height: Config.horizontal
                                ? Config.caseH
                                : (item ? item.implicitHeight : 0)
                        source: shell.moduleSource(modelData)
                    }
                }
            }

            // ── bas : son/wifi/DND + engrenage ────────────────────────────
            Flow {
                id: botGroup
                flow: Config.horizontal ? Flow.LeftToRight : Flow.TopToBottom
                spacing: Config.spacing
                // Somme des largeurs NATURELLES des modules de ce groupe
                // (indépendante de l'étirement, donc aucun cycle de liaison).
                readonly property real nat: {
                    var t = 0;
                    for (var k = 0; k < children.length; k++) {
                        var c = children[k];
                        if (c && c.natW !== undefined)
                            t += c.natW;
                    }
                    return t;
                }
                readonly property real main: Config.horizontal ? width : height
                x: Config.horizontal ? appsGroup.x + appsGroup.main + stack.gap : stack.cross
                y: Config.horizontal ? stack.cross : appsGroup.y + appsGroup.main + stack.gap

                Repeater {
                    model: shell.modulesIn("bottom")
                    delegate: Loader {
                        required property string modelData
                        readonly property real natW: item ? Math.ceil(item.implicitWidth) : 0
                        width: Config.horizontal
                               ? (natW + stack.extraModule)
                               : Config.block
                        height: Config.horizontal
                                ? Config.caseH
                                : (item ? item.implicitHeight : 0)
                        source: shell.moduleSource(modelData)
                    }
                }
            }
        }

        // État d'erreur global : point discret + infobulle. Il tient dans la
        // bande de 4 px du bas (inset) : il ne recouvre aucun bloc, donc son
        // MouseArea ne peut pas voler un clic à l'engrenage (v4 §5).
        Rectangle {
            visible: Config.lastError.length > 0
            width: 4
            height: 4
            radius: 2
            color: BarPalette.hot
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 0
            anchors.horizontalCenter: parent.horizontalCenter

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    var p = parent.mapToItem(null, 0, 0);
                    Tip.show(Config.lastError, p.y);
                }
                onExited: Tip.hide()
            }
        }
    }

    // ── Infobulle unique (brief §8, v4 §8) ────────────────────────────────
    // Trois garanties, dans l'ordre du brief :
    //   1. elle ne recouvre JAMAIS la colonne de blocs : sa marge gauche part
    //      du bord droit de la barre (8 px). Le repère des marges d'une surface
    //      layer est la zone UTILE de l'écran (mesuré en v1 : marge 72 → 134 px
    //      avec une barre de 62 px réservés), donc 8 px = 8 px après la barre.
    //      Si la barre ne réserve plus sa place (exclusiveZone false), la zone
    //      utile repart de 0 : on ajoute alors marginLeft + width.
    //   2. largeur maximale + retour à la ligne : une infobulle longue
    //      (« Subpage … — 1 fenêtre ») s'enroule au lieu de traverser l'écran.
    //   3. elle disparaît au clic : Ui.close()/Ui.open() appellent Tip.hideNow().
    PanelWindow {
        id: tipWin
        // v5b : l'infobulle suit le bord de la barre (gauche, droite) et passe
        // SOUS la barre quand elle est en haut (son y écran est alors ignoré).
        anchors {
            // v5c : en horizontal il faut DEUX ancrages opposés, sinon la
            // surface reste à 40 px de large (bug « top » : rien de visible).
            left: Config.horizontal || !Config.sideRight
            right: Config.horizontal || Config.sideRight
            top: true
        }
        readonly property int maxWidth: 300
        margins {
            // Le repère des marges d'une surface layer est la zone UTILE de
            // l'écran (hors exclusiveZone) : depuis elle, 8 px = 8 px après la
            // barre. Sans réserve, la zone utile repart de 0 → on ajoute
            // marge + épaisseur.
            left: Config.horizontal
                  ? Config.marginLeft + 8
                  : (Config.reserve ? 8 : Config.marginLeft + Config.width + 8)
            right: Config.sideRight
                   ? (Config.reserve ? 8 : Config.marginRight + Config.width + 8)
                   : 0
            top: Config.horizontal
                 ? Config.popupTop
                 : Math.max(2, Math.round(Config.marginTop + Tip.y - tipWin.implicitHeight / 2))
        }
        // Largeur = largeur NATURELLE du texte (TextMetrics, aucune dépendance
        // circulaire), plafonnée à maxWidth ; le texte s'enroule au-delà.
        implicitWidth: Math.min(tipWin.maxWidth,
                                Math.max(48, Math.ceil(tipMetrics.advanceWidth) + 20))
        implicitHeight: tipLabel.implicitHeight + 12
        exclusiveZone: 0
        color: "transparent"
        visible: Tip.visible && Config.enabled
        focusable: false
        WlrLayershell.namespace: "sasquatch-bar-tip"
        WlrLayershell.layer: WlrLayer.Overlay

        TextMetrics {
            id: tipMetrics
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            text: Tip.text
        }

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: BarPalette.a(BarPalette.bgSolid, 0.95)
            border.width: 1
            border.color: BarPalette.border

            Text {
                id: tipLabel
                width: tipWin.implicitWidth - 20
                anchors.centerIn: parent
                text: Tip.text
                color: BarPalette.text
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                maximumLineCount: 5
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
        }
    }

    // ── Popups : une surface chacune, exclusiveZone 0 ────────────────────
    CalendarPopup {}
    VolumePopup {}
    NetworkPopup {}
    NotificationsPopup {}
    WindowsPopup {}
    AddAppPopup {}
    AppMenuPopup {}

    // ── IPC : `qs -i <id> call bar popup calendar` (tests, keybinds) ──────
    // Les fonctions sans valeur de retour ne portent PAS l'annotation « : void » :
    // qmllint plante (exit 255, aucune sortie) sur cette annotation dans un
    // IpcHandler. Sans annotation elles restent enregistrées en void.
    IpcHandler {
        target: "bar"

        function popup(name: string) { Ui.open(name) }
        function close() { Ui.close() }
        function reload() { Config.file.reload() }

        // Même chemin de code qu'un clic de souris (brief v2 §1/§2) : les
        // tests appellent ces fonctions, pas une simulation d'événement.
        function focusApp(cls: string) { Hypr.focusClass(cls) }
        function clickApp(id: string) { shell.clickPinned(id) }
        function cycleApp(cls: string, delta: int) { Hypr.cycle(cls, delta) }
        // Pas de `return` : une fonction IpcHandler est void, renvoyer une
        // valeur produit un ERROR de coercion dans le journal.
        function action(name: string) { Ui.runAction(name) }

        function state(): string {
            return JSON.stringify({
                modules: Config.modules,
                position: Config.position,
                horizontal: Config.horizontal,
                width: Config.width,
                block: Config.block,
                hit: Config.hit,
                caseH: Config.caseH,
                pillRadius: Config.pillRadius,
                spacing: Config.spacing,
                persistentWorkspaces: Config.persistentWorkspaces,
                alphas: {
                    panel: Config.panelAlpha,
                    block: Config.blockAlpha,
                    card: Config.cardAlpha,
                    hover: Config.hoverAlpha,
                    active: Config.activeAlpha,
                    border: Config.borderAlpha
                },
                paletteLive: BarPalette.live,
                popup: Ui.popup,
                // Preuve §4 : état « ouverte » de CHAQUE app épinglée, calculé
                // par Hypr.pinnedState() (norm des deux côtés + id .desktop).
                pinnedOpen: Hypr.pinnedState(),
                stats: Backend.ttlOk,
                volume: Backend.volume,
                netUp: Backend.netUp,
                netDown: Backend.netDown,
                ramPct: Backend.ramPct,
                pinError: PinWriter.lastError,
                configError: Config.lastError
            });
        }

        // Géométrie RÉELLE de chaque cible cliquable (preuve §2/§5).
        function rects(): string { return JSON.stringify(Ui.dumpRects()) }
        // Géométrie des QUATRE groupes (preuve §3 : hauteurs et positions).
        function layout(): string { return JSON.stringify(shell.layoutInfo()) }
        // Géométrie de CHAQUE zone de molette (preuve §2 : tout le bloc).
        function wheels(): string { return JSON.stringify(Ui.dumpWheelZones()) }
        function clicks(): string { return JSON.stringify(Hypr.clickLog) }
        function windows(): string { return JSON.stringify(Hypr.dumpWindows()) }

        // Épinglage par commande (même chemin que le clic : PinWriter).
        function pinApp(id: string) { PinWriter.pin(id) }
        function unpinApp(id: string) { PinWriter.unpin(id) }
        function addApp() { Ui.openAddApp() }
    }

    // Clic sur une app épinglée, par identifiant de bar.json (même chemin).
    function clickPinned(id) {
        var apps = Config.apps;
        for (var i = 0; i < apps.length; i++) {
            if (apps[i] && ("" + apps[i].id) === ("" + id)) {
                var cls = "" + (apps[i].class || apps[i].id);
                var desk = ("" + (apps[i].desktop || apps[i].id)).replace(/\.desktop$/, "");
                return Hypr.activate(cls, desk);
            }
        }
        Hypr.miss("app inconnue dans bar.json : " + id);
        return false;
    }

    // ── Bar.json → groupes ────────────────────────────────────────────────
    // v4 §2 : QUATRE groupes fixes (haut / info / apps / bas). L'ordre de
    // bar.json pilote l'ordre DANS chaque groupe ; le groupe est un choix de
    // mise en page. Un module absent de cette table est ignoré (console.warn).
    readonly property var zones: ({
        search: "top",
        workspaces: "top",
        netRate: "info",
        clock: "info",
        volume: "info",
        pinnedApps: "apps",
        runningApps: "apps",
        quickToggles: "bottom",
        settings: "bottom"
    })

    function modulesIn(zone) {
        var out = [];
        var list = Config.modules;
        for (var i = 0; i < list.length; i++) {
            if (shell.zones[list[i]] === zone)
                out.push(list[i]);
            else if (shell.zones[list[i]] === undefined)
                console.warn("bar: module sans groupe (bar.json): " + list[i]);
        }
        return out;
    }

    // ── Géométrie vivante des quatre groupes (preuve §3 du rapport) ───────
    // `qs ipc call bar layout` : longueurs naturelles + positions réelles, en
    // nombres — la même arithmétique que le code (longueur = somme des blocs,
    // écart = Config.spacing + libre/3). v5b : les mêmes champs pour les trois
    // positions (x/w renseignés en horizontal, y/h en vertical ; les quatre
    // sont toujours présents).
    function layoutInfo() {
        function group(name, item) {
            return {
                name: name,
                x: Math.round(item.x),
                y: Math.round(item.y),
                w: Math.round(item.width),
                h: Math.round(item.height),
                main: Math.round(item.main),
                modules: shell.modulesIn(name === "bottom" ? "bottom" : name)
            };
        }
        return {
            position: Config.position,
            horizontal: Config.horizontal,
            barWidth: Math.round(stack.width),
            barHeight: Math.round(stack.height),
            block: Config.block,
            spacing: Config.spacing,
            inset: Config.inset,
            free: Math.round(stack.freeSpace),
            extraPerGap: Math.round(stack.extra * 10) / 10,
            groupGap: Math.round(stack.gap * 10) / 10,
            groups: [
                group("top", topGroup),
                group("info", infoGroup),
                group("apps", appsGroup),
                group("bottom", botGroup)
            ]
        };
    }

    function moduleSource(name) {
        var map = {
            search: "Search",
            workspaces: "Workspaces",
            netRate: "NetRate",
            clock: "Clock",
            volume: "VolumeSlider",
            pinnedApps: "AppDock",
            runningApps: "RunningApps",
            quickToggles: "QuickToggles",
            settings: "Settings"
        };
        var file = map[name];
        if (!file) {
            console.warn("bar: module inconnu dans bar.json: " + name);
            return "";
        }
        return Qt.resolvedUrl("modules/" + file + ".qml");
    }

    Component.onCompleted: {
        console.info("bar: " + Config.modules.length + " modules, position="
                     + Config.position + ", width=" + Config.width
                     + ", block=" + Config.block
                     + ", paletteLive=" + BarPalette.live);
    }
}
