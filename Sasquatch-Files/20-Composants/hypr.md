---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# hypr

## Rattachements

**Composant parent** : (aucun — racine du composant)

**Fichiers du composant** :
- [[20-Composants/hypr/hyprland-conf]] — entrée principale, source les conf.d/ et keybinds.conf
- [[20-Composants/hypr/hypridle-conf]] — idle + lock au capot
- [[20-Composants/hypr/hyprlock-conf]] — écran de verrouillage
- [[20-Composants/hypr/hyprpaper-conf]] — daemon wallpaper
- [[20-Composants/hypr/keybinds-conf]] — raccourcis clavier
- [[20-Composants/hypr/keybinds-user-conf]] — overrides écrits par Settings
- conf.d : [[20-Composants/hypr/conf.d/env-conf]], [[20-Composants/hypr/conf.d/monitors-conf]], [[20-Composants/hypr/conf.d/general-conf]], [[20-Composants/hypr/conf.d/decoration-conf]], [[20-Composants/hypr/conf.d/blur-conf]], [[20-Composants/hypr/conf.d/animations-conf]], [[20-Composants/hypr/conf.d/layout-conf]], [[20-Composants/hypr/conf.d/input-conf]], [[20-Composants/hypr/conf.d/misc-conf]], [[20-Composants/hypr/conf.d/rules-conf]] — modules sourcés par hyprland.conf
- scripts : [[20-Composants/hypr/scripts/autostart-sh]], [[20-Composants/hypr/scripts/cleanup-orphans-sh]], [[20-Composants/hypr/scripts/lock-ja-py]], [[20-Composants/hypr/scripts/lock-media-sh]], [[20-Composants/hypr/scripts/media-ctl-sh]], [[20-Composants/hypr/scripts/scroll-workspace-sh]], [[20-Composants/hypr/scripts/wallpaper-sh]]

**Fondations** :
- [[10-Fondations/symlinks]] — install.sh lie `hypr/` → `~/.config/hypr` (l.390), tout le composant
- [[10-Fondations/install]] — paquets hyprland/hyprpaper/hyprlock/hypridle + symlink + chmod des scripts
- [[10-Fondations/theme-dynamique]] — general.conf et hyprlock.conf portent des blocs SASQUATCH-PALETTE réécrits par theme-apply.py
