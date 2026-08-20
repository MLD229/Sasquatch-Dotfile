---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# waybar/style.css

## Rattachements

**Composant parent** : [[20-Composants/waybar]]

**Bloc SASQUATCH-PALETTE** (l. 4-23) :
- [[20-Composants/scripts/theme-apply-py]] — le réécrit à chaque changement de wallpaper (b_waybar)

**Lu par** :
- [[20-Composants/waybar/scripts/fastview-py]] — palette du popup d'aperçu (relue à chaque affichage)
- [[20-Composants/waybar/scripts/wallclock-ja-py]] — teinte accent (@color4) de l'horloge du wallpaper
- [[20-Composants/waybar/config]] — les sélecteurs stylent ses modules (#custom-fastview, #clock, #mpris…)

**Référencé par** :
- [[10-Fondations/theme-dynamique]] — la palette est la sortie du thème wallpaper
