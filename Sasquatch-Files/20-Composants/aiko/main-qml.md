---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# aiko/main.qml

## Rattachements

**Composant parent** : [[20-Composants/aiko]]

**Backend appelé** (XHR http://127.0.0.1:8780) :
- [[20-Composants/aiko/server-py]] — /api/history, /api/model/start|status, /api/chat + /api/chat/poll, /api/capture, /api/palette, /api/chat/reset, /api/session/save, /api/close

**Lancé par** :
- [[20-Composants/aiko/aiko-sh]] — `quickshell -p aiko/main.qml` (toggle Super+N)

**Fenêtre** : titre « Aiko », float via [[20-Composants/hypr/conf.d/rules-conf]] — position `move` injectée dynamiquement par aiko.sh

**Référencé par** :
- [[00-Index]]
