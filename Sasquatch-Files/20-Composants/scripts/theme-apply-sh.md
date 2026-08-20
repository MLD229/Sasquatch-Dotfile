---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# scripts/theme-apply.sh

## Rattachements

**Composant parent** : [[20-Composants/scripts]]

**Appels** : [[20-Composants/scripts/theme-apply-py]], `hyprctl reload`, `systemctl --user reload|start waybar`, `makoctl reload`, `kitty @ set-colors`, `flock` ; lit `~/.config/waypaper/config.ini` (wallpaper courant)

**Références** :
- [[20-Composants/waybar/waybar-service]] — rechargement SIGUSR2 sans tuer la barre

**Référencé par** :
- [[10-Fondations/theme-dynamique]] — point d'entrée shell du thème
- [[20-Composants/hypr/scripts/autostart-sh]] — appel au login (filet de sécurité)
- [[20-Composants/cc/apply-wallpaper-sh]] — après changement de wallpaper
- [[20-Composants/cc/wallpaper-py]] — via /api/wallpaper/apply
- [[20-Composants/wp/wp-sh]] — sélecteur de fonds d'écran
- [[20-Composants/settings/settings-py]] — relancé après palette/horloge
- [[10-Fondations/install]] — post_command de waypaper config.ini
