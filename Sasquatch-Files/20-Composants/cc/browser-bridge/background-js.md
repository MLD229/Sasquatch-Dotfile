---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/browser-bridge/background.js

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**POST** : `http://127.0.0.1:8765/api/music/web` → [[20-Composants/cc/web_bridge-py]] (via [[20-Composants/cc/server-py]])

**Reçoit de** : [[20-Composants/cc/browser-bridge/content-js]] — messages `nowplaying`

**Déclaré dans** : [[20-Composants/cc/browser-bridge/manifest-json]] — service_worker
