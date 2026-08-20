---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# hypr/hypridle.conf

## Rattachements

**Composant parent** : [[20-Composants/hypr]]

**Référence / source** :
- [[20-Composants/hypr/hyprlock-conf]] — `lock_cmd = pidof hyprlock || hyprlock` (lock au capot via logind)
- [[20-Composants/settings/settings-py]] — régénère ce fichier (templates VEILLE / lock-only) et relance hypridle

**Référencé par** :
- [[20-Composants/hypr/scripts/autostart-sh]] — lance `hypridle &` au login
- [[20-Composants/settings/settings-py]] — l'écrit (panneau Settings, Super+I)
- [[10-Fondations/symlinks]] — lu par le daemon hypridle via `~/.config/hypr/hypridle.conf`
