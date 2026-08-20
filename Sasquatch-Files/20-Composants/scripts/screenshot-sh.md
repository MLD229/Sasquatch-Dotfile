---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# scripts/screenshot.sh

## Rattachements

**Composant parent** : [[20-Composants/scripts]]

**Appels** : `grim`, `slurp`, `wl-copy`, `notify-send` (aperçu), `hyprctl dispatch closewindow` (masque le CC en mode `cc`) ; écrit dans `~/Pictures/Screenshots`

**Référencé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = Print` (full) et `$mod, Print` (area)
- [[20-Composants/cc/actions-py]] — capture via le CC (2e arg `cc`)
- [[20-Composants/aiko/config-json]] — `capture.screenshot_script`
- [[10-Fondations/requirements]] — grim, slurp
