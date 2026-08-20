---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# wp

## Rattachements

**Fichiers du composant** :
- [[20-Composants/wp/main-qml]] — UI Quickshell (Super+Y)
- [[20-Composants/wp/wp-sh]] — toggle launcher
- [[20-Composants/wp/qml/wpbutton-qml]] — bouton du sélecteur

**Lancé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, y, exec, ~/.config/wp/wp.sh` (Super+Y)

**Backend (serveur CC, port 8765)** :
- [[20-Composants/cc/server-py]] — dispatch des routes /api/wallpaper*
- [[20-Composants/cc/wallpaper-py]] — liste, apply, pick (zenity), thumb (cache), random
- [[20-Composants/cc/sasquatch-cc-service]] — service systemd user requis par wp.sh

**Pipeline d'application** :
- [[20-Composants/cc/apply-wallpaper-sh]] — hyprpaper direct (dépendance waypaper abandonnée)
- [[20-Composants/scripts/theme-apply-sh]] — palette du thème (waybar, kitty, CC…)
- [[20-Composants/hypr/scripts/wallpaper-sh]] — même script commun, restauration au login

**Config lue** : `~/.config/waypaper/config.ini` (clé `folder=`, souvenir du dossier)

**Fondations** :
- [[10-Fondations/symlinks]] — `~/.config/wp/` symlinké vers le repo
- [[10-Fondations/theme-dynamique]] — le thème suit le wallpaper
