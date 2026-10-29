---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-10-29
---

# subpage

Sub page = **scratchpad Hyprland** (`special:subpage`) + une **décoration
layer-shell de fond** qui n'est PAS une fenêtre.

## Rattachements

**Fichiers du composant** :
- [[20-Composants/subpage/shell-qml]] — décoration : surface layer-shell (étiquette seule, aucun voile)
- [[20-Composants/subpage/state-py]] — source de vérité « la page est-elle ouverte ? »
- [[20-Composants/subpage/subpage-sh]] — toggle (Super+S)
- [[20-Composants/subpage/send-sh]] — envoyer la fenêtre active dedans (Super+Alt+S)
- `tests/verify.sh` — preuves scriptées (lint, netteté, focus, layers, synchronisation)
- `_archive/main.qml` — ancienne décoration (fenêtre plein écran), archivée

**Lancé par** :
- [[20-Composants/hypr/keybinds-conf]] — `$mod, S` → subpage.sh, `$mod ALT, S` → send.sh

**Côté Hyprland** :
- [[20-Composants/hypr/conf.d/rules-conf]] — **aucune windowrule** pour la décoration
  (elle n'est pas une fenêtre) ; seule reste `workspace = special:subpage, gapsout:16, gapsin:6`
- `hyprctl dispatch togglespecialworkspace subpage` : ouvre/ferme la page

**Installation** :
- [[10-Fondations/symlinks]] — `~/.config/subpage` → repo
- [[10-Fondations/install]] — `chmod +x subpage/*.sh`, `chmod +x subpage/state.py`

## Architecture v2 (2026-10-29 — refonte à zéro)

L'ancienne décoration était une **FloatingWindow plein écran mappée DANS le
special workspace**. Pannes structurelles : Hyprland floutait toute sa surface
transparente (écran entier flou), `alterzorder bottom` à la main, et surtout
**mapper la fenêtre pendant que le special est ouvert le FERMAIT** → scripts
pleins de cas particuliers.

v2 : `PanelWindow` Quickshell en **layer-shell `top`**, namespace `subpage`,
`exclusiveZone: 0`, `keyboardFocus: None`, `focusable: false`. Elle ne vit pas
dans un workspace ⇒ plus de windowrule, plus d'alterzorder, plus de piège
d'ordre, aucun vol de focus. Visibilité pilotée en continu (150 ms) par
state.py sur l'état réel de Hyprland.

⚠️ `top` et non `background` : mesuré, un layer background/bottom est
**invisible** sous l'overlay du special workspace (il est dessiné sous le plan
des fenêtres). En `top`, la décoration est masquée par une fenêtre vraiment
plein écran (jeu) — c'est le comportement voulu, et elle n'existe de toute
façon pas quand la page est fermée.

**Dessin (v2.2)** : étiquette `サブページ` seule dans la gouttière de 16 px
(jamais sur le contenu d'une app). **Aucun voile, aucun coin** : la page
n'assombrit plus rien (le special workspace dimmait le bureau à 20 % →
`dim_special = 0` dans [[20-Composants/hypr/conf.d/decoration-conf]]).
Région d'entrée = surface entière : une page vide capte les clics.

**Échap ne ferme pas la page** (aucun focus clavier) : fermeture = Super+S.
