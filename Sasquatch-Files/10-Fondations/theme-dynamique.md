---
tags: [sasquatch-files, fondations]
type: reference
updated: 2026-08-19
---

# theme-dynamique

## Rattachements

**Moteur** :
- [[20-Composants/scripts/theme-apply-py]] — génère la palette et réécrit les fichiers cibles (bloc SASQUATCH-PALETTE)
- [[20-Composants/scripts/theme-apply-sh]] — point d'entrée shell (flock, skip idempotent)

**Fichiers régénérés par la palette** :
- [[20-Composants/waybar/style-css]]
- [[20-Composants/kitty/kitty-conf]]
- [[20-Composants/rofi/themes/colors-rasi]]
- [[20-Composants/hypr/hyprlock-conf]]
- [[20-Composants/fastfetch/config-jsonc]]
- [[20-Composants/mako/config]]
- [[20-Composants/hypr/conf.d/general-conf]]

**Déclenché par** :
- [[20-Composants/cc/apply-wallpaper-sh]] — appelle theme-apply.sh après chaque changement de wallpaper
- [[20-Composants/hypr/scripts/wallpaper-sh]] — restauration du wallpaper au login
