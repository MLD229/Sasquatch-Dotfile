---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# waybar/scripts/wallclock-ja.py

## Rattachements

**Composant parent** : [[20-Composants/waybar]]

**Lancé par** :
- [[20-Composants/hypr/scripts/autostart-sh]] — au login (layer-shell BOTTOM : au-dessus du wallpaper, sous les fenêtres)

**Lit** :
- [[20-Composants/waybar/style-css]] — bloc SASQUATCH-PALETTE (teinte accent @color4)
- config waypaper (`~/.config/waypaper/config.ini`, runtime non versionné) — wallpaper courant → [[10-Fondations/theme-dynamique]]

**Couleur adaptative** :
- [[20-Composants/scripts/theme-apply-py]] — calcule la palette (accent) depuis le wallpaper

**Tables de lecture partagées** :
- [[20-Composants/waybar/scripts/clock-ja-py]] — mêmes tables HOURS/MIN_*
- [[20-Composants/hypr/scripts/lock-ja-py]] — tables synchronisées

**Référencé par** :
- [[10-Fondations/requirements]] — python-numpy, python-cairo (install.sh)
