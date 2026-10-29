---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-10-29
---

# scripts/calc.sh

## Rattachements

**Composant parent** : [[20-Composants/scripts]]

**Appels** : `rofi` + plugin `rofi-calc` (`~/.local/lib/rofi/libcalc.so`), qui appelle `qalc` (libqalculate), `wl-copy`

**Référencé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, U` (calculatrice, déplacée de Super+C)
- [[20-Composants/rofi]] — modi `calc` natif du plugin (résultat pendant la frappe)
- [[10-Fondations/requirements]] — libqalculate
- [[10-Fondations/install]] — installe libqalculate
