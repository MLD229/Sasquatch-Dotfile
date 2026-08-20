---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# hypr/scripts/media-ctl.sh

## Rattachements

**Composant parent** : [[20-Composants/hypr]]

**Référence / source** :
- [[20-Composants/cc/server-py]] — API `/api/stats` + `/api/music/{toggle,next,prev,stop}` (MPRIS + MPD + web unifiés)
- playerctl — fallback si le serveur CC est down (binaire, pas de note)

**Référencé par** :
- [[20-Composants/hypr/keybinds-conf]] — bindl XF86AudioPlay/Next/Prev → toggle/next/prev
