// shell.qml — Sasquatch Sub page v2.3 : LA PAGE (deux surfaces layer-shell).
//
// Lancement : ~/.config/subpage/subpage.sh   (Super+S, toggle)
//
// ══════════════════════════════════════════════════════════════════════════
// CE QUE CES SURFACES SONT — ET CE QU'ELLES NE SONT PLUS
// ══════════════════════════════════════════════════════════════════════════
// La sub page est un special workspace Hyprland (`special:subpage`). Avant,
// le cadre était une FloatingWindow plein écran mappée DANS ce workspace : il
// fallait une windowrule `workspace special:subpage`, un `alterzorder bottom`
// à la main, un ordre de toggle précis (mapper pendant que le special est
// ouvert le FERMAIT), et Hyprland floutait toute sa surface transparente →
// écran entier flou, apps illisibles, coins en carrés flous.
//
// v2 : plus de fenêtre du tout. Des surfaces layer-shell qui ne vivent PAS
// dans un workspace :
//   • elles ne sont jamais mappées dans le workspace → aucune windowrule,
//     aucun piège d'ordre : on peut lancer la décoration avant OU après ;
//   • aucun blur demandé (aucune layerrule sur ces namespaces) → contenu NET ;
//   • keyboardFocus None / focusable false → aucun grab clavier, aucun vol de
//     focus (la leçon hyprlock : un grab clavier casse le mot de passe).
//
// v2.2 — RIEN NE S'ASSOMBRIT, RIEN N'EST CADRÉ (ni voile, ni coins).
//
// v2.3 — DEUX SURFACES (demande momo : « un petit ton chaud de fond, pas
// par-dessus les pages, juste assez pour voir que la page est ouverte ») :
//   1. `subpage-bg`  (WlrLayer.Background) : la TEINTE CHAUDE, derrière tout.
//      Un layer `background` est dessiné SOUS le plan des fenêtres : la teinte
//      colore le bureau et les zones vides de la page, JAMAIS les fenêtres de
//      la page (elles restent nettes et devant). Mesuré : une teinte α=0.35
//      sur ce layer ne modifie pas un pixel opaque d'une fenêtre.
//   2. `subpage`     (WlrLayer.Top) : l'étiquette サブページ + la région
//      d'entrée. C'est aussi le repère « la page existe » de subpage.sh
//      (`hyprctl layers` → namespace: subpage).
// Le ton chaud est DÉRIVÉ DES TOKENS (accent + warn), jamais un hex en dur :
// il suit donc le wallpaper comme le reste du thème.
//
// Pourquoi le layer `background` fonctionne ici alors qu'il « était
// invisible » en v2.1 : en v2.1 la surface background portait le CADRE et
// était donc jugée sur sa visibilité ; une teinte n'a pas besoin d'être
// au-dessus des fenêtres — au contraire, c'est exactement ce qu'on veut.
// (Vérifié le 2026-10-30 : namespace subpage-bg mappé 0 42 1920 1038, teinte
// visible sur le bureau, fenêtres intactes.)
//
// SOURIS : la région d'entrée du layer `top` couvre TOUTE la surface quand la
// page est ouverte. Sans ça un clic au centre tombait sur le bureau caché
// (Discord…) alors que l'utilisateur croyait cliquer dans la page. Les
// fenêtres envoyées dans le special sont dessinées au-dessus de ce layer :
// elles restent cliquables normalement. Le layer `background` ne prend aucun
// input utile (focusable: false) : il ne peut pas voler un clic.
//
// Visibilité : les deux surfaces suivent l'état RÉEL de Hyprland, en continu,
// via state.py (`hyprctl monitors -j` → specialWorkspace.name). Fermer la page
// par n'importe quel biais fait disparaître teinte + étiquette.
//
// Échap ne peut PAS fermer la page : aucune surface ne prend de focus clavier.
// Fermeture = Super+S (subpage.sh).

// PAS de `pragma ComponentBehavior: Bound` ici : inutile (aucun delegate) et
// il fait planter le qmllint de Qt 6.10 (rc=255, aucun message) alors que le
// même fichier sans le pragma se vérifie normalement.
//
// ShellRoot : conteneur sans surface visible qui autorise PLUSIEURS fenêtres
// dans un seul fichier (sinon la racine QML ne peut porter qu'un objet).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    // ── État de la page : source de vérité unique (state.py) ─────────────
    property bool specialOpen: false
    property string specialMonitor: ""
    property bool everOpened: false

    readonly property string stateScript: Quickshell.env("SUBPAGE_DIR")
                                          ? Quickshell.env("SUBPAGE_DIR") + "/state.py"
                                          : Quickshell.shellPath("state.py")

    // ── Palette : ~/.config/cc/qml/Palette.qml (généré par theme-apply.py) ─
    // Repli = palette par défaut du dotfile (olive), COMMENTÉ ici pour rester
    // lisible. Aucune couleur « à la main » : tout ce qui est peint descend de
    // ces deux propriétés.
    property color cAccent: "#90906f"     // repli : accent olive de Palette.qml
    property color cTextDim: "#7c7c7a"    // repli : textDim de Palette.qml
    property color cWarn: "#f9e2af"       // repli : warn de Palette.qml

    function paletteValue(source, key) {
        const re = new RegExp("property\\s+color\\s+" + key + "\\s*:\\s*\"(#[0-9a-fA-F]+)\"");
        const found = re.exec(source || "");
        return found ? found[1] : "";
    }

    function applyPalette(source) {
        const accent = shell.paletteValue(source, "accent");
        const textDim = shell.paletteValue(source, "textDim");
        const warn = shell.paletteValue(source, "warn");
        if (accent !== "")
            shell.cAccent = accent;
        if (textDim !== "")
            shell.cTextDim = textDim;
        if (warn !== "")
            shell.cWarn = warn;
    }

    FileView {
        id: paletteFile
        path: Quickshell.env("HOME") + "/.config/cc/qml/Palette.qml"
        watchChanges: true
        printErrors: false
        onLoaded: shell.applyPalette(text())
        onFileChanged: reload()
    }

    function applyStateLine(line) {
        const text = String(line).trim();
        if (text === "")
            return;
        if (text.indexOf("open") === 0) {
            shell.specialMonitor = text.substring(4).trim();
            shell.specialOpen = true;
            shell.everOpened = true;
        } else if (text.indexOf("closed") === 0) {
            shell.specialMonitor = "";
            shell.specialOpen = false;
        }
    }

    // Suivi continu (150 ms) : ~1 hyprctl, négligeable, et les surfaces se
    // synchronisent même si la page est fermée autrement.
    Process {
        id: stateWatcher
        running: true
        command: ["python3", shell.stateScript, "--watch"]
        stdout: SplitParser {
            onRead: line => shell.applyStateLine(line)
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
    // les surfaces explicitement ; ce timer couvre les autres chemins.
    Timer {
        interval: 5000
        repeat: false
        running: shell.everOpened && !shell.specialOpen
        onTriggered: Qt.quit()
    }

    // Écran : celui où le special est réellement ouvert.
    function monitorFor(name) {
        const mons = Quickshell.screens;
        for (let i = 0; i < mons.length; i++)
            if (name !== "" && mons[i].name === name)
                return mons[i];
        return mons.length > 0 ? mons[0] : null;
    }

    // ══════════════════════════════════════════════════════════════════════
    // 1. TEINTE CHAUDE — layer BACKGROUND (derrière les fenêtres de la page)
    // ══════════════════════════════════════════════════════════════════════
    // Teinte = mélange accent (60 %) + warn (40 %) : « warn » est le token
    // chaud de la palette (crème). Ainsi la teinte reste chaude ET suit le
    // thème (une palette rouge la réchauffe, une palette bleue la tempère).
    // α = 0.13 : mesuré « petit ton », perceptible sans voiler (0.35 = trop).
    readonly property color cWarmBase: Qt.rgba(
        shell.cAccent.r * 0.6 + shell.cWarn.r * 0.4,
        shell.cAccent.g * 0.6 + shell.cWarn.g * 0.4,
        shell.cAccent.b * 0.6 + shell.cWarn.b * 0.4,
        1.0)
    readonly property color cWarmTint: Qt.rgba(cWarmBase.r, cWarmBase.g, cWarmBase.b, 0.13)

    PanelWindow {
        id: backdrop

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "subpage-bg"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusiveZone: 0            // aucun espace réservé
        focusable: false            // ne prend jamais le focus
        aboveWindows: false
        // La teinte est peinte par la couleur de la surface elle-même : pas
        // d'enfant Rectangle (rien d'autre à dessiner, aucun blur demandé).
        color: shell.cWarmTint

        visible: shell.specialOpen
        screen: shell.monitorFor(shell.specialMonitor)

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        margins.top: 0
    }

    // ══════════════════════════════════════════════════════════════════════
    // 2. PAGE — layer TOP : étiquette + région d'entrée
    // ══════════════════════════════════════════════════════════════════════
    // ⚠️ TOP (mesuré) : Hyprland dessine la sub page comme un OVERLAY au-dessus
    // du workspace courant ; ce layer reste sous les notifications (overlay) et
    // sous la waybar, mais au-dessus du plan des fenêtres → l'étiquette est
    // visible et les clics d'une page vide sont absorbés.
    PanelWindow {
        id: page

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "subpage"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusiveZone: 0          // overlay : ne réserve aucune place
        focusable: false          // ne demande jamais le focus
        aboveWindows: false       // ne passe PAS au-dessus d'un plein écran (un jeu la masque)
        color: "transparent"      // aucun fond ici : la teinte est sur subpage-bg

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        // Hyprland place un layer `top` SOUS la zone réservée par la waybar
        // (reserved[1] = 42) : aucune marge à ajouter ici, sinon on double
        // l'écart avec la teinte de fond.
        margins.top: 0

        visible: shell.specialOpen
        screen: shell.monitorFor(shell.specialMonitor)

        // ── Géométrie / couleur du dessin ────────────────────────────────
        readonly property int edgeMargin: 10   // marge de l'étiquette
        readonly property int armLength: 56    // ancienne longueur de bras (décalage)
        // Accent éclairci : lisible sur la teinte chaude comme sur un wallpaper
        // sombre. Dérivé du token, jamais un hex.
        readonly property color cStroke: Qt.lighter(shell.cAccent, 1.9)

        // ── Zone de page invisible ───────────────────────────────────────
        // Transparent par design : ce rectangle définit la région d'entrée
        // (§8), donc la surface qui capte les clics d'une page vide.
        Rectangle {
            id: veil
            anchors.fill: parent
            color: "transparent"
        }

        // ── Étiquette, dans la GOUTTIÈRE du haut ─────────────────────────
        // Placée dans le vide entre le bord et les apps (gapsout:16 de
        // rules.conf) : elle ne recouvre donc jamais le contenu d'une fenêtre.
        Text {
            id: label
            text: "サブページ"
            font.pixelSize: 12
            font.letterSpacing: 1
            color: page.cStroke
            opacity: 0.95
            x: page.edgeMargin + page.armLength + 10
            y: 2
        }

        // ── Région d'entrée = TOUTE la surface (la page capte les clics) ──
        mask: Region {
            item: veil
        }
    }
}

