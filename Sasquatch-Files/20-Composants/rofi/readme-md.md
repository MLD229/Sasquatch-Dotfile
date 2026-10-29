---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# rofi/README.md

## Rattachements

**Composant parent** : [[20-Composants/rofi]]

**Fichiers documentés** :
- [[20-Composants/rofi/scripts/launcher-sh]]
- [[20-Composants/rofi/scripts/icon-gen-sh]]
- [[20-Composants/rofi/scripts/powermenu-sh]]
- [[20-Composants/rofi/themes/sasquatch-rasi]]
- [[20-Composants/rofi/themes/colors-rasi]]

**Références citées** :
- [[20-Composants/hypr/keybinds-conf]] — keybinds réels du launcher, de Super+U et du powermenu
- [[20-Composants/scripts/clipboard-sh]], [[20-Composants/scripts/keybinds-reminder-sh]] — piège rofi 2.0 (stdin vide) documenté
- [[20-Composants/scripts/calc-sh]] — Super+U, ouvre le modi `calc` du plugin rofi-calc

> rofi 2.0 n'exécute un mode script qu'au démarrage (`rofi-script(5)`) : pas de
> recalcul à chaque frappe. Le launcher passe donc son `-filter` via
> `SASQUATCH_CALC_FILTER`, et `Ctrl+Entrée` (`ROFI_RETV=2`) envoie le texte tapé
> au script. La calculatrice « live » (Super+U) passe par le plugin natif `rofi-calc`.
