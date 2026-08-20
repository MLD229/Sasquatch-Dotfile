---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# hypr/hyprlock.conf

## Rattachements

**Composant parent** : [[20-Composants/hypr]]

**Référence / source** :
- [[20-Composants/hypr/scripts/lock-ja-py]] — labels heure/date (`cmd[update:1000] python3 … lock-ja.py time|date`)
- [[20-Composants/hypr/scripts/lock-media-sh]] — now playing (`cmd[update:2000]`)
- [[10-Fondations/theme-dynamique]] — bloc SASQUATCH-PALETTE (couleurs) réécrit par theme-apply.py

**Référencé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, L, exec, hyprlock`
- [[20-Composants/hypr/hypridle-conf]] — `lock_cmd` du lock au capot
- [[20-Composants/scripts/theme-apply-py]] — réécrit le bloc palette (b_hyprlock)
- [[20-Composants/hypr/scripts/lock-ja-py]] — lit la couleur du label time dans ce fichier
- [[20-Composants/settings/settings-py]] — section HORLOGE (format horloge du lock)
