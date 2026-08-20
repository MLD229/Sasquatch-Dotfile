---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# wp/wp.sh

## Rattachements

**Composant parent** : [[20-Composants/wp]]

**Lancé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, y, exec, ~/.config/wp/wp.sh` (Super+Y)

**Lance** :
- [[20-Composants/wp/main-qml]] — `quickshell -p main.qml` (fenêtre « Sasquatch Wallpaper »)

**Dépend du backend CC** :
- [[20-Composants/cc/sasquatch-cc-service]] — `systemctl --user start sasquatch-cc` si inactif
- [[20-Composants/cc/server-py]] — health check /api/stats (port 8765)
