---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# pl/pl.sh

## Rattachements

**Composant parent** : [[20-Composants/pl]]

**Backend requis** :
- [[20-Composants/cc/sasquatch-cc-service]] — service systemd user `sasquatch-cc` démarré si inactif
- [[20-Composants/cc/server-py]] — health via GET /api/stats (port 8765)

**Lancé ici** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, p, exec, ~/.config/pl/pl.sh` (Super+P)
- [[20-Composants/cc/server-py]] — route POST /api/playlist/open (bouton 📃 du CC)

**Lance** :
- [[20-Composants/pl/main-qml]] — `quickshell -p` (position injectée par windowrule `move`)

**Référencé par** :
- [[10-Fondations/install]] — chmod +x pl/*.sh
- [[00-Index]]
