---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# settings/settings.sh

## Rattachements

**Composant parent** : [[20-Composants/settings]]

**Lancé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, I, exec, ~/.config/settings/settings.sh` (Super+I)

**Lance** :
- [[20-Composants/settings/settings-py]] — serveur backend (nohup, pidfile `/tmp/sasquatch-settings-server.pid`, log `/tmp/sasquatch-settings-server.log`)
- [[20-Composants/settings/main-qml]] — `quickshell -p main.qml` (fenêtre « Sasquatch Settings »)

**Pattern** : toggle launcher identique à `cc/cc.sh` (détection fenêtre via hyprctl, health check curl `127.0.0.1:8770/api/health` avant lancement)
