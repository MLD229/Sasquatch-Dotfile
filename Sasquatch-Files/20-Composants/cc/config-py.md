---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/config.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importé par (constantes partagées)** :
- [[20-Composants/cc/server-py]] · [[20-Composants/cc/metrics-py]] · [[20-Composants/cc/viz-py]] · [[20-Composants/cc/mpd-py]] · [[20-Composants/cc/player-py]] · [[20-Composants/cc/actions-py]] · [[20-Composants/cc/cava-py]] · [[20-Composants/cc/playlist-py]] · [[20-Composants/cc/translate-py]] · [[20-Composants/cc/wallpaper-py]] · [[20-Composants/cc/web_bridge-py]]

**Définit les chemins runtime** :
- [[20-Composants/cc/cava-py]] · [[20-Composants/cc/viz-py]] — fifos sasquatch-cava/audio.fifo (XDG_RUNTIME_DIR)
- [[20-Composants/mpd/mpd-conf]] — socket unix `~/.local/share/mpd/socket` (bind_to_address par user)
- [[20-Composants/cc/browser-bridge/content-js]] — token `WEB_BRIDGE_TOKEN` partagé avec l'extension
