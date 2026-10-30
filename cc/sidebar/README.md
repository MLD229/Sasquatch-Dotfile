# Sasquatch Sidebar — slide bar Quickshell

Panneau latéral droit (overlay) : modes système, to-do persistante,
chrono / timer / alarme, plus volume / luminosité / player / presse-papier.

    ~/.config/cc/sidebar/sidebar.sh        # toggle (Super+C)

## Carte des fichiers

| Fichier | Rôle |
|---|---|
| `shell.qml` | `PanelWindow` ancré à droite (392 px, `exclusiveZone: 0`, `aboveWindows`), toutes les sections |
| `qml/Section.qml` | carte de section (couleurs injectées) |
| `qml/Pill.qml` | bouton de mode (actif / inactif / **indisponible**) |
| `qml/SliderRow.qml` | slider maison (track + poignée) |
| `server.py` | backend HTTP **8778** : todo, temps, modes, système |
| `clock.py` | moteur chrono / timer / alarme (horloge absolue) |
| `modes.py` | modes avec sauvegarde / restauration de l'état d'avant |
| `sidebar.sh` | toggle (Super+C) |
| `sasquatch-sidebar.service` | service systemd **user** du backend |
| `install.sh` | symlink + service + contrôles |
| `tests/` | qmllint, tests temps déterministes, tests HTTP, chargement QML |

## Source de vérité et miroir

Source de vérité = **ce dépôt**. L'installé est un **symlink** :

    ~/.config/cc/sidebar  →  ~/Sasquatch-Dotfile/sidebar

Une seule copie sur le disque, donc aucune dérive dépôt/installé.
(`install.sh` le (re)crée ; il refuse de remplacer un vrai dossier.)

Le dépôt `~/Downloads/Sasquatch-Dotfile` est le dépôt git du dotfile :
`~/.config/cc` y pointe déjà (`~/.config/cc → ~/Downloads/Sasquatch-Dotfile/cc`),
donc le symlink ci-dessus place le dossier dans son arbre de travail, non
versionné (aucun commit n'a été fait).

## Palette (exigence « fond adaptatif »)

Aucune couleur en dur dans l'UI :

1. `server.py` importe `cc/palette.py` (le module du Control Center) qui lit
   `~/.config/cc/qml/Palette.qml`, fichier régénéré par `theme-apply.py` à
   chaque changement de wallpaper ;
2. si l'import échoue → `GET http://127.0.0.1:8765/api/palette` (le CC) ;
3. en dernier recours seulement, les défauts Catppuccin — **les mêmes** que
   `cc/palette.py` (jamais un thème inventé). Ces 12 lignes sont commentées
   comme valeurs de secours dans `shell.qml`.

`shell.qml` relit `/api/palette` toutes les 2 s et met à jour ses couleurs :
changer de fond d'écran change la sidebar sans la relancer.

`theme-apply.py`, `apply-wallpaper.sh` et `cc/main.qml` n'ont **pas** été
modifiés : on consomme le mécanisme existant.

## Temps qui continue panneau fermé

Le QML ne calcule **aucun** temps. Tout est dans `clock.py`, côté backend, qui
tourne en service systemd user **permanent** :

* le timer stocke un timestamp de fin (`ends_at`) et non un compteur → il
  reste juste même si le process n'a pas tourné (suspend, redémarrage) ;
* à l'échéance, le backend écrit un événement (`events`), envoie une
  notification (`notify-send` → mako) et joue un son (`pw-play`/`paplay`),
  panneau ouvert ou non ;
* l'UI ne fait que **lire** `/api/state` (poll 500 ms) et clignote quand un
  nouvel événement arrive.

Preuve : `tests/test_backend.py` lance un timer de 3 s puis **n'envoie aucune
requête pendant 4,5 s** ; l'événement de fin est quand même enregistré.

## Modes

| Mode | Action | Restauration |
|---|---|---|
| Allégé | `hyprctl keyword animations:enabled 0`, `decoration:blur:enabled false`, `decoration:shadow:enabled false` | valeurs lues avant avec `hyprctl getoption -j` et remises telles quelles |
| Gaming | allégé + DND + `powerprofilesctl set performance` (si présent) | profil précédent relu (`powerprofilesctl get`) |
| Lumière bleue | `hyprsunset -t <2500…6500 K>` | process arrêté |
| Ne pas déranger | `makoctl mode -a/-r do-not-disturb` | mako vérifié avant (`makoctl mode`) |
| Anti-veille | `systemd-inhibit --what=idle:sleep` | inhibiteur tué (mode off **et** arrêt du service) |
| Fond suivant | `POST /api/wallpaper/random` + `/api/wallpaper/apply` sur le CC 8765 (qui appelle `apply-wallpaper.sh`) | — |

Chaque mode est idempotent et **n'écrit son état actif qu'en cas de succès** :
outil absent ou session absente → `ok:false` + message affiché dans le panneau,
le bouton reste inactif. `hyprsunset` n'est pas installé sur cette machine :
le bouton est en état « non installé » (prérequis plus bas).

## État persistant

    ~/.local/state/sasquatch/sidebar-state.json      (écriture atomique)

Contient : todo, chrono, timer, alarmes, modes, événements, pids lancés.
Survit à la fermeture du panneau **et** au redémarrage du serveur/session.

## Installation

    bash ~/Sasquatch-Dotfile/sidebar/install.sh

Puis, pour l'ouvrir : `Super+C` (ou `~/.config/cc/sidebar/sidebar.sh`).

Bind ajouté dans `~/.config/hypr/keybinds.conf` :

    bind = $mod, U, exec, ~/.config/cc/sidebar/sidebar.sh

`Super+S` et `Super+Alt+S` étaient déjà pris (sub page / sub page send) →
`Super+C` est le bind actuel (Super+U est passé à la calculatrice, 2026-10-29).

## Prérequis optionnel

    sudo pacman -S hyprsunset      # mode « lumière bleue » (2500–6500 K)

Sans lui, la sidebar fonctionne : le mode est simplement marqué indisponible.

## Fermeture / focus

* `Échap` ferme ; la croix aussi ; `Super+C` referme.
* Fermeture sur clic hors panneau via `HyprlandFocusGrab`
  (protocole `hyprland_focus_grab_v1`). Si le compositeur ne l'implémente pas,
  Quickshell émet un `WARN` et la fermeture reste possible par Échap/Super+C.
* Le panneau est `focusable` pour la saisie (todo, HH:MM) ; à la fermeture le
  process Quickshell se termine (`Qt.quit` après l'animation), donc le focus
  retourne à la fenêtre précédente côté Hyprland — rien à rendre à la main.

## Vérifier en 2 minutes après login

    cd ~/Sasquatch-Dotfile/sidebar && bash tests/run-all.sh

Puis à la main :

    ~/.config/cc/sidebar/sidebar.sh          # Super+C : le panneau glisse
    # onglet Timer → 5 min → fermer le panneau → attendre : notification + son
    # mode Allégé → vérifier : hyprctl getoption animations:enabled → 0
    #                puis désactiver → la valeur d'origine revient

## Ce qui n'a PAS pu être testé ici (honnêteté)

Machinerie vérifiée : `qmllint`, tests HTTP, persistance, moteur de temps,
chargement réel du QML dans un compositeur de test (KWin virtuel).

Non vérifiable sans session Hyprland réelle :

* le **rendu visuel** (position, animation, lisibilité, thème réel) — aucun
  écran disponible, donc aucune capture ;
* `hyprctl keyword …` sur Hyprland (les modes ont été validés par la logique
  + `modes.py selftest`, pas sur un vrai compositeur Hyprland) ;
* `HyprlandFocusGrab` (non implémenté par le compositeur de test) → clic
  extérieur non prouvé ;
* notifications mako et son (aucune session graphique audio) ;
* `hyprsunset` (paquet absent) et `powerprofilesctl` (absent).
