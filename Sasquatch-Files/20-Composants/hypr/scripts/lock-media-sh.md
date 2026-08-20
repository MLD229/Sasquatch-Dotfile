---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# hypr/scripts/lock-media.sh

## Rattachements

**Composant parent** : [[20-Composants/hypr]]

**Référence / source** :
- [[20-Composants/cc/server-py]] — API `http://127.0.0.1:8765/api/music/status` (now playing du CC)

**Référencé par** :
- [[20-Composants/hypr/hyprlock-conf]] — `cmd[update:2000]` (label musique du lock)
- [[20-Composants/scripts/theme-apply-py]] — réécrit la ligne cmd du lock dans hyprlock.conf
