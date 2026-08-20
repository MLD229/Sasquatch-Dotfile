---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# waybar/config

## Rattachements

**Composant parent** : [[20-Composants/waybar]]

**Scripts lancés ici (`exec`)** :
- [[20-Composants/waybar/scripts/fastview-py]] — module `custom/fastview` (daemon d'aperçu, format vide)
- [[20-Composants/waybar/scripts/clock-ja-py]] — module `custom/clock-ja` (interval 30 s, return-type json)

**Fichiers référencés ici** :
- [[20-Composants/waybar/style-css]] — chargé par waybar à côté du config ; stylise les modules (#custom-fastview, #clock, #mpris…)
- [[20-Composants/rofi/themes/sasquatch-rasi]] — module `custom/clipboard` (on-click : cliphist | rofi -theme sasquatch.rasi)
- [[20-Composants/hypr/conf.d/rules-conf]] — `defaultName` des workspaces (いち…じゅう) affichés par le module workspaces (`format: "{name}"`)

**Libellés japonais documentés dans** :
- [[20-Composants/waybar/ui-ja-json]] — dictionnaire de référence (ワークスペース, シーピーユー, でんち…)

**Référencé par** :
- [[20-Composants/waybar/waybar-service]] — ExecStart=/usr/bin/waybar charge ce config
