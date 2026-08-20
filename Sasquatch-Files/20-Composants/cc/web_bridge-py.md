---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/web_bridge.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe** : [[20-Composants/cc/config-py]] — WEB_BRIDGE_TOKEN

**Importé par** : [[20-Composants/cc/server-py]] (POST /api/music/web), [[20-Composants/cc/player-py]] (web_status, push_command)

**Protocole avec l'extension** :
- [[20-Composants/cc/browser-bridge/background-js]] — POST du now-playing, reçoit les commandes
- [[20-Composants/cc/browser-bridge/content-js]] — token partagé « sasquatch-cc-bridge »
