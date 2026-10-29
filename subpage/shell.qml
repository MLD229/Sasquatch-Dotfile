// shell.qml — Sasquatch Sub page v2.1 : LA PAGE elle-même (surface layer-shell).
//
// Lancement : ~/.config/subpage/subpage.sh   (Super+S, toggle)
//
// ══════════════════════════════════════════════════════════════════════════
// CE QUE CETTE SURFACE EST — ET CE QU'ELLE N'EST PLUS
// ══════════════════════════════════════════════════════════════════════════
// La sub page est un special workspace Hyprland (`special:subpage`). Avant,
// le cadre était une FloatingWindow plein écran mappée DANS ce workspace : il
// fallait une windowrule `workspace special:subpage`, un `alterzorder bottom`
// à la main, un ordre de toggle précis (mapper pendant que le special est
// ouvert le FERMAIT), et Hyprland floutait toute sa surface transparente →
// écran entier flou, apps illisibles, coins en carrés flous.
//
// v2 : plus de fenêtre du tout. Une surface layer-shell qui ne vit PAS dans un
// workspace :
//   • elle n'est jamais mappée dans le workspace → aucune windowrule, aucun
//     piège d'ordre : on peut lancer la décoration avant OU après le toggle ;
//   • aucun blur demandé (aucune layerrule sur ce namespace) → contenu NET ;
//   • keyboardFocus None / focusable false → aucun grab clavier, aucun vol de
//     focus (la leçon hyprlock : un grab clavier casse le mot de passe) ;
//   • niveau `top` (et non `background`, cf. §1 : mesuré, background est
//     invisible sous l'overlay du special workspace).
//
// v2.2 — RIEN NE S'ASSOMBRIT, RIEN N'EST CADRÉ.
// La page ne peint plus de fond du tout : ni voile, ni coins (les « carrés
// bleus » ont été retirés). Il ne reste que l'étiquette サブページ. La surface
// existe donc uniquement pour (a) matérialiser la page et (b) capter les clics
// d'une page vide, pour qu'un clic au centre ne tombe pas sur le bureau caché.
//
// ══════════════════════════════════════════════════════════════════════════
// DESSIN (v2.2) : une étiquette seule, dans la gouttière du haut, sans blur
// compositeur (aucune layerrule : le flou d'une surface layer viendrait de là,
// cf. le bug « écran entier flou » — on ne demande donc rien).
//
// SOURIS : la région d'entrée couvre TOUTE la surface quand la page est
// ouverte (mask = le voile). Sans ça un clic au centre tombait sur le bureau
// caché (Discord…) alors que l'utilisateur croyait cliquer dans la page. Les
// fenêtres envoyées dans le special sont dessinées au-dessus de ce layer :
// elles restent cliquables normalement (Hyprland rend l'overlay du special
// après les layers `top`).
//
// Visibilité : elle suit l'état RÉEL de Hyprland, en continu, via state.py
// (`hyprctl monitors -j` → specialWorkspace.name). Fermer la page par
// n'importe quel biais (autre keybind, hyprctl à la main) fait disparaître la
// décoration sans passer par les scripts.
//
// Échap ne peut PAS fermer la page : la surface ne prend aucun focus clavier.
// Fermeture = Super+S (subpage.sh).

// PAS de `pragma ComponentBehavior: Bound` ici : inutile (aucun delegate) et
// il fait planter le qmllint de Qt 6.10 (rc=255, aucun message) alors que le
// même fichier sans le pragma se vérifie normalement.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    // ── 1. Contrat de surface ────────────────────────────────────────────
    // ⚠️ TOP, pas BACKGROUND — mesuré, pas supposé : un layer background/bottom
    // est dessiné SOUS le plan des fenêtres, or Hyprland dessine la sub page
    // comme un OVERLAY au-dessus du workspace courant (specialWorkspace). Une
    // surface background devient donc invisible dès que la page est ouverte
    // (capture 10-open-clean : aucune décoration, écran net, mais rien à
    // l'écran). Un layer `top` est au-dessus du plan des fenêtres → visible,
    // tout en restant SOUS les notifications (overlay) et sous la waybar.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "subpage"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0          // overlay : ne réserve aucune place
    focusable: false          // ne demande jamais le focus
    aboveWindows: false       // ne passe PAS au-dessus d'un plein écran (un jeu la masque)
    color: "transparent"      // le fond est dessiné par le voile (§5)

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // Hyprland place un layer `top` SOUS la zone réservée par la waybar
    // (reserved[1] = 42) : aucune marge à ajouter ici, sinon on double l'écart.
    margins.top: 0

    // ── 2. État : la sub page est-elle ouverte ? ─────────────────────────
    // Source de vérité unique : state.py (hyprctl monitors -j). Aucun état
    // stocké sur disque, aucun calcul depuis activeworkspace.
    property bool specialOpen: false
    property string specialMonitor: ""
    property bool everOpened: false

    readonly property string stateScript: Quickshell.env("SUBPAGE_DIR")
                                          ? Quickshell.env("SUBPAGE_DIR") + "/state.py"
                                          : Quickshell.shellPath("state.py")

    visible: root.specialOpen

    // La surface suit le moniteur où le special est réellement ouvert.
    screen: {
        const mons = Quickshell.screens;
        for (let i = 0; i < mons.length; i++)
            if (root.specialMonitor !== "" && mons[i].name === root.specialMonitor)
                return mons[i];
        return mons.length > 0 ? mons[0] : null;
    }

    function applyStateLine(line) {
        const text = String(line).trim();
        if (text === "")
            return;
        if (text.indexOf("open") === 0) {
            root.specialMonitor = text.substring(4).trim();
            root.specialOpen = true;
            root.everOpened = true;
        } else if (text.indexOf("closed") === 0) {
            root.specialMonitor = "";
            root.specialOpen = false;
        }
    }

    // Suivi continu (150 ms) : ~1 hyprctl, négligeable, et la décoration se
    // synchronise même si la page est fermée autrement.
    Process {
        id: stateWatcher
        running: true
        command: ["python3", root.stateScript, "--watch"]
        stdout: SplitParser {
            onRead: line => root.applyStateLine(line)
        }
        onExited: {
            console.warn("[subpage] state.py --watch s'est arrêté → relance");
            stateWatcherRetry.restart();
        }
    }

    Timer {
        id: stateWatcherRetry
        interval: 1000
        onTriggered: stateWatcher.running = true
    }

    // Nettoyage : page fermée depuis > 5 s (fermeture par un autre biais) →
    // on s'arrête au lieu de sonder Hyprland pour rien. subpage.sh tue aussi
    // la décoration explicitement ; ce timer couvre les autres chemins.
    Timer {
        interval: 5000
        repeat: false
        running: root.everOpened && !root.specialOpen
        onTriggered: Qt.quit()
    }

    // ── 3. Palette : ~/.config/cc/qml/Palette.qml (theme-apply.py) ───────
    // Valeurs de secours = palette par défaut du dotfile.
    property color cAccent: "#066678"
    property color cTextDim: "#6a8388"

    function paletteValue(source, key) {
        const re = new RegExp("property\\s+color\\s+" + key + "\\s*:\\s*\"(#[0-9a-fA-F]+)\"");
        const found = re.exec(source || "");
        return found ? found[1] : "";
    }

    function applyPalette(source) {
        const accent = root.paletteValue(source, "accent");
        const textDim = root.paletteValue(source, "textDim");
        if (accent !== "")
            root.cAccent = accent;
        if (textDim !== "")
            root.cTextDim = textDim;
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/cc/qml/Palette.qml"
        watchChanges: true
        printErrors: false
        onLoaded: root.applyPalette(text())
        onFileChanged: reload()
    }

    // ── 4. Géométrie / couleurs du dessin ────────────────────────────────
    readonly property int edgeMargin: 10      // marge de l'étiquette
    readonly property int armLength: 56       // ancienne longueur de bras (décalage de l'étiquette)

    // v2.2 — plus rien ne s'assombrit : ni voile, ni coins, ni calque.
    // La surface ne peint plus aucun fond (elle ne sert qu'à exister comme
    // page et à capter les clics). L'accent reste pour l'étiquette seule.
    readonly property color cStroke: Qt.lighter(root.cAccent, 1.9)

    // ── 5. Zone de page invisible (v2.2) ─────────────────────────────────
    // Plus de voile : la page ne doit RIEN assombrir. Ce rectangle reste
    // plein panneau mais transparent : c'est lui qui définit la région
    // d'entrée (§8), donc la surface qui capte les clics d'une page vide.
    Rectangle {
        id: veil
        anchors.fill: parent
        color: "transparent"
    }

    // v2.2 : les quatre coins en L sont supprimés (les « carrés bleus »).
    // Rien n'est dessiné à leur place.

    // ── 7. Étiquette, dans la GOUTTIÈRE du haut ─────────────────────────
    // Placée dans le vide entre le bord et les apps (gapsout:16 de rules.conf) :
    // elle ne recouvre donc jamais le contenu d'une fenêtre.
    Text {
        id: label
        text: "サブページ"
        font.pixelSize: 12
        font.letterSpacing: 1
        color: root.cStroke
        opacity: 0.95
        x: root.edgeMargin + root.armLength + 10
        y: 2
    }

    // ── 8. Région d'entrée = TOUTE la surface (la page capte les clics) ──
    // Une couche `top`, c'est au-dessus du plan des fenêtres : sans région
    // d'entrée plein écran, un clic au centre tombait sur le bureau caché
    // (Discord…). Avec, le clic est absorbé par la page (surface non focusable
    // ⇒ aucun client ne reçoit de focus).
    // Les fenêtres du special, elles, sont dessinées AU-DESSUS de ce layer :
    // elles reçoivent toujours leurs clics.
    mask: Region {
        item: veil
    }
}
