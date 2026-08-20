---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# pl/main.qml

## Rattachements

**Composant parent** : [[20-Composants/pl]]

**Composants QML importés** (`import "qml"`) :
- [[20-Composants/pl/qml/plbutton-qml]]
- [[20-Composants/pl/qml/pllibrow-qml]]
- [[20-Composants/pl/qml/plrow-qml]]

**Backend appelé** (XHR http://127.0.0.1:8765) :
- [[20-Composants/cc/server-py]] — /api/playlist/status|list|library|load|clear|shuffle|play|remove|add|pick|folder|toggle|seek|prev|playtoggle|stop|next + /api/palette (thème)
- [[20-Composants/cc/playlist-py]] — implémentation des routes playlist

**Lancé par** :
- [[20-Composants/pl/pl-sh]] — `quickshell -p pl/main.qml` (toggle Super+P)

**Référencé par** :
- [[00-Index]]
