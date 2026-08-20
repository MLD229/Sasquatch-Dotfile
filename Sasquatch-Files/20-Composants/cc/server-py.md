---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/server.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe (modules backend)** :
- [[20-Composants/cc/config-py]] — HOST/PORT, chemins runtime
- [[20-Composants/cc/metrics-py]] · [[20-Composants/cc/viz-py]] — GET /api/stats, /api/viz
- [[20-Composants/cc/mpd-py]] · [[20-Composants/cc/player-py]] · [[20-Composants/cc/web_bridge-py]] — musique unifiée
- [[20-Composants/cc/actions-py]] · [[20-Composants/cc/palette-py]] · [[20-Composants/cc/wallpaper-py]] · [[20-Composants/cc/playlist-py]] · [[20-Composants/cc/cava-py]]

**Consommé par** :
- [[20-Composants/cc/main-qml]] — poll XHR des routes /api/*
- [[20-Composants/cc/cc-sh]] · [[20-Composants/wp/wp-sh]] · [[20-Composants/pl/pl-sh]] — healthcheck GET /api/stats
- [[20-Composants/cc/sasquatch-cc-service]] — ExecStart=`python3 %h/.config/cc/server.py`

**Lit** :
- [[20-Composants/settings/settings-json]] — réglages `cc` (cover_art, cava, ocr_lang)
- [[20-Composants/cc/browser-bridge/background-js]] — POST /api/music/web (pont navigateur)
