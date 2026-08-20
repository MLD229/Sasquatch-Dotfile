---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/cc.sh

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Lance** :
- [[20-Composants/cc/main-qml]] — `quickshell -p $SCRIPT_DIR/main.qml` (fenêtre « Sasquatch CC »)
- [[20-Composants/cc/sasquatch-cc-service]] — `systemctl --user start` idempotent

**Healthcheck** : curl `http://127.0.0.1:8765/api/stats` → [[20-Composants/cc/server-py]]

**Référencé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, G`
- [[10-Fondations/install]] — chmod +x des scripts cc (install.sh)
- [[20-Composants/settings/settings-sh]] — même pattern de toggle (window_open + pkill)
