---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/main.qml

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe le dossier `qml/`** :
- [[20-Composants/cc/qml/gauge-qml]] — jauges CPU/RAM/GPU
- [[20-Composants/cc/qml/iconbutton-qml]] — boutons fermer + contrôles musique
- [[20-Composants/cc/qml/sparkline-qml]] — historiques métriques
- [[20-Composants/cc/qml/tile-qml]] — tuiles de section
- Palette.qml (pas de note) — pollé via /api/palette, régénéré par [[20-Composants/scripts/theme-apply-py]]

**Consomme l'API** (XHR 127.0.0.1:8765) : /api/stats, /api/palette, /api/music/status, /api/system/volume, /api/system/brightness, /api/viz, /api/screenshot, /api/music/finder, /api/translate, /api/imgsearch, /api/music/* (toggle/seek/…), /api/playlist/open → [[20-Composants/cc/server-py]]

**Lancé par** : [[20-Composants/cc/cc-sh]]

**Windowrules associées** : [[20-Composants/hypr/conf.d/rules-conf]] — float, border 0, move 0 0

**Note service** : `quit()` ne ferme que la fenêtre — le serveur vit en permanence ([[20-Composants/cc/sasquatch-cc-service]])
